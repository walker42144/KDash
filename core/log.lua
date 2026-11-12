-- 轻量日志：追加写文件，超过上限自动轮转。设备上不重复输出到 stdout。
local util = require("core.util")

local Log = {}
Log.__index = Log

function Log.new(opts)
    local self = setmetatable({}, Log)
    self.path = opts.path
    self.max_bytes = opts.max_bytes or 256 * 1024
    self.echo = opts.echo == true
    self.level = opts.level or "info"
    self._file = nil
    return self
end

local LEVELS = { debug = 10, info = 20, warn = 30, error = 40 }

function Log:_rotate_if_needed()
    local size = util.file_size(self.path)
    if size and size > self.max_bytes then
        if self._file then
            self._file:close()
            self._file = nil
        end
        os.remove(self.path .. ".1")
        os.rename(self.path, self.path .. ".1")
    end
end

function Log:_write(level, msg)
    if (LEVELS[level] or 20) < (LEVELS[self.level] or 20) then return end
    local line = string.format("%s [%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), level:upper(), msg)
    if self.echo then
        io.stderr:write(line)
    end
    if not self.path then return end
    self:_rotate_if_needed()
    if not self._file then
        self._file = io.open(self.path, "ab")
    end
    if self._file then
        self._file:write(line)
        self._file:flush()
    end
end

function Log:debug(msg) self:_write("debug", msg) end
function Log:info(msg) self:_write("info", msg) end
function Log:warn(msg) self:_write("warn", msg) end
function Log:error(msg) self:_write("error", msg) end

function Log:close()
    if self._file then
        self._file:close()
        self._file = nil
    end
end

return Log
