-- 模块注册表：扫描 modules/*/module.json，加载 init.lua，隔离初始化错误。
local json = require("core.json")
local errors = require("core.errors")

local Registry = {}
Registry.__index = Registry

function Registry.new(opts)
    local self = setmetatable({}, Registry)
    self.app_dir = opts.app_dir
    self.config = opts.config
    self.storage = opts.storage
    self.log = opts.log
    self.base_ctx = opts.ctx
    self.modules = {}
    self.by_id = {}
    return self
end

local function valid_manifest(m)
    return type(m) == "table" and type(m.id) == "string" and m.id ~= ""
        and type(m.version) == "string"
        and type(m.api_version) == "number"
end

function Registry:discover()
    local root = self.app_dir .. "/modules"
    local entries = self.storage:list_dir(root)
    table.sort(entries)
    local list = {}
    for _, entry in ipairs(entries) do
        local dir = root .. "/" .. entry
        local manifest_path = dir .. "/module.json"
        local raw = self.storage:read(manifest_path)
        if raw then
            local ok, manifest = pcall(json.decode, raw)
            if ok and valid_manifest(manifest) then
                manifest.entry = manifest.entry or "init.lua"
                manifest.dir = dir
                manifest.order = manifest.order or 100
                list[#list + 1] = manifest
            elseif self.log then
                self.log:warn("invalid module manifest: " .. manifest_path)
            end
        end
    end
    table.sort(list, function(a, b)
        if a.order == b.order then return a.id < b.id end
        return a.order < b.order
    end)
    self.modules = list
    return list
end

function Registry:is_enabled(id)
    local cfg = self.config:module(id)
    for _, manifest in ipairs(self.modules) do
        if manifest.id == id then
            local default = manifest.enabled ~= false
            if cfg.enabled == nil then return default end
            return cfg.enabled == true
        end
    end
    return false
end

function Registry:set_enabled(id, enabled)
    self.config:set("modules." .. id .. ".enabled", enabled and true or false)
    local m = self.by_id[id]
    if m and m.inst and m.inst.set_enabled then
        local ok, err = pcall(m.inst.set_enabled, enabled)
        if not ok and self.log then self.log:warn("module set_enabled failed: " .. id .. ": " .. tostring(err)) end
    end
end

function Registry:load_all()
    for _, manifest in ipairs(self.modules) do
        self:load_one(manifest)
    end
end

function Registry:load_one(manifest)
    local entry_path = manifest.dir .. "/" .. manifest.entry
    local chunk, load_err = loadfile(entry_path)
    local record = {
        manifest = manifest,
        id = manifest.id,
        inst = nil,
        error = nil,
    }
    if not chunk then
        record.error = "load failed: " .. tostring(load_err)
    else
        local ok, inst = pcall(chunk)
        if not ok then
            record.error = "exec failed: " .. tostring(inst)
        elseif type(inst) ~= "table" or type(inst.render) ~= "function" then
            record.error = "module must return a table with render()"
        else
            if manifest.api_version ~= 1 then
                record.error = string.format("unsupported module api %s", tostring(manifest.api_version))
            else
                local ctx = self:make_ctx(manifest)
                local init_ok, init_err = errors.guard(self.log, "init:" .. manifest.id, function()
                    if inst.init then return inst.init(ctx) end
                    return true
                end)
                if not init_ok then
                    record.error = "init failed: " .. tostring(init_err)
                else
                    inst.__ctx = ctx
                    inst.__manifest = manifest
                    inst.id = manifest.id
                    record.inst = inst
                end
            end
        end
    end
    if record.error and self.log then
        self.log:error("module " .. manifest.id .. ": " .. record.error)
    end
    self.by_id[manifest.id] = record
    return record
end

function Registry:make_ctx(manifest)
    local ctx = {}
    for k, v in pairs(self.base_ctx) do ctx[k] = v end
    ctx.module_id = manifest.id
    ctx.manifest = manifest
    ctx.config = self.config
    ctx.storage = self.storage
    ctx.log = self.log
    ctx.request_update = function()
        if ctx.on_update then ctx.on_update(ctx.module_id) end
    end
    ctx.finish = function(ok, err)
        if ctx.on_finish then ctx.on_finish(ctx.module_id, ok, err) end
    end
    ctx.set_page = function(page)
        if ctx.on_set_page then ctx.on_set_page(page) end
    end
    return ctx
end

-- 返回启用的模块记录（含初始化失败的记录，UI 显示错误卡片）。
function Registry:enabled()
    local out = {}
    for _, manifest in ipairs(self.modules) do
        if self:is_enabled(manifest.id) then
            out[#out + 1] = self.by_id[manifest.id] or { manifest = manifest, id = manifest.id, error = "not loaded" }
        end
    end
    return out
end

function Registry:get(id)
    return self.by_id[id]
end

function Registry:shutdown()
    for _, manifest in ipairs(self.modules) do
        local m = self.by_id[manifest.id]
        if m and m.inst and m.inst.shutdown then
            errors.guard(self.log, "shutdown:" .. manifest.id, function() m.inst.shutdown() end)
        end
    end
end

return Registry
