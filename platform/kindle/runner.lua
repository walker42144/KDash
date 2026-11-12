-- 子进程执行封装：统一捕获输出并记录失败。
local util = require("core.util")

local Runner = {}
Runner.__index = Runner

function Runner.new(opts)
    local self = setmetatable({}, Runner)
    self.log = opts and opts.log
    self.timeout_script=(opts and opts.timeout_script) or os.getenv('KDASH_COMMAND_TIMEOUT')
    self.popen=(opts and opts.popen) or io.popen
    self.posix=opts and opts.posix
    return self
end

function Runner:build(argv)
    local parts = {}
    for _, a in ipairs(argv) do
        parts[#parts + 1] = util.shell_quote(tostring(a))
    end
    return table.concat(parts, " ")
end

function Runner:run(argv, timeout_note, seconds)
    if self.timeout_script then
        local bounded={'/bin/sh',self.timeout_script,tostring(seconds or 8)}
        for _,a in ipairs(argv) do bounded[#bounded+1]=a end
        argv=bounded
    end
    local cmd = self:build(argv)
    -- LuaJIT's Lua 5.1 pclose can return true even for exit status != 0.
    -- Read an explicit status trailer from the shell on the POSIX device.
    local posix=self.posix==true or (self.posix==nil and package.config:sub(1,1)~='\\')
    if posix then cmd='('..cmd..'); rc=$?; printf "\\n__KDASH_RC__%s\\n" "$rc"' end
    local f = self.popen(posix and ('('..cmd..') 2>&1') or (cmd..' 2>&1'))
    if not f then
        if self.log then self.log:error("spawn failed: " .. cmd) end
        return -1, ""
    end
    local output = f:read("*a") or ""
    local ok, why, code = f:close()
    if posix then
        local body,status=output:match('^(.*)\n__KDASH_RC__(%d+)\r?\n$')
        code=tonumber(status) or -1;ok=code==0;why='exit'
        if body then output=body end
    end
    if not ok then
        if self.log then
            self.log:warn(string.format("command failed (%s %s): %s => %s",
                tostring(why), tostring(code), timeout_note or cmd, util.trim(output)))
        end
        return code or -1, output
    end
    return 0, output
end

function Runner:run_shell(cmd)
    if self.timeout_script then return self:run({'/bin/sh','-c',cmd},'local OS query') end
    local f = io.popen(cmd .. " 2>&1")
    if not f then return -1, "" end
    local output = f:read("*a") or ""
    local ok, why, code = f:close()
    if not ok then return code or -1, output end
    return 0, output
end

-- 后台执行一个脚本文件，完成标记由脚本自己写入。
function Runner:spawn_script(script_path,worker_pidfile)
    local cmd = "sh " .. util.shell_quote(script_path) .. " >/dev/null 2>&1 &"
    if not worker_pidfile then return os.execute(cmd) end
    -- Publish ownership before the HTTP script can send a request. If publishing
    -- fails, exec never runs; a late-starting worker sees the cancel marker.
    local worker='umask 077; echo "$$ $(awk \'{print $22}\' /proc/$$/stat)" > '..util.shell_quote(worker_pidfile)
        ..' || exit 1; exec sh '..util.shell_quote(script_path)
    return os.execute('sh -c '..util.shell_quote(worker)..' >/dev/null 2>&1 &')
end

function Runner:cancel_http(paths)
    local files=util.shell_quote(paths.pid)..' '..util.shell_quote(paths.worker)
    local identity='read p stamp < "$file"; case "$p:$stamp" in *[!0-9:]*|:|*:) continue;; esac; '
        ..'[ "$(awk \'{print $22}\' /proc/$p/stat 2>/dev/null)" = "$stamp" ] || continue; '
    local cmd='known=0; for file in '..files..'; do [ -r "$file" ] || continue; read p stamp < "$file"; '
        ..'case "$p:$stamp" in *[!0-9:]*|:|*:) continue;;esac; known=1; '
        ..'[ "$(awk \'{print $22}\' /proc/$p/stat 2>/dev/null)" = "$stamp" ] || continue; kill -TERM "$p" 2>/dev/null || true; done; '
        ..'sleep 1; active=$((1-known)); for file in '..files..'; do [ -r "$file" ] || continue; '..identity
        ..'if kill -0 "$p" 2>/dev/null; then kill -KILL "$p" 2>/dev/null || true; active=1; fi; done; exit "$active"'
    return self:run_shell(cmd)
end

-- Only terminate an owned curl PID if its kernel start time still matches.
function Runner:stop_http(pidfile)
 local cmd="if [ -r "..util.shell_quote(pidfile).." ]; then read p stamp < "..util.shell_quote(pidfile).."; "
  .."case \"$p:$stamp\" in *[!0-9:]*|:|*:) exit 0;; esac; "
  .."if [ \"$(awk '{print $22}' /proc/$p/stat 2>/dev/null)\" = \"$stamp\" ]; then kill -TERM \"$p\" 2>/dev/null || true; fi; fi"
 return self:run_shell(cmd)
end
return Runner
