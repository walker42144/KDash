return function(T)
 local App=require('core.app');local Power=require('platform.kindle.power')
 T.test('physical power button uses short press release and ignores repeat long press and dropped input',function()
  local p=Power.new({})
  local function e(v,t) return {type=1,code=116,value=v,sec=t,usec=0} end
  T.eq(#p:feed_button({e(1,10),e(2,10)}),0)
  T.eq(p:feed_button({e(0,11)})[1],'button')
  T.eq(#p:feed_button({e(0,11)}),0)
  T.eq(#p:feed_button({e(1,20),e(0,23)}),0)
  T.eq(#p:feed_button({e(1,30),{type=0,code=3},e(0,31)}),0)
 end)
 T.test('power reconciliation never blindly double toggles a settled native transition',function()
  local writes=0;local state='screenSaver'
  local p=Power.new({runner={run=function(_,args)
   if args[1]=='lipc-get-prop' then return 0,state end
   writes=writes+1;return 0,''
  end}})
  p:reconcile(true);T.eq(writes,0)
  state='active';p:reconcile(true);T.eq(writes,1)
  p:reconcile(false);T.eq(writes,1)
  state='readyToSuspend';p:reconcile(true);T.eq(writes,1)
 end)
 T.test('active mode resets idle timeout without blocking physical power-button suspend',function()
  local commands={};local p=Power.new({runner={run=function(_,args) commands[#commands+1]=table.concat(args,' ');return 0,'' end}})
  T.truthy(p:keep_active());T.truthy(p:keep_active())
  T.eq(#commands,3);T.truthy(commands[1]:find('preventScreenSaver 0',1,true))
  T.truthy(commands[2]:find('touchScreenSaverTimeout 1',1,true));T.eq(commands[2],commands[3])
 end)
 T.test('power event parser waits for complete lines and does not repeat events',function()
  local path=os.tmpname();local f=assert(io.open(path,'wb'));f:write('goingToScreenSaver 2');f:close()
  local p=Power.new({events_path=path});T.eq(#p:poll_events(),0)
  f=assert(io.open(path,'ab'));f:write('\noutOfScreenSaver 1\nignored 2\n');f:close()
  local ev=p:poll_events();T.eq(#ev,2);T.eq(ev[1],'sleep');T.eq(ev[2],'wake');T.eq(#p:poll_events(),0);os.remove(path)
 end)
 T.test('sleep replaces dashboard before releasing hold and blocks touch and all redraw',function()
  local seq={};local a=App.new({data_dir='unused',config={data={ui={refresh_minutes=5}}},clock={now=function() return 5000 end}})
  a.events={clear_hits=function() seq[#seq+1]='clear' end,route_tap=function() error('sleep touch must be ignored') end}
  a.renderer={render_screensaver=function() seq[#seq+1]='wallpaper' end,render_dirty=function() error('must not repaint') end}
  a.power={set_hold=function(_,on) seq[#seq+1]=on and 'hold' or 'release';return true end}
  a.display={available=true};a.log={info=function() end};a.scheduler={tick=function() error('must not sync') end}
  a.need_full=true;a.force_render=true;a.dirty.clock=true
  a:handle_power_event('sleep');T.truthy(a.sleeping);T.eq(table.concat(seq,','),'clear,wallpaper,release')
  a:refresh_due(5000);T.falsy(a:render_pending(5000));a:handle_input({{type='tap',x=1,y=1}})
  a:handle_power_event('sleep');T.eq(#seq,3,'duplicate sleep idempotent')
 end)
 T.test('wake releases hold first and retains common baseline after long sleep',function()
  local seq={};local a=App.new({config={data={ui={refresh_minutes=5}}},clock={now=function() return 5000 end}})
  a.sleeping=true;a.updates_paused=true;a.refresh_anchor=1000
  a.power={set_hold=function(_,on) T.falsy(on);seq[#seq+1]='active';return true end}
  a.scheduler={force_all=function(_,now) T.eq(now,5000);seq[#seq+1]='refresh' end};a.log={info=function() end}
  a:handle_power_event('wake');T.falsy(a.sleeping);T.falsy(a.updates_paused);T.truthy(a.need_full)
  T.eq(table.concat(seq,','),'active,refresh');T.eq(a.refresh_anchor,1000);T.eq(a.next_screen_at,5200)
  a:handle_power_event('wake');T.eq(#seq,2)
 end)
 T.test('screensaver clears private dashboard and does not use unsupported image decoding',function()
  local R=require('ui.renderer');local ops={}
  local d={width=1072,height=1448,begin_frame=function(_,full) T.truthy(full);ops[#ops+1]='clear' end,
   text=function(_,o) ops[#ops+1]=o.text end,flush=function(_,o) T.truthy(o.full);ops[#ops+1]='flush' end,
   image=function() error('FBInk IMAGE is unavailable') end}
  R.new({display=d}):render_screensaver('no-such-directory')
  T.eq(table.concat(ops,','),'clear,KDASH,已息屏,flush')
 end)
end
