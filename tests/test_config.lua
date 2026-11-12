return function(T)
    local Storage = require("core.storage")
    local Config = require("core.config")
    local util = require("core.util")

    local function temp_dir()
        local base = os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
        return base .. "/kdash-test-" .. tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999))
    end

    T.test("config merges defaults and persists", function()
        local dir = temp_dir()
        local storage = Storage.new()
        storage:mkdir_p(dir)
        local default = util.read_file("config/default.json")
        T.truthy(default, "default config readable")
        storage:write(dir .. "/default.json", default)
        storage:write(dir .. "/config.json", '{"language":"en","modules":{"clock":{"enabled":false}}}')
        local cfg = Config.load({
            storage = storage,
            path = dir .. "/config.json",
            default_path = dir .. "/default.json",
        })
        T.eq(cfg.data.language, "en")
        T.eq(cfg:get("modules.clock.enabled"), false)
        T.eq(cfg:get("modules.weather.city"), "")
        cfg:set("ui.margin", 64)
        T.truthy(cfg:save())
        local cfg2 = Config.load({
            storage = storage,
            path = dir .. "/config.json",
            default_path = dir .. "/default.json",
        })
        T.eq(cfg2:get("ui.margin"), 64)
        T.eq(cfg2.data.modules.clock.enabled, false)
        os.remove(dir .. "/config.json")
        os.remove(dir .. "/default.json")
        os.remove(dir)
    end)

    T.test("secrets are separate and persist", function()
        local dir = temp_dir()
        local storage = Storage.new()
        storage:mkdir_p(dir)
        local sec = Config.load_secrets({ storage = storage, path = dir .. "/secrets.json" })
        sec:set_secret("dida.access_token", "abc")
        T.truthy(sec:save_secrets())
        local sec2 = Config.load_secrets({ storage = storage, path = dir .. "/secrets.json" })
        T.eq(sec2:secret("dida.access_token"), "abc")
        os.remove(dir .. "/secrets.json")
        os.remove(dir)
    end)
end
