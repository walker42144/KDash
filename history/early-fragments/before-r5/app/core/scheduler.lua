-- 刷新调度器：纯逻辑，时间由外部注入，便于测试。
local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new(opts)
    local self = setmetatable({}, Scheduler)
    self.coalesce_window = (opts and opts.coalesce_window) or 3
    self.jobs = {}
    self.order = {}
    return self
end

local function align_time(now, policy, offset_min)
    if policy.align == "minute" then
        return now - (now % 60) + 60
    elseif policy.align == "hour" then
        return now - (now % 3600) + 3600
    elseif policy.align == "day" then
        local off = (offset_min or 0) * 60
        local local_now = now + off
        local day_start = local_now - (local_now % 86400)
        return day_start + 86400 - off
    end
    return now + (policy.interval or 60)
end

function Scheduler:add(id, policy)
    policy = policy or {}
    policy.interval = policy.interval or 60
    policy.max_backoff = policy.max_backoff or 3600
    local now = policy.now or os.time()
    local job = {
        id = id,
        policy = policy,
        failures = 0,
        last_ok = nil,
        last_error = nil,
        next_due = now + (policy.initial_delay or 0),
        running = false,
    }
    if policy.on_start == false then
        job.next_due = align_time(now, policy, policy.offset_min)
    end
    if not self.jobs[id] then
        self.order[#self.order + 1] = id
    end
    self.jobs[id] = job
    return job
end

function Scheduler:remove(id)
    if self.jobs[id] then
        self.jobs[id] = nil
        for i, v in ipairs(self.order) do
            if v == id then table.remove(self.order, i) break end
        end
    end
end

function Scheduler:set_policy(id, policy)
    local job = self.jobs[id]
    if not job then return end
    for k, v in pairs(policy) do job.policy[k] = v end
end

function Scheduler:force(id, now)
    local job = self.jobs[id]
    if job then job.next_due = now or os.time() end
end

function Scheduler:force_all(now)
    now = now or os.time()
    for _, id in ipairs(self.order) do
        self.jobs[id].next_due = now
    end
end

function Scheduler:set_running(id, running)
    local job = self.jobs[id]
    if job then job.running = running end
end

function Scheduler:is_due(id, now)
    local job = self.jobs[id]
    return job ~= nil and not job.running and job.next_due <= now
end

-- 返回本批次应刷新的模块 id 列表（合并相近的到期任务）。
function Scheduler:tick(now)
    local earliest = nil
    for _, id in ipairs(self.order) do
        local job = self.jobs[id]
        if job and not job.running and job.next_due <= now then
            if not earliest or job.next_due < earliest then earliest = job.next_due end
        end
    end
    if not earliest then return {} end
    local limit = math.max(now, earliest) + self.coalesce_window
    local out = {}
    for _, id in ipairs(self.order) do
        local job = self.jobs[id]
        if job and not job.running and job.next_due <= limit then
            out[#out + 1] = id
            job.running = true
        end
    end
    return out
end

function Scheduler:success(id, now)
    local job = self.jobs[id]
    if not job then return end
    now = now or os.time()
    job.failures = 0
    job.last_ok = now
    job.last_error = nil
    job.running = false
    job.next_due = align_time(now, job.policy, job.policy.offset_min)
    if job.next_due <= now then job.next_due = now + job.policy.interval end
end

function Scheduler:failure(id, err, now)
    local job = self.jobs[id]
    if not job then return end
    now = now or os.time()
    job.failures = job.failures + 1
    job.last_error = tostring(err)
    job.running = false
    local delay = job.policy.interval * (2 ^ math.min(job.failures, 6))
    delay = math.min(delay, job.policy.max_backoff)
    job.next_due = now + delay
end

function Scheduler:get(id)
    return self.jobs[id]
end

function Scheduler:all()
    local out = {}
    for _, id in ipairs(self.order) do out[#out + 1] = self.jobs[id] end
    return out
end

return Scheduler
