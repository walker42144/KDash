-- 系统时钟与无 fork 等待。设备上使用 LuaJIT FFI；无 FFI 时降级。
local Clock = {}
Clock.__index = Clock

function Clock.new()
    local self = setmetatable({}, Clock)
    self.has_ffi = false
    self.ffi = nil
    local ok, ffi = pcall(require, "ffi")
    if ok then
        pcall(function()
            ffi.cdef [[
                struct timeval { long tv_sec; long tv_usec; };
                int gettimeofday(struct timeval *tv, void *tz);
                int poll(void *fds, unsigned long nfds, int timeout);
            ]]
        end)
        self.ffi = ffi
        self.has_ffi = true
    end
    self._now_override = nil
    return self
end

function Clock:set_now(fn)
    self._now_override = fn
end

function Clock:now()
    if self._now_override then return self._now_override() end
    return os.time()
end

function Clock:now_ms()
    if self.has_ffi then
        local tv = self.ffi.new("struct timeval")
        if self.ffi.C.gettimeofday(tv, nil) == 0 then
            return tonumber(tv.tv_sec) * 1000 + math.floor(tonumber(tv.tv_usec) / 1000)
        end
    end
    return os.time() * 1000
end

function Clock:sleep_ms(ms)
    if self.has_ffi then
        self.ffi.C.poll(nil, 0, math.floor(ms or 0))
        return
    end
    os.execute("sleep " .. tostring(math.max(1, math.floor((ms or 1000) / 1000))))
end

return Clock
