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
        util.shell_quote(self.curl).." -sS -L --connect-timeout 10 --max-time " .. timeout,
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
    local remove={};for _,path in pairs(paths) do remove[#remove+1]=util.shell_quote(path) end
    local cleanup="rm -f "..table.concat(remove," ")
    local cancel=util.shell_quote(paths.cancel);local pidfile=util.shell_quote(paths.pid)
    local script = "#!/bin/sh\numask 077\nulimit -f "..math.ceil(max_bytes/512).."\n"
        .. "if [ -f "..cancel.." ]; then "..cleanup.."; exit 0; fi\n"
        .. "child=\ntrap "..util.shell_quote('if [ -n "$child" ]; then kill -TERM "$child" 2>/dev/null || true; fi; '..cleanup..'; exit 143').." TERM INT HUP\n"
        .. table.concat(cmd, " \\\n  ").." &\nchild=$!\n"
        .. "echo \"$child $(awk '{print $22}' /proc/$child/stat 2>/dev/null)\" > "..pidfile.."\n"
        .. "if [ -f "..cancel.." ]; then kill -TERM \"$child\" 2>/dev/null || true; fi\n"
        .. "wait \"$child\"\necho $? > "..util.shell_quote(paths.rc).."\n"
        .. "if [ -f "..cancel.." ]; then "..cleanup.."; exit 0; fi\n"
        .. "echo done > "..util.shell_quote(paths.done).."\n"
    return script
end

function Http:request(opts, cb)
    if self.closed then cb({ok=false,error="cancelled",status=0,body=""});return nil end
    local count=0;for _ in pairs(self.jobs) do count=count+1 end
    if count>=4 then cb({ok=false,error="request queue full",status=0,body=""});return nil end
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
        pid = prefix .. ".pid",
        cancel = prefix .. ".cancel",
        worker = prefix .. ".worker.pid",
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
        max_bytes = opts.max_bytes or 4*1024*1024,
        label = opts.label or "HTTP request",
        sensitive_values = opts.sensitive_values or {},
    }
    self.jobs[id] = job
    if self.log then self.log:debug("http start: " .. job.label) end
    local launched=self.runner:spawn_script(paths.script,paths.worker)
    if launched~=nil and launched~=0 and launched~=true then
        -- No process exists to consume a cancellation marker in this case.
        job.done_called=true;self.jobs[id]=nil
        for _,p in pairs(paths) do self.storage:remove(p) end
        cb({ok=false,error='spawn failed',status=0,body=''});return nil
    end
    return id
end

local function read_number(storage, path)
    local data = storage:read(path,128)
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
    local unfinished=not self.storage:exists(paths.done)
    if unfinished then
        self.storage:write(paths.cancel,"cancelled\n")
        if self.runner.cancel_http then
            -- Clear tombstones only after both owned processes are confirmed
            -- gone. An uninterruptible process retains its cancellation marker.
            if self.runner:cancel_http(paths)==0 then unfinished=false end
        elseif self.runner.stop_http then self.runner:stop_http(paths.pid) end
    end
    for name,p in pairs(paths) do
        if not unfinished or (name~='pid' and name~='worker' and name~='cancel') then self.storage:remove(p) end
    end
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
            local body,body_err = self.storage:read(job.paths.out,job.max_bytes)
            body=body or ""
            local stderr_text = (self.storage:read(job.paths.err,4096) or ""):sub(1,4096)
            local oversized=body_err~=nil or #body>job.max_bytes
            if oversized then body="" end
            local ok = (not oversized and rc == 0 and status >= 200 and status < 300)
            local error_message=nil
            if not ok then error_message=oversized and "response exceeds size limit" or string.format("curl rc=%d http=%d %s",rc,status,util.trim(stderr_text)) end
            self:_finish(job, {
                ok = ok,
                status = status,
                body = body,
                error = error_message,
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
    self.closed=true
    for _, job in pairs(self.jobs) do
        self:_finish(job, { ok = false, status = 0, body = "", error = "cancelled" })
    end
end

return Http
