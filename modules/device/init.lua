-- Device 模块：电池、充电、Wi-Fi、固件、运行时间、存储与前光。
local timeutil = require("core.timeutil")

local M = {}
local state = { info = nil }

function M.init(ctx)
    state.info = ctx.device_info()
    return true
end

function M.refresh_policy(ctx)
    local cfg = ctx.config:module("device")
    return { interval = math.max(60, (cfg.refresh_minutes or 5) * 60) }
end

function M.refresh(ctx)
    state.info = ctx.device_info(true)
    ctx.request_update()
    return true
end

local function gb(kb)
    if not kb then return "--" end
    return string.format("%.1fG", kb / 1024 / 1024)
end

function M.render(ctx, ui, rect, opts)
    local theme = ui.theme
    local l = ctx.config.data.language or "zh"
    local info = state.info or ctx.device_info()
    local detail = opts and opts.detail == true
    local bat = info.battery or {}
    local level = bat.level
    local level_text = level and (tostring(level) .. "%") or "--"
    local wifi = info.wifi or {}

    if not detail then
        local y = rect.y
        local size = theme.type.body
        local left = string.format("BAT %s%s", level_text, bat.charging and "  CHARGING" or "")
        ui:text({
            text = left,
            x = rect.x, y = y, w = rect.w,
            size = size, color = theme.colors.ink,
        })
        ui:text({
            text = wifi.label or "WIFI",
            x = rect.x, y = y, w = rect.w,
            size = theme.type.small, color = theme.colors.muted, align = "right",
        })
        local bar_y = y + ui.typo:line_height(size) + theme.space.xs
        local bar_w = math.floor(rect.w * 0.45)
        ui:progress({ x = rect.x, y = bar_y, w = bar_w, h = theme.line * 3 }, level or 0)
        ui:text({
            text = info.firmware or "unknown",
            x = rect.x, y = bar_y - theme.line, w = rect.w,
            size = theme.type.micro, color = theme.colors.muted, align = "right",
        })
        return
    end

    local rows = {
        { l == "zh" and "电池" or "BATTERY", level_text .. (bat.charging and (l == "zh" and " · 充电中" or " · CHARGING") or "") },
        { "WIFI", (wifi.label or "UNKNOWN") .. (wifi.iface and (" · " .. wifi.iface) or "") },
        { l == "zh" and "固件" or "FIRMWARE", info.firmware or "unknown" },
        { l == "zh" and "运行时间" or "UPTIME", timeutil.uptime_string(info.uptime) },
        { l == "zh" and "存储" or "STORAGE", info.storage and (gb(info.storage.free_kb) .. " " .. (l == "zh" and "可用" or "FREE")) or "--" },
        { l == "zh" and "前光" or "FRONTLIGHT", info.frontlight and tostring(info.frontlight) or "--" },
    }
    local y = rect.y
    local row_h = ui.typo:line_height(theme.type.small)
    local max_rows = math.floor((rect.y + rect.h - y) / row_h)
    for i = 1, math.min(#rows, max_rows) do
        local row = rows[i]
        ui:text({
            text = row[1],
            x = rect.x, y = y, w = math.floor(rect.w * 0.4),
            size = theme.type.small, color = theme.colors.muted,
        })
        ui:text({
            text = row[2],
            x = rect.x + math.floor(rect.w * 0.4), y = y, w = rect.w - math.floor(rect.w * 0.4),
            size = theme.type.small, color = theme.colors.ink,
        })
        y = y + row_h
    end
end

return M
