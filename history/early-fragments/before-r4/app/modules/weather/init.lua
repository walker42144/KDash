-- Weather 模块：Open-Meteo 当前天气与三日预报。
local WeatherAPI = require("services.api.weather")
local timeutil = require("core.timeutil")

local M = {}
local state = { view = nil, error = nil, cached_at = nil, adapter = nil, syncing = false }

local function lang(ctx) return ctx.config.data.language or "zh" end

function M.init(ctx)
    state.adapter = WeatherAPI.new({
        http = ctx.http,
        config = ctx.config,
        secrets = ctx.secrets,
        cache = ctx.cache,
        log = ctx.log,
        now = ctx.now,
    })
    local cached = ctx.cache:read("weather")
    if cached and cached.data and (cached.data.provider or "open-meteo") == (ctx.config:module("weather").provider or "open-meteo") then
        state.view = cached.data
        state.cached_at = cached.fetched_at
    end
    return true
end

function M.refresh_policy(ctx)
    local cfg = ctx.config:module("weather")
    return {
        interval = math.max(600, (cfg.sync_interval_minutes or 45) * 60),
        max_backoff = 7200,
    }
end

function M.refresh(ctx)
    if state.syncing then return false end
    state.syncing = true
    state.adapter:sync(function(ok, err, view)
        state.syncing = false
        if ok then
            state.view = view
            state.cached_at = ctx.now()
            state.error = nil
        else
            state.error = tostring(err)
        end
        ctx.request_update()
        ctx.finish(ok, err)
    end)
    return false
end

local function city_name(ctx)
    local cfg = ctx.config:module("weather")
    if lang(ctx) == "en" then return cfg.city_en or cfg.city or "" end
    return cfg.city or cfg.city_en or ""
end

function M.render(ctx, ui, rect, opts)
    local theme = ui.theme
    local l = lang(ctx)
    local detail = opts and opts.detail == true
    local view = state.view
    local city = city_name(ctx)
    if state.view and state.view.city then city = state.view.city end
    ui:text({
        text = string.upper(city),
        x = rect.x, y = rect.y, w = rect.w,
        size = theme.type.micro, color = theme.colors.muted, align = "right",
    })
    if not view then
        ui:empty({ x = rect.x, y = rect.y + theme.space.md, w = rect.w, h = rect.h - theme.space.md },
            l == "zh" and "暂无天气数据" or "NO WEATHER DATA")
        ui:hit(rect, "module_sync", "weather", "weather")
        return
    end

    local temp = view.temp and (tostring(view.temp) .. "°") or "--°"
    local temp_size = theme.type.display
    local status = state.error and (l == "zh" and "离线 · 显示缓存" or "OFFLINE · CACHED")
        or (state.cached_at and timeutil.format_time(state.cached_at,
            ctx.config.data.utc_offset_minutes or 480, true))
    local status_h = ui.typo:line_height(theme.type.micro)
    local bottom = rect.y + rect.h - status_h - 4

    if rect.h < 280 then
        -- 紧凑横向布局：温度在左，描述/高低温在右，避免侵入页脚。
        local temp_y = rect.y + 4
        ui:text({
            text = temp, x = rect.x, y = temp_y, w = rect.w,
            size = temp_size, color = theme.colors.ink,
        })
        local temp_w = ui.typo:measure(temp, temp_size)
        local right_x = rect.x + math.min(temp_w + theme.space.md, math.floor(rect.w * 0.55))
        local right_w = rect.w - (right_x - rect.x)
        ui:text({
            text = view.desc or "", x = right_x, y = rect.y + theme.space.xs,
            w = right_w, size = theme.type.body, color = theme.colors.ink,
        })
        local hl = string.format("H %s°  L %s°",
            view.high and tostring(view.high) or "--",
            view.low and tostring(view.low) or "--")
        if view.rain ~= nil then
            hl = hl .. string.format("   %s %d%%", l == "zh" and "降雨" or "RAIN", view.rain)
        end
        local hl_y = rect.y + theme.space.xs + ui.typo:line_height(theme.type.body)
        if hl_y + ui.typo:line_height(theme.type.small) <= bottom then
            ui:text({
                text = hl, x = right_x, y = hl_y, w = right_w,
                size = theme.type.small, color = theme.colors.muted,
            })
        end
        if detail and #view.days > 0 then
            local y = rect.y + ui.typo:line_height(temp_size)
            local row_h = ui.typo:line_height(theme.type.small)
            for _, day in ipairs(view.days) do
                if y + row_h > bottom then break end
                ui:text({
                    text = day.label, x = rect.x, y = y, w = math.floor(rect.w * 0.3),
                    size = theme.type.small, color = theme.colors.ink,
                })
                ui:text({
                    text = day.desc, x = rect.x + math.floor(rect.w * 0.3), y = y,
                    w = math.floor(rect.w * 0.4), size = theme.type.small, color = theme.colors.ink,
                })
                ui:text({
                    text = string.format("%s°/%s°", day.high or "--", day.low or "--"),
                    x = rect.x, y = y, w = rect.w, size = theme.type.small,
                    color = theme.colors.muted, align = "right",
                })
                y = y + row_h
            end
        end
    else
        local temp_y = rect.y + theme.space.sm
        ui:text({
            text = temp, x = rect.x, y = temp_y, w = rect.w,
            size = temp_size, color = theme.colors.ink,
        })
        local desc_y = temp_y + ui.typo:line_height(temp_size) - theme.space.sm
        ui:text({
            text = view.desc or "", x = rect.x, y = desc_y, w = rect.w,
            size = theme.type.body, color = theme.colors.ink,
        })
        local hl = string.format("H %s°  /  L %s°",
            view.high and tostring(view.high) or "--",
            view.low and tostring(view.low) or "--")
        if view.rain ~= nil then
            hl = hl .. string.format("   %s %d%%", l == "zh" and "降雨" or "RAIN", view.rain)
        end
        local hl_y = desc_y + ui.typo:line_height(theme.type.body)
        if hl_y + ui.typo:line_height(theme.type.small) <= bottom then
            ui:text({
                text = hl, x = rect.x, y = hl_y, w = rect.w,
                size = theme.type.small, color = theme.colors.muted,
            })
        end
        if detail and #view.days > 0 then
            local y = hl_y + ui.typo:line_height(theme.type.small) + theme.space.sm
            local row_h = ui.typo:line_height(theme.type.small)
            for _, day in ipairs(view.days) do
                if y + row_h > bottom then break end
                ui:text({
                    text = day.label, x = rect.x, y = y, w = math.floor(rect.w * 0.3),
                    size = theme.type.small, color = theme.colors.ink,
                })
                ui:text({
                    text = day.desc, x = rect.x + math.floor(rect.w * 0.3), y = y,
                    w = math.floor(rect.w * 0.4), size = theme.type.small, color = theme.colors.ink,
                })
                ui:text({
                    text = string.format("%s°/%s°", day.high or "--", day.low or "--"),
                    x = rect.x, y = y, w = rect.w, size = theme.type.small,
                    color = theme.colors.muted, align = "right",
                })
                y = y + row_h
            end
        end
    end
    if status then
        ui:text({
            text = status, x = rect.x, y = rect.y + rect.h - status_h,
            w = rect.w, size = theme.type.micro, color = theme.colors.muted, align = "right",
        })
    end
    ui:text({text=(view.provider == "amap" and "高德天气" or "Open-Meteo"),x=rect.x,y=rect.y+rect.h-ui.typo:line_height(theme.type.micro),w=rect.w,size=theme.type.micro})
    ui:hit(rect, "module_sync", "weather", "weather")
end

return M
