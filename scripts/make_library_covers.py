"""Distinct grayscale library covers; generated from native vector shapes, no AI bitmap dependency."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import math
root=Path(__file__).resolve().parents[1];assets=root/'assets';fontpath=str(assets/'fonts/NotoSansSC-Regular.otf')
items=[('dashboard','信息面板','时间 / 日期 / 事件倒计时','面板'),('diagnostics','设备诊断','读取设备能力与诊断日志','诊断'),('recovery','恢复界面','退出并恢复 Kindle 原版界面','恢复')]
previews=[]
for kind,title,subtitle,tag in items:
 im=Image.new('L',(600,800),255);d=ImageDraw.Draw(im)
 if kind=='dashboard':
  d.rectangle((174,130,426,382),fill=0)
  d.ellipse((204,160,396,352),outline=255,width=13)
  d.line((300,190,300,258,350,288),fill=255,width=15)
 elif kind=='diagnostics':
  d.ellipse((165,115,365,315),outline=0,width=17)
  d.line((340,290,430,380),fill=0,width=28)
  for y,w in [(175,90),(215,120),(255,70)]:d.line((207,y,207+w,y),fill=0,width=10)
 else:
  d.arc((182,130,418,366),start=45,end=310,fill=0,width=24)
  d.polygon([(405,128),(416,232),(330,201)],fill=0)
  d.line((248,266,292,310,360,222),fill=0,width=15)
  d.rectangle((18,18,581,781),outline=0,width=8)
 def centered(text,y,size,fill=0):
  font=ImageFont.truetype(fontpath,size);b=d.textbbox((0,0),text,font=font);d.text(((600-(b[2]-b[0]))/2,y),text,fill=fill,font=font)
 centered(title,440,64);centered(subtitle,548,27)
 d.rectangle((170,640,430,728),fill=0);centered(tag,644,51,255)
 centered('KDASH',752,19)
 im.save(assets/f'cover-{kind}-v2.png');previews.append(im.resize((300,400)))
contact=Image.new('L',(940,420),230)
for i,im in enumerate(previews):contact.paste(im,(10+i*310,10))
contact.save(root.parent/'三个入口封面.png')
print('Three distinct covers generated')
