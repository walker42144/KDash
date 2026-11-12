local ffi=require('ffi');ffi.cdef[[int memcmp(const void*,const void*,size_t);]];local D={};D.__index=D
function D.new(o)
 local self=setmetatable({width=o.width or 1072,height=o.height or 1448,runner=o.runner,fbink=o.fbink,log=o.log,
  available=true,partial_count=0,full_refresh_every=o.full_refresh_every or 24,out=o.out,fonts=o.fonts},D)
 self.font=require('platform.kindle.freetype').new(o.fonts)
 self.canvas=require('ui.canvas').new(self.width,self.height,self.font)
 if o.device then self.fb=require('platform.kindle.framebuffer').new() end
 self.dirty={};return self
end
function D:measure(text,size) return self.font:measure(text,size) end
function D:begin_frame(full)
 self.dirty={}
 if full then self.canvas:fill({x=0,y=0,w=self.width,h=self.height},'paper');self:add_dirty(0,0,self.width,self.height) end
end
function D:add_dirty(x,y,w,h)
 x,y,w,h=math.floor(x),math.floor(y),math.ceil(w),math.ceil(h)
 local x0,y0=math.max(0,x),math.max(0,y);local x1,y1=math.min(self.width,x+w),math.min(self.height,y+h)
 if x1>x0 and y1>y0 then self.dirty[#self.dirty+1]={x=x0,y=y0,w=x1-x0,h=y1-y0} end
end
function D:fill(r,c) self.canvas:fill(r,c);self:add_dirty(r.x,r.y,r.w,r.h) end
function D:hline(x,y,w,t,c) self:fill({x=x,y=y,w=w,h=t or 2},c) end
function D:vline(x,y,h,t,c) self:fill({x=x,y=y,w=t or 2,h=h},c) end
function D:text(o)
 self.canvas:text(o);self:add_dirty(o.x or 0,o.y or 0,o.w or self.width,math.max(o.h or 0,(o.size or 32)*1.35))
end
function D:icon(path,x,y,w,h) self:text({font=path,text='A',x=x,y=y,w=w,h=h,size=h,baseline=h}) end
function D:line(x0,y0,x1,y1,c,w,dash)
 self.canvas:line(x0,y0,x1,y1,c,w,dash);self:add_dirty(math.min(x0,x1)-4,math.min(y0,y1)-4,math.abs(x1-x0)+8,math.abs(y1-y0)+8)
end
function D:circle(x,y,r,c,filled,w) self.canvas:circle(x,y,r,c,filled,w);self:add_dirty(x-r-4,y-r-4,r*2+8,r*2+8) end
function D:prepare_screensaver(dir)
 local f=assert(io.open(dir..'/screensaver/wallpaper.y8','rb'),'wallpaper.y8 missing')
 local raw=f:read('*a');f:close();assert(#raw==self.width*self.height,'invalid wallpaper dimensions');self.wallpaper=raw
end
function D:show_screensaver()
 assert(self.wallpaper,'screensaver not preloaded');self.dashboard=self.canvas:string();self.canvas:load(self.wallpaper)
 self.dirty={};self:add_dirty(0,0,self.width,self.height);return self:flush({full=true,flash=true,screensaver=true})
end
function D:restore_dashboard()
 if not self.dashboard then return false end
 self.canvas:load(self.dashboard);self.dashboard=nil;self.dirty={};self:add_dirty(0,0,self.width,self.height);return self:flush({full=true})
end
function D:flush(o)
 o=o or {};if #self.dirty==0 then return true end
 if self.out then self.canvas:save(self.out) end
 if self.fb then
  local x,y,x1,y1=self.width,self.height,0,0
  if self.last_pixels and not o.full then
   for row=0,self.height-1 do
    local pos=row*self.width
    if ffi.C.memcmp(self.canvas.buf+pos,self.last_pixels+pos,self.width)~=0 then
     local left,right=0,self.width-1
     while left<right and self.canvas.buf[pos+left]==self.last_pixels[pos+left] do left=left+1 end
     while right>left and self.canvas.buf[pos+right]==self.last_pixels[pos+right] do right=right-1 end
     x,y,x1,y1=math.min(x,left),math.min(y,row),math.max(x1,right+1),math.max(y1,row+1)
    end
   end
   if x1<=x then self.dirty={};return true end
  else x,y,x1,y1=0,0,self.width,self.height end
  self.fb:commit(self.canvas.buf)
  self.partial_count=self.partial_count+1
  local argv={self.fbink,'-q','-w','-W','GC16'}
  if o.full or (self.full_refresh_every>0 and self.partial_count%self.full_refresh_every==0) then argv[#argv+1]='-s'
  else argv[#argv+1]=string.format('--refresh=top=%d,left=%d,width=%d,height=%d',y,x,x1-x,y1-y) end
  if o.flash then argv[#argv+1]='-f' end
  local code=self.runner:run(argv,'native canvas refresh')
  if code~=0 then self.available=false;return false end
  self.last_pixels=self.last_pixels or ffi.new('unsigned char[?]',self.width*self.height)
  ffi.copy(self.last_pixels,self.canvas.buf,self.width*self.height)
 end
 self.dirty={};return true
end
function D:close() if self.fb then self.fb:close() end;if self.font then self.font:close() end end
return D
