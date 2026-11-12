local errors = {}
local unpack = table.unpack or unpack

function errors.trace(err)
    if type(err) == "table" and err.message then return err.message end
    return tostring(err)
end

-- 统一隔离模块/回调异常，返回 ok, result_or_error
function errors.guard(log, name, fn, ...)
    local args = { ... }
    local function handler(e)
        local msg = tostring(e) .. "\n" .. debug.traceback("", 2)
        return msg
    end
    local ok, result = xpcall(function()
        return fn(unpack(args))
    end, handler)
    if not ok then
        if log then
            log:error(string.format("[%s] %s", name or "unknown", result))
        end
        return false, result
    end
    return true, result
end

return errors
