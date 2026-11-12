-- AMap Web Service weather, independent from Open-Meteo payloads.
local json=require('core.json')
local A={}
local function enc(s) return tostring(s):gsub('[^%w%-._~]',function(c) return string.format('%%%02X',c:byte()) end) end
function A.url(adcode,key,kind)
 if not tostring(adcode or ''):match('^%d%d%d%d%d%d$') then return nil,'AMAP_ADCODE_REQUIRED' end
 if not key or key=='' then return nil,'AMAP_KEY_REQUIRED' end
 return 'https://restapi.amap.com/v3/weather/weatherInfo?city='..adcode..'&key='..enc(key)..'&extensions='..(kind=='all' and 'all' or 'base')..'&output=JSON'
end
local function decode(body)
 local ok,d=pcall(json.decode,body or '')
 if not ok or type(d)~='table' then return nil,'AMAP_INVALID_JSON' end
 if tostring(d.status)~='1' then return nil,'AMAP_ERROR_'..tostring(d.infocode or 'UNKNOWN'):gsub('[^%w_]','') end
 return d
end
function A.parse_live(body,cfg,now)
 local d,err=decode(body); if not d then return nil,err end
 local live=d.lives and d.lives[1]
 if not live or not tonumber(live.temperature) then return nil,'AMAP_NO_CURRENT_WEATHER' end
 return {provider='amap',city=live.city or cfg.city,temp=tonumber(live.temperature),humidity=tonumber(live.humidity),
 desc=live.weather,icon='cloud',days={},fetched_at=now,reporttime=live.reporttime,attribution='高德天气'}
end
function A.add_forecast(view,body)
 local d,err=decode(body); if not d then return false,err end
 local f=d.forecasts and d.forecasts[1]
 if not f or type(f.casts)~='table' or #f.casts==0 then return false,'AMAP_NO_FORECAST' end
 for i=1,math.min(3,#f.casts) do
  local c=f.casts[i]
  view.days[#view.days+1]={date=c.date,label=c.date,desc=c.dayweather,high=tonumber(c.daytemp),low=tonumber(c.nighttemp)}
 end
 view.high,view.low=view.days[1].high,view.days[1].low
 return true
end
function A.sync(owner,cfg,cb)
 local key=owner.secrets and owner.secrets:secret('amap.key')
 local url,err=A.url(cfg.adcode,key,'base'); if not url then cb(false,err); return end
 owner.http:request({url=url,method='GET',timeout=25,sensitive_values={key},label='amap current',headers={Accept='application/json'}},function(res)
  if not res.ok then cb(false,'AMAP_HTTP_FAILED'); return end
  local view,err=A.parse_live(res.body,cfg,owner.now()); if not view then cb(false,err); return end
  owner.http:request({url=A.url(cfg.adcode,key,'all'),method='GET',timeout=25,sensitive_values={key},label='amap forecast',headers={Accept='application/json'}},function(forecast)
   local ok,err
   if forecast.ok then ok,err=A.add_forecast(view,forecast.body) end
   if not ok then view.forecast_error=err or 'AMAP_FORECAST_HTTP_FAILED' end
   owner.cache:write('weather',{data=view,fetched_at=owner.now()})
   cb(true,nil,view)
  end)
 end)
end
return A
