return function(T)
 local Today=require('services.today_tasks');local App=require('core.app')
 local function task(id,date,children)
  return {id=id,title=id,project_id='p',date_metadata=true,own_due_key=date,children=children or {},checklist={}}
 end
 T.test('today filter excludes old future and undated roots regardless of cached bucket',function()
  local view={today={task('old','2026-11-10'),task('today','2026-11-11')},upcoming={task('future','2026-11-12')},undated={task('none')}}
  local selected=Today.select(view,'2026-11-11');T.eq(#selected,1);T.eq(selected[1].id,'today')
 end)
 T.test('today parent stays visible when old child changed its legacy effective due date',function()
  local parent=task('parent','2026-11-11',{task('old','2026-11-10')});parent.due_key='2026-11-10'
  local selected=Today.select({overdue={parent}},'2026-11-11')
  T.eq(#selected,1);T.eq(#selected[1].children,0);T.eq(#parent.children,1,'source tree retained for completion guard')
 end)
 T.test('today tree retains checklist items and inherited-date children but hides future children',function()
  local parent=task('parent','2026-11-11',{task('none'),task('tomorrow','2026-11-12')})
  parent.checklist={{id='item',title='Checklist child'}}
  local selected=Today.select({today={parent}},'2026-11-11')
  T.eq(#selected[1].checklist,1);T.eq(#selected[1].children,1);T.eq(selected[1].children[1].id,'none')
 end)
 T.test('today child under non-today parent keeps read-only context',function()
  local parent=task('parent','2026-11-12',{task('child','2026-11-11')})
  local selected=Today.select({upcoming={parent}},'2026-11-11')
  T.eq(#selected,1);T.truthy(selected[1].context_only);T.eq(selected[1].children[1].id,'child')
  T.eq(Today.pending_count(selected),1)
 end)
 T.test('today projection rolls over cached buckets at midnight',function()
  local view={today={task('yesterday','2026-11-11')},upcoming={task('newday','2026-11-12')}}
  local selected=Today.select(view,'2026-11-12');T.eq(#selected,1);T.eq(selected[1].id,'newday')
 end)
 T.test('paused app skips scheduling and automatic redraw while allowing manual redraw',function()
  local ticked,draws=0,0
  local a=App.new({config={data={ui={refresh_minutes=5}}},clock={now=function() return 1000 end}})
  a.updates_paused=true;a.refresh_anchor=1000;a.next_screen_at=1300;a.dirty.clock=true
  a.scheduler={tick=function() ticked=ticked+1;return {} end};a.renderer={render_dirty=function() draws=draws+1 end}
  a:refresh_due(1300);T.eq(ticked,0);T.falsy(a:render_pending(1300));T.eq(draws,0)
  a.force_render=true;T.truthy(a:render_pending(1301));T.eq(draws,1);T.eq(a.next_screen_at,1600)
 end)
 T.test('master switch persists choice and resumes without resetting refresh baseline',function()
  local saved,forced=0,0
  local a=App.new({config={data={ui={direct_exit=true}},save=function() saved=saved+1 end},clock={now=function() return 1000 end}})
  a.refresh_anchor=1000;a.scheduler={force_all=function() forced=forced+1 end}
  a.http={cancel_all=function() error('must not interrupt pending write') end}
  a:handle_action({action='toggle_updates'});T.truthy(a.updates_paused);T.eq(a.config.data.ui.auto_update,false)
  a:handle_action({action='exit_request'});T.truthy(a.stop)
  a:handle_action({action='toggle_updates'});T.falsy(a.updates_paused);T.eq(forced,1);T.eq(saved,2);T.eq(a.refresh_anchor,1000)
 end)
end
