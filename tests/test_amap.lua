return function(T)
 local A=require('services.api.amap')
 local live='{"status":"1","lives":[{"city":"测试市","weather":"晴","temperature":"21","humidity":"50","winddirection":"北","windpower":"≤3","reporttime":"2026-11-11 18:00:00"}]}'
 local forecast='{"status":"1","forecasts":[{"casts":[{"date":"2026-11-11","dayweather":"多云","daytemp":"23","nighttemp":"12"}]}]}'
 T.test('amap parses current and forecast separately',function()
  local v=A.parse_live(live,{},1000);T.eq(v.temp,21);T.eq(v.desc,'晴');T.eq(v.provider,'amap');T.eq(v.wind_direction,'北');T.eq(v.wind_power,'≤3')
  T.truthy(A.add_forecast(v,forecast));T.eq(v.high,23);T.eq(v.low,12);T.eq(#v.days,1)
 end)
 T.test('amap service errors are sanitized codes',function()
  local v,e=A.parse_live('{"status":"0","infocode":"10001"}',{},0)
  T.eq(v,nil);T.eq(e,'AMAP_ERROR_10001')
 end)
 T.test('amap requires key and six-digit adcode',function()
  T.eq(A.url('bad','fake'),nil);T.eq(A.url('110101',''),nil)
  T.truthy(A.url('110101','fake'):find('extensions=base',1,true))
 end)
 T.test('amap sync fetches two endpoints and caches normalized result',function()
  local n,cache,done=0,nil,nil
  local owner={now=function() return 100 end,secrets={secret=function() return 'fake' end},cache={write=function(_,_,v) cache=v end},http={request=function(_,opts,cb)
   n=n+1;T.eq(opts.label,n==1 and 'amap current' or 'amap forecast');cb({ok=true,body=n==1 and live or forecast})
  end}}
  A.sync(owner,{adcode='110101'},function(ok,_,v) done=ok;T.eq(v.temp,21) end)
  T.eq(n,2);T.truthy(done);T.eq(cache.data.high,23)
 end)
 T.test('amap forecast failure retains current with explicit partial status',function()
  local n=0
  local owner={now=function() return 100 end,secrets={secret=function() return 'fake' end},cache={write=function() end},http={request=function(_,opts,cb)
   n=n+1;cb({ok=n==1,body=live})
  end}}
  A.sync(owner,{adcode='110101'},function(ok,_,v) T.truthy(ok);T.eq(v.temp,21);T.truthy(v.forecast_error);T.eq(#v.days,0) end)
 end)
end
