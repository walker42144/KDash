-- Standalone host stress harness. No network, framebuffer, account or USB I/O.
-- luajit tests/soak_native.lua [frames=1000], from the source root.
package.path='./?.lua;./?/init.lua;'..package.path
local frames=tonumber(arg[1]) or 1000
local D=require('platform.kindle.display_native')
local root='.';local library=assert(os.getenv('KDASH_TEST_FREETYPE'),'set KDASH_TEST_FREETYPE to a host FreeType library')
local d=D.new({fonts={library=library,cjk='assets/fonts/SourceHanSansCN-Medium.ttf',latin='assets/fonts/KumbhSans-500.ttf',display='assets/fonts/KumbhSans-600.ttf'}})
local storage=require('core.storage').new()
local config=require('core.config').load({storage=storage,path='tests/no-user-config.json',default_path='config/default.json'})
config.data.ui.minimal=false;config.data.ui.hide_settings=false
local cache={today={{id='fixture',project_id='p',title='压力测试任务',due_key='2026-11-12',tags={'学习','数学'},priority=5,children={},checklist={}}},today_completed=0}
local now=1794413100
local app=require('core.app').new({app_dir=root,data_dir='tests',storage=storage,config=config,secrets={secret=function() return nil end},log=require('core.log').new({}),display=d,input={},
 device={info=function() return {battery={level=78}} end},power={apply=function() end},http={request=function() error('no network permitted') end},clock={now=function() return now end}})
app:setup()
config.data.ui.minimal=false
config.data.pages={app.page,{id='extra',title='EXTRA',layout={}}}
-- The real page/card/footer renderer and native glyph cache are exercised.
app.renderer:render_full(app.page)
local hits=#app.events.hits
for i=1,frames do
 now=now+60
 app.renderer:render_dirty({'clock','countdown'},app.page)
 assert(#app.events.hits==hits,'navigation hit areas accumulated')
 if i%100==0 then
  print(string.format('frames=%d Lua_heap_KiB=%.0f glyph_bytes=%d hits=%d',i,collectgarbage('count'),d.font.cache_bytes,#app.events.hits));io.stdout:flush()
 end
end
for cp=0x4e00,0x4e00+3999 do d.font:glyph(cp,32) end
assert(d.font.cache_bytes<=d.font.max_cache_bytes)
d:close();print('PASS native stress; natural GC; 4000 glyphs; no device/runtime longevity claim')
