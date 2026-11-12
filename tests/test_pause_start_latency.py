"""Exercise the real UI-pause verification with fake process state."""
from pathlib import Path
import shutil, subprocess, tempfile, unittest
ROOT=Path(__file__).resolve().parents[1]
SH=shutil.which('sh') or r'C:\Program Files\Git\usr\bin\sh.exe'
def posix(p):
 s=str(Path(p).resolve()).replace('\\','/');return '/'+s[0].lower()+s[2:] if len(s)>1 and s[1]==':' else s
class PauseVerification(unittest.TestCase):
 def invoke(self,mode):
  source=(ROOT/'launcher/kdash-launch.sh').read_text(encoding='utf-8')
  start=source.index('done < "$RUN/ui.pids"',source.index("log 'ui_pause_begin"))+len('done < "$RUN/ui.pids"')
  end=source.index('# Snapshot the reviewed',start)
  with tempfile.TemporaryDirectory(prefix='kdash-ui-pause-') as tmp:
   run=Path(tmp);(run/'ui.pids').write_text('123 100 cvm\n')
   script='''RUN="$1"; MODE="$2"; short_sleep=1
log() { :; }
pid_stamp() { if [ "$MODE" = changed ];then echo 101;else echo 100;fi; }
awk() { if [ "$MODE" = running ];then echo S;else echo T;fi; }
sleep() { echo "$1" >> "$RUN/sleeps"; }
'''+source[start:end]+'\necho verified\n'
   f=run/'test.sh';f.write_text(script,encoding='utf-8',newline='\n')
   p=subprocess.run([SH,posix(f),posix(run),mode],capture_output=True,text=True,timeout=10)
   sleeps=(run/'sleeps').read_text().splitlines() if (run/'sleeps').exists() else []
   return p.returncode,sleeps,p.stdout
 def test_already_stopped_process_is_verified_without_fixed_wait(self):
  rc,sleeps,out=self.invoke('stopped');self.assertEqual(rc,0);self.assertIn('verified',out);self.assertNotIn('1',sleeps)
 def test_running_process_is_never_treated_as_paused(self):
  rc,sleeps,out=self.invoke('running');self.assertNotEqual(rc,0);self.assertNotIn('verified',out);self.assertLessEqual(len(sleeps),50)
 def test_changed_process_identity_aborts(self):
  rc,sleeps,out=self.invoke('changed');self.assertNotEqual(rc,0);self.assertNotIn('verified',out)
if __name__=='__main__':unittest.main()
