"""Compile supplied monochrome artwork to an OpenType glyph, without an image decoder on Kindle."""
from pathlib import Path
import sys
from PIL import Image
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
r=Path(__file__).resolve().parents[1];im=Image.open(r/'assets/logo-user.jpg').convert('L');assert im.size==(1024,1024)
# Encode the original ink silhouette as vector rectangles, merging equal runs vertically.
pix=im.load();active={};rects=[]
for y in range(1025):
 runs=set()
 if y<1024:
  x=0
  while x<1024:
   if pix[x,y]>=128:x+=1;continue
   left=x
   while x<1024 and pix[x,y]<128:x+=1
   runs.add((left,x))
 for run,start in list(active.items()):
  if run not in runs:rects.append((run[0],start,run[1],y));del active[run]
 for run in runs:
  if run not in active:active[run]=y
pen=TTGlyphPen(None)
for x0,y0,x1,y1 in rects:
 pen.moveTo((x0,1024-y1));pen.lineTo((x0,1024-y0));pen.lineTo((x1,1024-y0));pen.lineTo((x1,1024-y1));pen.closePath()
fb=FontBuilder(1024,isTTF=True);fb.setupGlyphOrder(['.notdef','face']);fb.setupCharacterMap({65:'face'})
fb.setupGlyf({'.notdef':TTGlyphPen(None).glyph(),'face':pen.glyph()});fb.setupHorizontalMetrics({'.notdef':(1024,0),'face':(1024,0)})
fb.setupHorizontalHeader(ascent=1024,descent=0);fb.setupNameTable({'familyName':'KDash User Face','styleName':'Regular','uniqueFontIdentifier':'KDashUserFace1','fullName':'KDash User Face Regular','psName':'KDashUserFace-Regular'})
fb.setupOS2(sTypoAscender=1024,sTypoDescender=0,sTypoLineGap=0,usWinAscent=1024,usWinDescent=0);fb.setupPost();fb.setupMaxp();fb.save(r/'assets/logo-user.ttf')
print('Compiled exact-size silhouette to glyph:',len(rects),'rectangles')
