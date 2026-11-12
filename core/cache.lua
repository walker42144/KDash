-- 模块数据缓存：JSON 文件，带抓取时间与错误状态；原子写入。
local json = require("core.json")

local Cache = {}
Cache.__index = Cache

function Cache.new(opts)
    local self = setmetatable({}, Cache)
    self.dir = opts.dir
    self.storage = opts.storage
    self.log = opts.log
    return self
end

local function safe_name(name)
    return name:gsub("[^%w%-_%.]", "_")
end

function Cache:path(name)
    return self.dir .. "/" .. safe_name(name) .. ".json"
end

function Cache:read(name)
    local data = self.storage:read(self:path(name))
    if not data then return nil end
    local ok, value = pcall(json.decode, data)
    if not ok then
        if self.log then self.log:warn("cache parse failed: " .. name .. ": " .. tostring(value)) end
        return nil
    end
    return value
end

function Cache:write(name, payload)
    local env = {
        cache_version = 1,
        saved_at = os.time(),
        data = payload.data,
        fetched_at = payload.fetched_at or os.time(),
        error = payload.error,
        status = payload.status,
    }
    local ok, encoded = pcall(json.encode, env, false)
    if not ok then return false, encoded end
    local wrote, err = self.storage:write_atomic(self:path(name), encoded)
    if not wrote and self.log then
        self.log:warn("cache write failed: " .. name .. ": " .. tostring(err))
    end
    return wrote, err
end

function Cache:clear(name)
    self.storage:remove(self:path(name))
end

function Cache:age(name, now)
    local env = self:read(name)
    if not env or not env.fetched_at then return nil end
    return (now or os.time()) - env.fetched_at
end

return Cache
