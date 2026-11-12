#!/usr/bin/env luajit
-- KDash 入口。Kindle 上由 launcher/kdash-launch.sh 调用；主机上可用 --preview 生成 SVG。
local function script_dir()
    local src = arg and arg[0] or "main.lua"
    local dir = src:match("^(.*)[/\\][^/\\]+$")
    return dir or "."
end

local APP_DIR = script_dir()
package.path = APP_DIR .. "/?.lua;" .. APP_DIR .. "/?/init.lua;" .. package.path

local util = require("core.util")
local Storage = require("core.storage")
local Log = require("core.log")
local Config = require("core.config")
local Clock = require("platform.kindle.clock")

local args = { _app_dir = APP_DIR }
do
    local i = 1
    while arg and arg[i] do
        local a = arg[i]
        if a == "--app-dir" then i = i + 1; args.app_dir = arg[i]
        elseif a == "--data-dir" then i = i + 1; args.data_dir = arg[i]
        elseif a == "--preview" then args.preview = true
        elseif a == "--page" then i = i + 1; args.page = arg[i]
        elseif a == "--out" then i = i + 1; args.out = arg[i]
        elseif a == "--font" then i = i + 1; args.font = arg[i]
        elseif a == "--fbink" then i = i + 1; args.fbink = arg[i]
        elseif a == "--now" then i = i + 1; args.now = tonumber(arg[i])
        elseif a == "--width" then i = i + 1; args.width = tonumber(arg[i])
        elseif a == "--height" then i = i + 1; args.height = tonumber(arg[i])
        elseif a == "--probe-native-display" then args.probe_native = true
        elseif a == "--probe-display" then args.probe_display = true
        elseif a == "--probe-touch" then args.probe_touch = true
        elseif a == "--no-touch" then args.no_touch = true
        elseif a == "--help" or a == "-h" then
            print("KDash 0.1.0\n  --preview --out preview.svg [--page home] [--data-dir DIR]\n  --app-dir DIR --data-dir /mnt/us/kdash")
            os.exit(0)
        end
        i = i + 1
    end
end
if args.app_dir then APP_DIR = args.app_dir end
package.path = APP_DIR .. "/?.lua;" .. APP_DIR .. "/?/init.lua;" .. package.path

local App = require("core.app")

local function fatal(msg, display)
    io.stderr:write("KDASH FATAL: " .. tostring(msg) .. "\n")
    if display and display.available~=false then
        pcall(function()
            display:begin_frame(true)
            display:fill({ x = 80, y = 200, w = display.width - 160, h = 500 }, "paper")
            display:text({
                x = 100, y = 240, w = display.width - 200, size = 44,
                text = "KDASH ERROR", color = "ink", bg = "paper",
            })
            local lines = util.wrap_text(tostring(msg), math.floor((display.width - 200) / 22))
            local y = 320
            for i = 1, math.min(#lines, 8) do
                display:text({
                    x = 100, y = y, w = display.width - 200, size = 28,
                    text = lines[i], color = "ink", bg = "paper",
                })
                y = y + 44
            end
            display:flush({ full = true })
        end)
    end
    return 1
end

local function native_fonts()
    return {cjk=APP_DIR.."/assets/fonts/SourceHanSansCN-Medium.ttf",latin=APP_DIR.."/assets/fonts/KumbhSans-500.ttf",
        display=APP_DIR.."/assets/fonts/KumbhSans-600.ttf",library=os.getenv("KDASH_FREETYPE")}
end
local function main()
    if args.probe_native then
        local D=require("platform.kindle.display_native")
        local d=D.new({device=true,fonts=native_fonts()})
        assert(d:measure("中文 KDASH 0123456789 ℃ ≤",32)>0,"native font probe failed")
        d.canvas:text({text="中文 KDASH 34天",x=0,y=0,size=32,w=600})
        print("native renderer preflight: FreeType glyphs and read-only framebuffer geometry OK")
        d:close();return 0
    end
    if args.probe_display then
        local Paths = require("platform.kindle.paths")
        local Runner = require("platform.kindle.runner")
        local paths = Paths.new({app_dir=APP_DIR})
        local w,h = paths:screen_size(Runner.new({}),assert(args.fbink,"--fbink is required"))
        print(string.format("visible viewport=%dx%d",w,h)); return 0
    end
    if args.probe_touch then
        local t = require("platform.kindle.touch").new({})
        local ok, err = t:open(false)
        if not ok then error(err) end
        print(t:description()); t:close(); return 0
    end
    local data_dir = args.data_dir or "/mnt/us/kdash"
    local storage = Storage.new()
    local is_preview = args.preview == true
    if not is_preview and storage:exists(data_dir..'/.kdash-save.pending') then
        return fatal('configuration save was interrupted; reconnect USB and reopen the PC configuration tool to recover')
    end
    local log
    if is_preview then
        log = Log.new({ echo = true, level = "warn" })
    else
        storage:mkdir_p(data_dir .. "/logs")
        storage:mkdir_p(data_dir .. "/cache")
        storage:mkdir_p(data_dir .. "/state")
        log = Log.new({ path = data_dir .. "/logs/kdash.log", echo = false, level = "info" })
    end

    local config = Config.load({
        storage = storage,
        path = data_dir .. "/config.json",
        default_path = APP_DIR .. "/config/default.json",
        log = log,
    })
    config:save()
    local secrets = Config.load_secrets({
        storage = storage,
        path = data_dir .. "/secrets.json",
        log = log,
    })

    local clock = Clock.new()
    if args.now then
        clock:set_now(function() return args.now end)
    end

    if is_preview then
        local HostDisplay = require("platform.host.display_svg")
        local display = HostDisplay.new({
            width = args.width or 1072,
            height = args.height or 1448,
            out = args.out or "preview.svg",
        })
        if os.getenv("KDASH_NATIVE_PREVIEW")=="1" then
            display=require("platform.kindle.display_native").new({fonts=native_fonts(),out=args.out or "preview.pgm"})
        end
        local device = {
            info = function()
                return {
                    battery = { level = 78, charging = false, status = "Discharging" },
                    wifi = { connected = true, label = "WIFI", iface = "wlan0" },
                    firmware = "Kindle 5.16.2.1.1",
                    uptime = 3600 * 26,
                    storage = { total_kb = 3145728, used_kb = 1048576, free_kb = 1048576 },
                    frontlight = 12,
                    timestamp = clock:now(),
                }
            end,
        }
        local http = {
            request = function(_, opts, cb) cb({ ok = false, error = "preview offline" }) end,
            poll = function() end,
            cancel_all = function() end,
            busy = function() return false end,
        }
        local power = { apply = function() end, release = function() end }
        local input = { fd = false, poll = function() return {} end, close = function() end }
        local app = App.new({
            app_dir = APP_DIR,
            data_dir = data_dir,
            storage = storage,
            config = config,
            secrets = secrets,
            log = log,
            display = display,
            input = input,
            device = device,
            power = power,
            http = http,
            clock = clock,
        })
        app:setup()
        if args.page then app.page = app:resolve_page(args.page) or app.page end
        if not app.page then error("no page configured") end
        app.renderer:render_full(app.page)
        print("preview written: " .. display.out)
        return 0
    end

    local Paths = require("platform.kindle.paths")
    local Runner = require("platform.kindle.runner")
    local Display = require("platform.kindle.display_native")
    local Touch = require("platform.kindle.touch")
    local Device = require("platform.kindle.device")
    local Power = require("platform.kindle.power")
    local Http = require("services.http")
    local util2 = require("core.util")

    local paths = Paths.new({ app_dir = APP_DIR, data_dir = data_dir })
    local font = args.font or config.data.ui.font
    local font_path = paths:find_font(font)
    if not font_path then
        return fatal("no CJK font found. Put DroidSansFallback.ttf in /mnt/us/kdash/assets/ or set ui.font in config.json.")
    end
    local fbink = args.fbink or os.getenv("KDASH_FBINK") or (APP_DIR .. "/vendor/kindle/fbink")
    if not util2.path_exists(fbink) then
        fbink = "/var/tmp/kdash-bin/fbink"
    end
    if not util2.path_exists(fbink) then
        return fatal("fbink not found; check package installation.")
    end

    local runner = Runner.new({ log = log })
    local sw, sh = paths:screen_size(runner, fbink)
    local display = Display.new({
        device=true,fonts=native_fonts(),
        runner = runner,
        fbink = fbink,
        width = args.width or sw,
        height = args.height or sh,
        font = font_path,
        log = log,
        full_refresh_every = config.data.power.full_refresh_every or 24,
        margin = config.data.ui.margin or 56,
        ink_mode = config.data.ui.ink_mode == true,
    })
    if not display then
        return fatal("display backend initialization failed (Display.new returned nil).")
    end
    -- The supervisor has stopped the stock painters and saved their framebuffer.
    -- Show the startup mark before opening input and loading module state.
    assert(require('ui.splash').render(display,APP_DIR) ~= false, 'startup display failed')
    display:prepare_screensaver(data_dir)

    local ic = config.data.input or {}
    local touch = Touch.new({ path = ic.device, width = display.width, height = display.height,
        swap_xy = ic.swap_xy, invert_x = ic.invert_x, invert_y = ic.invert_y,
        log = log, clock_ms = function() return clock:now_ms() end })
    if not args.no_touch and not touch:open() then
        fatal("touch input unavailable; see touch diagnostics.", display); return 1
    end

    local device = Device.new({ storage = storage, runner = runner, log = log })
    local power = Power.new({ runner = runner, log = log, events_path = os.getenv("KDASH_POWER_EVENTS") })
    local power_ok,power_err=power:open_button()
    if not power_ok then error(power_err) end
    local cacert = nil
    for _, p in ipairs({ "/etc/ssl/certs/ca-certificates.crt", "/etc/ssl/certs/ca-bundle.crt", "/etc/ssl/cert.pem" }) do
        if util2.path_exists(p) then cacert = p; break end
    end
    local http = Http.new({
        runner = runner,
        storage = storage,
        dir = os.getenv("KDASH_HTTP_DIR") or "/tmp",
        log = log,
        now = function() return clock:now() end,
        curl = os.getenv("KDASH_CURL") or "curl",
        cacert = cacert,
        insecure = config.data.network.insecure_tls == true,
    })

    local app = App.new({
        app_dir = APP_DIR,
        data_dir = data_dir,
        storage = storage,
        config = config,
        secrets = secrets,
        log = log,
        display = display,
        input = touch,
        device = device,
        power = power,
        http = http,
        clock = clock,
    })
    local ok, err = xpcall(function() return app:run() end, function(e)
        return tostring(e) .. "\n" .. debug.traceback("", 2)
    end)
    if not ok then
        pcall(function() app:cleanup() end)
        log:error("fatal: " .. tostring(err))
        fatal(err, display)
        if display.close then display:close() end
        return 1
    end
    if display.close then display:close() end
    return tonumber(err) or 0
end

local ok, rc = xpcall(main, function(e)
    return tostring(e) .. "\n" .. debug.traceback("", 2)
end)
if not ok then
    io.stderr:write("KDASH FATAL: " .. tostring(rc) .. "\n")
    os.exit(1)
end
os.exit(rc or 0)
