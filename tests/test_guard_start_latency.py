"""Exercise the real launcher's guard handshake with fake clock/processes."""
from pathlib import Path
import shutil, subprocess, tempfile, unittest

ROOT = Path(__file__).resolve().parents[1]
SH = shutil.which('sh') or r'C:\Program Files\Git\usr\bin\sh.exe'

def posix(p):
    s = str(Path(p).resolve()).replace('\\', '/')
    return '/'+s[0].lower()+s[2:] if len(s)>1 and s[1]==':' else s

class GuardHandshake(unittest.TestCase):
    def invoke(self, mode):
        source = (ROOT/'launcher/kdash-launch.sh').read_text(encoding='utf-8')
        start = source.index('i=0;', source.index('record_pid "$RUN/guard.pid"'))
        end = source.index('[ ! -f "$RUN/stop.request" ]', start)
        body = source[start:end]
        with tempfile.TemporaryDirectory(prefix='kdash-guard-start-') as tmp:
            run = Path(tmp)
            script = '''RUN="$1"; MODE="$2"
log() { :; }
trace_startup() { :; }
alive() { [ "$MODE" != dead ]; }
sleep() {
 echo "$1" >> "$RUN/sleeps"
 case "$MODE:$1" in unsupported:0.1) return 1;; esac
 [ "$MODE" = never ] || : > "$RUN/guard.ready"
}
''' + body + '\necho handshake-ok\n'
            f = run/'test.sh'; f.write_text(script, encoding='utf-8', newline='\n')
            p = subprocess.run([SH, posix(f), posix(run), mode], capture_output=True, text=True, timeout=10)
            sleeps = (run/'sleeps').read_text().splitlines() if (run/'sleeps').exists() else []
            return p.returncode, sleeps, p.stdout

    def test_ready_guard_does_not_force_a_full_second_wait(self):
        rc, sleeps, out = self.invoke('fast')
        self.assertEqual(rc, 0); self.assertIn('handshake-ok', out)
        self.assertNotIn('1', sleeps)

    def test_unsupported_fractional_sleep_falls_back_to_bounded_seconds(self):
        rc, sleeps, out = self.invoke('unsupported')
        self.assertEqual(rc, 0); self.assertIn('handshake-ok', out)
        self.assertIn('1', sleeps)

    def test_missing_guard_aborts_before_pause(self):
        rc, sleeps, out = self.invoke('never')
        self.assertNotEqual(rc, 0); self.assertNotIn('handshake-ok', out)
        self.assertLessEqual(len(sleeps), 51)

    def test_dead_guard_aborts_before_pause(self):
        rc, sleeps, out = self.invoke('dead')
        self.assertNotEqual(rc, 0); self.assertNotIn('handshake-ok', out)

if __name__ == '__main__': unittest.main()
