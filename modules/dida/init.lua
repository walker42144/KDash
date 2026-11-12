-- Interactive task list. Writes are only sent after explicit checkbox taps.
local DidaAPI=require('services.api.dida')
local timeutil=require('core.timeutil')
local util=require('core.util')
local M={}
local state={expanded={},page=1,saving=false,syncing=false,uncertain={}}
local function immediate(ctx) (ctx.request_immediate_update or ctx.request_update)() end
function M.init(ctx)
 state={expanded={},page=1,saving=false,syncing=false,uncertain={}}
 state.adapter=DidaAPI.new({http=ctx.http,config=ctx.config,secrets=ctx.secrets,cache=ctx.cache,log=ctx.log,now=ctx.now,offset=ctx.config.data.utc_offset_minutes or 480})
 local cached=ctx.cache:read('dida')
 if cached and cached.data then state.view=cached.data.view;state.cached_at=cached.fetched_at end
 return true
end
function M.refresh_policy(ctx)
 return {interval=math.max(300,(ctx.config:module('dida').sync_interval_minutes or 15)*60),max_backoff=3600}
end
function M.refresh(ctx,keep_notice)
 if state.syncing or state.saving then return false end
 if not keep_notice then state.notice=nil end
 if state.adapter:auth_state()=='missing' then state.error='AUTH_REQUIRED';ctx.request_update();return true end
 state.syncing=true
 state.adapter:sync(function(ok,err,view)
  state.syncing=false
  if ok then state.view=view;state.cached_at=ctx.now();state.error=nil;state.uncertain={}
  else state.error=tostring(err);if keep_notice then state.notice='完成已提交；列表刷新失败，请稍后刷新核对' end end
  ctx.request_update();ctx.finish(ok,err)
  if keep_notice then immediate(ctx) end
 end)
 return false
end
local messages={OPEN_CHILDREN='请先完成全部子项（可能有其他日期的子任务）',WRITE_FORBIDDEN='口令缺少写入权限，请在电脑端更换令牌',AUTH_REQUIRED='令牌失效，请在电脑配置工具中更换',READ_ONLY='当前仅查看，请在电脑端允许勾选完成',BUSY='正在提交，请稍候',
 WRITE_UNCONFIRMED='完成结果未确认，请点击空白处刷新核对',READ_FAILED='读取最新任务失败，未发送完成操作',ITEM_NOT_FOUND='子项已变化，请刷新后重试',TASK_NOT_FOUND='任务已变化，请刷新后核对',TASK_ALREADY_COMPLETED='父任务已完成，请刷新核对',TASK_CHANGED='重复任务已进入下一次，请先刷新核对'}
local function key(task) return tostring(task.project_id)..':'..tostring(task.id) end
local function counts(task)
 local done,total=0,0
 for _,c in ipairs(task.checklist or {}) do total=total+1;if tonumber(c.status)==1 then done=done+1 end end
 for _,c in ipairs(task.children or {}) do
  total=total+1;if c.completed then done=done+1 end
  local d,t=counts(c);done=done+d;total=total+t
 end
 return done,total
end
local function find_task(view,target)
 local function visit(tasks)
  for _,task in ipairs(tasks or {}) do
   if task.id==target.task_id and task.project_id==target.project_id then return task end
   local found=visit(task.children);if found then return found end
  end
 end
 for _,bucket in ipairs({'overdue','today','upcoming','undated'}) do local t=visit(view and view[bucket]);if t then return t end end
end
function M.on_action(ctx,action)
 if action.kind=='page' then state.page=math.max(1,state.page+(action.delta or 0));immediate(ctx);return end
 if action.kind=='expand' then state.expanded[action.key]=not state.expanded[action.key];immediate(ctx);return end
 if action.kind~='complete' then return end
 if state.saving or state.syncing then state.notice='正在同步或提交，请稍候';immediate(ctx);return end
 if ctx.config:module('dida').allow_complete==false then state.notice=messages.READ_ONLY;immediate(ctx);return end
 local task=find_task(state.view,action)
 if not task then state.notice=messages.TASK_NOT_FOUND;immediate(ctx);return end
 if state.uncertain[key(task)] then state.notice='请先点击空白处刷新核对完成状态，再操作';immediate(ctx);return end
 if not action.item_id then
  local done,total=counts(task)
  if done<total then state.notice=messages.OPEN_CHILDREN;state.expanded[key(task)]=true;immediate(ctx);return end
 end
 state.saving=true;state.notice='正在提交完成…';immediate(ctx)
 if ctx.log then ctx.log:info('dida completion started kind='..(action.item_id and 'checklist' or 'task')) end
 state.adapter:complete(action,function(ok,err)
  state.saving=false
  if ctx.log then ctx.log:info("dida completion result ok="..tostring(ok).." code="..tostring(err or "OK")) end
  if not ok then
   if err=='WRITE_UNCONFIRMED' then state.uncertain[key(task)]=true end
   state.notice=messages[err] or '操作未完成，请刷新核对';immediate(ctx);ctx.finish(false,err);return end
  if action.item_id then
   for _,item in ipairs(task.checklist or {}) do if item.id==action.item_id then item.status=1 end end
  else task.completed=true end
  -- Persist only server-acknowledged state, never optimistic/offline completion.
  ctx.cache:write('dida',{data={view=state.view},fetched_at=state.cached_at or ctx.now()})
  state.notice=action.item_id and '子项已完成，父任务保留' or '任务已完成'
  immediate(ctx);M.refresh(ctx,true)
 end)
end
local function rows_for(view,ctx,selected)
 local rows={}
 local function add(tasks,depth)
  for _,task in ipairs(tasks or {}) do
   local done,total=counts(task)
   rows[#rows+1]={task=task,depth=depth,done=done,total=total}
   if task.context_only or state.expanded[key(task)] then
    for _,item in ipairs(task.checklist or {}) do rows[#rows+1]={task=task,item=item,depth=depth+1} end
    add(task.children,depth+1)
   end
  end
 end
 local today=timeutil.date_key(ctx.now(),ctx.config.data.utc_offset_minutes or 480)
 add(selected or require('services.today_tasks').select(view,today),0)
 return rows
end
function M.render(ctx,ui,rect,opts)
 local t=ui.theme;local micro=t.type.micro
 -- Background refresh is registered first so row controls have precedence.
 ui:hit(rect,'module_sync','dida','dida-sync')
 if not state.view then
  ui:empty(rect,'暂无任务数据')
  ui:text({text=state.error and '请检查令牌与网络，点击刷新' or '等待首次同步',x=rect.x,y=rect.y+rect.h-ui.typo:line_height(micro),w=rect.w,size=micro})
  return
 end
 local view=state.view
 local today=timeutil.date_key(ctx.now(),ctx.config.data.utc_offset_minutes or 480)
 local selected=require('services.today_tasks').select(view,today)
 local pending=require('services.today_tasks').pending_count(selected)
 local done=view.today_completed or 0
 if view.synced_at and timeutil.date_key(view.synced_at,ctx.config.data.utc_offset_minutes or 480)~=today then done=0 end
 ui:text({text=string.format('%d / %d 完成',done,pending+done),x=rect.x,y=rect.y,w=rect.w,size=micro,color=t.colors.muted})
 local by=rect.y+ui.typo:line_height(micro)+t.space.xs
 ui:progress({x=rect.x,y=by,w=rect.w,h=t.line*3},pending+done>0 and math.floor(done*100/(pending+done)) or 0)
 local y=by+t.line*3+t.space.sm;local row_h=math.max(44,ui.typo:line_height(32))
 local status_h=math.max(40,ui.typo:line_height(micro))
 local available=rect.y+rect.h-y-status_h
 local rows=rows_for(view,ctx,selected);local page_rows={{}};local used=0
 for _,row in ipairs(rows) do
  local task,item=row.task,row.item;local indent=math.min(row.depth,4)*32
  row.title=item and item.title or task.title
  if task.context_only then row.title='所属任务：'..row.title end
  row.meta=task.context_only and '今日子任务' or (not item and row.total>0 and (string.format('%d/%d ',row.done,row.total)..(state.expanded[key(task)] and '收起' or '展开')) or nil)
  row.priority=task.context_only and 0 or (item and (item.priority or 0) or task.priority)
  row.reserved=ui:priority_reserve(row.priority)
  row.opts={size=(item or row.depth>0) and 28 or 32,badges=task.context_only and {} or require('services.task_metadata').badges(item or task,ctx.config.data.utc_offset_minutes or 480)}
  row.indent=indent;row.width=rect.w-indent-row.reserved
  -- A task with unusually many tags can continue on later pages without
  -- painting over the footer. Continuations have no completion checkbox.
  local chunks={};local all=row.opts.badges;local cursor=1;local first_chunk=true
  repeat
   local chunk={};for k,v in pairs(row) do chunk[k]=v end
   chunk.opts={size=row.opts.size,badges={},no_checkbox=not first_chunk}
   chunk.continuation=not first_chunk
   if not first_chunk then chunk.title=row.title..'（续）';chunk.meta=nil end
   while cursor<=#all do
    chunk.opts.badges[#chunk.opts.badges+1]=all[cursor]
    if ui:task_layout({w=row.width},chunk.title,chunk.meta,chunk.opts).h>available and #chunk.opts.badges>1 then
     table.remove(chunk.opts.badges);break
    end
    cursor=cursor+1
   end
   chunk.h=ui:task_layout({w=row.width},chunk.title,chunk.meta,chunk.opts).h
   chunks[#chunks+1]=chunk;first_chunk=false
  until cursor>#all
  for _,chunk in ipairs(chunks) do
   if used+chunk.h>available and #page_rows[#page_rows]>0 then page_rows[#page_rows+1]={};used=0 end
   page_rows[#page_rows][#page_rows[#page_rows]+1]=chunk;used=used+chunk.h
  end
 end
 local pages=#page_rows;state.pages=pages;state.page=math.max(1,math.min(state.page,pages))
 for _,row in ipairs(page_rows[state.page]) do
  local task,item=row.task,row.item
  local rr={x=rect.x+row.indent,y=y,w=rect.w-row.indent,h=44}
  local completed=item and tonumber(item.status)==1 or (not item and task.completed)
  if not row.continuation then ui:priority_marks(rr,row.priority) end
  ui:task_with_badges({x=rr.x,y=y,w=row.width,h=row.h},row.title,row.meta,completed,row.opts)
  if not row.continuation and not task.context_only and not completed and task.id and task.project_id and (not item or item.id) then
   ui:hit({x=rr.x,y=y,w=56,h=44},'module_action',{module='dida',kind='complete',project_id=task.project_id,task_id=task.id,item_id=item and item.id,expected_due=task.source_due},'complete')
  end
  if not row.continuation and not item and not task.context_only and row.total>0 then
   ui:hit({x=rr.x+56,y=y,w=rr.w-56,h=row.h},'module_action',{module='dida',kind='expand',key=key(task)},'expand')
  end
  y=y+row.h
 end
 if #rows==0 then ui:empty({x=rect.x,y=y,w=rect.w,h=row_h*2},'今天没有待办任务') end
 local status=state.notice or (state.error and '同步失败，保留缓存；点击空白处刷新') or (state.cached_at and ('同步于 '..timeutil.format_time(state.cached_at,ctx.config.data.utc_offset_minutes or 480,true))) or '尚未同步'
 local sy=rect.y+rect.h-status_h;local nav_w=250
 ui:text({text=ui.typo:fit(status,rect.w-nav_w-16,micro),x=rect.x,y=sy+7,w=rect.w-nav_w-16,size=micro,color=t.colors.muted})
 local x=rect.x+rect.w-nav_w
 for _,b in ipairs({{label='上',delta=-1,x=x,enabled=state.page>1},{label='下',delta=1,x=x+180,enabled=state.page<pages}}) do
  local box={x=b.x,y=sy,w=70,h=40};local color=b.enabled and t.colors.ink or t.colors.faint
  ui:rounded_box(box,6,color)
  ui:page_chevron(box,b.delta<0,color)
  ui:hit(box,b.enabled and 'module_action' or 'noop',b.enabled and {module='dida',kind='page',delta=b.delta} or nil,'task-page')
 end
 ui:text({text=state.page..'/'..pages,x=x+70,y=sy+7,w=110,size=micro,align='center'})
end
return M
