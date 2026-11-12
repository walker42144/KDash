-- Single in-memory Y8 canvas. All geometry is clipped before touching memory.
local ffi=require('ffi');local C={};C.__index=C
local colors={ink=0,paper=255,gray1=48,gray2=100,gray3=145,gray4=190,gray5=220,gray6=238}
function C.new(w,h,font)
 local self=setmetatable({width=w,height=h,font=font},C);self.buf=ffi.new('unsigned char[?]',w*h);ffi.fill(self.buf,w*h,255);return self
end
function C:fill(r,color)
 local x0,y0=math.max(0,math.floor(r.x or 0)),math.max(0,math.floor(r.y or 0))
 local x1,y1=math.min(self.width,math.ceil((r.x or 0)+(r.w or 0))),math.min(self.height,math.ceil((r.y or 0)+(r.h or 0)))
 for y=y0,y1-1 do if x1>x0 then ffi.fill(self.buf+y*self.width+x0,x1-x0,colors[color] or tonumber(color) or 0) end end
end
function C:pixel(x,y,color)
 x,y=math.floor(x+.5),math.floor(y+.5);if x>=0 and y>=0 and x<self.width and y<self.height then self.buf[y*self.width+x]=colors[color] or tonumber(color) or 0 end
end
function C:line(x0,y0,x1,y1,color,width,dashed)
 local length=math.max(math.abs(x1-x0),math.abs(y1-y0));local n=math.max(1,math.ceil(length));width=width or 2
 for i=0,n do if not dashed or math.floor(i/8)%2==0 then self:fill({x=x0+(x1-x0)*i/n-width/2,y=y0+(y1-y0)*i/n-width/2,w=width,h=width},color) end end
end
function C:circle(x,y,r,color,filled,width)
 if filled then
  for yy=math.floor(-r),math.ceil(r) do local xx=math.sqrt(math.max(0,r*r-yy*yy));self:fill({x=x-xx,y=y+yy,w=2*xx+1,h=1},color) end
 else
  local n=math.max(24,math.ceil(r*8));for i=0,n do local a=i*math.pi*2/n;self:fill({x=x+math.cos(a)*r-(width or 2)/2,y=y+math.sin(a)*r-(width or 2)/2,w=width or 2,h=width or 2},color) end
 end
end
-- Supersampled masks are small, color-independent and shared across frames.
local mask_cache={};local mask_bytes,mask_count=0,0
local function mask(key,w,h,inside)
 local found=mask_cache[key];if found then return found end
 local rows={}
 for y=0,h-1 do
  local row={}
  for x=0,w-1 do
   local coverage=0
   for sy=0,3 do for sx=0,3 do if inside(x+(sx+.5)/4,y+(sy+.5)/4) then coverage=coverage+1 end end end
   row[#row+1]=string.char(math.floor(coverage*255/16+.5))
  end
  rows[#rows+1]=table.concat(row)
 end
 local result=table.concat(rows)
 if mask_count>=64 or mask_bytes+#result>256*1024 then mask_cache={};mask_count=0;mask_bytes=0 end
 if #result<=256*1024 then mask_cache[key]=result;mask_bytes=mask_bytes+#result;mask_count=mask_count+1 end
 return result
end
function C:blend_mask(raw,x,y,w,h,color)
 local fg=colors[color or 'ink'] or tonumber(color) or 0;x,y=math.floor(x+.5),math.floor(y+.5)
 for yy=0,h-1 do local dy=y+yy;if dy>=0 and dy<self.height then
  for xx=0,w-1 do local dx=x+xx;if dx>=0 and dx<self.width then
   local alpha=raw:byte(yy*w+xx+1)
   if alpha>0 then local pos=dy*self.width+dx;self.buf[pos]=math.floor((fg*alpha+tonumber(self.buf[pos])*(255-alpha)+127)/255) end
  end end
 end end
end
function C:rounded_box(r,radius,color,stroke)
 local w,h=math.floor(r.w+.5),math.floor(r.h+.5);if w<=0 or h<=0 then return end
 assert(w<=2048 and h<=256,'rounded mask exceeds UI bounds')
 radius=math.max(0,math.min(radius,w/2,h/2));stroke=stroke or 2
 local key=table.concat({'round',w,h,radius,stroke},':')
 local raw=mask(key,w,h,function(px,py)
  local qx,qy=math.abs(px-w/2)-(w/2-radius),math.abs(py-h/2)-(h/2-radius)
  local ax,ay=math.max(qx,0),math.max(qy,0)
  local distance=math.sqrt(ax*ax+ay*ay)+math.min(math.max(qx,qy),0)-radius
  return distance<=0 and distance>=-stroke
 end)
 self:blend_mask(raw,r.x,r.y,w,h,color)
end
function C:chevron(r,up,color)
 local w,h=24,14
 local function distance(x,y,ax,ay,bx,by)
  local vx,vy=bx-ax,by-ay;local t=math.max(0,math.min(1,((x-ax)*vx+(y-ay)*vy)/(vx*vx+vy*vy)))
  return (x-ax-t*vx)^2+(y-ay-t*vy)^2
 end
 local raw=mask('chevron:'..tostring(up),w,h,function(x,y)
  if not up then y=h-y end
  return math.min(distance(x,y,2,11,12,3),distance(x,y,12,3,22,11))<=1.25^2
 end)
 self:blend_mask(raw,r.x+(r.w-w)/2,r.y+(r.h-h)/2,w,h,color)
end
function C.mask_cache_stats() return {bytes=mask_bytes,count=mask_count} end

function C:text(o)
 local size=math.floor(o.size or 32);local w=self.font:measure(o.text or '',size,o.font)
 local x=o.x or 0;local y=o.y or 0
 local clip_x0,clip_y0=math.max(0,x),math.max(0,y)
 local clip_x1=math.min(self.width,o.w and (x+math.max(0,o.w)) or self.width)
 local clip_y1=math.min(self.height,o.h and (y+math.max(0,o.h)) or self.height)
 if o.align=='center' then x=x+((o.w or w)-w)/2 elseif o.align=='right' then x=x+(o.w or w)-w end
 if o.valign=='center' then y=y+((o.h or size)-size)/2 end
 local baseline=y+(o.baseline or math.ceil(size*.9));local fg=colors[o.color or 'ink'] or 0
 for _,ch in ipairs(require('core.util').utf8_codepoints(o.text or '')) do
  local g=self.font:glyph(ch.cp,size,o.font);local gx=math.floor(x+g.left+.5);local gy=math.floor(baseline-g.top+.5)
  for yy=0,g.h-1 do local dy=gy+yy;if dy>=clip_y0 and dy<clip_y1 then
   for xx=0,g.w-1 do local dx=gx+xx;if dx>=clip_x0 and dx<clip_x1 then
    local a=g.pixels:byte(yy*g.w+xx+1);if a>0 then local p=dy*self.width+dx;self.buf[p]=math.floor((fg*a+tonumber(self.buf[p])*(255-a)+127)/255) end
   end end
  end end
  x=x+g.advance
 end
end
function C:string() return ffi.string(self.buf,self.width*self.height) end
function C:load(raw) assert(#raw==self.width*self.height,'invalid Y8 canvas size');ffi.copy(self.buf,raw,#raw) end
function C:save(path)
 local f=assert(io.open(path,'wb'));f:write('P5\n'..self.width..' '..self.height..'\n255\n',self:string());f:close()
end
return C
