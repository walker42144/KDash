return function(T)
 local C=require('ui.canvas')
 T.test('rounded border has symmetric antialiased corners and an unfilled center',function()
  local c=C.new(90,34);c:rounded_box({x=0,y=0,w=90,h=34},17,'ink')
  local gray=false
  for y=0,33 do for x=0,89 do
   local v=c.buf[y*90+x];if v>0 and v<255 then gray=true end
   T.eq(v,c.buf[y*90+89-x]);T.eq(v,c.buf[(33-y)*90+x])
  end end
  T.truthy(gray);T.eq(c.buf[17*90+45],255)
 end)
 T.test('up and down chevrons are exact vertical mirrors inside their touch boxes',function()
  local a,b=C.new(24,14),C.new(24,14);local r={x=0,y=0,w=24,h=14}
  a:chevron(r,true,'ink');b:chevron(r,false,'ink')
  for y=0,13 do for x=0,23 do T.eq(a.buf[y*24+x],b.buf[(13-y)*24+x]) end end
 end)
 T.test('supersampled mask cache is reused and remains bounded with changing widths',function()
  local c=C.new(256,40);c:rounded_box({x=0,y=0,w=90,h=34},17,'ink');local before=C.mask_cache_stats()
  c:rounded_box({x=0,y=0,w=90,h=34},17,'ink');T.eq(C.mask_cache_stats().count,before.count)
  for w=40,250 do c:rounded_box({x=0,y=0,w=w,h=34},17,'ink');local s=C.mask_cache_stats();T.truthy(s.bytes<=256*1024);T.truthy(s.count<=64) end
 end)
end
