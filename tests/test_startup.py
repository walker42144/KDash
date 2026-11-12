from pathlib import Path
import subprocess,tempfile,shutil
ROOT=Path(__file__).resolve().parents[1];SH=shutil.which('sh') or r'C:\Program Files\Git\usr\bin\sh.exe'
def posix(p):
 s=str(p.resolve()).replace('\\','/');return '/'+s[0].lower()+s[2:] if s[1]==':' else s
launch=(ROOT/'launcher/kdash-launch.sh').read_text('utf-8');prefix=launch[:launch.index('RUN=$(mktemp')]
with tempfile.TemporaryDirectory(prefix='kdash-lock-') as tmp:
 for scenario in ['fresh','orphan','recovering','healthy','starting','stopping','completed','invalid-path']:
  base=Path(tmp)/scenario;pkg=base/'pkg';(pkg/'launcher').mkdir(parents=True);data=base/'data';data.mkdir();run=base/'run.old';run.mkdir()
  if scenario!='fresh':
   (base/'session.lock').mkdir();(base/'session.lock/run').write_text(posix(run) if scenario!='invalid-path' else '/tmp/not-owned')
  common='''alive() {
 p=123
 case "$1" in
 */recover.pid) [ "$CASE" = recovering ] && [ ! -f "$BASE/ticked" ];;
 */supervisor.pid) case "$CASE" in healthy|starting|stopping) return 0;; *) return 1;; esac;;
 */app.pid) [ "$CASE" = healthy ];;
 esac
}
recover() { echo recover >> "$BASE/trace"; rm -f "$BASE/session.lock/run"; rmdir "$BASE/session.lock"; }
kill() { echo "$*" >> "$BASE/trace"; }
'''
  (pkg/'launcher/session-common.sh').write_text(common,encoding='utf-8',newline='\n')
  if scenario in ['healthy','stopping']:(run/'app.pid').touch()
  if scenario=='stopping':(run/'stop.request').touch()
  if scenario=='completed':(run/'recovery.done').touch()
  script=('export PATH=/usr/bin:/bin:$PATH\n'+prefix).replace('PKG=$(CDPATH=\'\' cd "$(dirname "$0")/.." && pwd -P)',"PKG='"+posix(pkg)+"'").replace('DATA=/mnt/us/kdash-candidate',"DATA='"+posix(data)+"'").replace('BASE=/var/tmp/kdash-candidate',"BASE='"+posix(base)+"'")
  # Accelerate deterministic wait; emulate recovery finishing after a tick.
  script=script.replace('attempt=0',f'''CASE='{scenario}'
sleep() {{
 : > "$BASE/ticked"
 case "$CASE" in recovering|stopping) rm -f "$BASE/session.lock/run";rmdir "$BASE/session.lock";; esac
}}
attempt=0''')
  script+='echo acquired\n';f=base/'launch-test.sh';f.write_text(script,encoding='utf-8',newline='\n')
  result=subprocess.run([SH,posix(f)],capture_output=True,text=True,timeout=10)
  success=scenario not in ['healthy','starting','invalid-path']
  assert (result.returncode==0)==success,(scenario,result.stdout,result.stderr)
  if success:assert 'acquired' in result.stdout
  trace=(base/'trace').read_text() if (base/'trace').exists() else ''
  if scenario in ['healthy','starting','invalid-path']:assert not trace
  if scenario=='orphan':assert 'recover' in trace
  print('PASS startup lock:',scenario)
print('PASS 8 startup ownership/recovery scenarios; no device access')
