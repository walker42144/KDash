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
function C:text(o)
 local size=math.floor(o.size or 32);local w=self.font:measure(o.text or '',size,o.font)
 local x=o.x or 0;local y=o.y or 0
 if o.align=='center' then x=x+((o.w or w)-w)/2 elseif o.align=='right' then x=x+(o.w or w)-w end
 if o.valign=='center' then y=y+((o.h or size)-size)/2 end
 local baseline=y+(o.baseline or math.ceil(size*.9));local fg=colors[o.color or 'ink'] or 0
 for _,ch in ipairs(require('core.util').utf8_codepoints(o.text or '')) do
  local g=self.font:glyph(ch.cp,size,o.font);local gx=math.floor(x+g.left+.5);local gy=math.floor(baseline-g.top+.5)
  for yy=0,g.h-1 do local dy=gy+yy;if dy>=0 and dy<self.height then
   for xx=0,g.w-1 do local dx=gx+xx;if dx>=0 and dx<self.width then
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
