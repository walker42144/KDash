return function(T)
    local Http = require("services.http")

    local function fake_storage()
        local s = { files = {} }
        function s:write(path, data) self.files[path] = data; return true end
        function s:read(path) return self.files[path] end
        function s:exists(path) return self.files[path] ~= nil end
        function s:remove(path) self.files[path] = nil end
        function s:chmod(path, mode) self.files[path .. ".mode"] = mode; return true end
        return s
    end

    local function fake_runner()
        local r = { scripts = {} }
        function r:spawn_script(path) self.scripts[#self.scripts + 1] = path; return 0 end
        return r
    end

    T.test("http script has valid shebang and completion markers", function()
        local storage = fake_storage()
        local runner = fake_runner()
        local http = Http.new({
            runner = runner, storage = storage, dir = "/tmp/kdash-http",
            now = function() return 1000 end,
        })
        local called = false
        http:request({
            url = "https://example.com/a?b=1",
            headers = { ["Authorization"] = "Bearer abc" },
            method = "GET",
            timeout = 20,
        }, function() called = true end)
        local script = storage.files["/tmp/kdash-http/http-1000-1.sh"]
        T.truthy(script, "script written")
        T.truthy(script:sub(1, 10) == "#!/bin/sh\n", "valid shebang")
        T.falsy(script:find("#!/bin/sh \\", 1, true), "shebang must not be continued")
        T.truthy(script:find("echo $? >", 1, true), "rc marker")
        T.truthy(script:find("echo done >", 1, true), "done marker")
        T.truthy(script:find("Authorization: Bearer abc", 1, true), "header")
        T.truthy(script:find("--max-time 20", 1, true), "timeout")
        T.falsy(called)
    end)

    T.test("http poll completes a successful request", function()
        local storage = fake_storage()
        local runner = fake_runner()
        local http = Http.new({
            runner = runner, storage = storage, dir = "/tmp/kdash-http",
            now = function() return 2000 end,
        })
        local result = nil
        http:request({ url = "https://example.com/ok", method = "GET" }, function(res)
            result = res
        end)
        local prefix = "/tmp/kdash-http/http-2000-1"
        storage.files[prefix .. ".done"] = "done"
        storage.files[prefix .. ".rc"] = "0"
        storage.files[prefix .. ".status"] = "200"
        storage.files[prefix .. ".out"] = '{"ok":true}'
        storage.files[prefix .. ".err"] = ""
        http:poll()
        T.truthy(result)
        T.eq(result.ok, true)
        T.eq(result.status, 200)
        T.eq(result.body, '{"ok":true}')
    end)

    T.test("http poll reports http errors", function()
        local storage = fake_storage()
        local runner = fake_runner()
        local http = Http.new({
            runner = runner, storage = storage, dir = "/tmp/kdash-http",
            now = function() return 3000 end,
        })
        local result = nil
        http:request({ url = "https://example.com/bad" }, function(res) result = res end)
        local prefix = "/tmp/kdash-http/http-3000-1"
        storage.files[prefix .. ".done"] = "done"
        storage.files[prefix .. ".rc"] = "0"
        storage.files[prefix .. ".status"] = "401"
        storage.files[prefix .. ".out"] = "{}"
        storage.files[prefix .. ".err"] = ""
        http:poll()
        T.truthy(result)
        T.eq(result.ok, false)
        T.eq(result.status, 401)
    end)
end
