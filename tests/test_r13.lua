return function(T)
 local Dida=require('services.api.dida');local json=require('core.json')
 local now=require('core.timeutil').parse_iso8601('2026-11-11T23:30:00+0800')
 local function sync(wanted,projects,inbox_failed)
  local calls,output={},nil
  local api=Dida.new({now=function() return now end,offset=480,config={module=function() return {project_ids=wanted} end},
   secrets={secret=function(_,k,v) if k=='dida.access_token' then return 'fake' end;return v end},cache={write=function(_,_,v) output=v end},
   http={request=function(_,o,cb)
    T.eq(o.method,'GET');calls[#calls+1]=o.url
    local data={tasks={}}
    if o.url:match('/project$') then data=projects or {{id='p',name='Other'}}
    elseif o.url:match('/inbox/data$') then
     if inbox_failed then cb({ok=false,status=503,error='test failure'});return end
     data={tasks={{id='new',projectId='inbox123',title='Today',dueDate='2026-11-11T00:00:00+0800',isAllDay=true,status=0,priority=5}}}
    end
    cb({ok=true,status=200,body=json.encode(data)})
   end}})
  local ok,err,view;api:sync(function(a,b,c) ok,err,view=a,b,c end)
  return ok,err,view,calls,output
 end
 T.test('all-list sync explicitly reads omitted inbox and preserves concrete project ID',function()
  local ok,err,v,calls,output=sync({});T.eq(output.data.project_data,nil);T.truthy(ok,err);T.eq(#calls,3);T.eq(#v.today,1)
  T.eq(v.today[1].project_id,'inbox123');T.eq(v.today[1].project,'收集箱');T.eq(v.today[1].priority,5)
 end)
 T.test('explicit normal-list selection excludes inbox without changing filter meaning',function()
  local ok,_,v,calls=sync({'p'});T.truthy(ok);T.eq(#calls,2);T.eq(#v.today,0)
 end)
 T.test('literal or concrete inbox selection reads inbox once and never duplicates listed inbox',function()
  for _,wanted in ipairs({{'inbox'},{'inbox123'}}) do
   local ok,_,v,calls=sync(wanted);T.truthy(ok);T.eq(#calls,2);T.eq(#v.today,1)
  end
  local ok,_,v,calls=sync({},{{id='inbox',name='收集箱'}});T.truthy(ok);T.eq(#calls,2);T.eq(#v.today,1)
 end)
 T.test('inbox failure fails the whole sync rather than silently replacing complete cache',function()
  local ok,_,_,_,output=sync({},nil,true);T.falsy(ok);T.eq(output,nil)
 end)
 T.test('weather labels stay in fixed rows even when day and night curves cross',function()
  local P=require('ui.weather_panel');local rect={x=56,y=930,w=960,h=350};local texts={}
  local no=function() end
  local ui={display={line=no,circle=no,fill=no},typo={fit=function(_,s) return s end},text=function(_,o) texts[#texts+1]=o end}
  local ctx={now=function() return now end,config={data={utc_offset_minutes=480},module=function() return {solar_location={latitude=34.2,longitude=118.8}} end}}
  P.render(ctx,ui,rect,{city='Test',desc='晴',temp=-15,humidity=100,wind_direction='东北',wind_power='≤3',days={{date='2026-11-11',high=-5,low=15},{date='2026-11-12',high=14,low=13}}},{})
  local ys={}
  for _,o in ipairs(texts) do
   T.truthy(o.y>=rect.y and o.y+o.size<=rect.y+rect.h+1)
   if o.text=='-5°' or o.text=='14°' then ys.day=ys.day or o.y;T.eq(ys.day,o.y) end
   if o.text=='15°' or o.text=='13°' then ys.night=ys.night or o.y;T.eq(ys.night,o.y) end
  end
  T.truthy(ys.night>ys.day+40)
 end)
end
