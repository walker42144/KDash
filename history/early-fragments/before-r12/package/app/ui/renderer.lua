-- 页面渲染器：页眉、页脚、卡片布局、设置页、退出确认。
local timeutil = require("core.timeutil")
local util = require("core.util")
local UI = require("ui.components")

local Renderer = {}
Renderer.__index = Renderer

function Renderer.new(opts)
    local self = setmetatable({}, Renderer)
    self.app_dir = opts.app_dir or "."
    self.display = opts.display
    self.theme = opts.theme
    self.typo = opts.typo
    self.registry = opts.registry
    self.config = opts.config
    self.events = opts.events
    self.layout = opts.layout
    self.log = opts.log
    self.device_info=opts.device_info
    self.now = opts.now or os.time
    self.rects = {}
    self.page = nil
    self.last_page = nil
    return self
end

function Renderer:lang()
    return self.config.data.language or "zh"
end

function Renderer:pages()
    return self.config.data.pages or {}
end

function Renderer:content_rect()
    local t = self.theme
    local x = t.margin
    local y = t.margin + t.header_h + t.space.sm
    local w = self.display.width - t.margin * 2
    local h = self.display.height - y - t.margin - t.footer_h - t.space.sm
    return { x = x, y = y, w = w, h = h }
end

function Renderer:new_ui(module_id, page_id)
    return UI.new({
        display = self.display,
        theme = self.theme,
        typo = self.typo,
        events = self.events,
        module_id = module_id,
        page_id = page_id,
    })
end

function Renderer:render_header(page)
    local t = self.theme
    local ui = self:new_ui("__header", page and page.id or "")
    local y = t.margin
    -- Render the supplied artwork unchanged, scaled only at display time.
    local logo_size=math.floor(80*t.scale)
    self.display:icon(self.app_dir.."/assets/logo-user.ttf",t.margin,y-20,logo_size,logo_size)
    ui:text({
        text = "KDASH", x = t.margin+logo_size+t.space.sm, y = y+t.space.xs,
        w = 200, size = t.type.small, color = t.colors.ink,
    })
    if page and page.title and string.upper(page.title) ~= "KDASH" then
        ui:text({
            text = string.upper(page.title or page.id),
            x = t.margin, y = y + ui.typo:line_height(t.type.small) - t.space.xs,
            w = 400, size = t.type.micro, color = t.colors.muted,
        })
    end
    local now = self.now()
    local offset = self.config.data.utc_offset_minutes or 480
    local l = self:lang()
    local weekday=timeutil.weekday(now,offset,"en",false)
    weekday=weekday:sub(1,1)..weekday:sub(2):lower()
    local date = weekday .. "  " .. timeutil.date_label(now, offset, l)
    ui:text({
        text = date,
        x = math.floor(self.display.width / 2) - 220, y = y + t.space.xs,
        w = 440, size = t.type.micro, color = t.colors.muted, align = "center",
    })
    local bw,bh=math.floor(112*t.scale),math.floor(52*t.scale)
    local ex=self.display.width-t.margin-bw
    local ey=y
    ui:box({x=ex,y=ey,w=bw,h=bh},false,t.colors.faint)
    ui:text({text=self:lang()=="zh" and "退出" or "EXIT",x=ex+2,y=ey+2,w=bw-4,h=bh-4,valign="center",
        size=t.type.micro,align="center",color=t.colors.ink,bg=t.colors.paper})
    -- The visual button is quiet; its touch target remains generous.
    ui:hit({x=ex-t.space.sm,y=ey-t.space.sm,w=bw+t.space.sm*2,h=bh+t.space.sm*2},
        "exit_request",nil,"exit")

end

-- Dedicated screen, never an overlay on potentially private task content.
-- The wallpaper adapter is supplied as precompiled glyph tiles, not JPG decoding on Kindle.
function Renderer:render_screensaver(data_dir)
    local d=self.display
    d:begin_frame(true)
    local path=data_dir.."/screensaver/wallpaper.ttf"
    local f=io.open(path,"rb")
    if f then
        f:close()
        local tw,th=d.width/8,d.height/8
        for row=0,7 do for col=0,7 do
            d:text({font=path,text=string.char(33+row*8+col),x=col*tw,y=row*th,
                w=tw,h=th,size=th,measure_w=tw,color="ink",bg="paper"})
        end end
    else
        d:text({text="KDASH",x=80,y=math.floor(d.height*0.43),w=d.width-160,
            size=48,align="center",color="ink",bg="paper"})
        d:text({text="已息屏",x=80,y=d.height-100,w=d.width-160,
            size=24,align="center",color="gray2",bg="paper"})
    end
    d:flush({full=true})
end

function Renderer:render_footer(page)
    local t = self.theme
    local ui = self:new_ui("__footer", page and page.id or "")
    local y = self.display.height - t.margin - t.footer_h
    ui:hline(t.margin, y, self.display.width - t.margin * 2, t.colors.ink)
    if self.config.data.ui.minimal then
        local battery=self.device_info and (self.device_info().battery or {}) or {}
        local level=tonumber(battery.level)
        local bx=self.display.width-t.margin-170;local by=y+t.space.sm+12
        ui:box({x=bx,y=by+3,w=52,h=26},false,t.colors.ink)
        ui:fill({x=bx+52,y=by+10,w=5,h=12},t.colors.ink)
        if level then ui:fill({x=bx+4,y=by+7,w=math.floor(44*math.max(0,math.min(100,level))/100),h=18},t.colors.ink) end
        ui:text({text=(level and (tostring(math.floor(level)).."%") or "--%")..(battery.charging and " +" or ""),
            x=bx+68,y=by,w=100,size=t.type.micro,color=t.colors.ink})
        if self.config.data.ui.power_button_sleep then
            ui:text({text="短按电源键休息 · 再按返回",x=t.margin,y=y+t.space.sm+12,
                w=self.display.width-t.margin*2-200,size=t.type.micro,color=t.colors.muted})
            return
        end
        local paused=self.config.data.ui.auto_update==false
        ui:button({x=t.margin,y=y+t.space.sm,w=330,h=56},paused and "恢复自动更新" or "暂停自动更新",false,"toggle_updates")
        ui:text({text=paused and "自动更新已暂停" or "自动更新已开启",x=t.margin+366,y=y+t.space.sm+12,
            w=self.display.width-t.margin*2-366,size=t.type.micro,align="right",color=t.colors.muted})
        return
    end
    local pages = self:pages()
    if #pages == 0 then return end
    local content = self:content_rect()
    local item_w = math.floor(content.w / #pages)
    for i, p in ipairs(pages) do
        local x = content.x + (i - 1) * item_w
        local active = page and page.id == p.id
        local label = (p.id == "home") and "HOME" or string.upper(p.nav_title or p.title or p.id)
        ui:text({
            text = label,
            x = x, y = y + t.space.md,
            w = item_w, size = t.nav_size,
            color = active and t.colors.ink or t.colors.muted,
            align = "center",
        })
        if active then
            local label_w = ui.typo:measure(label, t.nav_size)
            local ux = x + math.floor((item_w - label_w) / 2)
            ui:hline(ux, y + t.space.md + ui.typo:line_height(t.nav_size) - 4, label_w, t.colors.ink)
        end
        self.events:add_hit({
            x = x, y = y, w = item_w, h = t.footer_h,
            action = "page", payload = p.id, label = "nav:" .. p.id,
        })
    end
end

function Renderer:draw_card(record, rect, page, clear)
    local t = self.theme
    local manifest = record.manifest
    local ui = self:new_ui(record.id, page and page.id or "")
    self.events:remove_module_hits(record.id)
    if clear then
        ui:fill({ x = rect.x, y = rect.y, w = rect.w, h = rect.h }, t.colors.paper)
    end
    local content = rect
    if manifest.layout == nil or manifest.layout.show_title ~= false then
        local titles = {countdown="目标倒计时",dida="今日待办",weather="天气"}
        local title = (page.overview and titles[record.id]) or manifest.display_title or manifest.name or manifest.id
        local cy = ui:section(title, rect)
        content = { x = rect.x, y = cy, w = rect.w, h = rect.h - (cy - rect.y) }
    end
    if page.overview and not self.registry:is_enabled(record.id) then
        local messages={dida="请在电脑配置工具中启用滴答清单并授权",weather="请在电脑配置工具中启用天气并设置城市"}
        ui:empty(content,messages[record.id] or "此分区已关闭")
        return
    end
    if record.error or not record.inst then
        ui:error(content, record.error or "module not initialized")
        return
    end
    record.inst.__ctx.page_id = page and page.id
    local ok, err = pcall(record.inst.render, record.inst.__ctx, ui, content, {
        page_id = page and page.id,
        detail = page and page.detail == true,
        overview = page and page.overview == true,
        language = self:lang(),
    })
    if not ok then
        if self.log then self.log:error("render:" .. record.id .. ": " .. tostring(err)) end
        ui:error(content, tostring(err))
    end
end

function Renderer:render_full(page)
    self.events:clear_hits()
    self.rects = {}
    self.page = page
    self.display:begin_frame(true)
    self:render_header(page)
    local content = self:content_rect()
    if page.kind == "settings" then
        self:render_settings(content)
    else
        local rows = self.layout:compute(page, content)
        if #rows == 0 then
            local ui = self:new_ui("__empty", page.id)
            ui:empty(content, self:lang() == "zh" and "所有模块均已关闭" or "ALL MODULES ARE DISABLED")
        end
        for _, row in ipairs(rows) do
            if not row.first then
                local y = row.rect.y - math.floor(self.theme.space.md / 2)
                self.display:hline(content.x, y, content.w, self.theme.line, self.theme.colors.ink)
            end
            if page.overview and #row.cells==2 then
                self.display:vline(row.cells[1].x+row.cells[1].w+math.floor(self.theme.space.lg/2),row.rect.y,row.rect.h,self.theme.line,self.theme.colors.faint)
            end
            for i, id in ipairs(row.modules) do
                local cell = row.cells[i]
                if cell then
                    local record = self.registry:get(id)
                    if record then
                        self:draw_card(record, cell, page, false)
                        self.rects[id] = { card = cell }
                    end
                end
            end
        end
    end
    self:render_footer(page)
    assert(self.display:flush({ full = true, flash = page.id ~= self.last_page }) ~= false, "full display failed")
    self.last_page = page.id
end

function Renderer:render_dirty(ids, page)
    if not self.page or self.page.id ~= (page and page.id) then return false end
    local any = false
    self.display:begin_frame(false)
    for _, id in ipairs(ids or {}) do
        if id == "clock" then
            self.events:remove_module_hits("__header")
            self.display:fill({x=0,y=0,w=self.display.width,h=self.theme.margin+self.theme.header_h},"paper")
            self:render_header(page)
            self.events:remove_module_hits("__footer")
            local fy=self.display.height-self.theme.margin-self.theme.footer_h
            self.display:fill({x=0,y=fy,w=self.display.width,h=self.display.height-fy},"paper")
            self:render_footer(page)
        end
        local rect = self.rects[id]
        local record = self.registry:get(id)
        if rect and record then
            self:draw_card(record, rect.card, page, true)
            any = true
        end
    end
    if not any then return false end
    assert(self.display:flush({ full = false }) ~= false, "partial display failed")
    return true
end

function Renderer:render_settings(content)
    local t = self.theme
    local ui = self:new_ui("__settings", "settings")
    local l = self:lang()
    local y = content.y
    ui:text({
        text = l == "zh" and "模块" or "MODULES",
        x = content.x, y = y, w = content.w,
        size = t.type.micro, color = t.colors.muted,
    })
    y = y + ui.typo:line_height(t.type.micro) + t.space.sm
    local row_h = math.floor(ui.typo:line_height(t.type.body) * 1.7)
    for _, manifest in ipairs(self.registry.modules) do
        local enabled = self.registry:is_enabled(manifest.id)
        local yi = y + math.floor((row_h - ui.typo:line_height(t.type.body)) / 2)
        ui:text({
            text = manifest.name or manifest.id,
            x = content.x, y = yi, w = content.w - 180,
            size = t.type.body, color = t.colors.ink,
        })
        local box = { x = content.x + content.w - 120, y = y + math.floor((row_h - 44) / 2), w = 120, h = 44 }
        ui:button(box, enabled and "ON" or "OFF", enabled, "toggle_module", manifest.id)
        ui:hline(content.x, y + row_h - 1, content.w, t.colors.faint)
        y = y + row_h
    end
    y = y + t.space.lg
    ui:text({
        text = l == "zh" and "操作" or "ACTIONS",
        x = content.x, y = y, w = content.w,
        size = t.type.micro, color = t.colors.muted,
    })
    y = y + ui.typo:line_height(t.type.micro) + t.space.sm
    local bw = math.floor((content.w - t.space.md) / 2)
    ui:button({ x = content.x, y = y, w = bw, h = 64 }, l == "zh" and "立即同步" or "SYNC NOW", false, "sync_all")
    local policy = self.config.data.power.keep_awake or "plugged"
    ui:button({ x = content.x + bw + t.space.md, y = y, w = bw, h = 64 },
        string.upper((l == "zh" and "唤醒策略: " or "AWAKE: ") .. policy), false, "cycle_power")
    y = y + 64 + t.space.md
    ui:button({ x = content.x, y = y, w = bw, h = 64 }, l == "zh" and "退出 KDASH" or "EXIT KDASH", true, "exit_request")
    ui:text({
        text = "CONFIG  /mnt/us/kdash/config.json",
        x = content.x + bw + t.space.md, y = y + 20, w = bw,
        size = t.type.micro, color = t.colors.muted,
    })
    y = y + 64 + t.space.lg
    ui:text({
        text = l == "zh" and "复杂设置（Token、城市、倒计时事件）请用电脑编辑 config.json / secrets.json"
            or "EDIT config.json / secrets.json ON A COMPUTER FOR TOKENS, CITY AND EVENTS",
        x = content.x, y = y, w = content.w,
        size = t.type.micro, color = t.colors.muted,
    })
end

function Renderer:render_confirm()
    local t = self.theme
    local w = math.min(680, self.display.width - t.margin * 2)
    local h = 360
    local x = math.floor((self.display.width - w) / 2)
    local y = math.floor((self.display.height - h) / 2)
    self.events:clear_hits()
    self.display:begin_frame(false)
    self.display:fill({ x = x, y = y, w = w, h = h }, t.colors.ink)
    self.display:fill({ x = x + 4, y = y + 4, w = w - 8, h = h - 8 }, t.colors.paper)
    local ui = self:new_ui("__confirm", "confirm")
    local l = self:lang()
    ui:text({
        text = l == "zh" and "退出 KDASH？" or "EXIT KDASH?",
        x = x + t.space.xl, y = y + t.space.xl, w = w - t.space.xl * 2,
        size = t.type.title, color = t.colors.ink, align = "center",
    })
    ui:text({
        text = l == "zh" and "退出后将返回 Kindle 书库" or "THE KINDLE LIBRARY WILL BE RESTORED",
        x = x + t.space.xl, y = y + t.space.xl + ui.typo:line_height(t.type.title) + t.space.md,
        w = w - t.space.xl * 2, size = t.type.micro, color = t.colors.muted, align = "center",
    })
    local bw = 240
    local by = y + h - 100
    ui:button({ x = x + t.space.xl, y = by, w = bw, h = 64 }, l == "zh" and "取消" or "CANCEL", false, "exit_cancel")
    ui:button({ x = x + w - t.space.xl - bw, y = by, w = bw, h = 64 }, l == "zh" and "退出" or "EXIT", true, "exit_confirm")
    self.display:flush({ full = false, waveform = "GC16" })
end

return Renderer
