"""Real shell processes, fake power service; no Kindle I/O."""
from pathlib import Path
import os,shutil,subprocess,tempfile,time,unittest
ROOT=Path(__file__).resolve().parents[1]
SH=shutil.which('sh') or r'C:\Program Files\Git\usr\bin\sh.exe'
def posix(p):
 s=str(Path(p).resolve()).replace('\\','/')
 return '/'+s[0].lower()+s[2:] if len(s)>1 and s[1]==':' else s
class PowerLatency(unittest.TestCase):
 def test_superseded_sleep_does_not_keep_waiting_on_stalled_power_service(self):
  with tempfile.TemporaryDirectory(prefix='kdash-power-latency-') as tmp:
   run=Path(tmp);(run/'logs').mkdir();(run/'bin').mkdir()
   for name in ['session-common.sh','command-timeout.sh']:
    (run/name).write_text((ROOT/'launcher'/name).read_text('utf-8'),newline='\n')
   (run/'bin/lipc-get-prop').write_text('#!/bin/sh\necho active\n',newline='\n')
   (run/'bin/lipc-set-prop').write_text('#!/bin/sh\necho started > "$RUN/started"\nsleep 4\necho finished > "$RUN/finished"\n',newline='\n')
   for f in (run/'bin').iterdir():f.chmod(0o755)
   (run/'power.desired').write_text('1 sleep\n',newline='\n')
   control=(ROOT/'launcher/power-control.sh').read_text('utf-8').replace('DATA=/mnt/us/kdash-candidate',"DATA='"+posix(run)+"'")
   (run/'control.sh').write_text(control,newline='\n')
   cmd=f"export RUN='{posix(run)}'; export KDASH_TIMEOUT_SINGLE_PID=1; export PATH='{posix(run/'bin')}':/usr/bin:/bin:$PATH; /bin/sh '{posix(run/'control.sh')}' '{posix(run)}'"
   proc=subprocess.Popen([SH,'-c',cmd],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
   try:
    until=time.monotonic()+6
    while not (run/'started').exists() and time.monotonic()<until:time.sleep(.05)
    self.assertTrue((run/'started').exists(),'fake sleep request did not start')
    start=time.monotonic();(run/'power.desired').write_text('2 wake\n',newline='\n')
    while time.monotonic()-start<3.3:
     log=(run/'logs/session.log').read_text() if (run/'logs/session.log').exists() else ''
     if 'power_state request=sleep result=' in log:break
     time.sleep(.05)
    self.assertIn('power_state request=sleep result=',log)
    self.assertFalse((run/'finished').exists(),'superseded sleep request finished after wake')
   finally:
    (run/'stop.request').touch()
    try:proc.wait(timeout=7)
    except subprocess.TimeoutExpired:proc.terminate();proc.wait(timeout=5)
if __name__=='__main__':unittest.main()
