return function(T)
 local Device=require('platform.kindle.device')
 T.test('Device filesystem dependency does not shadow storage method',function()
  local fs={list_dir=function() return {} end}
  local d=Device.new({storage=fs,runner={}})
  T.eq(type(d.storage),'function')
 end)
 T.test('real Device info handles missing sysfs and caches a valid result',function()
  local requests=0
  local d=Device.new({storage={list_dir=function() return {} end},runner={
   run=function(_,args)
    requests=requests+1
    if args[#args]=='battLevel' then return 0,'71' end
    if args[#args]=='isCharging' then return 0,'0' end
    return 0,'8'
   end,
   run_shell=function() return 0,'' end,
  }})
  local info=d:info(1000);T.eq(info.battery.level,71);T.eq(info.battery.charging,false)
  local before=requests;T.eq(d:info(1001),info);T.eq(requests,before)
 end)
end
