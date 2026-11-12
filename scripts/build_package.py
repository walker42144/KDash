from pathlib import Path
import hashlib,json,shutil,zipfile,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT.parent
STAGE=OUT/'KDash-USB-candidate'
assert STAGE.resolve().parent==OUT.resolve() and STAGE.name=='KDash-USB-candidate'
required=['screensaver/wallpaper.y8','assets/fonts/SourceHanSansCN-Medium.ttf','assets/fonts/KumbhSans-500.ttf','assets/fonts/KumbhSans-600.ttf','launcher/command-timeout.sh']
for name in required:
 if not (ROOT/name).is_file():raise SystemExit('BUILD FAILED: required resource missing: '+name)
if (ROOT/'screensaver/wallpaper.y8').stat().st_size!=1072*1448:raise SystemExit('BUILD FAILED: wallpaper.y8 must be 1072x1448 Y8')
if STAGE.exists():shutil.rmtree(STAGE)
PKG=STAGE/'kdash-candidate/package';APP=PKG/'app'
for name in ['main.lua','VERSION','config','core','platform','ui','modules','services','assets']:
 src=ROOT/name;dst=APP/name
 if src.is_dir():shutil.copytree(src,dst,ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
 else:dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
for name in ['luajit','fbink','libfreetype.so.6','libz.so.1','FreeType-FTL.txt','zlib-LICENSE.txt','THIRD_PARTY.md','FBInk-LICENSE','LuaJIT-COPYING']:
 dst=PKG/'runtime'/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/'vendor'/name,dst)
for name in ['kdash-launch.sh','session-common.sh','session-guard.sh','power-control.sh','power-monitor.sh','command-timeout.sh']:
 dst=PKG/'launcher'/name;dst.parent.mkdir(exist_ok=True);shutil.copyfile(ROOT/'launcher'/name,dst)
shutil.copyfile(ROOT/'launcher/session-limit',PKG/'session-limit')
shutil.copyfile(ROOT/'launcher/diagnose.sh',PKG/'diagnose.sh')
for src,name in [('library-entry.sh','Kindle Dashboard Candidate.sh'),('library-recover.sh','KDash Candidate Recovery.sh'),('library-diagnostics.sh','KDash Candidate Diagnostics.sh')]:
 dst=STAGE/'documents'/name;dst.parent.mkdir(exist_ok=True);shutil.copyfile(ROOT/'launcher'/src,dst)
shutil.copyfile(ROOT/'config/default.json',STAGE/'kdash-candidate/config.json')
wallpaper=ROOT/'screensaver/wallpaper.ttf'
(STAGE/'kdash-candidate/screensaver').mkdir(parents=True,exist_ok=True)
if wallpaper.exists():
 dst=STAGE/'kdash-candidate/screensaver/wallpaper.ttf';dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(wallpaper,dst)
wallpaper_raw=ROOT/'screensaver/wallpaper.y8'
if wallpaper_raw.exists():shutil.copyfile(wallpaper_raw,STAGE/'kdash-candidate/screensaver/wallpaper.y8')
manifest=[]
for f in sorted(STAGE.rglob('*')):
 if not f.is_file():continue
 if f.suffix=='.sh' or f.name=='session-limit':f.write_bytes(f.read_bytes().removeprefix(b'\xef\xbb\xbf').replace(b'\r\n',b'\n'))
 manifest.append({'path':f.relative_to(STAGE).as_posix(),'bytes':f.stat().st_size,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()})
(STAGE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
archive=OUT/'KDash-0.1.1-candidate1-USB.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for f in sorted(STAGE.rglob('*')):
  if f.is_file():
   rel=f.relative_to(STAGE).as_posix();info=zipfile.ZipInfo(rel);info.create_system=3
   executable=f.suffix=='.sh' or rel in ['kdash-candidate/package/runtime/luajit','kdash-candidate/package/runtime/fbink']
   info.external_attr=(0o100755 if executable else 0o100644)<<16;info.compress_type=zipfile.ZIP_DEFLATED
   z.writestr(info,f.read_bytes())
with zipfile.ZipFile(archive) as z:
 assert z.testzip() is None
 for m in manifest:assert hashlib.sha256(z.read(m['path'])).hexdigest()==m['sha256']
(OUT/'KDash-0.1.1-candidate1-USB.sha256').write_text(hashlib.sha256(archive.read_bytes()).hexdigest()+'  '+archive.name+'\n',encoding='ascii',newline='\n')
print('BUILD PASS',archive,'files=',len(manifest),'bytes=',archive.stat().st_size)
