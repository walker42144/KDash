-- 滴答清单 Open API：视图、层级与用户点选完成。
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
    opts=opts or {};local today=timeutil.date_key(now,offset)
    local names,map,raw={},{},{}
    for _,p in ipairs(projects or {}) do names[p.id]=p.name end
    for project_id,data in pairs(project_data or {}) do
        for _,t in ipairs(data.tasks or {}) do
            local pid=t.projectId or project_id;local key=pid..":"..tostring(t.id)
            raw[key]=t
            map[key]={id=t.id,project_id=pid,project=names[pid] or pid,title=t.title or t.content or "(untitled)",
                priority=tonumber(t.priority) or 0,priority_label=PRIORITY[tonumber(t.priority) or 0],
                due_key=task_time_key(t,offset),source_due=t.dueDate,repeat_flag=t.repeatFlag,tags=t.tags or {},parent_id=type(t.parentId)=="string" and t.parentId~="" and t.parentId or nil,
                completed=tonumber(t.status)==2,children={},checklist=util.deep_copy(t.items or {})}
        end
    end
    local view={today={},overdue={},upcoming={},undated={},completed_today=0,total_today=0,progress=0,projects=projects or {},synced_at=now}
    local attached={}
    for key,item in pairs(map) do
        local parent=item.parent_id and map[item.project_id..":"..item.parent_id]
        if parent and parent~=item and not parent.completed then
            -- Reject cyclic parent chains instead of recursing forever.
            local cur,seen=parent,{};local cycle=false
            while cur do
                if cur==item or seen[cur] then cycle=true;break end
                seen[cur]=true;cur=cur.parent_id and map[cur.project_id..":"..cur.parent_id]
            end
            if not cycle then parent.children[#parent.children+1]=item;attached[key]=true end
        end
    end
    local function inherit(item,seen)
        seen=seen or {};if seen[item] then return end;seen[item]=true
        for _,child in ipairs(item.children) do
            inherit(child,seen)
            if not child.due_key then child.due_key=item.due_key end
            if not child.completed and child.due_key and (not item.due_key or child.due_key<item.due_key) then item.due_key=child.due_key end
        end
    end
    for key,item in pairs(map) do
        if not attached[key] then
            inherit(item)
            if item.completed then
                if completed_key(raw[key],offset)==today then view.completed_today=view.completed_today+1 end
            else
                local date=item.due_key
                if not date then view.undated[#view.undated+1]=item
                elseif date<today then view.overdue[#view.overdue+1]=item
                elseif date==today then view.today[#view.today+1]=item
                else
                    local diff=timeutil.days_until_date(date,today)
                    if diff and diff<=(opts.upcoming_days or 7) then item.days_left=diff;view.upcoming[#view.upcoming+1]=item end
                end
            end
        end
    end
    local function cmp(a,b)
        if a.completed~=b.completed then return not a.completed end
        if a.priority~=b.priority then return a.priority>b.priority end
        if a.due_key~=b.due_key then return (a.due_key or "9999")<(b.due_key or "9999") end
        return a.title<b.title
    end
    local function sort_tree(list)
        table.sort(list,cmp);for _,item in ipairs(list) do sort_tree(item.children) end
    end
    for _,bucket in ipairs({'today','overdue','upcoming','undated'}) do sort_tree(view[bucket]) end
    view.total_today=#view.today+view.completed_today
    if view.total_today>0 then view.progress=util.clamp(math.floor(view.completed_today*100/view.total_today+0.5),0,100) end
    return view
end

local function has_open_children(task,tasks,seen)
    seen=seen or {};if seen[task.id] then return true end;seen[task.id]=true
    for _,item in ipairs(task.items or {}) do if tonumber(item.status)~=1 then return true end end
    for _,child in ipairs(tasks or {}) do
        if child.parentId==task.id and (tonumber(child.status)~=2 or has_open_children(child,tasks,seen)) then return true end
    end
    for _,id in ipairs(task.childIds or {}) do
        local found=false
        for _,child in ipairs(tasks or {}) do if child.id==id and tonumber(child.status)==2 then found=true end end
        if not found then return true end
    end
    return false
end

-- User-triggered writes only. Never queue or automatically retry a completion.
function Dida:complete(target,cb)
    if self.config:module('dida').allow_complete==false then cb(false,'READ_ONLY');return end
    if self.writing then cb(false,'BUSY');return end
    if not target.project_id or not target.task_id then cb(false,'INVALID_TARGET');return end
    self.writing=true
    local function done(ok,err) self.writing=false;cb(ok,err) end
    local pid,tid=urlencode(target.project_id),urlencode(target.task_id)
    local function post(path,body,after)
        local token=self.secrets:secret('dida.access_token')
        self.http:request({url=Dida.API_BASE..path,method='POST',body=body and json.encode(body) or nil,
            headers={Authorization='Bearer '..tostring(token),['Content-Type']='application/json',Accept='application/json'},
            timeout=30,label='dida completion',sensitive_values={token}},function(res)
            if not res.ok then
                done(false,res.status==403 and 'WRITE_FORBIDDEN' or res.status==401 and 'AUTH_REQUIRED' or 'WRITE_UNCONFIRMED');return
            end
            if res.status~=200 and res.status~=201 and res.status~=204 then done(false,'WRITE_UNCONFIRMED');return end
            if res.body and res.body~='' then
                local payload=parse_json_body(res.body)
                if type(payload)=='table' and ((type(payload.error)=='string' and payload.error~='') or (payload.errorCode and payload.errorCode~=0)) then done(false,'WRITE_UNCONFIRMED');return end
            end
            if after then after() else done(true) end
        end)
    end
    local function start()
        if target.item_id then
            local path='/project/'..pid..'/task/'..tid
            self:_api_get(path,function(ok,err,fresh)
                if not ok or type(fresh)~='table' or fresh.id~=target.task_id or (type(fresh.projectId)=='string' and fresh.projectId~=target.project_id) then done(false,'READ_FAILED');return end
                if tonumber(fresh.status)==2 then done(false,'TASK_ALREADY_COMPLETED');return end
                local items=util.deep_copy(fresh.items or {});local picked
                for _,item in ipairs(items) do if item.id==target.item_id then picked=item end end
                if not picked then done(false,'ITEM_NOT_FOUND');return end
                if tonumber(picked.status)==1 then done(true);return end
                picked.status=1;picked.completedTime=os.date('!%Y-%m-%dT%H:%M:%S+0000',self.now())
                local body={id=fresh.id,projectId=target.project_id,items=items}
                if type(fresh.etag)=='string' then body.etag=fresh.etag end
                post('/task/'..tid,body,function()
                    self:_api_get(path,function(ok2,err2,check)
                        if ok2 and type(check)=='table' then
                            for _,item in ipairs(check.items or {}) do
                                if item.id==target.item_id and tonumber(item.status)==1 then done(true);return end
                            end
                        end
                        done(false,'WRITE_UNCONFIRMED')
                    end)
                end)
            end)
        else
            self:_api_get('/project/'..pid..'/data',function(ok,err,data)
                if not ok or type(data)~='table' then done(false,'READ_FAILED');return end
                local fresh
                for _,task in ipairs(data.tasks or {}) do if task.id==target.task_id then fresh=task end end
                if not fresh then done(false,'TASK_NOT_FOUND');return end
                if tonumber(fresh.status)==2 then done(true);return end
                if type(fresh.repeatFlag)=='string' and fresh.repeatFlag~='' and target.expected_due~=fresh.dueDate then done(false,'TASK_CHANGED');return end
                -- Active-project responses can omit completed children. Resolve referenced IDs before deciding.
                local fetched=0
                local function check_children()
                    local by_id={};for _,task in ipairs(data.tasks or {}) do by_id[task.id]=task end
                    local visited={}
                    local function unknown(node)
                        if visited[node.id] then return end;visited[node.id]=true
                        for _,id in ipairs(node.childIds or {}) do
                            if not by_id[id] then return id,node.id end
                            local missing,parent=unknown(by_id[id]);if missing then return missing,parent end
                        end
                        for _,child in ipairs(data.tasks or {}) do
                            if child.parentId==node.id then local missing,parent=unknown(child);if missing then return missing,parent end end
                        end
                    end
                    local missing,parent=unknown(fresh)
                    if missing then
                        fetched=fetched+1;if fetched>64 then done(false,'READ_FAILED');return end
                        self:_api_get('/project/'..pid..'/task/'..urlencode(missing),function(ok3,err3,child)
                            if not ok3 or type(child)~='table' or child.id~=missing then done(false,'READ_FAILED');return end
                            child.parentId=parent;data.tasks[#data.tasks+1]=child;check_children()
                        end)
                        return
                    end
                    if has_open_children(fresh,data.tasks) then done(false,'OPEN_CHILDREN');return end
                    post('/project/'..pid..'/task/'..tid..'/complete')
                end
                check_children()
            end)
        end
    end
    local auth=self:auth_state()
    if auth=='missing' then done(false,'AUTH_REQUIRED')
    elseif auth=='expired' then self:refresh_token(function(ok) if ok then start() else done(false,'AUTH_REQUIRED') end end)
    else start() end
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
