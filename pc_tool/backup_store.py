"""Credential backups use Windows DPAPI for the current user; POSIX mode 0600."""
from pathlib import Path
import ctypes,os,shutil

def _dpapi(data,encrypt):
    from ctypes import wintypes as w
    class Blob(ctypes.Structure):_fields_=[('size',w.DWORD),('data',ctypes.POINTER(ctypes.c_ubyte))]
    buf=ctypes.create_string_buffer(data);src=Blob(len(data),ctypes.cast(buf,ctypes.POINTER(ctypes.c_ubyte)));dst=Blob()
    crypt=ctypes.WinDLL('crypt32',use_last_error=True);kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    if encrypt:
        crypt.CryptProtectData.argtypes=[ctypes.POINTER(Blob),w.LPCWSTR,ctypes.c_void_p,ctypes.c_void_p,ctypes.c_void_p,w.DWORD,ctypes.POINTER(Blob)]
        ok=crypt.CryptProtectData(ctypes.byref(src),'KDash secret backup',None,None,None,1,ctypes.byref(dst))
    else:
        crypt.CryptUnprotectData.argtypes=[ctypes.POINTER(Blob),ctypes.c_void_p,ctypes.c_void_p,ctypes.c_void_p,ctypes.c_void_p,w.DWORD,ctypes.POINTER(Blob)]
        ok=crypt.CryptUnprotectData(ctypes.byref(src),None,None,None,None,1,ctypes.byref(dst))
    if not ok:raise OSError('无法处理密钥备份；须使用创建备份的 Windows 用户')
    try:return ctypes.string_at(dst.data,dst.size)
    finally:
        kernel.LocalFree.argtypes=[ctypes.c_void_p];kernel.LocalFree(ctypes.cast(dst.data,ctypes.c_void_p))

def write(folder,name,data):
    p=Path(folder)/name
    if name=='secrets.json' and os.name=='nt':p=p.with_suffix('.json.dpapi');data=_dpapi(data,True)
    with open(p,'xb') as f:f.write(data)
    if os.name!='nt':os.chmod(p,0o600)

def read_secrets(folder):
    folder=Path(folder);enc=folder/'secrets.json.dpapi'
    if enc.exists():
        if os.name!='nt':raise ValueError('此备份需要原 Windows 用户解密')
        return _dpapi(enc.read_bytes(),False)
    p=folder/'secrets.json'
    return p.read_bytes() if p.exists() else b'{}'

def prune(root,keep=10):
    root=Path(root).resolve()
    folders=sorted((p for p in root.iterdir() if p.is_dir() and not p.is_symlink() and (p/'backup-info.json').is_file()),key=lambda p:p.name,reverse=True)
    for p in folders[keep:]:
        if p.resolve().parent==root:shutil.rmtree(p)
