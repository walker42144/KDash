-- The KPW3 framebuffer ABI is 32-bit Linux. This adapter never guesses offsets.
local ffi=require('ffi');local B={};B.__index=B
ffi.cdef[[
struct kd_fb_bitfield {unsigned int offset,length,msb_right;};
struct kd_fb_var {unsigned int xres,yres,xres_virtual,yres_virtual,xoffset,yoffset,bits_per_pixel,grayscale;struct kd_fb_bitfield red,green,blue,transp;unsigned int nonstd,activate,height,width,accel_flags,pixclock,left_margin,right_margin,upper_margin,lower_margin,hsync_len,vsync_len,sync,vmode,rotate,colorspace,reserved[4];};
struct kd_fb_fix {char id[16];unsigned long smem_start;unsigned int smem_len,type,type_aux,visual;unsigned short xpanstep,ypanstep,ywrapstep;unsigned int line_length;unsigned long mmio_start;unsigned int mmio_len,accel;unsigned short capabilities,reserved[2];};
int open(const char*,int,...);int close(int);int ioctl(int,unsigned long,...);
void *mmap(void*,unsigned long,int,int,int,long);int munmap(void*,unsigned long);
]]
function B.validate(v,f)
 assert(v.xres==1072 and v.yres==1448 and v.bits_per_pixel==8,'unsupported visible framebuffer geometry')
 assert(v.rotate==3,'unreviewed framebuffer rotation')
 assert(f.line_length==1088 and v.xres_virtual==1088 and v.yres_virtual==6144,'unreviewed framebuffer stride/allocation')
 assert(v.xoffset+v.xres<=v.xres_virtual and v.yoffset+v.yres<=v.yres_virtual,'framebuffer viewport outside allocation')
 assert(f.smem_len>=f.line_length*(v.yoffset+v.yres),'framebuffer memory too short')
 return {width=1072,height=1448,stride=1088,xoffset=tonumber(v.xoffset),yoffset=tonumber(v.yoffset),length=tonumber(f.smem_len)}
end
function B.new()
 assert(ffi.os=='Linux' and ffi.abi('32bit'),'framebuffer requires reviewed 32-bit Linux ABI')
 assert(ffi.sizeof('struct kd_fb_var')==160 and ffi.sizeof('struct kd_fb_fix')==68,'framebuffer ABI size mismatch')
 local self=setmetatable({},B);self.fd=ffi.C.open('/dev/fb0',2);assert(self.fd>=0,'cannot open framebuffer')
 local v=ffi.new('struct kd_fb_var[1]');local f=ffi.new('struct kd_fb_fix[1]')
 local ok,err=pcall(function()
  assert(ffi.C.ioctl(self.fd,0x4600,v)==0 and ffi.C.ioctl(self.fd,0x4602,f)==0,'framebuffer ioctl failed')
  self.geometry=B.validate(v[0],f[0]);self.length=self.geometry.length
  self.map=ffi.C.mmap(nil,self.length,3,1,self.fd,0)
  assert(self.map~=ffi.cast('void*',-1),'framebuffer mmap failed')
  self.bytes=ffi.cast('unsigned char*',self.map)
 end)
 if not ok then self:close();error(err) end
 return self
end
function B:commit(buf)
 local g=self.geometry
 for y=0,g.height-1 do ffi.copy(self.bytes+(y+g.yoffset)*g.stride+g.xoffset,buf+y*g.width,g.width) end
end
function B:close()
 if self.map and self.map~=ffi.cast('void*',-1) then ffi.C.munmap(self.map,self.length);self.map=nil end
 if self.fd and self.fd>=0 then ffi.C.close(self.fd);self.fd=nil end
end
return B
