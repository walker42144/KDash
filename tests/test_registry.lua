return function(T)
    local Storage = require("core.storage")
    local Registry = require("core.registry")

    local function temp_dir()
        local base = os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
        return base .. "/kdash-reg-" .. tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999))
    end

    local function write(path, data)
        local f = io.open(path, "wb")
        f:write(data)
        f:close()
    end

    T.test("registry loads a new module without core changes", function()
        local dir = temp_dir()
        local storage = Storage.new()
        storage:mkdir_p(dir .. "/modules/hello")
        write(dir .. "/modules/hello/module.json", [[
{"id":"hello","name":"Hello","version":"1.0.0","api_version":1,
 "order":1,"enabled":true,"layout":{"min_height":80}}
]])
        write(dir .. "/modules/hello/init.lua", [[
local M = {}
function M.init(ctx) _G.__kdash_hello_init = true; return true end
function M.refresh(ctx) return true end
function M.render(ctx, ui, rect) end
return M
]])
        local config = {
            module = function() return {} end,
        }
        local log = { info = function() end, warn = function() end, error = function() end }
        local registry = Registry.new({
            app_dir = dir, config = config, storage = storage, log = log,
            ctx = { now = function() return 1 end },
        })
        registry:discover()
        registry:load_all()
        T.truthy(_G.__kdash_hello_init)
        local record = registry:get("hello")
        T.truthy(record)
        T.truthy(record.inst)
        T.eq(record.error, nil)
        T.eq(#registry:enabled(), 1)
        T.truthy(record.inst.render)
    end)

    T.test("registry isolates unsupported module api", function()
        local dir = temp_dir()
        local storage = Storage.new()
        storage:mkdir_p(dir .. "/modules/bad")
        write(dir .. "/modules/bad/module.json", [[
{"id":"bad","name":"Bad","version":"1.0.0","api_version":99,"order":2,"enabled":true}
]])
        write(dir .. "/modules/bad/init.lua", [[
return { render = function() end }
]])
        local config = { module = function() return {} end }
        local log = { info = function() end, warn = function() end, error = function() end }
        local registry = Registry.new({
            app_dir = dir, config = config, storage = storage, log = log,
            ctx = { now = function() return 1 end },
        })
        registry:discover()
        registry:load_all()
        local record = registry:get("bad")
        T.truthy(record)
        T.falsy(record.inst)
        T.truthy(record.error:find("unsupported", 1, true))
    end)
end
