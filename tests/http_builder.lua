local root=assert(arg[2]);package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
local f=assert(io.open(arg[1],'rb'));local d=require('core.json').decode(f:read('*a'));f:close()
local h=require('services.http').new({});h.curl='curl'
local text=h:build_script(d.opts,d.paths);local out=assert(io.open(d.output,'wb'));out:write(text);out:close()
