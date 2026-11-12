"""Bounded command and recovery regression tests, mock device paths only."""
from pathlib import Path
import os,shutil,subprocess,tempfile,time,unittest
ROOT=Path(__file__).resolve().parents[1]
SH=shutil.which('sh') or r'C:\Program Files\Git\usr\bin\sh.exe'
def posix(p):
 s=str(Path(p).resolve()).replace('\\','/')
 return '/'+s[0].lower()+s[2:] if len(s)>1 and s[1]==':' else s
def shell(code,timeout=10):
 return subprocess.run([SH,'-c','export PATH=/usr/bin:/bin:$PATH\n'+code],capture_output=True,text=True,timeout=timeout)

class ReviewShellTests(unittest.TestCase):
 def test_guard_can_time_out_its_own_orphan_recovery_worker(self):
  with tempfile.TemporaryDirectory() as tmp:
   run=Path(tmp);(run/'logs').mkdir();(run/'limit').write_text('0\n')
   common=(ROOT/'launcher/session-common.sh').read_text()+'''
sleep() { command sleep 0.02; }
recover() { record_pid "$RUN/recover.pid" $$;while :;do :;done; }
'''
   (run/'session-common.sh').write_text(common,newline='\n')
   guard=(ROOT/'launcher/session-guard.sh').read_text().replace('DATA=/mnt/us/kdash-candidate',"DATA='"+posix(run)+"'").replace(' -le 60',' -le 2')
   (run/'guard.sh').write_text(guard,newline='\n')
   result=shell("/bin/sh '"+posix(run/'guard.sh')+"' '"+posix(run)+"'",timeout=10)
   self.assertEqual(result.returncode,1,result.stderr)
   self.assertTrue((run/'recovery.failed').exists())
   self.assertIn('deadline exceeded',(run/'logs/session.log').read_text())

 def test_manual_recovery_skips_responsive_owner_but_can_recover_a_stalled_one(self):
  for responsive in [True,False]:
   with tempfile.TemporaryDirectory() as tmp:
    base=Path(tmp);run=base/'run.abc';run.mkdir();(base/'logs').mkdir();(base/'session.lock').mkdir();(base/'session.lock/run').write_text(posix(run))
    (run/'app.pid').touch();(run/'heartbeat').write_text(str(int(time.time())-(0 if responsive else 100)))
    common='''alive() { p=123;return 0; }
log() { echo "$*" >> "$RUN/trace"; }
kill() { echo "kill $*" >> "$RUN/trace"; }
sleep() { :; }
recover() { echo recovered >> "$RUN/trace"; }
'''
    (run/'session-common.sh').write_text(common,newline='\n')
    code=(ROOT/'launcher/library-recover.sh').read_text().replace('/var/tmp/kdash-candidate',posix(base)).replace('/mnt/us/kdash-candidate',posix(base))
    result=shell('set -- --recovery-worker\n'+code);self.assertEqual(result.returncode,0,result.stderr)
    trace=(run/'trace').read_text();self.assertEqual('kill -TERM' in trace,not responsive)
    self.assertEqual('recovered' in trace,not responsive)

 def test_manual_recovery_quarantines_ownerless_lock_without_deleting_it(self):
  with tempfile.TemporaryDirectory() as tmp:
   base=Path(tmp);(base/'logs').mkdir();(base/'session.lock').mkdir();(base/'session.lock/unexpected').write_text('keep')
   code=(ROOT/'launcher/library-recover.sh').read_text().replace('/var/tmp/kdash-candidate',posix(base)).replace('/mnt/us/kdash-candidate',posix(base))
   result=shell('set -- --recovery-worker\n'+code);self.assertEqual(result.returncode,0,result.stderr)
   self.assertFalse((base/'session.lock').exists());self.assertEqual(len(list(base.glob('session.lock.abandoned.*/unexpected'))),1)

 def test_bounded_command_returns_child_status_and_output(self):
  helper=posix(ROOT/'launcher/command-timeout.sh')
  result=shell(f"KDASH_TIMEOUT_SINGLE_PID=1 /bin/sh '{helper}' 2 /bin/sh -c 'echo example;exit 7'")
  self.assertEqual(result.returncode,7,result.stderr);self.assertEqual(result.stdout.strip(),'example')

 def test_hung_command_is_stopped_instead_of_waiting_forever(self):
  helper=posix(ROOT/'launcher/command-timeout.sh');start=time.monotonic()
  result=shell(f"KDASH_TIMEOUT_SINGLE_PID=1 /bin/sh '{helper}' 1 sleep 30",timeout=6)
  self.assertNotEqual(result.returncode,0,result.stderr);self.assertLess(time.monotonic()-start,5)

 def test_recovery_retry_budget_preserves_snapshot_and_stops_flashing(self):
  with tempfile.TemporaryDirectory() as tmp:
   run=Path(tmp);(run/'ui.intent').touch();(run/'stock.fb').write_text('stock');(run/'ui.pids').write_text('')
   (run/'fbink').write_text('#!/bin/sh\necho flash >> "$(dirname "$0")/trace"\nexit 1\n',newline='\n')
   (run/'fb').write_text('old')
   common=(ROOT/'launcher/session-common.sh').read_text().replace('/dev/fb0',posix(run/'fb'))
   code=common+f"\nRUN='{posix(run)}';DATA=\"$RUN\";LOG=\"$RUN/log\"\n"+'''
pid_stamp() { echo 200; }
sleep() { :; }
pidof() { echo 1; }
lipc-set-prop() { return 0; }
recover || true
recover || true
recover || true
recover || true
'''
   result=shell(code);self.assertEqual(result.returncode,0,result.stderr)
   self.assertEqual((run/'trace').read_text().count('flash'),6)
   self.assertTrue((run/'stock.fb').exists());self.assertTrue((run/'recovery.failed').exists())

 def test_release_owned_lock_with_extra_file_keeps_owner_and_is_reacquirable(self):
  with tempfile.TemporaryDirectory() as tmp:
   base=Path(tmp);run=base/'run.abc';run.mkdir();lock=base/'session.lock';lock.mkdir()
   (lock/'run').write_text(posix(run));(lock/'unexpected').write_text('preserve')
   code=(ROOT/'launcher/session-common.sh').read_text()+f"\nBASE='{posix(base)}';RUN='{posix(run)}';LOG='{posix(base/'log')}'\nrelease_lock\nmkdir \"$BASE/session.lock\"\n"
   result=shell(code);self.assertEqual(result.returncode,0,result.stderr)
   self.assertEqual((base/'lock-released.run.abc/unexpected').read_text(),'preserve')

if __name__=='__main__':unittest.main()
