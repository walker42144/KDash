-- 文件存储抽象。设备上是 POSIX；主机测试可替换为内存实现。
local util = require("core.util")
local storage = {}
storage.__index = storage

local IS_WINDOWS = package.config:sub(1, 1) == "\\"

function storage.new(opts)
    return setmetatable({
        root = opts and opts.root or nil,
        windows = IS_WINDOWS,
    }, storage)
end

function storage:path(p)
    if not self.root then return p end
    return p
end

function storage:read(path, max_bytes)
    return util.read_file(self:path(path), max_bytes)
end

function storage:exists(path)
    local f=io.open(self:path(path),'rb')
    if not f then return false end
    f:close();return true
end

function storage:write(path, data)
    return util.write_file(self:path(path), data)
end

function storage:write_atomic(path, data)
    local p = self:path(path)
    local tmp = p .. ".tmp-" .. tostring(os.time()) .. "-" .. tostring(math.random(1,2147483647)) .. "-" .. tostring({}):gsub('[^%w]','')
    local ok, err = util.write_file(tmp, data)
    if not ok then return false, err end
    local rok,rerr
    if self.windows then
        local ffi=require('ffi');ffi.cdef[[int MoveFileExA(const char*,const char*,unsigned long);]]
        rok=ffi.load('kernel32').MoveFileExA(tmp,p,9)~=0
        if not rok then rerr='atomic replace failed' end
    else rok,rerr=os.rename(tmp,p) end
    if not rok then
        os.remove(tmp)
        return false, rerr
    end
    return true
end

function storage:remove(path)
    os.remove(self:path(path))
end

function storage:rename(from, to)
    return os.rename(self:path(from), self:path(to))
end

function storage:mkdir_p(path)
    local p = self:path(path)
    if self.windows then
        local ok = os.execute(
            'powershell -NoProfile -Command "New-Item -ItemType Directory -Force -Path ' ..
            util.shell_quote(p:gsub("/", "\\")) .. ' | Out-Null"'
        )
        return ok == 0 or ok == true
    end
    local ok = os.execute("mkdir -p " .. util.shell_quote(p))
    return ok == 0 or ok == true
end

function storage:chmod(path, mode)
    if self.windows then return true end
    local ok = os.execute("chmod " .. mode .. " " .. util.shell_quote(self:path(path)))
    return ok == 0 or ok == true
end

function storage:list_dir(path)
    local p = self:path(path)
    local out = {}
    if self.windows then
        local cmd = 'dir /b /a "' .. p:gsub("/", "\\") .. '" 2>NUL'
        local f = io.popen(cmd)
        if not f then return out end
        for line in f:lines() do
            if util.trim(line) ~= "" then out[#out + 1] = util.trim(line) end
        end
        f:close()
        return out
    end
    local f = io.popen("ls -1 " .. util.shell_quote(p) .. " 2>/dev/null")
    if not f then return out end
    for line in f:lines() do
        if util.trim(line) ~= "" then out[#out + 1] = util.trim(line) end
    end
    f:close()
    return out
end

function storage:is_dir(path)
    if self.windows then return false end
    local ok = os.execute("test -d " .. util.shell_quote(self:path(path)))
    return ok == 0 or ok == true
end

function storage:run(cmd)
    local f = io.popen(cmd)
    if not f then return nil, "popen failed" end
    local out = f:read("*a")
    local ok = f:close()
    return out, ok
end

function storage:spawn(cmd)
    return os.execute(cmd .. " >/dev/null 2>&1 &")
end

return storage
