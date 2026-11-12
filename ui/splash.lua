-- Startup view uses the same glyph and Latin font as the dashboard header.
local M={}
function M.render(display,app_dir)
 local w,h=display.width,display.height
 local size=math.floor(math.min(w,h)*0.25)
 local x=math.floor((w-size)/2)
 local y=math.floor(h*0.38)-math.floor(size/2)
 display:begin_frame(true)
 display:icon(app_dir..'/assets/logo-user.ttf',x,y,size,size)
 display:text({text='KDASH',x=0,y=y+size+48,w=w,size=46,align='center',color='ink'})
 return display:flush({full=true,flash=false})
end
return M
