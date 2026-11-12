return function(T)
 local Device=require('platform.kindle.device');local App=require('core.app')
 T.test('home battery reads never wait for unrelated frontlight or storage commands',function()
  local d=Device.new({storage={},runner={run=function() error('LIPC must not run on the home screen') end,run_shell=function() error('df must not run on the home screen') end}})
  local count=0;d._battery_from_power_supply=function() count=count+1;return {level=71,charging=false} end
  T.eq(d:dashboard_info(1000).battery.level,71);T.eq(d:dashboard_info(1001).battery.level,71);T.eq(count,1)
 end)
 T.test('physical power idle check does not synchronously read device status',function()
  local a=App.new({device={info=function() error('unneeded full status') end},power={keep_active=function() return true end},log={warn=function() end}})
  a.power_sleep_enabled=true;a.last_power_check=0;a:maybe_power(100);T.eq(a.power_failures,0)
 end)
 T.test('missing sysfs battery starts an asynchronous fallback and keeps output responsive',function()
  local files,started={},0
  local fs={read=function(_,p) return files[p] end,write=function(_,p,v) files[p]=v;return true end}
  local d=Device.new({storage=fs,run_dir='/fake',runner={run=function() error('must not block') end,spawn_script=function() started=started+1;return 0 end}})
  d._battery_from_power_supply=function() return nil end
  T.eq(d:dashboard_info(1000).battery.level,nil);T.eq(started,1)
  files['/fake/http/battery.result']='68 1\n'
  T.eq(d:dashboard_info(1021).battery.level,68);T.truthy(d:dashboard_info(1021).battery.charging);T.eq(started,1)
 end)
 T.test('disabled device module does not read full device status on startup',function()
  local M=assert(loadfile('modules/device/init.lua'))()
  T.truthy(M.init({config={module=function() return {enabled=false} end},device_info=function() error('unneeded status') end}))
 end)
end
