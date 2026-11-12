-- 子进程执行封装：统一捕获输出并记录失败。
local util = require("core.util")

local Runner = {}
Runner.__index = Runner

function Runner.new(opts)
    local self = setmetatable({}, Runner)
    self.log = opts and opts.log
    return self
end

function Runner:build(argv)
    local parts = {}
    for _, a in ipairs(argv) do
        parts[#parts + 1] = util.shell_quote(tostring(a))
    end
    return table.concat(parts, " ")
end

function Runner:run(argv, timeout_note)
    local cmd = self:build(argv)
    local f = io.popen(cmd .. " 2>&1")
    if not f then
        if self.log then self.log:error("spawn failed: " .. cmd) end
        return -1, ""
    end
    local output = f:read("*a") or ""
    local ok, why, code = f:close()
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
    local f = io.popen(cmd .. " 2>&1")
    if not f then return -1, "" end
    local output = f:read("*a") or ""
    local ok, why, code = f:close()
    if not ok then return code or -1, output end
    return 0, output
end

-- 后台执行一个脚本文件，完成标记由脚本自己写入。
function Runner:spawn_script(script_path)
    local cmd = "sh " .. util.shell_quote(script_path) .. " >/dev/null 2>&1 &"
    return os.execute(cmd)
end

return Runner
