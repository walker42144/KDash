-- Countdown 模块：事件倒计时（日期型按日历天，时刻型按秒）。
local timeutil = require("core.timeutil")
local util = require("core.util")

local M = {}
local state = { key = nil, entries = {} }

local function lang(ctx) return ctx.config.data.language or "zh" end

local function event_name(ev, l)
    if l == "en" and ev.name_en and ev.name_en ~= "" then return ev.name_en end
    return ev.name or ev.id or "EVENT"
end

local function compute_entries(ctx, now)
    local cfg = ctx.config:module("countdown")
    local offset = ctx.config.data.utc_offset_minutes or 480
    local l = lang(ctx)
    local entries = {}
    for _, ev in ipairs(cfg.events or {}) do
        if not ev.hidden then
            local days, hours, minutes, expired, target = timeutil.countdown(ev, now, offset)
            if days then
                entries[#entries + 1] = {
                    id = ev.id,
                    name = event_name(ev, l),
                    date = ev.date,
                    days = days,
                    hours = hours,
                    minutes = minutes,
                    expired = expired,
                    target = target,
                    pinned = ev.pinned == true,
                    timed = ev.time and ev.time ~= "",
                }
            end
        end
    end
    table.sort(entries, function(a, b)
        if a.pinned ~= b.pinned then return a.pinned end
        if a.expired ~= b.expired then return not a.expired end
        if a.days ~= b.days then return a.days < b.days end
        return a.name < b.name
    end)
    return entries
end

function M.init(ctx)
    state.key = nil
    state.entries = compute_entries(ctx, ctx.now())
    return true
end

function M.refresh_policy(ctx)
    for _,event in ipairs(ctx.config:module("countdown").events or {}) do
        if not event.hidden and event.time and event.time~="" then
            return {interval=require("core.refresh_policy").minutes(ctx.config.data)*60,
                align="interval",on_start=false,no_coalesce=true}
        end
    end
    return {interval=86400,align="day",on_start=false,no_coalesce=true}
end

function M.refresh(ctx)
    local entries = compute_entries(ctx, ctx.now())
    local key = ""
    for _, e in ipairs(entries) do
        key = key .. e.id .. ":" .. e.days .. ":" .. e.hours .. ":" .. e.minutes .. ":" .. tostring(e.expired) .. ";"
    end
    if key ~= state.key then
        state.key = key
        state.entries = entries
        ctx.request_update()
    end
    return true
end

local function draw_main(ui, rect, entry, l, overview)
    local theme = ui.theme
    local name_size = theme.type.small
    ui:text({
        text = ui.typo:fit(entry.name,rect.w,name_size),
        x = rect.x,
        y = rect.y,
        w = rect.w,
        size = name_size,
        color = theme.colors.ink,
    })
    local big_y = rect.y + ui.typo:line_height(name_size) + theme.space.xs
    local big = tostring(entry.days)
    local big_size = theme.type.display
    if rect.h < 230 then big_size = theme.type.title * 2 end
    while ui.typo:measure(big,big_size)>rect.w-theme.type.title*2 and big_size>theme.type.body do big_size=big_size-2 end
    local big_w = ui.typo:measure(big, big_size)
    ui:text({
        text = big,
        x = rect.x,
        y = big_y,
        w = rect.w,
        size = big_size,
        color = theme.colors.ink,
    })
    local unit = entry.expired and (l == "zh" and "天前" or "DAYS AGO") or (l == "zh" and "天" or "DAYS")
    if not entry.expired and entry.days == 0 then
        unit = l == "zh" and "今天" or "TODAY"
    elseif not entry.expired and entry.days == 1 then
        unit = l == "zh" and "明天" or "TOMORROW"
    end
    ui:text({
        text = unit,
        x = rect.x + big_w + theme.space.sm,
        y = big_y + math.floor(big_size * 0.55),
        w = rect.w - big_w - theme.space.sm,
        size = theme.type.title,
        color = theme.colors.muted,
    })
    if entry.timed then
        ui:text({
            text = string.format("%02d:%02d", entry.hours, entry.minutes),
            x = rect.x + big_w + theme.space.sm,
            y = big_y + math.floor(big_size * 0.55) + ui.typo:line_height(theme.type.title),
            w = rect.w - big_w - theme.space.sm,
            size = theme.type.micro,
            color = theme.colors.muted,
        })
    end
end

function M.render(ctx, ui, rect, opts)
    local l = lang(ctx)
    local entries = state.entries
    if #entries == 0 then
        ui:empty(rect, l == "zh" and "请设置目标日期" or "NO COUNTDOWN EVENTS")
        return
    end
    local main = entries[1]
    draw_main(ui, rect, main, l, opts and opts.overview)
    if opts and opts.overview then
        ui:text({text="目标日期 "..tostring(main.date),x=rect.x,y=rect.y+rect.h-ui.typo:line_height(ui.theme.type.micro),w=rect.w,size=ui.theme.type.micro,color=ui.theme.colors.muted})
    end
    if #entries > 1 and rect.h > 250 then
        local extra = {}
        for i = 2, math.min(#entries, 3) do
            extra[#extra + 1] = entries[i].name .. " " .. tostring(entries[i].days)
        end
        local y = rect.y + rect.h - ui.typo:line_height(ui.theme.type.micro)
        ui:text({
            text = table.concat(extra, "  ·  "),
            x = rect.x,
            y = y,
            w = rect.w,
            size = ui.theme.type.micro,
            color = ui.theme.colors.muted,
            align = "right",
        })
    end
    -- 点击卡片立即刷新
    ui:hit(rect, "module_sync", "countdown", "countdown")
end

return M
