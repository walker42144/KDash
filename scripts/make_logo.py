from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
root=Path(__file__).resolve().parents[1]
p=root/'assets'; p.mkdir(exist_ok=True)
svg='''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 56 56"><rect width="56" height="56" fill="black"/><g fill="white"><path d="M8 8h24v24H8zM38 8h10v24H38zM8 39h40v3H8zM8 47h27v3H8z"/></g><path d="M19 12h3v9h6v3h-9z" fill="black"/></svg>'''
(p/'logo.svg').write_text(svg,encoding='utf-8',newline='\n')
logo=Image.new('L',(448,448),0); d=ImageDraw.Draw(logo)
for x,y,w,h in [(8,8,24,24),(38,8,10,24),(8,39,40,3),(8,47,27,3)]:d.rectangle((x*8,y*8,(x+w)*8-1,(y+h)*8-1),fill=255)
for x,y,w,h in [(19,12,3,11),(19,21,9,3)]:d.rectangle((x*8,y*8,(x+w)*8-1,(y+h)*8-1),fill=0)
logo.save(p/'logo.png')
cover=Image.new('L',(600,800),255); cover.paste(logo.resize((224,224)),(188,130));d=ImageDraw.Draw(cover)
fontpath=str(root/'assets/fonts/NotoSansSC-Regular.otf')
for text,y,size in [('Kindle',430,46),('Dashboard',490,54),('时间 · 日期 · 事件倒计时',605,25),('KDASH  /  CANDIDATE 01',724,20)]:
 font=ImageFont.truetype(fontpath,size); box=d.textbbox((0,0),text,font=font); w=box[2]-box[0]; d.text(((600-w)/2,y),text,font=font,fill=0)
d.line((64,680,536,680),fill=0,width=2); cover.save(p/'cover.png')
print('logo.svg logo.png cover.png generated')
