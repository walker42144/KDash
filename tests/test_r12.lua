return function(T)
 local S=require('services.solar');local R=require('core.refresh_policy');local App=require('core.app')
 T.test('solar UTC epochs belong to the requested Shanghai civil date, including previous UTC day',function()
  local s=assert(S.calculate('2024-01-01',34.2,118.8,480))
  T.eq(require('core.timeutil').date_key(s.sunrise,480),'2024-01-01')
  T.eq(require('core.timeutil').date_key(s.sunset,480),'2024-01-01')
  T.truthy(s.sunrise_minute>400 and s.sunrise_minute<500);T.truthy(s.sunset_minute>1000 and s.sunset_minute<1100)
  T.eq(math.floor(s.daylight_minutes+s.night_minutes+.5),1440)
 end)
 T.test('solar follows seasons, leap days and high-latitude daylight states without inventing events',function()
  local winter=S.calculate('2026-12-21',34.2,118.8,480)
  local summer=S.calculate('2026-06-21',34.2,118.8,480)
  T.truthy(summer.daylight_minutes>winter.daylight_minutes+200)
  T.truthy(S.calculate('2024-02-29',34.2,118.8,480))
  T.eq(S.calculate('2025-02-29',34,118,480),nil)
  T.eq(S.calculate('2026-06-21',89,0,0).state,'polar_day')
  T.eq(S.calculate('2026-12-21',89,0,0).state,'polar_night')
  T.eq(S.calculate('2026-01-01',91,118,480),nil)
 end)
 T.test('initial refresh uses whole minutes and a single upcoming ten-minute calibration',function()
  local cfg={ui={refresh_minutes=15,refresh_alignment='first_10min'},utc_offset_minutes=480}
  local anchor,at=R.initial(cfg,1794407652)
  T.eq(anchor%60,0);T.eq((at+480*60)%600,0);T.truthy(at>=1794407652 and at-1794407652<600)
  local a,t=R.initial(cfg,at);T.eq(a,at);T.eq(t,nil)
 end)
 T.test('calibration rephases network jobs once without starting network requests or losing retry backoff',function()
  local scheduler=require('core.scheduler').new({coalesce_window=0})
  scheduler:add('weather',{now=1000,interval=2700,anchor=960,align='interval',no_coalesce=true})
  local a=App.new({config={data={ui={refresh_minutes=5}}},clock={now=function() return 1200 end}})
  a.scheduler=scheduler;a.calibration_at=1200;a.log={info=function() end};local local_jobs={}
  a.run_refresh=function(_,id) local_jobs[#local_jobs+1]=id end
  a:maybe_calibrate(1200);T.eq(a.refresh_anchor,1200);T.eq(a.calibration_at,nil)
  T.eq(scheduler:get('weather').next_due,3900);T.eq(#local_jobs,2);T.truthy(a.force_render)
  a:maybe_calibrate(1800);T.eq(#local_jobs,2)
 end)
 T.test('sleep postpones calibration without waking or replaying missed slots',function()
  local a=App.new({config={data={ui={refresh_minutes=1}}}});a.calibration_at=1200;a.sleeping=true
  a:maybe_calibrate(1800);T.eq(a.calibration_at,1200)
 end)
 T.test('manual refresh is immediate, coalesces results, and never changes the automatic anchor',function()
  local draws,forced=0,0;local a=App.new({clock={now=function() return 1300 end},config={data={ui={}}}})
  a.refresh_anchor=1200;a.page={id='home'};a.registry={enabled=function() return {{id='weather'},{id='dida'}} end}
  a.scheduler={get=function() return {running=false} end,force=function() forced=forced+1 end}
  a.renderer={render_full=function() draws=draws+1 end}
  a:request_manual_refresh();T.eq(draws,1);T.eq(forced,2);T.truthy(a.config.data.ui.refreshing)
  a:request_manual_refresh();T.eq(forced,2)
  a:check_manual_batch(1301);T.truthy(a.manual_batch);T.eq(a.refresh_anchor,1200)
  a.manual_refresh={};a:check_manual_batch(1302);T.eq(a.manual_batch,nil);T.truthy(a.need_full);T.falsy(a.config.data.ui.refreshing)
 end)
 T.test('manual timeout retains cached UI and can never paint over a sleeping screensaver',function()
  local a=App.new({config={data={ui={refreshing=true}}}});a.sleeping=true;a.manual_refresh={weather=true};a.manual_batch={deadline=60}
  a:check_manual_batch(61);T.eq(a.need_full,true);T.eq(a.manual_batch,nil);T.falsy(a.config.data.ui.refreshing)
  -- render_pending still rejects every sleep redraw, including an existing full-render flag.
  T.falsy(a:render_pending(61))
 end)
 T.test('framebuffer guard rejects stride, rotation, depth and viewport corruption before any write',function()
  local B=require('platform.kindle.framebuffer')
  local v={xres=1072,yres=1448,bits_per_pixel=8,rotate=3,xres_virtual=1088,yres_virtual=6144,xoffset=0,yoffset=0}
  local f={line_length=1088,smem_len=6684672}
  T.eq(B.validate(v,f).width,1072)
  for key,bad in pairs({bits_per_pixel=16,rotate=1,xoffset=100,yoffset=6000}) do local old=v[key];v[key]=bad;T.falsy(pcall(B.validate,v,f));v[key]=old end
 end)
 T.test('weather icon families preserve dangerous-weather precedence and explicit unknown state',function()
  local P=require('ui.weather_panel');T.eq(P.kind('雷阵雨'),'storm');T.eq(P.kind('雨夹雪'),'snow');T.eq(P.kind('晴'),'sun');T.eq(P.kind('未知'),'unknown')
 end)
end
