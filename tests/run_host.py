"""Portable host entry; never deploys, scans USB, or contacts personal APIs."""
from pathlib import Path
import argparse,os,shutil,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
ap=argparse.ArgumentParser();ap.add_argument('--freetype');ap.add_argument('--soak-frames',type=int,default=0);args=ap.parse_args()
env=os.environ.copy()
if args.freetype:env['KDASH_TEST_FREETYPE']=str(Path(args.freetype).resolve())
def run(command):
 print('RUN',*command,flush=True);subprocess.run(command,cwd=ROOT,env=env,check=True,timeout=240)
run(['luajit','tests/run.lua'])
run([sys.executable,'-m','unittest','discover','-s','pc_tool','-p','test*.py'])
for name in ['test_startup.py','test_recovery.py','test_power_control.py','test_review_shell.py','test_http_scripts.py']:
 run([sys.executable,'tests/'+name])
if env.get('KDASH_TEST_FREETYPE'):
 run(['luajit','tests/test_native_canvas.lua','.'])
 if args.soak_frames:run(['luajit','tests/soak_native.lua',str(args.soak_frames)])
else:print('SKIP native FreeType: supply --freetype; no native pass claimed',flush=True)
print('PASS host suite; Kindle power/display/runtime not verified')
