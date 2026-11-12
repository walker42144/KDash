local root=assert(arg[2]);package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
local f=assert(io.open(arg[1],'rb'));local d=require('core.json').decode(f:read('*a'));f:close()
local h=require('services.http').new({});h.curl='curl'
local text=h:build_script(d.opts,d.paths);local out=assert(io.open(d.output,'wb'));out:write(text);out:close()
if d.spawn_output then
 local execute=os.execute
 os.execute=function(cmd) local f=assert(io.open(d.spawn_output,'wb'));f:write(cmd);f:close();return 0 end
 require('platform.kindle.runner').new({}):spawn_script(d.paths.script,d.paths.worker)
 os.execute=execute
end
