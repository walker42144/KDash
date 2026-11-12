-- 主机 SVG 预览后端：与 FBInk 后端相同的绘制接口，用于布局自检。
local HostDisplay = {}
HostDisplay.__index = HostDisplay

local COLORS = {
    paper = "#ffffff", ink = "#000000",
    gray1 = "#3f3f46", gray2 = "#71717a", gray3 = "#a1a1aa",
    gray4 = "#d4d4d8", gray5 = "#e4e4e7", gray6 = "#f4f4f5",
    gray7 = "#fafafa", gray8 = "#f4f4f5", gray9 = "#fafafa",
}

local function color(c)
    return COLORS[c] or c or "#000000"
end

local function esc(s)
    return tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
        :gsub('"', "&quot;")
end

function HostDisplay.new(opts)
    local self = setmetatable({}, HostDisplay)
    self.width = opts.width or 1072
    self.height = opts.height or 1448
    self.out = opts.out or "preview.svg"
    self.ops = {}
    self.available = true
    return self
end

function HostDisplay:begin_frame(full)
    if full then
        self.ops = {}
        self.ops[#self.ops + 1] = {
            kind = "fill",
            rect = { x = 0, y = 0, w = self.width, h = self.height },
            color = "paper",
        }
    end
end

function HostDisplay:fill(rect, c)
    self.ops[#self.ops + 1] = { kind = "fill", rect = rect, color = c or "ink" }
end

function HostDisplay:hline(x, y, w, thickness, c)
    self:fill({ x = x, y = y, w = w, h = thickness or 2 }, c or "ink")
end

function HostDisplay:vline(x, y, h, thickness, c)
    self:fill({ x = x, y = y, w = thickness or 2, h = h }, c or "ink")
end

function HostDisplay:text(opts)
    self.ops[#self.ops + 1] = {
        kind = "text",
        x = opts.x or 0,
        y = opts.y or 0,
        w = opts.w or 0,
        size = opts.size or 24,
        h = opts.h, valign = opts.valign,
        text = opts.text or "",
        align = opts.align or "left",
        color = opts.color or "ink",
        bg = opts.bg,
    }
end

function HostDisplay:image() end
function HostDisplay:icon(font,x,y,w,h)
    self.ops[#self.ops+1]={kind="icon",x=x,y=y,w=w,h=h}
end

function HostDisplay:flush()
    local out = {}
    out[#out + 1] = string.format(
        '<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">',
        self.width, self.height, self.width, self.height)
    out[#out + 1] = '<rect width="100%" height="100%" fill="#ffffff"/>'
    for _, op in ipairs(self.ops) do
        if op.kind == "fill" then
            local r = op.rect
            out[#out + 1] = string.format(
                '<rect x="%d" y="%d" width="%d" height="%d" fill="%s"/>',
                math.floor(r.x), math.floor(r.y), math.floor(r.w), math.floor(r.h), color(op.color))
        elseif op.kind == "icon" then
            out[#out+1]=string.format('<text x="%d" y="%d" font-family="KDash User Face" font-size="%d">A</text>',op.x,op.y+op.h,op.h)
        elseif op.kind == "text" then
            local anchor = "start"
            local x = op.x
            if op.align == "center" then
                anchor = "middle"
                x = op.x + op.w / 2
            elseif op.align == "right" then
                anchor = "end"
                x = op.x + op.w
            end
            local text_y=op.y
            if op.valign=="center" and op.h then text_y=text_y+(op.h-op.size)/2 end
            out[#out + 1] = string.format(
                '<text x="%.1f" y="%.1f" font-family="Noto Sans SC, sans-serif" font-size="%d" fill="%s" text-anchor="%s">%s</text>',
                x, text_y + op.size * 0.8, op.size, color(op.color), anchor, esc(op.text))
        end
    end
    out[#out + 1] = "</svg>"
    local f = io.open(self.out, "wb")
    if not f then return false end
    f:write(table.concat(out, "\n"))
    f:close()
    return true
end

function HostDisplay:clear() end

return HostDisplay
