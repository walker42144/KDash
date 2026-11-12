"""Build static fonts on the PC; never instantiate variable fonts on the Kindle.
Inputs: official KumbhSans[YOPQ,wght].ttf (wght=500/600,YOPQ=300), and
SourceHanSansCN-VF.ttf (wght=500). Source Han's reserved name is not used by
the derived static font's family names. Outlines are unchanged instance data.
Usage: python prepare_fonts.py --inputs PATH_CONTAINING_VF_FILES
Requires fontTools; source URLs below identify reproducible upstream inputs.
"""
from pathlib import Path
import argparse
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
SOURCES={
 'KumbhSans-VF.ttf':'https://raw.githubusercontent.com/google/fonts/main/ofl/kumbhsans/KumbhSans%5BYOPQ%2Cwght%5D.ttf',
 'SourceHanSansCN-VF.ttf':'https://raw.githubusercontent.com/adobe-fonts/source-han-sans/release/Variable/TTF/Subset/SourceHanSansCN-VF.ttf'}
def rename(f,family,style,ps):
 for n in f['name'].names:
  value={1:family,2:style,3:ps+'-r12',4:family+' '+style,6:ps,16:family,17:style}.get(n.nameID)
  if value is not None:n.string=value.encode(n.getEncoding(),errors='replace')
def build(inputs,out):
 for weight,style in [(500,'Medium'),(600,'SemiBold')]:
  f=instantiateVariableFont(TTFont(inputs/'KumbhSans-VF.ttf'),{'wght':weight,'YOPQ':300},inplace=True)
  rename(f,'Kumbh Sans',style,'KumbhSans-'+style);f.save(out/f'KumbhSans-{weight}.ttf')
 f=instantiateVariableFont(TTFont(inputs/'SourceHanSansCN-VF.ttf'),{'wght':500},inplace=True)
 rename(f,'KDASH Han SC','Medium','KDASHHanSC-Medium');f.save(out/'SourceHanSansCN-Medium.ttf')
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--inputs',type=Path,required=True);a=p.parse_args()
 build(a.inputs,Path(__file__).resolve().parents[1]/'assets/fonts')
