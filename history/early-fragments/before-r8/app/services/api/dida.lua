-- 滴答清单（Dida365）Open API 适配器与只读视图构建。
local json = require("core.json")
local timeutil = require("core.timeutil")
local util = require("core.util")

local Dida = {}
Dida.__index = Dida

Dida.API_BASE = "https://api.dida365.com/open/v1"
Dida.TOKEN_URL = "https://dida365.com/oauth/token"

local function urlencode(s)
    return tostring(s):gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

local function parse_json_body(body)
    local ok, value = pcall(json.decode, body or "")
    if not ok then return nil, "invalid json: " .. tostring(value) end
    return value
end

function Dida.new(opts)
    local self = setmetatable({}, Dida)
    self.http = opts.http
    self.config = opts.config
    self.secrets = opts.secrets
    self.cache = opts.cache
    self.log = opts.log
    self.now = opts.now or os.time
    self.offset = opts.offset or 480
    return self
end

function Dida:enabled()
    local c = self.config:module("dida")
    return c.enabled ~= false
end

function Dida:auth_state()
    local s = self.secrets
    if not s:secret("dida.access_token") then return "missing" end
    local exp = s:secret("dida.expires_at", 0)
    if exp and exp > 0 and exp <= self.now() + 300 then return "expired" end
    return "ok"
end

function Dida:save_token(payload)
    if type(payload) ~= "table" or not payload.access_token then
        return false, "token response missing access_token"
    end
    local expires_in = tonumber(payload.expires_in) or 3600
    self.secrets:set_secret("dida.access_token", payload.access_token)
    if payload.refresh_token then
        self.secrets:set_secret("dida.refresh_token", payload.refresh_token)
    end
    self.secrets:set_secret("dida.expires_at", self.now() + expires_in - 60)
    self.secrets:set_secret("dida.scope", payload.scope)
    self.secrets:save_secrets()
    return true
end

-- 优先使用 refresh_token 换取新 access_token。
function Dida:refresh_token(cb)
    local client_id = self.secrets:secret("dida.client_id")
    local client_secret = self.secrets:secret("dida.client_secret")
    local refresh = self.secrets:secret("dida.refresh_token")
    if not client_id or not client_secret or not refresh then
        cb(false, "missing client credentials or refresh token")
        return
    end
    local body = table.concat({
        "client_id=" .. urlencode(client_id),
        "client_secret=" .. urlencode(client_secret),
        "grant_type=refresh_token",
        "refresh_token=" .. urlencode(refresh),
    }, "&")
    self.http:request({
        url = Dida.TOKEN_URL,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Accept"] = "application/json",
        },
        body = body,
        timeout = 30,
        label = "dida token refresh",
        sensitive_values = {client_secret,refresh},
    }, function(res)
        if not res.ok then
            cb(false, "token refresh failed: " .. tostring(res.error))
            return
        end
        local data, err = parse_json_body(res.body)
        if not data then
            cb(false, err)
            return
        end
        if not self:save_token(data) then
            cb(false, "invalid token payload")
            return
        end
        cb(true)
    end)
end

function Dida:_api_get(path, cb)
    local token = self.secrets:secret("dida.access_token")
    self.http:request({
        url = Dida.API_BASE .. path,
        method = "GET",
        headers = {
            ["Authorization"] = "Bearer " .. tostring(token),
            ["Accept"] = "application/json",
        },
        timeout = 40,
        label = "dida API",
        sensitive_values = {token},
    }, function(res)
        if not res.ok then
            cb(false, res.status == 401 and "unauthorized" or res.error, nil, res.status)
            return
        end
        local data, err = parse_json_body(res.body)
        if not data then cb(false, err) return end
        cb(true, nil, data, res.status)
    end)
end

local function task_time_key(task, offset)
    if task.isAllDay == true or task.isAllDay == "true" then
        local date = tostring(task.dueDate or ""):match("^(%d%d%d%d%-%d%d%-%d%d)")
        if date then return date end
    end
    local ts = timeutil.parse_iso8601(task.dueDate)
    if not ts then return nil end
    return timeutil.date_key(ts, offset)
end

local function completed_key(task, offset)
    local raw = task.completedTime
    if type(raw) == "number" then
        return timeutil.date_key(raw / 1000, offset)
    end
    if type(raw) == "string" then
        local ts = timeutil.parse_iso8601(raw)
        if ts then return timeutil.date_key(ts, offset) end
    end
    return nil
end

local PRIORITY = { [5] = "HIGH", [3] = "MED", [1] = "LOW", [0] = "NONE" }

-- 纯函数：把 API 数据转换为 UI 视图（可单测）。
function Dida.build_view(projects, project_data, now, offset, opts)
    opts = opts or {}
    local today = timeutil.date_key(now, offset)
    local project_names = {}
    for _, p in ipairs(projects or {}) do
        project_names[p.id] = p.name
    end
    local tasks = {}
    for project_id, data in pairs(project_data or {}) do
        for _, t in ipairs(data.tasks or {}) do
            t.__project_id = t.projectId or project_id
            tasks[#tasks + 1] = t
        end
    end
    local view = {
        today = {},
        overdue = {},
        upcoming = {},
        completed_today = 0,
        total_today = 0,
        progress = 0,
        projects = projects or {},
        synced_at = now,
    }
    for _, t in ipairs(tasks) do
        local status = tonumber(t.status) or 0
        local ck = completed_key(t, offset)
        if status == 2 then
            if ck == today then view.completed_today = view.completed_today + 1 end
        else
            local key = task_time_key(t, offset)
            if key then
                local item = {
                    id = t.id,
                    title = t.title or t.content or "(untitled)",
                    project = project_names[t.__project_id] or t.projectId or "",
                    project_id = t.__project_id,
                    priority = tonumber(t.priority) or 0,
                    priority_label = PRIORITY[tonumber(t.priority) or 0] or "NONE",
                    due_key = key,
                    due_time = nil,
                    tags = t.tags or {},
                }
                if not (t.isAllDay == true or t.isAllDay == "true") then
                    local ts = timeutil.parse_iso8601(t.dueDate)
                    if ts then
                        item.due_time = timeutil.format_time(ts, offset, true)
                    end
                end
                if key < today then
                    view.overdue[#view.overdue + 1] = item
                elseif key == today then
                    view.today[#view.today + 1] = item
                else
                    local diff = timeutil.days_until_date(key, today)
                    if diff and diff <= (opts.upcoming_days or 7) then
                        item.days_left = diff
                        view.upcoming[#view.upcoming + 1] = item
                    end
                end
            end
        end
    end
    local function cmp(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        if a.due_key ~= b.due_key then return a.due_key < b.due_key end
        return a.title < b.title
    end
    table.sort(view.today, cmp)
    table.sort(view.overdue, function(a, b)
        if a.due_key ~= b.due_key then return a.due_key < b.due_key end
        return a.priority > b.priority
    end)
    table.sort(view.upcoming, function(a, b)
        if a.due_key ~= b.due_key then return a.due_key < b.due_key end
        return a.priority > b.priority
    end)
    view.total_today = #view.today + view.completed_today
    if view.total_today > 0 then
        view.progress = util.clamp(math.floor(view.completed_today * 100 / view.total_today + 0.5), 0, 100)
    end
    return view
end

-- 同步：刷新 token（如需）→ 项目列表 → 逐个项目取数据。
function Dida:sync(cb)
    local cfg = self.config:module("dida")
    local function start()
        self:_api_get("/project", function(ok, err, projects, status)
            if not ok then cb(false, err) return end
            if type(projects) ~= "table" then cb(false, "project list is not an array") return end
            local selected = {}
            local wanted = cfg.project_ids
            local wanted_set = nil
            if type(wanted) == "table" and #wanted > 0 then
                wanted_set = {}
                for _, id in ipairs(wanted) do wanted_set[id] = true end
            end
            for _, p in ipairs(projects) do
                local is_task_project = (p.kind == nil or p.kind == "TASK")
                local not_closed = p.closed ~= true
                local picked = (wanted_set == nil) or wanted_set[p.id] == true
                if is_task_project and not_closed and picked then
                    selected[#selected + 1] = p
                end
            end
            if #selected > 25 then
                for i = #selected, 26, -1 do table.remove(selected, i) end
            end
            local datas = {}
            local index = 1
            local function next_project()
                if index > #selected then
                    local view = Dida.build_view(projects, datas, self.now(), self.offset, cfg)
                    self.cache:write("dida", {
                        data = { view = view, projects = projects, project_data = datas },
                        fetched_at = self.now(),
                    })
                    cb(true, nil, view)
                    return
                end
                local p = selected[index]
                index = index + 1
                self:_api_get("/project/" .. p.id .. "/data", function(ok2, err2, data, st)
                    if not ok2 then
                        cb(false, "project " .. tostring(p.name or p.id) .. ": " .. tostring(err2))
                        return
                    end
                    if type(data) == "table" then datas[p.id] = data end
                    next_project()
                end)
            end
            next_project()
        end)
    end
    local state = self:auth_state()
    if state == "missing" then
        cb(false, "AUTH_REQUIRED")
        return
    end
    if state == "expired" then
        self:refresh_token(function(ok, err)
            if not ok then cb(false, "AUTH_REQUIRED: " .. tostring(err)) return end
            start()
        end)
        return
    end
    start()
end

return Dida
