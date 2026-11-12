"""Exercise shipped recovery/guard scripts with deterministic OS mocks, no device access."""
from pathlib import Path
import subprocess,tempfile,shutil
ROOT=Path(__file__).resolve().parents[1]
SH=shutil.which('sh') or r'C:\Program Files\Git\usr\bin\sh.exe'
def posix(p):
 s=str(p.resolve()).replace('\\','/')
 return '/'+s[0].lower()+s[2:] if len(s)>1 and s[1]==':' else s
with tempfile.TemporaryDirectory(prefix='kdash-recovery-') as tmp:
 base=Path(tmp);common=(ROOT/'launcher/session-common.sh').read_text('utf-8')
 tests=[('normal',True,False,False),('preflight',False,False,False),('reused-pid',True,True,False),('retry',True,False,True)]
 for name,intent,reused,fail in tests:
  run=base/name;run.mkdir();(run/'app.pid').write_text('10 '+('999' if reused else '100')+'\n',newline='\n')
  (run/'ui.pids').write_text('20 200 awesome\n',newline='\n');(run/'screensaver.before').write_text('7\n',newline='\n')
  if intent:(run/'ui.intent').touch()
  script=common.replace('/var/tmp/kdash-candidate',posix(base))
  f=run/'session-common.sh';f.write_text(script,encoding='utf-8',newline='\n')
  code=f'''export PATH=/usr/bin:/bin:$PATH
RUN='{posix(run)}'; LOG="$RUN/log"; TRACE="$RUN/trace"; : > "$TRACE"
. "$RUN/session-common.sh"
app_live=1
pid_stamp() {{ case "$1" in 10) echo 100;; 20) echo 200;; *) echo 300;; esac; }}
kill() {{
 case "$1" in -0) [ "$2" != 10 ] || [ "$app_live" = 1 ];;
 -TERM|-KILL) echo "$1 $2" >> "$TRACE"; app_live=0;;
 *) echo "$1 $2" >> "$TRACE";; esac
}}
sleep() {{ :; }}
awk() {{ echo S; }}
pidof() {{ echo 20; }}
fail_home={1 if fail else 0}
lipc-set-prop() {{ echo "lipc $*" >> "$TRACE"; if [ "$2" = com.lab126.powerd ]; then return 0; fi; [ "$fail_home" = 0 ]; }}
recover
'''
  if fail:code+='[ ! -f "$RUN/recovery.done" ] || exit 51\nfail_home=0\nrecover || exit 52\n'
  code+='[ -f "$RUN/recovery.done" ] || exit 53\n'
  proc=subprocess.run([SH,'-c',code],capture_output=True,text=True)
  assert proc.returncode==0,(name,proc.stdout,proc.stderr)
  trace=(run/'trace').read_text()
  assert ('-TERM 10' in trace)!=reused,(name,trace)
  assert ('-CONT 20' in trace)==intent,(name,trace)
  assert ('preventScreenSaver 7' in trace)==intent,(name,trace)
  print('PASS recovery:',name)
 # Run the actual watchdog loop against an orphaned supervisor, using the same recovery.
 run=base/'guard';run.mkdir();(run/'limit').write_text('180\n',newline='\n');(run/'ui.intent').touch()
 (run/'ui.pids').write_text('20 200 awesome\n',newline='\n');(run/'screensaver.before').write_text('0\n',newline='\n')
 mocks='''
pid_stamp() { echo 200; }
kill() { echo "$*" >> "$RUN/trace"; return 0; }
sleep() { :; }
awk() { echo S; }
pidof() { echo 20; }
lipc-set-prop() { echo "lipc $*" >> "$RUN/trace"; }
'''
 (run/'session-common.sh').write_text(common.replace('/var/tmp/kdash-candidate',posix(base))+mocks,encoding='utf-8',newline='\n')
 guard=(ROOT/'launcher/session-guard.sh').read_text('utf-8').replace('DATA=/mnt/us/kdash-candidate',"DATA='"+posix(run)+"'")
 (run/'logs').mkdir();f=run/'guard.sh';f.write_text(guard,encoding='utf-8',newline='\n')
 proc=subprocess.run([SH,'-c',f"export PATH=/usr/bin:/bin:$PATH; /bin/sh '{posix(f)}' '{posix(run)}'"],capture_output=True,text=True,timeout=10)
 assert proc.returncode==0,(proc.stdout,proc.stderr)
 assert (run/'guard.ready').exists() and (run/'recovery.done').exists()
 assert '-CONT 20' in (run/'trace').read_text()
 print('PASS watchdog: orphaned supervisor restores UI')
 # Supervisor remains alive until guard sends TERM: exercise the timeout branch.
 run2=base/'timeout';shutil.copytree(run,run2)
 for name in ['recovery.done','guard.ready','trace','recovery-worker.pid']:
  (run2/name).unlink(missing_ok=True)
 (run2/'supervisor.pid').write_text('30 200\n',newline='\n')
 (run2/'limit').write_text('1\n',newline='\n')
 c=(run2/'session-common.sh').read_text('utf-8')
 c=c.replace('kill() { echo "$*" >> "$RUN/trace"; return 0; }', '''kill() {
 echo "$*" >> "$RUN/trace"
 if [ "$1" = -0 ]; then [ "$2" != 30 ] || [ ! -f "$RUN/parent-dead" ]; return $?; fi
 if [ "$1" = -TERM ] && [ "$2" = 30 ]; then : > "$RUN/parent-dead"; fi
 return 0
}''')
 (run2/'session-common.sh').write_text(c,encoding='utf-8',newline='\n')
 f=run2/'guard.sh';f.write_text(guard.replace(posix(run),posix(run2)),encoding='utf-8',newline='\n')
 proc=subprocess.run([SH,'-c',f"export PATH=/usr/bin:/bin:$PATH; /bin/sh '{posix(f)}' '{posix(run2)}'"],capture_output=True,text=True,timeout=10)
 assert proc.returncode==0,(proc.returncode,proc.stdout,proc.stderr,(run2/'logs/session.log').read_text(),(run2/'trace').read_text())
 assert (run2/'recovery.done').exists() and (run2/'parent-dead').exists()
 assert '-TERM 30' in (run2/'trace').read_text()
 print('PASS watchdog: deadline terminates supervisor and resumes UI')
 # Unlimited sessions must survive beyond the trial deadline, yet recover on parent death.
 run3=base/'unlimited';shutil.copytree(run,run3)
 for name in ['recovery.done','guard.ready','trace','recovery-worker.pid']:
  (run3/name).unlink(missing_ok=True)
 (run3/'supervisor.pid').write_text('30 200\n',newline='\n')
 (run3/'limit').write_text('0\n',newline='\n')
 c=(run3/'session-common.sh').read_text('utf-8')
 c=c.replace('kill() { echo "$*" >> "$RUN/trace"; return 0; }', '\n'.join([
 'kill() {', ' echo "$*" >> "$RUN/trace"',
 ' if [ "$1" = -0 ]; then [ "$2" != 30 ] || [ ! -f "$RUN/parent-dead" ]; return $?; fi', ' return 0', '}']))
 c=c.replace('sleep() { :; }', 'ticks=0\nsleep() { ticks=$((ticks+1)); if [ "$ticks" -ge 185 ]; then : > "$RUN/parent-dead"; fi; }')
 (run3/'session-common.sh').write_text(c,encoding='utf-8',newline='\n')
 f=run3/'guard.sh';f.write_text(guard.replace(posix(run),posix(run3)),encoding='utf-8',newline='\n')
 proc=subprocess.run([SH,'-c',f"export PATH=/usr/bin:/bin:$PATH; /bin/sh '{posix(f)}' '{posix(run3)}'"],capture_output=True,text=True,timeout=10)
 assert proc.returncode==0,(proc.stdout,proc.stderr)
 trace=(run3/'trace').read_text()
 assert (run3/'parent-dead').exists() and (run3/'recovery.done').exists()
 assert '-TERM 30' not in trace and '-CONT 20' in trace,trace
 print('PASS watchdog: unlimited session survives 180 ticks and restores UI after parent death')
 # A dead power subscriber must not leave a dashboard that cannot observe wake/sleep.
 run4=base/'monitor-dead';shutil.copytree(run,run4)
 for name in ['recovery.done','guard.ready','trace','recovery-worker.pid']:
  (run4/name).unlink(missing_ok=True)
 (run4/'supervisor.pid').write_text('30 200\n',newline='\n')
 (run4/'power-monitor.pid').write_text('40 999\n',newline='\n')
 (run4/'power-monitor.ready').touch();(run4/'limit').write_text('0\n',newline='\n')
 c=(run4/'session-common.sh').read_text('utf-8')
 c=c.replace('kill() { echo "$*" >> "$RUN/trace"; return 0; }', 'kill() { echo "$*" >> "$RUN/trace"; [ "$1:$2" != "-0:40" ]; }')
 (run4/'session-common.sh').write_text(c,encoding='utf-8',newline='\n')
 f=run4/'guard.sh';f.write_text(guard.replace(posix(run),posix(run4)),encoding='utf-8',newline='\n')
 proc=subprocess.run([SH,'-c',f"export PATH=/usr/bin:/bin:$PATH; /bin/sh '{posix(f)}' '{posix(run4)}'"],capture_output=True,text=True,timeout=10)
 assert proc.returncode==0,(proc.stdout,proc.stderr)
 assert (run4/'recovery.done').exists() and '-CONT 20' in (run4/'trace').read_text()
 print('PASS watchdog: dead power subscriber restores original UI')
 # Normal recovery owns the lock: a deliberately stopped subscriber is not a fault.
 run5=base/'normal-cleanup';shutil.copytree(run4,run5)
 for name in ['recovery.done','guard.ready','trace','recovery-worker.pid']:
  (run5/name).unlink(missing_ok=True)
 (run5/'recover.pid').write_text('50 200\n',newline='\n')
 c=(run5/'session-common.sh').read_text('utf-8').replace('sleep() { :; }', 'ticks=0; sleep() { ticks=$((ticks+1)); if [ "$ticks" -ge 2 ]; then : > "$RUN/recovery.done"; fi; }')
 (run5/'session-common.sh').write_text(c,encoding='utf-8',newline='\n')
 f=run5/'guard.sh';f.write_text(guard.replace(posix(run),posix(run5)),encoding='utf-8',newline='\n')
 proc=subprocess.run([SH,'-c',f"export PATH=/usr/bin:/bin:$PATH; /bin/sh '{posix(f)}' '{posix(run5)}'"],capture_output=True,text=True,timeout=10)
 assert proc.returncode==0,(proc.stdout,proc.stderr)
 assert not (run5/'trace').exists() or '-TERM 30' not in (run5/'trace').read_text()
 print('PASS watchdog: normal cleanup suppresses subscriber-death recovery')
 # Restore a fake framebuffer before resuming any original painter, then flash twice.
 run6=base/'frame';run6.mkdir();(run6/'ui.intent').touch();(run6/'stock.fb').write_text('original')
 fb=run6/'fake-fb';fb.write_text('kdash');(run6/'ui.pids').write_text('20 200 awesome\n',newline='\n')
 (run6/'fbink').write_text('#!/bin/sh\necho "flash $*" >> "$(dirname "$0")/trace"\n',newline='\n')
 code='export PATH=/usr/bin:/bin:$PATH\n'+common.replace('/dev/fb0',posix(fb))+f"""
RUN='{posix(run6)}';LOG="$RUN/log";DATA="$RUN"
pid_stamp() {{ echo 200; }}
kill() {{ if [ "$1" = -CONT ]; then [ "$(cat '{posix(fb)}')" = original ] || exit 70; fi; }}
sleep() {{ :; }}
awk() {{ echo S; }}
pidof() {{ echo 20; }}
lipc-set-prop() {{ :; }}
recover
"""
 proc=subprocess.run([SH,'-c',code],capture_output=True,text=True,timeout=10)
 assert proc.returncode==0,(proc.returncode,proc.stdout,proc.stderr,(run6/'log').read_text() if (run6/'log').exists() else '')
 assert fb.read_text()=='original' and (run6/'trace').read_text().count('flash ')==2
 assert not (run6/'stock.fb').exists()
 print('PASS recovery: snapshot restored before stock resume, two full flashes, snapshot removed')
print('PASS: 10 shell mock scenarios (not Linux device/process validation)')
