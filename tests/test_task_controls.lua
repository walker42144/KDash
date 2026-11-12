return function(T)
 local UI=require('ui.components');local Theme=require('ui.theme');local Typo=require('ui.typography');local Events=require('core.events');local json=require('core.json')
 local function fixture()
  local M=assert(loadfile('modules/dida/init.lua'))()
  local view={today={{id='parent',project_id='p',title='Parent',due_key='1970-01-01',checklist={{id='item',title='Checklist child',status=0}},
   children={{id='child',project_id='p',title='Nested child',checklist={},children={}}}}},overdue={},upcoming={},undated={}}
  local requests,updates={},0
  local ctx={config={data={language='zh'},module=function() return {allow_complete=true} end},
   secrets={secret=function(_,k,d) if k=='dida.access_token' then return 'fake' end;return d end},
   cache={read=function() return {data={view=view},fetched_at=1000} end,write=function() end},
   now=function() return 1000 end,request_update=function() end,request_immediate_update=function() updates=updates+1 end,finish=function() end,
   http={request=function(_,opts,cb) requests[#requests+1]={opts=opts,cb=cb} end}}
  ctx.log={info=function(_,message) assert(not message:find('fake',1,true),'token leaked to log') end}
  M.init(ctx)
  local events=Events.new();local display={text=function() end,fill=function() end,hline=function() end,vline=function() end}
  local ui=UI.new({display=display,theme=Theme.new({}),typo=Typo.new({}),events=events,module_id='dida'})
  local function render() events:clear_hits();M.render(ctx,ui,{x=56,y=500,w=960,h=440},{overview=true}) end
  return M,ctx,view,requests,events,render
 end
 T.test('task checkbox and expansion override background sync hit; subtask targets remain distinct',function()
  local M,ctx,view,requests,events,render=fixture();render()
  local parent,expand
  for _,hit in ipairs(events.hits) do if hit.label=='complete' then parent=hit elseif hit.label=='expand' then expand=hit end end
  T.eq(events:hit_test(parent.x+10,parent.y+10).action,'module_action')
  M.on_action(ctx,parent.payload);T.eq(#requests,0,'unfinished children block parent before network write')
  render();local item,child
  for _,hit in ipairs(events.hits) do
   if hit.label=='complete' and hit.payload.item_id then item=hit end
   if hit.label=='complete' and hit.payload.task_id=='child' then child=hit end
  end
  T.truthy(item);T.truthy(child);T.eq(item.payload.task_id,'parent');T.eq(child.payload.item_id,nil)
  T.eq(events:hit_test(item.x+10,item.y+10).payload.item_id,'item')
 end)
 T.test('module leaves checkbox unchanged until server write and readback acknowledge it',function()
  local M,ctx,view,requests,events,render=fixture()
  local action={kind='complete',project_id='p',task_id='parent',item_id='item'}
  M.on_action(ctx,action);T.eq(view.today[1].checklist[1].status,0);T.eq(#requests,1)
  M.on_action(ctx,action);T.eq(#requests,1,'duplicate touch suppressed')
  requests[1].cb({ok=true,status=200,body=json.encode({id='parent',items={{id='item',title='Child',status=0}}})})
  T.eq(#requests,2);T.eq(view.today[1].checklist[1].status,0)
  requests[2].cb({ok=true,status=200,body=''})
  T.eq(view.today[1].checklist[1].status,0)
  requests[3].cb({ok=true,status=200,body=json.encode({items={{id='item',status=1}}})})
  T.eq(view.today[1].checklist[1].status,1)
  T.falsy(view.today[1].completed,'checking child never completes parent')
  T.eq(requests[4].opts.method,'GET','follow-up is a read, not another completion')
 end)
 T.test('failed completion retains old checkbox and no offline replay is scheduled',function()
  local M,ctx,view,requests,events,render=fixture()
  M.on_action(ctx,{kind='complete',project_id='p',task_id='child'})
  requests[1].cb({ok=true,status=200,body=json.encode({tasks={{id='child',parentId='parent',status=0}}})})
  requests[2].cb({ok=false,status=403,body=''})
  T.falsy(view.today[1].children[1].completed);T.eq(#requests,2)
 end)
 T.test('pagination makes all tasks reachable without changing the home page',function()
  local M,ctx,view,requests,events,render=fixture()
  view.today={}
  for i=1,20 do view.today[i]={id='t'..i,project_id='p',title='Task '..i,due_key='1970-01-01'} end
  local seen={}
  for page=1,4 do
   render();local next_hit
   for _,h in ipairs(events.hits) do
    if h.label=='complete' then seen[h.payload.task_id]=true end
    if h.label=='task-page' and h.payload.delta==1 then next_hit=h end
   end
   T.truthy(next_hit);M.on_action(ctx,next_hit.payload)
  end
  local total=0;for _ in pairs(seen) do total=total+1 end
  T.eq(total,20);T.eq(#requests,0,'paging is local')
 end)
 T.test('priority marks use 0/1/2/3 nine-pixel lines and reserve title space',function()
  for _,case in ipairs({{0,0},{1,1},{3,2},{5,3}}) do
   local shapes={};local ui=UI.new({theme=Theme.new({}),typo=Typo.new({}),display={fill=function(_,rect) shapes[#shapes+1]=rect end}})
   local reserved=ui:priority_marks({x=56,y=100,w=960,h=46},case[1])
   T.eq(#shapes,case[2]);T.eq(reserved,case[2]==0 and 0 or 57)
   for _,rect in ipairs(shapes) do T.eq(rect.w,9);T.eq(rect.h,28);T.eq(rect.y,109);T.truthy(rect.x+rect.w<=1016) end
  end
 end)
 T.test('unconfirmed completion blocks another write until a successful refresh',function()
  local M,ctx,view,requests,events,render=fixture()
  local action={kind='complete',project_id='p',task_id='child'}
  M.on_action(ctx,action)
  requests[1].cb({ok=true,status=200,body=json.encode({tasks={{id='child',status=0}}})})
  requests[2].cb({ok=false,status=0,body=''})
  M.on_action(ctx,action);T.eq(#requests,2)
 end)

 T.test('non-today parent context cannot be completed and today child is immediately visible',function()
  local M,ctx,view,requests,events,render=fixture()
  local parent=view.today[1];parent.date_metadata=true;parent.own_due_key='1970-01-02'
  parent.children[1].date_metadata=true;parent.children[1].own_due_key='1970-01-01'
  render();local child=false
  for _,h in ipairs(events.hits) do
   if h.label=='complete' then T.eq(h.payload.task_id,'child');child=true end
  end
  T.truthy(child);T.eq(#requests,0)
 end)

end
