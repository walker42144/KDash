return function(T)
 local Dida=require('services.api.dida');local json=require('core.json');local util=require('core.util')
 local now=require('core.timeutil').parse_iso8601('2026-11-11T12:00:00+0800')
 local function fixture(steps,allow)
  local calls,waiting={},{}
  local ctx={config={data={language='zh'},module=function() return {allow_complete=allow} end},
   secrets={secret=function(_,key,default) if key=='dida.access_token' then return 'fake-token' end;return default end},
   cache={write=function() end},now=function() return now end}
  ctx.http={request=function(_,opts,cb)
   calls[#calls+1]=opts;local step=steps[#calls];assert(step,'unexpected request '..opts.url)
   assert(opts.method==step.method,'unexpected method')
   assert(opts.url:find(step.path,1,true),'unexpected path '..opts.url)
   local res={ok=step.ok~=false,status=step.status or 200,body=step.body or (step.data and json.encode(step.data)) or ''}
   if step.defer then waiting[#waiting+1]=function() cb(res) end else cb(res) end
  end}
  return Dida.new(ctx),calls,waiting,ctx
 end
 local function run(steps,target,allow)
  local api,calls=fixture(steps,allow);local success,error
  api:complete(target or {project_id='p',task_id='parent'},function(ok,err) success,error=ok,err end)
  return success,error,calls
 end
 T.test('completion waits for acknowledgement, serializes duplicate taps and accepts empty success body',function()
  local api,calls,waiting=fixture({{method='GET',path='/project/p/data',data={tasks={{id='child',parentId='parent',status=0}}}},
   {method='POST',path='/project/p/task/child/complete',defer=true}})
  local result=nil
  api:complete({project_id='p',task_id='child'},function(ok) result=ok end)
  T.eq(result,nil);T.eq(#calls,2)
  api:complete({project_id='p',task_id='child'},function(ok,err) T.falsy(ok);T.eq(err,'BUSY') end)
  T.eq(#calls,2);waiting[1]();T.truthy(result);T.falsy(api.writing)
 end)
 T.test('parent with unfinished checklist items sends no write',function()
  local ok,err,calls=run({{method='GET',path='/data',data={tasks={{id='parent',items={{id='i',status=0}}}}}}})
  T.falsy(ok);T.eq(err,'OPEN_CHILDREN');T.eq(#calls,1)
 end)
 T.test('parent with unfinished nested tasks sends no write',function()
  local ok,err,calls=run({{method='GET',path='/data',data={tasks={{id='parent'},{id='child',parentId='parent',status=0}}}}})
  T.falsy(ok);T.eq(err,'OPEN_CHILDREN');T.eq(#calls,1)
 end)
 T.test('parent completes only after all children are already complete',function()
  local ok,err,calls=run({{method='GET',path='/data',data={tasks={{id='parent',items={{id='i',status=1}}},{id='child',parentId='parent',status=2}}}},
   {method='POST',path='/project/p/task/parent/complete'}})
  T.truthy(ok);T.eq(#calls,2)
 end)
 T.test('checklist completion patches freshest item list and preserves siblings and fields',function()
  local fresh={id='parent',projectId='p',title='keep',etag='v2',items={{id='a',title='first',status=0,sortOrder=1},{id='b',title='new phone edit',status=0,extra='keep'}}}
  local snapshot=util.deep_copy(fresh)
  local ok,err,calls=run({{method='GET',path='/project/p/task/parent',data=fresh},
   {method='POST',path='/task/parent'},
   {method='GET',path='/project/p/task/parent',data={items={{id='a',status=1},{id='b',status=0}}}}},
   {project_id='p',task_id='parent',item_id='a'})
  T.truthy(ok);local body=json.decode(calls[2].body)
  T.eq(body.items[1].status,1);T.eq(body.items[2].status,0);T.eq(body.items[2].extra,'keep')
  T.eq(body.etag,'v2');T.eq(body.title,nil);T.eq(body.status,nil);T.eq(fresh.items[1].status,snapshot.items[1].status)
 end)
 T.test('checklist write is unconfirmed if readback does not show completion',function()
  local ok,err=run({{method='GET',path='/task/parent',data={id='parent',items={{id='a',status=0}}}},
   {method='POST',path='/task/parent'},{method='GET',path='/task/parent',data={items={{id='a',status=0}}}}},
   {project_id='p',task_id='parent',item_id='a'})
  T.falsy(ok);T.eq(err,'WRITE_UNCONFIRMED')
 end)
 T.test('write forbidden and timeout do not claim completion or retry',function()
  for _,status in ipairs({403,0}) do
   local ok,err,calls=run({{method='GET',path='/data',data={tasks={{id='parent'}}}},
    {method='POST',path='/complete',ok=false,status=status}})
   T.falsy(ok);T.eq(err,status==403 and 'WRITE_FORBIDDEN' or 'WRITE_UNCONFIRMED');T.eq(#calls,2)
  end
 end)
 T.test('read-only configuration never sends completion requests',function()
  local ok,err,calls=run({},nil,false);T.falsy(ok);T.eq(err,'READ_ONLY');T.eq(#calls,0)
 end)
 T.test('view preserves hierarchy, undated children and checklist status without modifying inputs',function()
  local data={p={tasks={{id='parent',title='Parent',dueDate='2026-11-11',isAllDay=true,parentId=json.null,items={{id='a',title='item',status=1}}},
   {id='child',title='Child',parentId='parent',status=0},{id='grand',title='Grandchild',parentId='child',status=0}}}}
  local view=Dida.build_view({{id='p',name='P'}},data,now,480,{})
  T.eq(#view.today,1);local root=view.today[1]
  T.eq(root.checklist[1].status,1);T.eq(root.children[1].id,'child');T.eq(root.children[1].children[1].id,'grand')
  T.eq(data.p.tasks[1].__project_id,nil)
 end)
 T.test('view handles cyclic parent links without recursion failure',function()
  local view=Dida.build_view({}, {p={tasks={{id='a',title='A',parentId='b'},{id='b',title='B',parentId='a'}}}},now,480,{})
  T.eq(#view.undated,2)
 end)
 T.test('stale recurring task cannot accidentally complete its next occurrence',function()
  local ok,err,calls=run({{method='GET',path='/data',data={tasks={{id='parent',repeatFlag='RRULE:FREQ=DAILY',dueDate='2026-11-12'}}}}},
   {project_id='p',task_id='parent',expected_due='2026-11-11'})
  T.falsy(ok);T.eq(err,'TASK_CHANGED');T.eq(#calls,1)
 end)

 T.test('omitted completed child is checked individually before parent completion',function()
  local ok,err,calls=run({{method='GET',path='/data',data={tasks={{id='parent',childIds={'child'}}}}},
   {method='GET',path='/task/child',data={id='child',status=2}},
   {method='POST',path='/project/p/task/parent/complete'}})
  T.truthy(ok);T.eq(#calls,3)
 end)

 T.test('null recurrence fields do not block normal undated task completion',function()
  local ok,err=run({{method='GET',path='/data',data={tasks={{id='parent',repeatFlag=json.null,dueDate=json.null}}}},
   {method='POST',path='/complete'}})
  T.truthy(ok)
 end)

end

