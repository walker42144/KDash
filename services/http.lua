-- 异步 HTTP：每个请求写一个临时 shell 脚本，后台 curl 执行，主循环轮询完成标记。
local util = require("core.util")

local Http = {}
Http.__index = Http

function Http.new(opts)
    local self = setmetatable({}, Http)
    self.runner = opts.runner
    self.storage = opts.storage
    self.dir = opts.dir
    self.log = opts.log
    self.now = opts.now or os.time
    self.seq = 0
    self.jobs = {}
    self.curl = opts.curl or "curl"
    self.cacert = opts.cacert
    self.insecure = opts.insecure == true
    return self
end

local function header_args(headers)
    local out = {}
    for k, v in pairs(headers or {}) do
        out[#out + 1] = "-H"
        out[#out + 1] = util.shell_quote(k .. ": " .. tostring(v))
    end
    return table.concat(out, " ")
end

function Http:build_script(opts, paths)
    local timeout = opts.timeout or 30
    local max_bytes = opts.max_bytes or 4 * 1024 * 1024
    local cmd = {
        "curl -sS -L --connect-timeout 10 --max-time " .. timeout,
        "--max-filesize " .. max_bytes,
        "-A " .. util.shell_quote("KDash/0.1 (Kindle)"),
    }
    if self.cacert and self.cacert ~= "" then
        cmd[#cmd + 1] = "--cacert " .. util.shell_quote(self.cacert)
    elseif self.insecure then
        cmd[#cmd + 1] = "-k"
    end
    local headers = header_args(opts.headers)
    if headers ~= "" then cmd[#cmd + 1] = headers end
    local method = (opts.method or "GET"):upper()
    if method == "POST" then
        cmd[#cmd + 1] = "-X POST"
        if opts.body then
            cmd[#cmd + 1] = "--data-binary " .. util.shell_quote(opts.body)
        end
    elseif method ~= "GET" then
        cmd[#cmd + 1] = "-X " .. util.shell_quote(method)
        if opts.body then
            cmd[#cmd + 1] = "--data-binary " .. util.shell_quote(opts.body)
        end
    end
    cmd[#cmd + 1] = "-o " .. util.shell_quote(paths.out)
    cmd[#cmd + 1] = "-w '%{http_code}'"
    cmd[#cmd + 1] = util.shell_quote(opts.url)
    cmd[#cmd + 1] = "> " .. util.shell_quote(paths.status)
    cmd[#cmd + 1] = "2> " .. util.shell_quote(paths.err)
    -- curl 参数用反斜杠续行；命令重定向结束后另起 echo，避免把 rc/done 写进 curl 参数。
    local script = "#!/bin/sh\n"
        .. table.concat(cmd, " \\\n  ")
        .. "\necho $? > " .. util.shell_quote(paths.rc)
        .. "\necho done > " .. util.shell_quote(paths.done)
        .. "\n"
    return script
end

function Http:request(opts, cb)
    self.seq = self.seq + 1
    local id = tostring(self.now()) .. "-" .. tostring(self.seq)
    local prefix = self.dir .. "/http-" .. id
    local paths = {
        script = prefix .. ".sh",
        out = prefix .. ".out",
        err = prefix .. ".err",
        rc = prefix .. ".rc",
        status = prefix .. ".status",
        done = prefix .. ".done",
    }
    local script = self:build_script(opts, paths)
    local ok, err = self.storage:write(paths.script, script)
    if not ok then
        cb({ ok = false, error = "write script failed: " .. tostring(err) })
        return nil
    end
    self.storage:chmod(paths.script, "700")
    local job = {
        id = id,
        paths = paths,
        cb = cb,
        started = self.now(),
        timeout = (opts.timeout or 30) + 20,
        done_called = false,
        label = opts.label or "HTTP request",
        sensitive_values = opts.sensitive_values or {},
    }
    self.jobs[id] = job
    if self.log then self.log:debug("http start: " .. job.label) end
    self.runner:spawn_script(paths.script)
    return id
end

local function read_number(storage, path)
    local data = storage:read(path)
    if not data then return nil end
    return tonumber(util.trim(data))
end

function Http:_finish(job, result)
    if result.error then
        for _, secret in ipairs(job.sensitive_values or {}) do
            if secret ~= "" then
                local pattern = secret:gsub("(%W)", "%%%1")
                result.error = result.error:gsub(pattern, "[REDACTED]")
            end
        end
    end
    if job.done_called then return end
    job.done_called = true
    self.jobs[job.id] = nil
    local paths = job.paths
    for _, p in pairs(paths) do self.storage:remove(p) end
    if self.log then
        if result.ok then
            self.log:debug("http done: " .. job.label .. " " .. tostring(result.status))
        else
            self.log:warn("http failed: " .. job.label .. ": " .. tostring(result.error))
        end
    end
    local ok, err = pcall(job.cb, result)
    if not ok and self.log then self.log:error("http callback error: " .. tostring(err)) end
end

function Http:poll()
    local now = self.now()
    for id, job in pairs(self.jobs) do
        if self.storage:exists(job.paths.done) then
            local rc = read_number(self.storage, job.paths.rc) or -1
            local status = read_number(self.storage, job.paths.status) or 0
            local body = self.storage:read(job.paths.out) or ""
            local stderr_text = self.storage:read(job.paths.err) or ""
            local ok = (rc == 0 and status >= 200 and status < 300)
            self:_finish(job, {
                ok = ok,
                status = status,
                body = body,
                error = ok and nil or string.format("curl rc=%d http=%d %s", rc, status, util.trim(stderr_text)),
            })
        elseif now - job.started > job.timeout then
            self:_finish(job, { ok = false, status = 0, body = "", error = "timeout" })
        end
    end
end

function Http:busy()
    return next(self.jobs) ~= nil
end

function Http:cancel_all()
    for _, job in pairs(self.jobs) do
        self:_finish(job, { ok = false, status = 0, body = "", error = "cancelled" })
    end
end

return Http
