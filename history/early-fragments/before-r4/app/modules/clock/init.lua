-- Clock 模块：大字号时间、日期、星期，中英文与 12/24 小时制。
local timeutil = require("core.timeutil")

local M = {}
local state = { minute_key = nil }

local function lang(ctx)
    return ctx.config.data.language or "zh"
end

function M.init(ctx)
    state.minute_key = nil
    return true
end

function M.refresh_policy(ctx)
    local cfg = ctx.config:module("clock")
    if cfg.show_seconds then
        return { interval = 10, align = "minute" }
    end
    return { interval = 30, align = "minute" }
end

function M.refresh(ctx)
    local now = ctx.now()
    local offset = ctx.config.data.utc_offset_minutes or 480
    local key = os.date("!%Y-%m-%dT%H:%M", now + offset * 60)
    if state.minute_key ~= key then
        state.minute_key = key
        ctx.request_update()
    end
    return true
end

function M.render(ctx, ui, rect, opts)
    local cfg = ctx.config:module("clock")
    local now = ctx.now()
    local offset = ctx.config.data.utc_offset_minutes or 480
    local l = lang(ctx)
    local use_24h = cfg.format ~= "12h"
    local time_text = timeutil.format_time(now, offset, use_24h)
    local theme = ui.theme

    -- 日期/星期由全局页眉显示；卡片保持极简的大字号时间。
    local hero_size = theme.type.hero
    if rect.h < 260 then hero_size = theme.type.display end
    local hero_line = ui.typo:line_height(hero_size)
    local hero_y = rect.y + math.max(0, math.floor((rect.h - hero_line) / 2))
    ui:text({
        text = time_text,
        x = rect.x,
        y = hero_y,
        w = rect.w,
        size = hero_size,
        align = "center",
        color = theme.colors.ink,
    })

    if cfg.show_seconds then
        local sec = os.date("!%S", now + offset * 60)
        ui:text({
            text = sec,
            x = rect.x,
            y = hero_y + math.floor(hero_size * 0.9),
            w = rect.w,
            size = theme.type.small,
            align = "center",
            color = theme.colors.muted,
        })
    end
end

return M
