from pathlib import Path
import subprocess,sys,os
root=Path(__file__).resolve().parents[1]
subprocess.check_call([sys.executable,'-m','PyInstaller','--noconfirm','--onefile','--windowed','--name',os.getenv('KDASH_CONFIG_EXE_NAME','KDash-Config'),'--icon',str(root/'assets/logo.ico'),'--add-data',str(root/'assets/logo.png')+':.','--add-data',str(root/'config/default.json')+':config','--distpath',str(root.parent),'--workpath',str(root.parent.parent/'work/pc-build'),'--specpath',str(root.parent.parent/'work'),str(root/'pc_tool/configurator.py')])
