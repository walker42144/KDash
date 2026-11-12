import json,os,subprocess,sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parent))
import config_model as m
import bundle_store as b

class ReviewTests(unittest.TestCase):
 def test_interrupted_two_file_save_recovers_under_lock_on_next_read(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp)/'config.json';s=p.with_name('secrets.json');p.write_text('{"old":1}');s.write_text('{"old":2}')
   code="""
import os,sys
from pathlib import Path
import config_model as m
p=Path(sys.argv[1]);real=os.replace
def replace(a,dst):
 if Path(dst).name=='secrets.json':os._exit(99)
 return real(a,dst)
os.replace=replace
m.save_bundle(p,{'new':1},{'new':2},m.digest(p),m.digest(p.with_name('secrets.json')),p.parent/'backups')
"""
   env={**os.environ,'PYTHONPATH':str(Path(__file__).resolve().parent)}
   result=subprocess.run([sys.executable,'-c',code,str(p)],env=env,timeout=10,capture_output=True)
   self.assertEqual(result.returncode,99,result.stderr)
   self.assertTrue((p.parent/'.kdash-save.pending').exists());self.assertEqual(json.loads(p.read_text()),{'new':1})
   with self.assertRaises(ValueError):m.load(p)
   m.recover_bundle(p)
   self.assertEqual(m.load(p)[0],{'old':1});self.assertEqual(m.load(s)[0],{'old':2})
   self.assertFalse((p.parent/'.kdash-save.pending').exists())

 def test_second_process_cannot_save_while_first_holds_os_lock(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp)/'config.json';p.write_text('{}')
   code="import sys,bundle_store as b\nwith b.locked(sys.argv[1]):\n print('LOCKED',flush=True)\n sys.stdin.readline()\n"
   env={**os.environ,'PYTHONPATH':str(Path(__file__).resolve().parent)}
   child=subprocess.Popen([sys.executable,'-c',code,tmp],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env)
   try:
    self.assertEqual(child.stdout.readline().strip(),'LOCKED')
    with self.assertRaises(ValueError):m.save_bundle(p,{'new':1},{},m.digest(p),None,Path(tmp)/'backup')
    self.assertEqual(p.read_text(),'{}')
   finally:child.communicate('\n',timeout=10)

 def test_backup_credentials_are_recoverable_and_not_plaintext_on_windows(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp)/'config.json';p.write_text('{}');s=p.with_name('secrets.json');s.write_text('{"token":"fake-secret"}')
   backup,_,_=m.save_bundle(p,{}, {'token':'new'},m.digest(p),m.digest(s),Path(tmp)/'backups')
   self.assertEqual(m.read_backup(backup)[1],{'token':'fake-secret'})
   if os.name=='nt':
    self.assertFalse((backup/'secrets.json').exists());self.assertNotIn(b'fake-secret',(backup/'secrets.json.dpapi').read_bytes())

 def test_journal_refuses_path_traversal(self):
  with tempfile.TemporaryDirectory() as tmp:
   (Path(tmp)/'.kdash-save.pending').write_text(json.dumps({'originals':{'../victim.json':None,'secrets.json':None}}))
   with b.locked(tmp):
    with self.assertRaises(ValueError):b.recover(tmp)
   self.assertTrue((Path(tmp)/'.kdash-save.pending').exists())

 def test_no_default_resource_does_not_crash_the_configuration_tool(self):
  import configurator
  with tempfile.TemporaryDirectory() as tmp,patch.object(configurator,'RESOURCE',Path(tmp)):
   self.assertEqual(configurator.default_config()['utc_offset_minutes'],480)

 def test_normal_read_is_strictly_read_only(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp)/'config.json';p.write_text('{}');before={x.name:x.stat().st_mtime_ns for x in Path(tmp).iterdir()}
   self.assertEqual(m.load(p)[0],{})
   self.assertEqual(before,{x.name:x.stat().st_mtime_ns for x in Path(tmp).iterdir()})

if __name__=='__main__':unittest.main()
