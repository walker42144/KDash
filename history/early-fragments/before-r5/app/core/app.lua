-- 应用主循环：生命周期、刷新调度、事件分发、页面切换与安全退出。
local Cache = require("core.cache")
local Registry = require("core.registry")
local Scheduler = require("core.scheduler")
local Events = require("core.events")
local errors = require("core.errors")
local util = require("core.util")
local Theme = require("ui.theme")
local Typo = require("ui.typography")
local Layout = require("ui.layout")
local Renderer = require("ui.renderer")

local App = {}
App.__index = App

function App.new(opts)
    local self = setmetatable({}, App)
    self.app_dir = opts.app_dir
    self.data_dir = opts.data_dir
    self.storage = opts.storage
    self.config = opts.config
    self.secrets = opts.secrets
    self.log = opts.log
    self.display = opts.display
    self.input = opts.input
    self.device = opts.device
    self.power = opts.power
    self.http = opts.http
    self.clock = opts.clock
    self.dirty = {}
    self.async_started = {}
    self.pending_confirm = false
    self.stop = false
    self.need_full = true
    self.last_power_check = 0
    return self
end

function App:setup()
    require("ui.dashboard").apply(self.config.data)
    self.theme = Theme.new({
        width = self.display.width,
        height = self.display.height,
        font_scale = self.config.data.ui.font_scale or 1.0,
        ink_mode = self.config.data.ui.ink_mode == true,
        margin = self.config.data.ui.margin or 56,
    })
    self.typo = Typo.new({})
    self.events = Events.new()
    self.cache = Cache.new({
        dir = self.data_dir .. "/cache",
        storage = self.storage,
        log = self.log,
    })

    local base_ctx = {
        config = self.config,
        secrets = self.secrets,
        cache = self.cache,
        http = self.http,
        device = self.device,
        storage = self.storage,
        log = self.log,
        now = function() return self.clock:now() end,
        device_info = function(force)
            return self.device:info(self.clock:now())
        end,
        on_update = function(id) self:mark_dirty(id) end,
        on_finish = function(id, ok, err) self:finish_refresh(id, ok, err) end,
        on_set_page = function(page) self:set_page(page) end,
    }
    self.registry = Registry.new({
        app_dir = self.app_dir,
        config = self.config,
        storage = self.storage,
        log = self.log,
        ctx = base_ctx,
    })
    self.registry:discover()
    self.registry:load_all()

    self.scheduler = Scheduler.new({ coalesce_window = 3 })
    for _, record in ipairs(self.registry:enabled()) do
        if record.inst then self:add_job(record.id) end
    end

    self.layout = Layout.new({ theme = self.theme, registry = self.registry })
    self.renderer = Renderer.new({
        display = self.display,
        theme = self.theme,
        typo = self.typo,
        registry = self.registry,
        config = self.config,
        events = self.events,
        layout = self.layout,
        now = function() return self.clock:now() end,
        log = self.log,
    })

    self:_ensure_settings_page()
    self.page = self:resolve_page(self.config.data.last_page) or self:_first_page()
    if self.page then
        self.config.data.last_page = self.page.id
        self.need_full = true
    end
    if self.power then
        local info = self.device:info(self.clock:now())
        self.power:apply(self.config.data.power.keep_awake or "plugged",
            info.battery and info.battery.charging)
        self.last_power_check = self.clock:now()
    end
    self.log:info(string.format("KDash %s started; %d modules, page=%s",
        require("core.version"), #self.registry:enabled(), self.page and self.page.id or "?"))
    return true
end

function App:_ensure_settings_page()
    if self.config.data.ui.minimal or self.config.data.ui.hide_settings then return end
    local has = false
    for _, p in ipairs(self.config.data.pages) do
        if p.kind == "settings" or p.id == "settings" then has = true end
    end
    if not has then
        self.config.data.pages[#self.config.data.pages + 1] = {
            id = "settings", title = "SETTINGS", kind = "settings",
        }
    end
end

function App:_first_page()
    for _, p in ipairs(self.config.data.pages) do
        if p.kind ~= "settings" then return p end
    end
    return self.config.data.pages[1]
end

function App:resolve_page(id)
    for _, p in ipairs(self.config.data.pages) do
        if p.id == id then return p end
    end
    return nil
end

function App:add_job(id)
    local record = self.registry:get(id)
    if not record or not record.inst then return end
    local policy = nil
    if record.inst.refresh_policy then
        local ok, p = pcall(record.inst.refresh_policy, record.inst.__ctx)
        if ok and type(p) == "table" then policy = p end
    end
    policy = policy or record.manifest.refresh or { interval = 300 }
    policy.now = self.clock:now()
    policy.offset_min = self.config.data.utc_offset_minutes or 480
    self.scheduler:add(id, policy)
end

function App:mark_dirty(id)
    if self.need_full then self.dirty[id] = true return end
    if self.renderer and self.renderer.rects[id] then
        self.dirty[id] = true
    end
end

function App:finish_refresh(id, ok, err)
    self.async_started[id] = nil
    if ok then
        self.scheduler:success(id, self.clock:now())
    else
        self.scheduler:failure(id, err, self.clock:now())
        if self.log then self.log:warn("refresh failed: " .. id .. ": " .. tostring(err)) end
    end
    self:mark_dirty(id)
end

function App:run_refresh(id, now)
    local record = self.registry:get(id)
    if not record or not record.inst then
        self.scheduler:failure(id, "module not initialized", now)
        return
    end
    if not self.registry:is_enabled(id) then
        self.scheduler:success(id, now)
        return
    end
    local ctx = record.inst.__ctx
    ctx.page_id = self.page and self.page.id
    local ok, result = xpcall(function()
        if record.inst.refresh then return record.inst.refresh(ctx) end
        return true
    end, function(e) return tostring(e) .. "\n" .. debug.traceback("", 2) end)
    if not ok then
        self.log:error("refresh error: " .. id .. ": " .. tostring(result))
        self.scheduler:failure(id, result, now)
        self:mark_dirty(id)
        return
    end
    if result == false then
        -- 只有仍在运行的任务才需要超时监控；模块可能已同步调用 finish()。
        local job = self.scheduler:get(id)
        if job and job.running then
            self.async_started[id] = now
        end
    else
        self.scheduler:success(id, now)
    end
end

function App:refresh_due(now)
    if self.pending_confirm then return end
    local ids = self.scheduler:tick(now)
    for _, id in ipairs(ids) do
        errors.guard(self.log, "refresh:" .. id, function() self:run_refresh(id, now) end)
    end
end

function App:check_async(now)
    local timeout = 180
    for id, started in pairs(self.async_started) do
        if now - started > timeout then
            self.async_started[id] = nil
            self.scheduler:failure(id, "async timeout", now)
            self:mark_dirty(id)
            self.log:warn("module refresh timeout: " .. id)
        end
    end
end

function App:maybe_power(now)
    if not self.power then return end
    if now - self.last_power_check < 60 then return end
    self.last_power_check = now
    local info = self.device:info(now)
    self.power:apply(self.config.data.power.keep_awake or "plugged",
        info.battery and info.battery.charging)
end

function App:set_page(id)
    local page = self:resolve_page(id)
    if not page then return end
    self.page = page
    self.config.data.last_page = id
    self.config:save()
    self.pending_confirm = false
    self.need_full = true
    self.dirty = {}
end

function App:next_page(delta)
    local pages = self.config.data.pages
    if #pages == 0 then return end
    local index = 1
    for i, p in ipairs(pages) do
        if self.page and p.id == self.page.id then index = i end
    end
    index = index + delta
    if index < 1 then index = #pages end
    if index > #pages then index = 1 end
    self:set_page(pages[index].id)
end

function App:handle_action(ev)
    local action = ev.action
    if action == "page" then
        self:set_page(ev.payload)
    elseif action == "exit_request" then
        if self.config.data.ui.direct_exit then self.stop = true
        else self.pending_confirm = true; self.renderer:render_confirm() end
    elseif action == "exit_cancel" then
        self.pending_confirm = false
        self.need_full = true
    elseif action == "exit_confirm" then
        self.stop = true
    elseif action == "toggle_module" then
        local id = ev.payload
        local enabled = not self.registry:is_enabled(id)
        self.registry:set_enabled(id, enabled)
        self.config:save()
        if enabled then
            self:add_job(id)
            self.scheduler:force(id, self.clock:now())
        else
            self.scheduler:remove(id)
        end
        self.need_full = true
    elseif action == "sync_all" then
        self.scheduler:force_all(self.clock:now())
    elseif action == "module_sync" then
        self.scheduler:force(ev.payload, self.clock:now())
    elseif action == "cycle_power" then
        local values = { "plugged", "always", "never" }
        local current = self.config.data.power.keep_awake or "plugged"
        local idx = 1
        for i, v in ipairs(values) do if v == current then idx = i end end
        local nextv = values[(idx % #values) + 1]
        self.config:set("power.keep_awake", nextv)
        self.config:save()
        if self.power then
            local info = self.device:info(self.clock:now())
            self.power:apply(nextv, info.battery and info.battery.charging)
        end
        self.need_full = true
    end
end

function App:handle_input(events)
    for _, ev in ipairs(events or {}) do
        if ev.type == "swipe" then
            if not self.pending_confirm then
                if ev.direction == "left" then self:next_page(1)
                elseif ev.direction == "right" then self:next_page(-1) end
            end
        elseif ev.type == "tap" then
            self.tap_count = (self.tap_count or 0) + 1
            if self.tap_count <= 40 then self.log:info(string.format("tap x=%d y=%d", ev.x, ev.y)) end
            local hit = self.events:route_tap(ev)
            if hit then
                errors.guard(self.log, "action", function() self:handle_action(ev) end)
            end
        end
    end
end

function App:render_once(page_id)
    if page_id then self:set_page(page_id) end
    if self.page then
        self.renderer:render_full(self.page)
        self.need_full = false
        self.dirty = {}
        return true
    end
    return false
end

function App:run()
    if not self:setup() then return 1 end
    if self.page then
        self.renderer:render_full(self.page)
        self.need_full = false
        self.dirty = {}
    end
    if not self.display.available then error("initial display failed") end
    self.log:info("entering main loop")
    while not self.stop do
        local evs = self.input:poll(200)
        if not self.input.fd then
            self.clock:sleep_ms(200)
        end
        self:handle_input(evs)
        if self.stop then break end
        local now = self.clock:now()
        self:refresh_due(now)
        self.http:poll()
        self:check_async(now)
        self:maybe_power(now)
        if self.pending_confirm then
            -- 确认弹窗期间不重绘底层页面，避免覆盖弹窗
        elseif self.need_full and self.page then
            self.renderer:render_full(self.page)
            self.need_full = false
            self.dirty = {}
            if not self.display.available then
                self.log:error("display became unavailable; stopping")
                self.stop = true
            end
        elseif next(self.dirty) ~= nil then
            local ids = {}
            for id in pairs(self.dirty) do ids[#ids + 1] = id end
            table.sort(ids)
            self.dirty = {}
            self.renderer:render_dirty(ids, self.page)
        end
    end
    self:cleanup()
    return 0
end

function App:cleanup()
    self.log:info("shutting down")
    if self.http then self.http:cancel_all() end
    if self.registry then self.registry:shutdown() end
    if self.power then self.power:release() end
    if self.input then self.input:close() end
    self.config:save()
end

return App
