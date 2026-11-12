return function(T)
    local Storage = require("core.storage")
    local Config = require("core.config")
    local Log = require("core.log")
    local Display = require("platform.kindle.display_fbink")
    local App = require("core.app")
    local Device = require("platform.kindle.device")

    T.test("app boots and renders with real Device adapter and FBInk backend wiring", function()
        local base = os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
        local dir = base .. "/kdash-boot-" .. tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999))
        local storage = Storage.new()
        storage:mkdir_p(dir)
        storage:write(dir .. "/default.json", assert(io.open("config/default.json", "rb")):read("*a"))
        local log = Log.new({ echo = false, level = "error" })
        local config = Config.load({
            storage = storage,
            path = dir .. "/config.json",
            default_path = dir .. "/default.json",
            log = log,
        })
        local secrets = Config.load_secrets({ storage = storage, path = dir .. "/secrets.json", log = log })

        local calls = 0
        local runner = {
            run = function(_, argv, note)
                calls = calls + 1
                if argv[1] == "lipc-get-prop" then
                    if argv[#argv] == "battLevel" then return 0, "78" end
                    if argv[#argv] == "isCharging" then return 0, "0" end
                    if argv[#argv] == "flIntensity" then return 0, "10" end
                end
                return 0, ""
            end,
            run_shell = function() return 0, "1000 500 500" end,
        }
        local display = Display.new({
            runner = runner, fbink = "/var/tmp/kdash-bin/fbink",
            width = 1072, height = 1448, font = "/mnt/us/kdash/assets/DroidSansFallbackFull.ttf",
            log = log,
        })
        T.truthy(display, "display instance")

        local app = App.new({
            app_dir = ".",
            data_dir = dir,
            storage = storage,
            config = config,
            secrets = secrets,
            log = log,
            display = display,
            input = { fd = false, poll = function() return {} end, close = function() end },
            device = Device.new({ storage = storage, runner = runner, log = log }),
            power = { apply = function() end, release = function() end },
            http = {
                request = function(_, _, cb) cb({ ok = false, error = "offline" }) end,
                poll = function() end,
                cancel_all = function() end,
            },
            clock = {
                now = function() return 1794369600 end,
                now_ms = function() return 0 end,
                sleep_ms = function() end,
            },
        })
        config.data.ui.auto_update=false
        T.truthy(app:setup(), "setup")
        T.truthy(app.updates_paused,"saved pause choice is restored on startup")
        T.truthy(app.page, "page")
        T.eq(type(app.device.storage), "function", "storage service must not hide storage method")
        T.eq(app.device:info(1794369600).battery.level,78)
        T.eq(app.registry:get("device").error,nil,"real device module initialized")
        T.truthy(app.renderer, "renderer")
        app.renderer:render_full(app.page)
        T.truthy(calls > 0, "fbink commands were issued")
        for _,id in ipairs({"clock","countdown","dida","weather"}) do
            local rect=app.renderer.rects[id].card
            T.truthy(rect.y+rect.h <= app.renderer:content_rect().y+app.renderer:content_rect().h,"section within content: "..id)
        end
        T.eq(app.config.data.modules.dida.enabled,false,"layout must not enable API requests")
        T.truthy(app.renderer:render_dirty({"clock","countdown"},app.page),"partial refresh remains usable")
        app:handle_input({{type="tap",x=980,y=70}})
        T.truthy(app.stop,"exit hit survives partial clock refresh")
        app:cleanup()
    end)
end
