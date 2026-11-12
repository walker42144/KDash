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
        interval = math.max(300, (cfg.sync_interval_minutes or 45) * 60),
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
    if opts and opts.overview then
        local function text(value,x,y,w,size,color)
            ui:text({text=value,x=x,y=y,w=w,size=size,color=color or theme.colors.ink})
        end
        if not view then
            ui:empty(rect,state.error and "天气同步失败，请检查网络和电脑端配置" or "天气已启用，等待首次同步")
            ui:hit(rect,"module_sync","weather","weather"); return
        end
        local left=math.floor(rect.w*0.30)
        text(view.temp and (tostring(view.temp).."°") or "--°",rect.x,rect.y+20, left,theme.type.display)
        local rx=rect.x+left; local rw=rect.w-left
        text(ui.typo:fit(city.."  "..(view.desc or ""),rw,theme.type.body),rx,rect.y+12,rw,theme.type.body)
        text(string.format("最高 %s°   最低 %s°",view.high or "--",view.low or "--"),rx,rect.y+68,rw,theme.type.small,theme.colors.muted)
        local extra={}
        if view.humidity~=nil then extra[#extra+1]="湿度 "..tostring(view.humidity).."%" end
        if view.wind_direction or view.wind_power then extra[#extra+1]=(view.wind_direction or "").."风 "..tostring(view.wind_power or "--").."级" end
        if view.feels~=nil then extra[#extra+1]="体感 "..tostring(view.feels).."°" end
        if view.rain~=nil then extra[#extra+1]="降雨概率 "..tostring(view.rain).."%" end
        text(ui.typo:fit(table.concat(extra,"  "),rw,theme.type.micro),rx,rect.y+112,rw,theme.type.micro,theme.colors.muted)
        local fy=rect.y+166
        for i=2,math.min(3,#(view.days or {})) do
            local day=view.days[i]
            local offset=ctx.config.data.utc_offset_minutes or 480
            local key=day.date
            local label=(key==timeutil.date_key(ctx.now()+86400,offset) and "明天")
                or (key==timeutil.date_key(ctx.now()+172800,offset) and "后天") or key or ("第"..i.."日")
            local value=label.."  "..(day.desc or "--").."  "..tostring(day.low or "--").."～"..tostring(day.high or "--").."°"
            if day.night_desc and day.night_desc~=day.desc then value=value.."  夜间"..day.night_desc end
            if fy+ui.typo:line_height(theme.type.micro)<=rect.y+rect.h-ui.typo:line_height(theme.type.micro)-12 then
                text(ui.typo:fit(value,rect.w,theme.type.micro),rect.x,fy,rect.w,theme.type.micro,theme.colors.ink)
                fy=fy+34
            end
        end
        local provider=view.provider=="amap" and "高德天气" or "Open-Meteo"
        local status=state.error and "同步失败 · 显示缓存" or (state.cached_at and ("同步于 "..timeutil.format_time(state.cached_at,ctx.config.data.utc_offset_minutes or 480,true)) or "尚未同步")
        local sy=rect.y+rect.h-ui.typo:line_height(theme.type.micro)
        text(provider,rect.x,sy,left,theme.type.micro,theme.colors.muted)
        ui:text({text=status,x=rx,y=sy,w=rw,size=theme.type.micro,color=theme.colors.muted,align="right"})
        ui:hit(rect,"module_sync","weather","weather"); return
    end
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
