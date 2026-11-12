-- FreeType's public ABI. The same engine is exercised with a Windows DLL on host
-- and KOReader's existing libfreetype.so.6 on this 32-bit Kindle.
local ffi=require('ffi')
ffi.cdef[[
typedef struct {void *data; void (*finalizer)(void*);} kd_ft_generic;
typedef struct {long xMin,yMin,xMax,yMax;} kd_ft_bbox;
typedef struct {long x,y;} kd_ft_vector;
typedef struct {long width,height,horiBearingX,horiBearingY,horiAdvance,vertBearingX,vertBearingY,vertAdvance;} kd_ft_metrics;
typedef struct {unsigned int rows,width;int pitch;unsigned char *buffer;unsigned short num_grays;unsigned char pixel_mode,palette_mode;void *palette;} kd_ft_bitmap;
typedef struct kd_ft_face_rec *kd_ft_face;
typedef struct kd_ft_slot_rec *kd_ft_slot;
struct kd_ft_slot_rec {void *library;kd_ft_face face;kd_ft_slot next;unsigned int glyph_index;kd_ft_generic generic;kd_ft_metrics metrics;long linearHoriAdvance,linearVertAdvance;kd_ft_vector advance;unsigned int format;kd_ft_bitmap bitmap;int bitmap_left,bitmap_top;};
struct kd_ft_face_rec {long num_faces,face_index,face_flags,style_flags,num_glyphs;char *family_name,*style_name;int num_fixed_sizes;void *available_sizes;int num_charmaps;void *charmaps;kd_ft_generic generic;kd_ft_bbox bbox;unsigned short units_per_EM;short ascender,descender,height,max_advance_width,max_advance_height,underline_position,underline_thickness;kd_ft_slot glyph;void *size,*charmap;};
int FT_Init_FreeType(void **);
int FT_Done_FreeType(void *);
int FT_New_Face(void *,const char *,long,kd_ft_face *);
int FT_Done_Face(kd_ft_face);
int FT_Set_Pixel_Sizes(kd_ft_face,unsigned int,unsigned int);
unsigned int FT_Get_Char_Index(kd_ft_face,unsigned long);
int FT_Load_Char(kd_ft_face,unsigned long,int);
]]
local F={};F.__index=F
function F.new(opts)
 local self=setmetatable({faces={},cache={},cache_n=0,cache_bytes=0,max_cache_bytes=opts.max_cache_bytes or 6*1024*1024},F)
 if ffi.os=='Linux' then self.zlib=ffi.load(os.getenv('KDASH_ZLIB') or '/mnt/us/koreader/libs/libz.so.1',true) end
 self.lib=ffi.load(opts.library or os.getenv('KDASH_FREETYPE') or '/mnt/us/koreader/libs/libfreetype.so.6')
 local p=ffi.new('void*[1]');assert(self.lib.FT_Init_FreeType(p)==0,'FreeType init failed');self.handle=p[0]
 self.cjk=opts.cjk;self.latin=opts.latin;self.display=opts.display or opts.latin
 for _,path in ipairs({self.cjk,self.latin,self.display}) do self:face(path) end
 return self
end
function F:face(path)
 if self.faces[path] then return self.faces[path] end
 local p=ffi.new('kd_ft_face[1]');assert(self.lib.FT_New_Face(self.handle,path,0,p)==0,'cannot load font '..path)
 assert(p[0].units_per_EM>=16 and p[0].units_per_EM<=16384,'unexpected FreeType face ABI')
 self.faces[path]=p[0];return p[0]
end
function F:glyph(cp,size,explicit)
 size=math.max(8,math.floor(size));assert(size<=512,'font size exceeds reviewed limit');local path=explicit
 if not path then
  path=(cp<0x2e80) and (size>=48 and self.display or self.latin) or self.cjk
  if self.lib.FT_Get_Char_Index(self:face(path),cp)==0 then path=self.cjk end
 end
 local key=path..':'..size..':'..cp;if self.cache[key] then return self.cache[key] end
 local face=self:face(path);assert(self.lib.FT_Set_Pixel_Sizes(face,0,size)==0,'font size rejected')
 assert(self.lib.FT_Load_Char(face,cp,4)==0,'glyph rendering failed')
 local slot=face.glyph;local b=slot.bitmap
 assert(b.pixel_mode==2 or b.width==0,'unexpected FreeType bitmap mode')
 assert(tonumber(b.rows)*tonumber(b.width)<=1024*1024,'glyph bitmap exceeds size limit')
 local pixels={}
 for y=0,tonumber(b.rows)-1 do pixels[#pixels+1]=ffi.string(b.buffer+y*b.pitch,tonumber(b.width)) end
 local result={w=tonumber(b.width),h=tonumber(b.rows),left=slot.bitmap_left,top=slot.bitmap_top,advance=tonumber(slot.advance.x)/64,pixels=table.concat(pixels)}
 local bytes=#result.pixels+128+#key
 if self.cache_n>=1800 or self.cache_bytes+bytes>self.max_cache_bytes then self.cache={};self.cache_n=0;self.cache_bytes=0 end
 if bytes<=self.max_cache_bytes then self.cache[key]=result;self.cache_n=self.cache_n+1;self.cache_bytes=self.cache_bytes+bytes end;return result
end
function F:measure(text,size,explicit)
 local n=0;for _,ch in ipairs(require('core.util').utf8_codepoints(text or '')) do n=n+self:glyph(ch.cp,size,explicit).advance end
 return math.ceil(n)
end
function F:close()
 self.cache={};self.cache_n=0;self.cache_bytes=0
 for _,face in pairs(self.faces) do self.lib.FT_Done_Face(face) end;self.faces={}
 if self.handle then self.lib.FT_Done_FreeType(self.handle);self.handle=nil end
end
return F
