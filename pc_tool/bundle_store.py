"""Serialized, recoverable two-file saves. No claim of two-file atomicity on FAT.

The journal is durable before either replace. A disconnected/terminated save is
rolled back on the next read/save under the OS lock. Kindle refuses to start
while the journal is present. No account values are written to diagnostics.
"""
from contextlib import contextmanager
from pathlib import Path
import base64,json,os,secrets

@contextmanager
def locked(parent):
    f=open(Path(parent)/'.kdash-config.lock','a+b')
    acquired=False
    try:
        f.seek(0,2)
        if not f.tell():f.write(b'0');f.flush()
        f.seek(0)
        try:
            if os.name=='nt':
                import msvcrt
                msvcrt.locking(f.fileno(),msvcrt.LK_NBLCK,1)
            else:
                import fcntl
                fcntl.flock(f.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
            acquired=True
        except OSError:raise ValueError('另一配置工具正在读写，请稍后重试') from None
        yield
    finally:
        if acquired:
            f.seek(0)
            if os.name=='nt':
                import msvcrt
                msvcrt.locking(f.fileno(),msvcrt.LK_UNLCK,1)
            else:
                import fcntl
                fcntl.flock(f.fileno(),fcntl.LOCK_UN)
        f.close()

def atomic_bytes(path,data):
    path=Path(path);tmp=path.with_name(path.name+'.kdash-'+secrets.token_hex(8)+'.tmp')
    try:
        with open(tmp,'xb') as f:
            f.write(data);f.flush();os.fsync(f.fileno())
        os.replace(tmp,path)
        sync_directory(path.parent)
    finally:tmp.unlink(missing_ok=True)

def sync_directory(path):
    if os.name!='nt':
        fd=os.open(path,os.O_RDONLY)
        try:os.fsync(fd)
        finally:os.close(fd)

def recover(parent):
    parent=Path(parent);journal=parent/'.kdash-save.pending'
    if not journal.exists():return
    # Bound and validate the journal before touching any destination.
    if journal.stat().st_size>12*1024*1024:raise ValueError('保存恢复记录过大，请保留文件并联系维护者')
    record=json.loads(journal.read_text('utf-8'));entries=record.get('originals')
    if not isinstance(entries,dict) or len(entries)!=2 or 'secrets.json' not in entries:raise ValueError('保存恢复记录格式错误')
    restored={}
    for name,value in entries.items():
        if Path(name).name!=name or '/' in name or '\\' in name or not name.endswith('.json'):raise ValueError('保存恢复记录路径错误')
        target=parent/name
        if target.is_symlink():raise ValueError('恢复目标不能是符号链接')
        restored[target]=None if value is None else base64.b64decode(value,validate=True)
    for p,data in restored.items():
        if data is None:p.unlink(missing_ok=True)
        else:atomic_bytes(p,data)
    journal.unlink();sync_directory(parent)

def begin(parent,originals):
    data={'version':1,'originals':{p.name:None if b is None else base64.b64encode(b).decode('ascii') for p,b in originals.items()}}
    atomic_bytes(Path(parent)/'.kdash-save.pending',json.dumps(data).encode('utf-8'))

def commit(parent):
    (Path(parent)/'.kdash-save.pending').unlink();sync_directory(parent)
