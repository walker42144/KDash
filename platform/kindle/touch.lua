-- Linux evdev: persistent frames, axis calibration, protocol A/B and single touch.
local Touch = {}; Touch.__index = Touch
function Touch.new(o)
 o=o or {}; return setmetatable({path=o.path,log=o.log,width=o.width or 1072,height=o.height or 1448,
 swap_xy=o.swap_xy,invert_x=o.invert_x,invert_y=o.invert_y,axes=o.axes,
 clock_ms=o.clock_ms or function() return os.time()*1000 end,pending={},raw={slot=0},state={}},Touch)
end
function Touch.decode_event(s)
 if #s~=16 then return nil end
 local function u16(n) return s:byte(n)+s:byte(n+1)*256 end
 local function i32(n) local v=u16(n)+u16(n+2)*65536; return v>=2147483648 and v-4294967296 or v end
 return {sec=i32(1),usec=i32(5),type=u16(9),code=u16(11),value=i32(13)}
end
function Touch:map(x,y)
 local a=self.axes; if not a then return x,y end
 x,y=(x-a.xmin)/(a.xmax-a.xmin),(y-a.ymin)/(a.ymax-a.ymin)
 if x<0 or x>1 or y<0 or y>1 then return nil end
 if self.swap_xy then x,y=y,x end
 if self.invert_x then x=1-x end; if self.invert_y then y=1-y end
 return math.floor(x*(self.width-1)+.5),math.floor(y*(self.height-1)+.5)
end
function Touch:_emit(p)
 local s,now=self.state,self.clock_ms()
 if p.down then
  if not s.down then s.start_x,s.start_y,s.start_ms=p.x,p.y,now end
  s.down,s.x,s.y=true,p.x,p.y
 elseif s.down then
  local x,y=s.start_x,s.start_y; local dx,dy=(s.x or x)-x,(s.y or y)-y; s.down=false
  if math.abs(dx)>120 and math.abs(dx)>math.abs(dy)*1.5 then
   self.pending[#self.pending+1]={type='swipe',direction=dx>0 and 'right' or 'left',x=x,y=y}
  elseif dx*dx+dy*dy<1600 and now-s.start_ms<900 then
   self.pending[#self.pending+1]={type='tap',x=x,y=y}
  end
 end
end
function Touch:feed(records)
 local r=self.raw
 for _,e in ipairs(records) do
  if e.type==0 and e.code==3 then
   self.state={}; r={slot=0,dropped=true}; self.raw=r
  elseif r.dropped then
   if (e.type==1 and e.code==330 and e.value==0) or (e.type==3 and e.code==57 and e.value<0) then r.dropped=false end
  elseif e.type==3 and e.code==47 then
   r.slot=e.value; r.has_slots=true; if e.value~=0 then r.multitouch=true end
  elseif e.type==3 and e.code==57 and (r.slot or 0)==0 then r.tracking=e.value>=0
  elseif e.type==3 and (r.slot or 0)==0 then
   if e.code==(self.xcode or 53) then r.x=e.value; r.frame_x=true end
   if e.code==(self.ycode or 54) then r.y=e.value; r.frame_y=true end
  elseif e.type==1 and e.code==330 then r.button=e.value~=0
  elseif e.type==0 and e.code==2 then
   r.protocol_a=true
   if r.frame_x and r.frame_y then
    r.contacts=(r.contacts or 0)+1; if r.contacts==1 then r.first_x,r.first_y=r.x,r.y end
   end
   r.frame_x,r.frame_y=false,false
  elseif e.type==0 and e.code==0 then
   local down
   if r.button~=nil then down=r.button elseif r.has_slots then down=r.tracking==true
   elseif r.protocol_a then down=(r.contacts or 0)>0 else down=r.tracking==true end
   if r.multitouch or (r.contacts or 0)>1 then self.state={}; r.suppress=true end
   local px,py=r.first_x or r.x,r.first_y or r.y
   if px~=nil and py~=nil and not r.suppress then local x,y=self:map(px,py); if x then self:_emit({x=x,y=y,down=down}) end end
   if not down then r.suppress=false; r.multitouch=false; r.x,r.y=nil,nil end
   r.contacts,r.first_x,r.first_y=nil,nil,nil; r.frame_x,r.frame_y=false,false
  end
 end
 local out=self.pending; self.pending={}; return out
end
function Touch.decode_packet(records)
 local t=Touch.new(); local points={}; t._emit=function(_,p) points[#points+1]=p end
 t:feed(records); return points
end
function Touch:inject(p) self:_emit(p); local out=self.pending; self.pending={}; return out end
function Touch:open(grab)
 local ffi=require('ffi'); if ffi.os~='Linux' or not ffi.abi('32bit') then return false,'requires 32-bit Linux' end
 ffi.cdef[[int open(const char*,int,...); long read(int,void*,unsigned long); int close(int);
 int poll(void*,unsigned long,int); int ioctl(int,unsigned long,...);
 struct kdash_pollfd {int fd; short events; short revents;};
 struct kdash_absinfo {int value,min,max,fuzz,flat,resolution;};]]
 self.ffi=ffi
 local function axis(fd,c)
  local a=ffi.new('struct kdash_absinfo[1]')
  if ffi.C.ioctl(fd,0x80184540+c,a)~=0 or a[0].max<=a[0].min then return nil end
  return tonumber(a[0].min),tonumber(a[0].max)
 end
 for _,path in ipairs(self.path and {self.path} or {'/dev/input/event1','/dev/input/event0','/dev/input/event2'}) do
  local fd=ffi.C.open(path,2048)
  if fd>=0 then
   for _,pair in ipairs({{53,54},{0,1}}) do
    local xmin,xmax=axis(fd,pair[1]); local ymin,ymax=axis(fd,pair[2])
    if xmin and ymin then self.fd,self.path,self.xcode,self.ycode=fd,path,pair[1],pair[2]; self.axes={xmin=xmin,xmax=xmax,ymin=ymin,ymax=ymax}; break end
   end
   if self.fd then break end; ffi.C.close(fd)
  end
 end
 if not self.fd then return false,'no readable coordinate device' end
 if grab~=false and ffi.C.ioctl(self.fd,0x40044590,ffi.cast('int',1))~=0 then self:close(); return false,'EVIOCGRAB failed' end
 self.grabbed=grab~=false; if self.log then self.log:info(self:description()) end; return true
end
function Touch:description()
 local a=self.axes
 return string.format('touch path=%s axes=%s,%s range=%d..%d,%d..%d swap=%s invert=%s,%s',self.path or '?',self.xcode or '?',self.ycode or '?',a.xmin,a.xmax,a.ymin,a.ymax,tostring(self.swap_xy==true),tostring(self.invert_x==true),tostring(self.invert_y==true))
end
function Touch:poll(timeout)
 if not self.fd then return {} end
 local ffi=self.ffi; local p=ffi.new('struct kdash_pollfd[1]'); p[0].fd=self.fd; p[0].events=1
 local n=ffi.C.poll(p,1,timeout or 0); if n<0 then if ffi.errno()==4 then return {} end;error('touch poll failed') end; if n==0 or tonumber(p[0].revents)==0 then return {} end
 if tonumber(p[0].revents)~=1 then error('touch disconnected') end
 local b=ffi.new('unsigned char[16]'); local records={}
 for _=1,512 do
  local got=tonumber(ffi.C.read(self.fd,b,16)); if got<0 and (ffi.errno()==11 or ffi.errno()==4) then break end
  if got~=16 then self.state={};self.raw={slot=0};self.pending={};error('touch short read/disconnected') end
  records[#records+1]=assert(Touch.decode_event(ffi.string(b,16)))
 end
 return self:feed(records)
end
function Touch:close()
 if self.fd then
  if self.grabbed then self.ffi.C.ioctl(self.fd,0x40044590,self.ffi.cast('int',0)) end
  self.ffi.C.close(self.fd); self.fd=nil
 end
end
return Touch
