return function(T)
 local Http=require('services.http')
 local function fixture()
  local now=1000; local storage={files={}};local runner={scripts={}}
  function storage:write(p,v) self.files[p]=v;return true end
  function storage:read(p) return self.files[p] end
  function storage:exists(p) return self.files[p]~=nil end
  function storage:remove(p) self.files[p]=nil end
  function storage:chmod() return true end
  function runner:spawn_script(p) self.scripts[#self.scripts+1]=p;return 0 end
  local h=Http.new{storage=storage,runner=runner,dir='/tmp/test',now=function()return now end}
  local function finish(n,rc,status)
   local prefix='/tmp/test/http-'..now..'-'..n
   storage.files[prefix..'.done']='done';storage.files[prefix..'.rc']=tostring(rc);storage.files[prefix..'.status']=tostring(status);storage.files[prefix..'.out']='{}';storage.files[prefix..'.err']=''
  end
  return h,storage,runner,finish,function(x)now=x end
 end
 T.test('new requests created by callbacks wait for the next poll',function()
  local early=0
  for attempt=1,200 do
   local s={exists=function(_,p)return p=='done'end,read=function(_,p)if p=='rc'then return '0' elseif p=='status'then return '200'else return ''end end,remove=function()end,write=function()end}
   local h=Http.new{storage=s,runner={},dir='/tmp',now=function()return 100 end};local count=0
   for j=1,(attempt%4+1) do
    local id='old-'..j..'-'..attempt
    h.jobs[id]={id=id,paths={done='done',rc='rc',status='status',out='out',err='err'},started=100,timeout=30,max_bytes=1000,label='fake',cb=function()
     local key='new-'..j..'-'..attempt;h.jobs[key]={id=key,paths={done='done',rc='rc',status='status',out='out',err='err'},started=100,timeout=30,max_bytes=1000,label='fake',cb=function()count=count+1 end}
    end}
   end
   h:poll();if count>0 then early=early+1 end
  end
  T.eq(early,0,'callbacks must not extend the active iteration')
 end)
 T.test('transient GET retries are delayed and bounded to three attempts',function()
  local h,s,r,finish,clock=fixture();local result
  h:request({url='https://example.com',method='GET'},function(x)result=x end)
  finish(1,0,503);h:poll();T.eq(result,nil);T.eq(#r.scripts,1)
  clock(1004);h:poll();T.eq(#r.scripts,1)
  clock(1005);h:poll();T.eq(#r.scripts,2)
  finish(2,0,503);h:poll();T.eq(result,nil)
  clock(1015);h:poll();T.eq(#r.scripts,3)
  finish(3,0,503);h:poll();T.truthy(result);T.eq(result.ok,false);T.eq(#r.scripts,3)
 end)
 T.test('POST failure and authentication errors are never blindly retried',function()
  for _,case in ipairs({{method='POST',rc=28,status=0},{method='GET',rc=0,status=401},{method='GET',rc=28,status=401},{method='GET',rc=0,status=429}}) do
   local h,s,r,finish,clock=fixture();local result
   h:request({url='https://example.com',method=case.method},function(x)result=x end)
   finish(1,case.rc,case.status);h:poll();T.truthy(result);T.eq(result.ok,false)
   clock(1100);h:poll();T.eq(#r.scripts,1)
  end
 end)
 T.test('an unreadable response is not misreported as oversized',function()
  local h,s,r,finish=fixture();local result
  local oldread=s.read
  function s:read(p) if p:match('%.out$') then return nil,'cannot open temporary output' end;return oldread(self,p) end
  h:request({url='https://example.com',method='POST'},function(x)result=x end)
  finish(1,0,200);h:poll();T.truthy(result);T.eq(result.ok,false);T.eq(result.error,'response unavailable')
 end)
 T.test('cancelling pending retry calls callback once and prevents resend',function()
  local h,s,r,finish,clock=fixture();local calls=0
  h:request({url='https://example.com',method='GET'},function()calls=calls+1 end)
  finish(1,0,503);h:poll();T.eq(calls,0);h:cancel_all();T.eq(calls,1)
  clock(1100);h:poll();T.eq(#r.scripts,1);T.eq(calls,1)
 end)
 T.test('successful retry completes once and clears pending state',function()
  local h,s,r,finish,clock=fixture();local calls,result=0,nil
  h:request({url='https://example.com',method='GET'},function(x)calls=calls+1;result=x end)
  finish(1,28,0);h:poll();T.truthy(h:busy());T.eq(calls,0)
  clock(1005);h:poll();finish(2,0,200);h:poll();T.eq(calls,1);T.eq(result.ok,true);T.falsy(h:busy())
 end)
 T.test('sleep or paused updates cancel deferred retries without new requests',function()
  local h,s,r,finish,clock=fixture();local calls,result=0,nil
  h:request({url='https://example.com',method='GET'},function(x)calls=calls+1;result=x end)
  finish(1,0,503);h:poll(false);T.eq(calls,1);T.eq(result.error,'cancelled');T.falsy(h:busy())
  clock(1100);h:poll(false);T.eq(#r.scripts,1);T.eq(calls,1)
 end)
 T.test('a callback can cancel other jobs without repeat completion',function()
  local h,s,r,finish=fixture();local calls=0
  h:request({url='https://example.com/a'},function()calls=calls+1;h:cancel_all() end)
  h:request({url='https://example.com/b'},function()calls=calls+1 end)
  finish(1,0,200);finish(2,0,200);h:poll();T.eq(calls,2);T.falsy(h:busy())
 end)
 T.test('network poll error is isolated and paused without stopping the app',function()
  local App=require('core.app');local polls,cancels,warns=0,0,0
  local app=App.new({});app.http={closed=false,poll=function()polls=polls+1;error('synthetic')end,cancel_all=function(self)cancels=cancels+1;self.closed=true end}
  app.log={warn=function()warns=warns+1 end,error=function()end}
  app:poll_http_safely(100);T.eq(polls,1);T.eq(cancels,1);T.falsy(app.http.closed)
  app:poll_http_safely(102);T.eq(polls,1)
  app:poll_http_safely(105);T.eq(polls,2);T.eq(cancels,2);T.truthy(warns>0)
  app:poll_http_safely(115);T.eq(polls,3);T.eq(cancels,3)
  app:poll_http_safely(174);T.eq(polls,3)
  app:poll_http_safely(175);T.eq(polls,4)
 end)
 T.test('network poll cleanup failure disables the subsystem without crashing',function()
  local App=require('core.app');local polls=0
  local app=App.new({});app.http={poll=function()polls=polls+1;error('synthetic')end,cancel_all=function()error('cleanup')end}
  app.log={warn=function()end,error=function()end}
  app:poll_http_safely(1);T.truthy(app.http_disabled)
  app:poll_http_safely(1000);T.eq(polls,1)
 end)
 T.test('network poll suppresses deferred retries in sleep and paused mode',function()
  local App=require('core.app');local values={}
  local app=App.new({});app.http={poll=function(_,allowed)values[#values+1]=allowed end}
  app.sleeping=true;app:poll_http_safely(1)
  app.sleeping=false;app.updates_paused=true;app:poll_http_safely(2)
  app.manual_batch={};app:poll_http_safely(3)
  T.eq(values[1],false);T.eq(values[2],false);T.eq(values[3],true)
 end)
 T.test('many successful requests leave no retained jobs or retry entries',function()
  local h,s,r,finish=fixture();local calls=0
  for i=1,5000 do
   h:request({url='https://example.com',method='GET'},function()calls=calls+1 end)
   finish(i,0,200);h:poll();T.falsy(h:busy())
  end
  T.eq(calls,5000);T.eq(#h.retries,0);T.eq(next(h.jobs),nil)
 end)
end
