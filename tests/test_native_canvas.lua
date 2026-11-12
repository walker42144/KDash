-- Host regression for the actual native renderer, with a host FreeType DLL.
local root='outputs/KDash-main';package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
local ffi=require('ffi');local D=require('platform.kindle.display_native')
local d=D.new({fonts={library=assert(os.getenv('KDASH_TEST_FREETYPE')),cjk=root..'/assets/fonts/SourceHanSansCN-Medium.ttf',latin=root..'/assets/fonts/KumbhSans-500.ttf',display=root..'/assets/fonts/KumbhSans-600.ttf'}})
local refreshes,commits=0,0
-- No /dev/fb0 access: fake only the final framebuffer sink and FBInk refresh command.
d.fb={commit=function() commits=commits+1 end,close=function() end}
d.runner={run=function(_,args) refreshes=refreshes+1;assert(args[1]=='mock-fbink');if d.wallpaper and not d.dashboard then return 0,'' end;if d.dashboard then local found=false;for _,a in ipairs(args) do if a=='-f' then found=true end end;assert(found,'screensaver must request a cleaning flash') end;return 0,'' end};d.fbink='mock-fbink'
d:begin_frame(true);d:text({text='KDASH 34天 湿度50% ≤3级',size=32,x=56,y=80,w=960});d:line(0,0,1072,1448,'ink',3,true);d:circle(500,500,20,'ink',false,3)
assert(refreshes==0,'text and graphics must not spawn FBInk');assert(d:flush({full=true}));assert(refreshes==1)
local expected=d.canvas:string();d:begin_frame(false);d:add_dirty(0,0,1072,1448);assert(d:flush({}));assert(refreshes==1,'unchanged pixels must not refresh')
d:prepare_screensaver(root);local start=os.clock();assert(d:show_screensaver());assert(refreshes==2 and commits==2)
assert(d.canvas:string()~=expected);assert(d:restore_dashboard());assert(d.canvas:string()==expected);assert(refreshes==3)
-- Canary padding/offsets: commit copies only visible pixels, never virtual padding.
local B=require('platform.kindle.framebuffer');local bytes=ffi.new('unsigned char[64]');ffi.fill(bytes,64,117)
local fb=setmetatable({geometry={width=3,height=4,stride=8,xoffset=2,yoffset=1},bytes=bytes},B)
local tiny=ffi.new('unsigned char[12]');ffi.fill(tiny,12,99);fb:commit(tiny)
for y=0,7 do for x=0,7 do local visible=(y>=1 and y<5 and x>=2 and x<5);assert(bytes[y*8+x]==(visible and 99 or 117)) end end
d:close();print(string.format('PASS native canvas: real FreeType mixed fonts; no per-glyph subprocess; unchanged frame skipped; one refresh per screen; wallpaper restore; clipped mmap padding; host CPU %.3fs',os.clock()-start))
