from pathlib import Path
import subprocess,tempfile,shutil
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as d:
 out=Path(d)/'home.svg'
 subprocess.check_call([shutil.which('luajit'),str(root/'main.lua'),'--preview','--data-dir',d,'--out',str(out),'--now','1794394800'])
 text=out.read_text('utf-8')
 assert '示例事件' in text and '>1147<' in text and '退出' in text
 assert '请设置目标日期' not in text and 'MODULE ERROR' not in text
 print('PASS candidate preview: 1147 calendar days, direct exit, no module error')
