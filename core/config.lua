-- 配置加载、合并、校验、迁移与持久化。
local json = require("core.json")
local util = require("core.util")

local Config = {}
Config.__index = Config

Config.SCHEMA_VERSION = 1

local function read_json(storage, path)
    local data, err = storage:read(path,1024*1024)
    if not data then return nil, err end
    local ok, value = pcall(json.decode, data)
    if not ok then return nil, "invalid json: " .. tostring(value) end
    return value
end

-- 按点路径读写，如 "modules.clock.format"
local function get_path(t, path)
    local cur = t
    for part in path:gmatch("[^%.]+") do
        if type(cur) ~= "table" then return nil end
        cur = cur[part]
    end
    return cur
end

local function set_path(t, path, value)
    local parts = {}
    for part in path:gmatch("[^%.]+") do parts[#parts + 1] = part end
    local cur = t
    for i = 1, #parts - 1 do
        local k = parts[i]
        if type(cur[k]) ~= "table" then cur[k] = {} end
        cur = cur[k]
    end
    cur[parts[#parts]] = value
end

function Config.new(opts)
    local self = setmetatable({}, Config)
    self.storage = opts.storage
    self.path = opts.path
    self.default_path = opts.default_path
    self.log = opts.log
    self.data = {}
    self.dirty = false
    return self
end

function Config:migrate()
    local v = self.data.schema_version or 1
    if v > Config.SCHEMA_VERSION then
        error(string.format("config schema %d is newer than app schema %d", v, Config.SCHEMA_VERSION))
    end
    if v < 1 then
        self.data.schema_version = 1
    end
    -- 后续版本迁移在此追加：
    -- if self.data.schema_version == 1 then ... self.data.schema_version = 2 end
end

function Config:validate()
    local cfg = self.data
    cfg.schema_version = cfg.schema_version or Config.SCHEMA_VERSION
    cfg.language = (cfg.language == "en") and "en" or "zh"
    cfg.utc_offset_minutes = cfg.utc_offset_minutes or 480
    cfg.wifi_sync_interval = util.clamp(cfg.wifi_sync_interval or 15, 1, 1440)
    cfg.ui = cfg.ui or {}
    cfg.ui.refresh_minutes = math.floor(util.clamp(tonumber(cfg.ui.refresh_minutes) or 1,1,60))
    cfg.ui.ink_mode = cfg.ui.ink_mode == true
    cfg.ui.margin = util.clamp(cfg.ui.margin or 56, 16, 160)
    cfg.ui.font_scale = util.clamp(cfg.ui.font_scale or 1.0, 0.6, 1.8)
    cfg.power = cfg.power or {}
    cfg.power.keep_awake = cfg.power.keep_awake or "plugged"
    cfg.power.full_refresh_every = math.floor(util.clamp(tonumber(cfg.power.full_refresh_every) or 24, 0, 1000))
    cfg.modules = cfg.modules or {}
    -- Seconds cannot be truthful on a minute-based e-ink refresh grid.
    if cfg.modules.clock then cfg.modules.clock.show_seconds=false end
    cfg.pages = cfg.pages or {}
    if #cfg.pages == 0 then
        cfg.pages = {
            { id = "home", title = "KDASH", layout = {} },
        }
    end
    return true
end

-- 合并默认配置与用户配置；数组整体替换。
function Config.load(opts)
    local self = Config.new(opts)
    local defaults = read_json(self.storage, self.default_path)
    if not defaults then error("cannot read default config: " .. tostring(self.default_path)) end
    self.data = util.deep_copy(defaults)
    local user = read_json(self.storage, self.path)
    if user then
        self.data = util.deep_merge(self.data, user)
    end
    self:migrate()
    self:validate()
    if user then
        local ok,serialized=pcall(json.encode,user,true)
        if ok then self.saved_data=serialized end
    end
    if not user then self.dirty = true end
    return self
end

function Config:get(path, default)
    local v = get_path(self.data, path)
    if v == nil then return default end
    return v
end

function Config:set(path, value)
    set_path(self.data, path, value)
    self.dirty = true
end

function Config:module(id)
    self.data.modules = self.data.modules or {}
    self.data.modules[id] = self.data.modules[id] or {}
    return self.data.modules[id]
end

function Config:page(id)
    for _, p in ipairs(self.data.pages or {}) do
        if p.id == id then return p end
    end
    return nil
end

function Config:save()
    local ok, data = pcall(json.encode, self.data, true)
    if not ok then return false, data end
    if self.saved_data==data then self.dirty=false;return true end
    local wrote, err = self.storage:write_atomic(self.path, data)
    if wrote then self.dirty = false;self.saved_data=data end
    return wrote, err
end

-- 凭证单独存放，权限 600。
function Config.load_secrets(opts)
    local self = setmetatable({ data = {}, storage = opts.storage, path = opts.path }, Config)
    local value, err = read_json(opts.storage, opts.path)
    if value then
        self.data = value
    elseif err and not err:find("cannot open", 1, true) then
        if opts.log then opts.log:warn("secrets: " .. tostring(err)) end
    end
    return self
end

function Config:save_secrets()
    local ok, data = pcall(json.encode, self.data, true)
    if not ok then return false, data end
    local wrote, err = self.storage:write_atomic(self.path, data)
    if wrote then
        self.storage:chmod(self.path, "600")
    end
    return wrote, err
end

function Config:secret(path, default)
    local v = get_path(self.data, path)
    if v == nil then return default end
    return v
end

function Config:set_secret(path, value)
    set_path(self.data, path, value)
end

return Config
