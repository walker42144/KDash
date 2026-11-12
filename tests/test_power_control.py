"""Mock powerd IPC and test stale-request rejection without touching any device."""
from pathlib import Path
import subprocess,tempfile,shutil
root=Path(__file__).resolve().parents[1];sh=shutil.which('sh') or r'C:\Program Files\Git\usr\bin\sh.exe'
def posix(p):
 s=str(p.resolve()).replace('\\','/');return '/'+s[0].lower()+s[2:]
for name,target,state,stale,expected in [('sleep','sleep','active',False,True),('settled','sleep','screenSaver',False,False),('wake','wake','screenSaver',False,True),('stale','sleep','active',True,False),('ignore','ignore','active',False,False)]:
 with tempfile.TemporaryDirectory(prefix='kdash-power-') as tmp:
  run=Path(tmp);(run/'logs').mkdir();(run/'power.desired').write_text('1 '+target+'\n',newline='\n')
  code=f'''pid_stamp() {{ echo 200; }}
record_pid() {{ echo "$2 200" > "$1"; }}
log() {{ echo "$*" >> "$RUN/logs/session.log"; }}
lipc-get-prop() {{ {'echo "2 wake" > "$RUN/power.desired";' if stale else ''} echo {state}; }}
lipc-set-prop() {{ echo "$*" >> "$RUN/trace"; }}
sleep() {{ : > "$RUN/stop.request"; }}
'''
  (run/'session-common.sh').write_text(code,encoding='utf-8',newline='\n')
  src=(root/'launcher/power-control.sh').read_text('utf-8-sig').replace('DATA=/mnt/us/kdash-candidate',f"DATA='{posix(run)}'")
  script=run/'control.sh';script.write_text(src,'utf-8',newline='\n')
  p=subprocess.run([sh,'-c',f"export PATH=/usr/bin:/bin:$PATH; /bin/sh '{posix(script)}' '{posix(run)}'"],capture_output=True,text=True,timeout=10)
  assert p.returncode==0,(name,p.stdout,p.stderr)
  assert (run/'trace').exists()==expected,name
  print('PASS async power:',name)
print('PASS: 5 async power mock scenarios; no device access')
