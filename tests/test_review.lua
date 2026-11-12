-- Reproductions from the two independent r15 reviews. No device/account access.
return function(T)
 local util=require('core.util')
 T.test('native LIPC sleep events coexist with an opened physical button',function()
  local path=os.tmpname();util.write_file(path,'goingToScreenSaver\noutOfScreenSaver\n')
  local p=require('platform.kindle.power').new({events_path=path});p.button_fd=7;p.read_button=function() return {} end
  local events=p:poll_events();os.remove(path);T.eq(events[1],'sleep');T.eq(events[2],'wake')
 end)
 T.test('transient missing or rotated power event file retains physical input',function()
  local path=os.tmpname();os.remove(path)
  local p=require('platform.kindle.power').new({events_path=path});p.read_button=function() return {'button'} end
  T.eq(p:poll_events()[1],'button')
  util.write_file(path,'outOfScreenSaver\n');p.event_offset=999;p.read_button=function() return {} end;p.ignore_native_until=0
  T.eq(p:poll_events()[1],'wake');os.remove(path)
 end)
 T.test('wake redraws once and preserves explicit automatic-update pause',function()
  local a=require('core.app').new({config={data={ui={auto_update=false,refresh_minutes=1}}},clock={now=function() return 6000 end}})
  local restored=0;a.sleeping=true;a.updates_paused=true;a.refresh_anchor=0
  a.display={restore_dashboard=function() restored=restored+1;return true end}
  a.power={set_hold=function() return true end};a.scheduler={force_all=function() end};a.log={info=function() end}
  a:handle_power_event('wake');T.truthy(a.need_full);T.eq(restored,0);T.truthy(a.updates_paused)
 end)
 T.test('text pixels are clipped to the requested rectangle on both sides',function()
  local font={measure=function(_,text) return #text*4 end,glyph=function() return {w=4,h=4,left=0,top=4,advance=4,pixels=string.rep(string.char(255),16)} end}
  local c=require('ui.canvas').new(30,12,font)
  for _,align in ipairs({'left','center','right'}) do
   c:fill({x=0,y=0,w=30,h=12},'paper');c:text({text='abcdefgh',x=10,y=2,w=8,h=5,size=8,baseline=4,align=align})
   for y=0,11 do for x=0,29 do if x<10 or x>=18 or y<2 or y>=7 then T.eq(tonumber(c.buf[y*30+x]),255) end end end
  end
 end)
 T.test('task tag cardinality and metadata work are bounded with explicit overflow badge',function()
  local tags={};for i=1,2000 do tags[i]='tag'..i end
  local badges=require('services.task_metadata').badges({tags=tags},480)
  T.truthy(#badges<=65);T.truthy(badges[#badges].text:find('更多',1,true))
 end)
 T.test('Open-Meteo timezone cannot inject extra query parameters',function()
  local url=require('services.api.weather').build_url({latitude=34,longitude=118,timezone='A&B#C'})
  T.falsy(url:find('A&B',1,true));T.truthy(url:find('A%%26B%%23C'))
 end)
 T.test('malformed project responses preserve the previous task cache',function()
  local json=require('core.json');local writes=0
  for _,payload in ipairs({'{"code":200}','{"data":[]}','null','[{"name":"missing id"}]'}) do
   local result,reason
   local api=require('services.api.dida').new({config={module=function() return {} end},secrets={secret=function(_,k) if k=='dida.access_token' then return 'mock' end end},
    cache={write=function() writes=writes+1 end},http={request=function(_,o,cb) cb({ok=true,status=200,body=payload}) end},now=function() return 100 end})
   api:sync(function(ok,err) result,reason=ok,err end);T.falsy(result);T.truthy(reason)
  end
  T.eq(writes,0)
 end)
 T.test('whole-task completion is not acknowledged until readback confirms status',function()
  local json=require('core.json');local calls=0;local result,reason
  local api=require('services.api.dida').new({config={module=function() return {} end},secrets={secret=function(_,k) if k=='dida.access_token' then return 'mock' end end},cache={},now=function() return 100 end,
   http={request=function(_,o,cb) calls=calls+1;cb({ok=true,status=200,body=o.method=='POST' and '' or json.encode(calls==1 and {tasks={{id='t'}}} or {id='t',status=0})}) end}})
  api:complete({project_id='p',task_id='t'},function(ok,err) result,reason=ok,err end)
  T.falsy(result);T.eq(reason,'WRITE_UNCONFIRMED');T.eq(calls,3)
 end)
 T.test('unchanged config save does not write flash twice',function()
  local writes=0;local c=require('core.config').new({path='mock',storage={write_atomic=function() writes=writes+1;return true end}})
  c.data={ui={auto_update=true}};T.truthy(c:save());T.truthy(c:save());T.eq(writes,1)
  c.data.ui.auto_update=false;T.truthy(c:save());T.eq(writes,2)
 end)
 T.test('LuaJIT pclose success cannot conceal a failed child command',function()
  local r=require('platform.kindle.runner').new({posix=true,popen=function(command)
   T.truthy(command:find('__KDASH_RC__',1,true))
   return {read=function() return 'failure details\n__KDASH_RC__7\n' end,close=function() return true end}
  end})
  local code,out=r:run({'fbink','-s'});T.eq(code,7);T.eq(out,'failure details')
 end)
 T.test('interrupted input is retried but repeated disconnect exits through recovery',function()
  local a=require('core.app').new({log={warn=function() end}})
  local function fail() error('EINTR') end
  T.eq(#a:poll_safely('touch',fail),0)
  T.eq(#a:poll_safely('touch',function() return {} end),0)
  T.eq(#a:poll_safely('touch',fail),0);T.eq(#a:poll_safely('touch',fail),0)
  T.falsy(pcall(function() a:poll_safely('touch',fail) end))
 end)
 T.test('manual refresh remains usable while automatic updates are paused',function()
  local a=require('core.app').new({config={data={ui={}}}});a.updates_paused=true
  a.scheduler=require('core.scheduler').new();a.scheduler:add('dida',{now=100,interval=900});a.scheduler:add('weather',{now=100,interval=900})
  local called={};a.run_refresh=function(_,id) called[#called+1]=id end
  a.manual_refresh.dida=true;a:refresh_due(100)
  T.eq(#called,1);T.eq(called[1],'dida');T.falsy(a.scheduler:get('weather').running)
 end)
 T.test('malformed cached task trees cannot bypass hierarchy validation',function()
  local api=require('services.api.dida');local root={id='a',title='a',children={}};root.children[1]=root
  T.falsy(api.valid_cached_view({today={root}}))
  T.falsy(api.valid_cached_view({today={{id='a',title='a',checklist={true}}}}))
  T.truthy(api.valid_cached_view({today={{id='a',title='a',children={},checklist={}}}}))
 end)
 T.test('metadata text and priority marks have disjoint horizontal reservations',function()
  local UI=require('ui.components');local theme=require('ui.theme').new({});local texts={}
  local d={text=function(_,o) texts[#texts+1]=o end,fill=function() end,hline=function() end,vline=function() end}
  local ui=UI.new({display=d,theme=theme,typo=require('ui.typography').new({})})
  local reserve=ui:priority_reserve(5)
  ui:task_with_badges({x=0,y=0,w=960-reserve,h=44},'Task','1/3 展开',false,{size=32})
  for _,o in ipairs(texts) do T.truthy(o.x+o.w<=960-reserve) end
 end)
 T.test('missing authorization and busy module both finish the scheduler immediately',function()
  local M=assert(loadfile('modules/dida/init.lua'))();local results={};local token=nil
  local ctx={config={data={},module=function() return {} end},now=function() return 100 end,
   cache={read=function() return nil end},http={request=function() end},secrets={secret=function(_,key) if key=='dida.access_token' then return token end end},
   request_update=function() end,finish=function(ok,err) results[#results+1]={ok,err} end}
  M.init(ctx);T.eq(M.refresh(ctx),false);T.eq(results[1][2],'AUTH_REQUIRED')
  token='mock';M.refresh(ctx);T.eq(#results,1);M.refresh(ctx);T.eq(results[2][2],'BUSY')
 end)
 T.test('HTTP launch failure finishes once and removes all request artifacts',function()
  local files={};local count=0
  local storage={write=function(_,p,s) files[p]=s;return true end,read=function(_,p) return files[p] end,exists=function(_,p) return files[p]~=nil end,chmod=function() end,remove=function(_,p) files[p]=nil end}
  local h=require('services.http').new({storage=storage,dir='/mock',now=function() return 100 end,runner={spawn_script=function() return 1 end}})
  h:request({url='https://example.invalid'},function(res) count=count+1;T.falsy(res.ok);T.eq(res.error,'spawn failed') end)
  T.eq(count,1);T.falsy(h:busy());T.eq(next(files),nil)
 end)
 T.test('wide shallow JSON has a node budget as well as a depth budget',function()
  local json=require('core.json')
  T.falsy(pcall(json.decode,'['..string.rep('0,',50000)..'0]'))
  T.eq(#json.decode('[0,1]'),2,'a failed decode must not poison the next request')
 end)
end
