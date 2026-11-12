-- Weather panel composed as one canvas: observational data, daily forecast, solar.
local P={};local time=require('core.timeutil');local Solar=require('services.solar')
local function text(ui,t,x,y,w,s,align,color)
 ui:text({text=t or '',x=x,y=y,w=w,size=s,align=align,color=color or 'ink'})
end
local function segment(d,x,y,s,points,width)
 for i=2,#points do d:line(x+points[i-1][1]*s,y+points[i-1][2]*s,x+points[i][1]*s,y+points[i][2]*s,'ink',width or 3) end
end
local function curve(d,x,y,s,p,width)
 local points={};for i=0,16 do local t=i/16;local a=1-t;points[#points+1]={a^3*p[1]+3*a*a*t*p[3]+3*a*t*t*p[5]+t^3*p[7],a^3*p[2]+3*a*a*t*p[4]+3*a*t*t*p[6]+t^3*p[8]} end
 segment(d,x,y,s,points,width)
end
function P.kind(desc)
 desc=desc or ''
 for _,item in ipairs({{'雷','storm'},{'雪','snow'},{'雨','rain'},{'霾','haze'},{'雾','fog'},{'沙','haze'},{'尘','haze'},{'云','cloud'},{'阴','cloud'},{'晴','sun'},{'风','wind'}}) do if desc:find(item[1],1,true) then return item[2] end end
 return 'unknown'
end
function P.icon(d,kind,x,y,size)
 local s=size/64;local w=math.max(2,3*s)
 if kind=='sun' then
  d:circle(x+32*s,y+32*s,12*s,'ink',false,w)
  for i=0,7 do local a=i*math.pi/4;d:line(x+(32+19*math.cos(a))*s,y+(32+19*math.sin(a))*s,x+(32+27*math.cos(a))*s,y+(32+27*math.sin(a))*s,'ink',w) end
 elseif kind=='moon' then
  d:circle(x+30*s,y+31*s,21*s,'ink',true);d:circle(x+40*s,y+22*s,20*s,'paper',true)
 elseif kind=='wind' then
  for i=0,2 do curve(d,x,y,s,{5,18+i*13,63,18+i*13,58,3+i*13,46,9+i*13},w) end
 else
  curve(d,x,y,s,{14,43,0,43,0,24,15,24},w)
  curve(d,x,y,s,{15,24,17,4,44,3,48,23},w)
  curve(d,x,y,s,{48,23,65,21,67,43,52,43},w)
  d:line(x+14*s,y+43*s,x+52*s,y+43*s,'ink',w)
  if kind=='rain' then for i=0,2 do d:line(x+(20+i*13)*s,y+50*s,x+(16+i*13)*s,y+59*s,'ink',w) end
  elseif kind=='storm' then segment(d,x,y,s,{{36,45},{27,54},{36,54},{29,63}},w)
  elseif kind=='snow' then
   for i=0,2 do local xx=18+i*16;segment(d,x,y,s,{{xx-3,50},{xx+3,58}},w);segment(d,x,y,s,{{xx+3,50},{xx-3,58}},w) end
  elseif kind=='haze' or kind=='fog' then for i=0,2 do d:line(x+12*s,y+(50+i*6)*s,x+53*s,y+(50+i*6)*s,'ink',w) end
  elseif kind=='unknown' then d:circle(x+33*s,y+31*s,3*s,'ink',true) end
 end
end
local directions={['北']=0,['东北']=45,['东']=90,['东南']=135,['南']=180,['西南']=225,['西']=270,['西北']=315}
function P.solar(ctx)
 local w=ctx.config:module('weather');local loc=w.solar_location or w
 return Solar.calculate(time.date_key(ctx.now(),ctx.config.data.utc_offset_minutes or 480),loc.latitude,loc.longitude,ctx.config.data.utc_offset_minutes or 480)
end
function P.render(ctx,ui,r,view,meta)
 local d=ui.display;local x,y,w=r.x,r.y,r.w
 -- Four independent bands; text never follows the moving chart points.
 local sc=math.min(1,(r.h-24)/330)
 local function Y(a) return y+math.floor(a*sc) end
 local function tx(value,xx,yy,ww,size,align)
  text(ui,ui.typo:fit(tostring(value or ''),ww,size),xx,yy,ww,size,align)
 end
 local city=(view and view.city) or ctx.config:module('weather').city or '天气'
 local status=meta.error and '同步失败 · 缓存' or (meta.syncing and '同步中' or nil)
 if not view then
  tx(city,x,Y(0),w,26)
  tx(meta.error and '天气暂不可用，请检查网络' or '等待天气首次同步',x,Y(40),w,26)
 else
  -- Current conditions: one large reading and two aligned small readings.
  tx(city..'  '..(view.desc or '--'),x,Y(0),w*.44,24)
  P.icon(d,P.kind(view.desc),x,Y(30),52)
  tx(view.temp~=nil and (tostring(view.temp)..'°') or '--°',x+68,Y(27),w*.3,58)
  local wind=view.wind_direction or '--';if directions[wind] then wind=wind..'风' end
  tx('风向 / 风力',x+w*.46,Y(6),w*.29,22,'center')
  tx(wind..' '..tostring(view.wind_power or '--')..'级',x+w*.46,Y(43),w*.29,26,'center')
  tx('相对湿度',x+w*.77,Y(6),w*.23,22,'center')
  tx(view.humidity~=nil and (tostring(view.humidity)..'%') or '--%',x+w*.77,Y(43),w*.23,30,'center')
  d:line(x,Y(96),x+w,Y(96),'gray4',1)
  local days={};local minv,maxv=math.huge,-math.huge
  for i=1,3 do
   local key=time.date_key(ctx.now()+(i-1)*86400,ctx.config.data.utc_offset_minutes or 480)
   for _,day in ipairs(view.days or {}) do if day.date==key then days[i]=day;break end end
   for _,field in ipairs({'high','low'}) do local n=tonumber(days[i] and days[i][field]);if n then minv,maxv=math.min(minv,n),math.max(maxv,n) end end
  end
  local left=x+96;local span=w-144
  local function px(i) return left+(i-.5)*span/3 end
  tx('白天',x,Y(141),80,22)
  tx('夜间',x,Y(229),80,22)
  if minv==math.huge then minv,maxv=0,1 end
  minv,maxv=minv-2,maxv+2
  local gy0,gy1=Y(180),Y(215)
  local function gy(t) return gy1-(t-minv)/(maxv-minv)*(gy1-gy0) end
  for i=1,3 do
   local cx=px(i);local day=days[i]
   tx(({'今天','明天','后天'})[i],cx-60,Y(108),70,23,'center')
   if day then P.icon(d,P.kind(day.desc),cx+20,Y(105),28) end
   tx(day and day.high~=nil and (tostring(day.high)..'°') or '--',cx-60,Y(141),120,25,'center')
   tx(day and day.low~=nil and (tostring(day.low)..'°') or '--',cx-60,Y(229),120,25,'center')
  end
  for series,field in ipairs({'high','low'}) do
   local last
   for i=1,3 do
    local cx=px(i);local value=tonumber(days[i] and days[i][field])
    if value then
     local py=gy(value)
     if last then d:line(last.x,last.y,cx,py,'ink',2,series==2) end
     if series==2 then d:circle(cx,py,4,'paper',true) end
     d:circle(cx,py,4,'ink',series==1,2);last={x=cx,y=py}
    else last=nil end
   end
  end
  -- Fixed legend: day = solid filled, night = dashed open.
  d:line(x+2,Y(185),x+44,Y(185),'ink',2);d:circle(x+23,Y(185),3,'ink',true)
  d:line(x+2,Y(211),x+44,Y(211),'ink',2,true);d:circle(x+23,Y(211),3,'paper',true);d:circle(x+23,Y(211),3,'ink',false,2)
 end
 local solar=P.solar(ctx)
 d:line(x,Y(264),x+w,Y(264),'gray4',1)
 if solar then
  if solar.state=='normal' then
   tx('日出 '..Solar.hhmm(solar.sunrise_minute),x,Y(278),w/2,23)
   tx('日落 '..Solar.hhmm(solar.sunset_minute),x+w/2,Y(278),w/2,23,'right')
  else tx(solar.state=='polar_day' and '极昼 · 全天白昼' or '极夜 · 全天夜间',x,Y(278),w,23) end
  local by=Y(310);d:fill({x=x,y=by,w=w,h=10},'ink')
  if solar.state=='normal' then
   local left=x+w*solar.sunrise_minute/1440;local right=x+w*solar.sunset_minute/1440
   if right>=left then d:fill({x=left,y=by+2,w=right-left,h=6},'paper')
   else d:fill({x=x+2,y=by+2,w=right-x-2,h=6},'paper');d:fill({x=left,y=by+2,w=x+w-left-2,h=6},'paper') end
  elseif solar.state=='polar_day' then d:fill({x=x+2,y=by+2,w=w-4,h=6},'paper') end
 else tx('请在电脑端设置日照位置',x,Y(278),w,23) end
 local reported=view and view.reporttime and view.reporttime:sub(12,16)
 local stamp=reported and ('发布 '..reported) or (meta.cached_at and ('更新 '..time.format_time(meta.cached_at,ctx.config.data.utc_offset_minutes or 480,true))) or ''
 local duration=''
 if solar then local m=math.floor(solar.daylight_minutes+.5);duration=string.format('白昼 %d小时%02d分 · %.0f%%',math.floor(m/60),m%60,solar.day_fraction*100) end
 tx(duration,x,y+r.h-24,w*.66,20)
 tx(status or stamp,x+w*.66,y+r.h-24,w*.34,20,'right')
end
return P
