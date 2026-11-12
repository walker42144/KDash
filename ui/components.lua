-- UI 绘制辅助：所有模块通过它排版，保证字号、间距和触控命中一致。
local util = require("core.util")

local UI = {}
UI.__index = UI

function UI.new(opts)
    local self = setmetatable({}, UI)
    self.display = opts.display
    self.theme = opts.theme
    self.typo = opts.typo
    self.events = opts.events
    self.module_id = opts.module_id
    self.page_id = opts.page_id
    return self
end

function UI:text(opts)
    local size = opts.size or self.theme.type.body
    local text = tostring(opts.text or "")
    local measured = self.typo:measure(text, size)
    local w = opts.w or (self.display.width - (opts.x or 0) - self.theme.margin)
    local x = opts.x or self.theme.margin
    local align = opts.align or "left"
    if align == "right" then
        x = x + w - measured
        align = "left"
    end
    if align == "center" then
        x = opts.x or self.theme.margin
    end
    self.display:text({
        x = x,
        y = opts.y,
        w = w,
        h = opts.h,
        valign = opts.valign,
        size = size,
        text = text,
        align = align,
        color = opts.color or self.theme.colors.ink,
        bg = opts.bg or self.theme.colors.paper,
        weight = opts.weight,
        measure_w = measured,
    })
    return measured
end

function UI:fill(rect, color)
    self.display:fill(rect, color or self.theme.colors.ink)
end

function UI:hline(x, y, w, color)
    self.display:hline(x, y, w, self.theme.line, color)
end

function UI:vline(x, y, h, color)
    self.display:vline(x, y, h, self.theme.line, color)
end

function UI:box(rect, filled, color)
    local c = color or self.theme.colors.ink
    if filled then
        self:fill(rect, c)
        return
    end
    local t = self.theme.line
    self:fill({ x = rect.x, y = rect.y, w = rect.w, h = t }, c)
    self:fill({ x = rect.x, y = rect.y + rect.h - t, w = rect.w, h = t }, c)
    self:fill({ x = rect.x, y = rect.y, w = t, h = rect.h }, c)
    self:fill({ x = rect.x + rect.w - t, y = rect.y, w = t, h = rect.h }, c)
end

function UI:checkbox(x, y, checked, size)
    size = size or 24
    self:box({ x = x, y = y, w = size, h = size }, false)
    if checked then
        local pad = math.max(4, math.floor(size / 5))
        self:fill({ x = x + pad, y = y + pad, w = size - pad * 2, h = size - pad * 2 })
    end
    return size
end

function UI:progress(rect, value)
    local v = util.clamp(value or 0, 0, 100)
    self:fill(rect, self.theme.colors.faint)
    if v > 0 then
        self:fill({ x = rect.x, y = rect.y, w = math.floor(rect.w * v / 100), h = rect.h })
    end
end

function UI:label(text, x, y, w, opts)
    opts = opts or {}
    return self:text({
        text = string.upper(text or ""),
        x = x,
        y = y,
        w = w,
        size = opts.size or self.theme.type.micro,
        color = opts.color or self.theme.colors.muted,
        align = opts.align or "left",
    })
end

-- 卡片标题，返回内容起始 y。
function UI:section(title, rect, opts)
    opts = opts or {}
    if title == nil or title == "" then return rect.y end
    local size = self.theme.type.micro
    local y = rect.y + (opts.pad_top or 0)
    self:text({
        text = string.upper(title),
        x = rect.x,
        y = y,
        w = rect.w,
        size = size,
        color = self.theme.colors.muted,
        align = opts.align or "left",
    })
    return y + self.typo:line_height(size) + math.floor(self.theme.space.xs / 2)
end

function UI:empty(rect, text)
    local size = self.theme.type.small
    self:text({
        text = text,
        x = rect.x,
        y = rect.y + math.floor(rect.h / 2) - size,
        w = rect.w,
        size = size,
        align = "center",
        color = self.theme.colors.muted,
    })
end

function UI:error(rect, err)
    local size = self.theme.type.small
    local y = rect.y
    self:text({
        text = "MODULE ERROR",
        x = rect.x,
        y = y,
        w = rect.w,
        size = size,
        color = self.theme.colors.ink,
    })
    local lines = self.typo:wrap(tostring(err or "unknown"), rect.w, self.theme.type.micro)
    for i = 1, math.min(2, #lines) do
        self:text({
            text = lines[i],
            x = rect.x,
            y = y + self.typo:line_height(size) + i * self.typo:line_height(self.theme.type.micro),
            w = rect.w,
            size = self.theme.type.micro,
            color = self.theme.colors.muted,
        })
    end
end

-- KPW3 is 300dpi: 9px ~= 0.76mm. Priority values: 0/1/3/5.
function UI:priority_marks(rect,priority)
    local count=({[1]=1,[3]=2,[5]=3})[tonumber(priority)] or 0
    if count==0 then return 0 end
    local scale=self.theme.scale or 1
    local width=math.max(1,math.floor(9*scale+0.5));local gap=math.max(1,math.floor(7*scale+0.5))
    local height=math.min(rect.h,math.floor(28*scale+0.5))
    local occupied=count*width+(count-1)*gap
    local x=rect.x+rect.w-occupied;local y=rect.y+math.floor((rect.h-height)/2)
    for i=0,count-1 do self:fill({x=x+i*(width+gap),y=y,w=width,h=height},self.theme.colors.ink) end
    return 3*width+2*gap+self.theme.space.sm
end

function UI:task_row(rect, title, meta, checked, opts)
    opts = opts or {}
    local box_size = opts.box_size or 22
    local size = opts.size or self.theme.type.body
    self:checkbox(rect.x, rect.y + math.floor((rect.h-box_size)/2), checked, box_size)
    local text_x = rect.x + box_size + self.theme.space.sm
    local meta_size = self.theme.type.micro
    local meta_w = 0
    if meta and meta ~= "" then
        meta_w = self.typo:measure(meta, meta_size) + self.theme.space.sm
    end
    local title_text = self.typo:fit(title or "", rect.w - (text_x - rect.x) - meta_w, size)
    self:text({
        text = title_text,
        x = text_x,
        y = rect.y + math.floor((rect.h-size)/2),
        w = rect.w - (text_x - rect.x) - meta_w,
        size = size,
        color = self.theme.colors.ink,
    })
    if meta and meta ~= "" then
        self:text({
            text = meta,
            x = rect.x,
            y = rect.y + math.floor((rect.h-meta_size)/2),
            w = rect.w,
            size = meta_size,
            color = self.theme.colors.muted,
            align = "right",
        })
    end
    return self.typo:line_height(size)
end

function UI:button(rect, label, inverted, action, payload)
    if inverted then
        self:fill(rect, self.theme.colors.inverse_bg)
    else
        self:box(rect, false)
    end
    local size = self.theme.type.small
    self:text({
        text = label,
        x = rect.x,
        y = rect.y + math.floor((rect.h - size) / 2),
        w = rect.w,
        size = size,
        align = "center",
        color = inverted and self.theme.colors.inverse_fg or self.theme.colors.ink,
        bg = inverted and self.theme.colors.inverse_bg or self.theme.colors.paper,
    })
    self:hit(rect, action, payload)
end

function UI:hit(rect, action, payload, label)
    if not self.events then return end
    self.events:add_hit({
        x = rect.x,
        y = rect.y,
        w = rect.w,
        h = rect.h,
        action = action,
        payload = payload,
        label = label,
        module_id = self.module_id,
    })
end

function UI:line(text, x, y, w, size, color)
    return self:text({ text = text, x = x, y = y, w = w, size = size or self.theme.type.body, color = color })
end

return UI
