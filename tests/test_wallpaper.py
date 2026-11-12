"""Host-only regression: dense supplied wallpaper must render through FreeType."""
from pathlib import Path
import importlib.util,tempfile
from PIL import Image,ImageDraw,ImageFont
from fontTools.ttLib import TTFont
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('wallpaper',root/'scripts/prepare_wallpaper.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
with tempfile.TemporaryDirectory(prefix='kdash-wallpaper-') as tmp:
    target=Path(tmp)/'wallpaper.ttf';expected=m.prepare(root/'screensaver/source.jpg',target)
    font=TTFont(target)
    for name in font.getGlyphOrder():
        glyph=font['glyf'][name]
        assert glyph.numberOfContours<4095, name
    actual=Image.new('L',(1072,1448),255);draw=ImageDraw.Draw(actual)
    face=ImageFont.truetype(str(target),181)
    for i in range(64):draw.text((i%8*134,i//8*181+181),chr(33+i),font=face,fill=0,anchor='ls')
    assert actual.convert('1').tobytes()==expected.tobytes()
print('PASS: supplied wallpaper, 64 glyph tiles, host FreeType output pixel-exact')
