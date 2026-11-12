"""Prepare a chosen wallpaper for the Kindle's verified OpenType renderer.
Usage: python prepare_wallpaper.py input.jpg output.ttf [--preview output.png]
Requires Pillow and fontTools on Windows, no image decoder on Kindle.
"""
from pathlib import Path
import argparse
from PIL import Image, ImageOps
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

def prepare(source, target, preview=None):
    with Image.open(source) as image:
        image=ImageOps.fit(ImageOps.exif_transpose(image).convert('L'),(1072,1448),method=Image.Resampling.LANCZOS)
    # JPEG background contains near-white noise. Clean only values >=248;
    # retain the original midtones and never threshold the entire photograph.
    image=image.point(lambda value:255 if value>=248 else value)
    # Keep an 8-bit grayscale asset for the fast canvas path, plus legacy font fallback.
    raw=image.tobytes();raw_path=Path(target).with_suffix('.y8');raw_path.parent.mkdir(parents=True,exist_ok=True);raw_path.write_bytes(raw)
    image=image.convert('1',dither=Image.Dither.FLOYDSTEINBERG)
    if preview: image.save(preview)
    names=['.notdef']+[f'tile{i}' for i in range(64)]
    glyphs={'.notdef':TTGlyphPen(None).glyph()};metrics={'.notdef':(134,0)}
    for i in range(64):
        tile=image.crop(((i%8)*134,(i//8)*181,(i%8+1)*134,(i//8+1)*181))
        pix=tile.load();active={};rects=[]
        for y in range(182):
            runs=set();x=0
            while y<181 and x<134:
                if pix[x,y]: x+=1;continue
                start=x
                while x<134 and not pix[x,y]: x+=1
                runs.add((start,x))
            for run,start in list(active.items()):
                if run not in runs: rects.append((run[0],start,run[1],y));del active[run]
            for run in runs:active.setdefault(run,y)
        # FreeType rejects >=4095 contours in a simple glyph. Dense dithering
        # uses small component glyphs while preserving the 64 public tile glyphs.
        components=[]
        for part in range(0,len(rects),1000):
            pen=TTGlyphPen(None)
            for x0,y0,x1,y1 in rects[part:part+1000]:
                pen.moveTo((x0,181-y1));pen.lineTo((x0,181-y0));pen.lineTo((x1,181-y0));pen.lineTo((x1,181-y1));pen.closePath()
            name=f'tile{i}_part{part//1000}'
            glyph=pen.glyph();glyph.recalcBounds(None)
            glyphs[name]=glyph;metrics[name]=(134,getattr(glyph,'xMin',0));components.append(name)
        pen=TTGlyphPen(glyphs)
        for name in components:pen.addComponent(name,(1,0,0,1,0,0))
        glyph=pen.glyph();glyph.recalcBounds(glyphs)
        glyphs[names[i+1]]=glyph;metrics[names[i+1]]=(134,getattr(glyph,'xMin',0))
    names+=sorted(set(glyphs)-set(names))
    fb=FontBuilder(181,isTTF=True);fb.setupGlyphOrder(names)
    fb.setupCharacterMap({33+i:names[i+1] for i in range(64)})
    fb.setupGlyf(glyphs);fb.setupHorizontalMetrics(metrics);fb.setupHorizontalHeader(ascent=181,descent=0)
    fb.setupNameTable({'familyName':'KDASH Screensaver','styleName':'Regular','uniqueFontIdentifier':'KDASH-Screensaver1','fullName':'KDASH Screensaver Regular','psName':'KDASH-Screensaver'})
    fb.setupOS2(sTypoAscender=181,sTypoDescender=0,sTypoLineGap=0,usWinAscent=181,usWinDescent=0)
    fb.setupPost();fb.setupMaxp();Path(target).parent.mkdir(parents=True,exist_ok=True);fb.save(target)
    return image

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('input');p.add_argument('output');p.add_argument('--preview');a=p.parse_args()
    prepare(a.input,a.output,a.preview);print('Prepared 1072x1448 monochrome wallpaper, 64 glyph tiles:',a.output)
