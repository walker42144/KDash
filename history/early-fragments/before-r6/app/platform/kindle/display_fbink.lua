-- FBInk 显示后端：批量写入 framebuffer，合并脏区域后统一刷新。
local util = require("core.util")

local Display = {}
Display.__index = Display

local COLOR_NAME = {
    ink = "BLACK",
    paper = "WHITE",
    gray1 = "GRAY1",
    gray2 = "GRAY2",
    gray3 = "GRAY3",
    gray4 = "GRAY4",
    gray5 = "GRAY5",
    gray6 = "GRAY6",
    gray7 = "GRAY7",
    gray8 = "GRAY8",
    gray9 = "GRAY9",
}

local function color_name(c)
    return COLOR_NAME[c] or c or "BLACK"
end

function Display.new(opts)
    local self = setmetatable({}, Display)
    self.runner = opts.runner
    self.fbink = opts.fbink
    self.width = opts.width or 1072
    self.height = opts.height or 1448
    self.font = opts.font
    self.log = opts.log
    self.ops = {}
    self.dirty = {}
    self.partial_count = 0
    self.full_refresh_every = opts.full_refresh_every or 24
    self.margin = opts.margin or 56
    self.color_ink = opts.ink_mode and "paper" or "ink"
    self.color_paper = opts.ink_mode and "ink" or "paper"
    self.available = true
    return self
end

function Display:begin_frame(full)
    self.ops = {}
    self.dirty = {}
    if full then
        self:fill({ x = 0, y = 0, w = self.width, h = self.height }, "paper")
    end
end

function Display:add_dirty(x, y, w, h)
    x = math.floor(x or 0)
    y = math.floor(y or 0)
    w = math.floor(w or 0)
    h = math.floor(h or 0)
    if w <= 0 or h <= 0 then return end
    local x2 = math.min(self.width, x + w)
    local y2 = math.min(self.height, y + h)
    x = math.max(0, x)
    y = math.max(0, y)
    w = x2 - x
    h = y2 - y
    if w <= 0 or h <= 0 then return end
    self.dirty[#self.dirty + 1] = { x = x, y = y, w = w, h = h }
end

function Display:fill(rect, color)
    local c = color or "paper"
    local r = {
        x = util.clamp(math.floor(rect.x or 0), 0, self.width - 1),
        y = util.clamp(math.floor(rect.y or 0), 0, self.height - 1),
        w = math.floor(rect.w or 0),
        h = math.floor(rect.h or 0),
    }
    if r.w <= 0 or r.h <= 0 then return end
    if r.x + r.w > self.width then r.w = self.width - r.x end
    if r.y + r.h > self.height then r.h = self.height - r.y end
    self.ops[#self.ops + 1] = {
        kind = "fill",
        rect = r,
        color = c,
    }
    self:add_dirty(r.x, r.y, r.w, r.h)
end

function Display:hline(x, y, w, thickness, color)
    self:fill({ x = x, y = y, w = w, h = thickness or 2 }, color or "ink")
end

function Display:vline(x, y, h, thickness, color)
    self:fill({ x = x, y = y, w = thickness or 2, h = h }, color or "ink")
end

-- opts: x, y, w, h, size, text, align ("left"|"center"|"right"), color, bg
function Display:text(opts)
    if not opts.text or opts.text == "" then return end
    local size = math.max(8, math.floor(opts.size or 32))
    local line_h = opts.h or util.round(size * 1.3)
    local x = math.floor(opts.x or self.margin)
    local w = opts.w
    if w == nil then w = self.width - x - self.margin end
    local y = math.floor(opts.y or 0)
    local right = self.width - (x + w)
    local bottom = self.height - (y + line_h)
    if right < 0 then right = 0 end
    if bottom < 0 then bottom = 0 end
    local font = opts.font or self.font
    local tt = string.format("regular=%s,px=%d,top=%d,bottom=%d,left=%d,right=%d,style=%s",
        font, size, y, bottom, x, right, "REGULAR")
    local argv = {
        self.fbink, "-q", "-b",
        "-t", tt,
        "-B", color_name(opts.bg or self.color_paper),
        "-C", color_name(opts.color or self.color_ink),
    }
    if opts.align == "center" then
        argv[#argv + 1] = "-m"
    elseif opts.align == "right" then
        -- FBInk 没有右对齐的 OTF 选项，调用方应自行计算 x；此处保留左对齐语义
    end
    argv[#argv + 1] = "--"
    argv[#argv + 1] = opts.text
    self.ops[#self.ops + 1] = { kind = "text", argv = argv }
    local measured_w = opts.measure_w or w
    local dirty_x = x
    if opts.align == "center" then
        dirty_x = x + math.floor((w - measured_w) / 2)
    end
    self:add_dirty(dirty_x, y, measured_w, line_h)
end

function Display:image(path, x, y, w, h)
    local argv = {
        self.fbink, "-q", "-b",
        "-g", string.format("file=%s,x=%d,y=%d,w=%d,h=%d", path, 0, 0, w or 0, h or 0),
        "-X", tostring(math.floor(x or 0)),
        "-Y", tostring(math.floor(y or 0)),
    }
    self.ops[#self.ops + 1] = { kind = "argv", argv = argv }
    self:add_dirty(x, y, w or 64, h or 64)
end

local function merge_rects(rects, gap)
    if #rects == 0 then return {} end
    table.sort(rects, function(a, b)
        if a.y == b.y then return a.x < b.x end
        return a.y < b.y
    end)
    local out = {}
    for _, r in ipairs(rects) do
        local merged = false
        for _, m in ipairs(out) do
            if r.y <= m.y + m.h + gap and r.y + r.h + gap >= m.y then
                local x1 = math.min(m.x, r.x)
                local y1 = math.min(m.y, r.y)
                local x2 = math.max(m.x + m.w, r.x + r.w)
                local y2 = math.max(m.y + m.h, r.y + r.h)
                m.x, m.y, m.w, m.h = x1, y1, x2 - x1, y2 - y1
                merged = true
                break
            end
        end
        if not merged then
            out[#out + 1] = { x = r.x, y = r.y, w = r.w, h = r.h }
        end
    end
    return out
end

function Display:union(rects)
    local x1, y1, x2, y2 = self.width, self.height, 0, 0
    for _, r in ipairs(rects) do
        x1 = math.min(x1, r.x)
        y1 = math.min(y1, r.y)
        x2 = math.max(x2, r.x + r.w)
        y2 = math.max(y2, r.y + r.h)
    end
    return { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
end

function Display:flush(opts)
    opts = opts or {}
    if #self.ops == 0 and #self.dirty == 0 then return true end
    for _, op in ipairs(self.ops) do
        local ok = true
        if op.kind == "fill" then
            local r = op.rect
            local argv = {
                self.fbink, "-q", "-b",
                string.format("--cls=top=%d,left=%d,width=%d,height=%d", r.y, r.x, r.w, r.h),
                "-B", color_name(op.color),
            }
            local code, out = self.runner:run(argv, "fill")
            ok = code == 0
            if not ok and self.log then self.log:error("fbink fill failed: " .. tostring(out)) end
        elseif op.kind == "text" or op.kind == "argv" then
            local code, out = self.runner:run(op.argv, "draw")
            ok = code == 0
            if not ok and self.log then self.log:error("fbink draw failed: " .. tostring(out)) end
        end
        if not ok then
            self.available = false
            return false
        end
    end
    local regions = merge_rects(self.dirty, 24)
    if #regions == 0 then return true end
    if #regions > 5 then
        regions = { self:union(regions) }
    end
    self.partial_count = self.partial_count + 1
    local force_full = opts.full == true
        or (self.full_refresh_every > 0 and self.partial_count % self.full_refresh_every == 0)
    if force_full then
        local argv = { self.fbink, "-q", "-w", "-s", "-W", "GC16" }
        if opts.flash then argv[#argv + 1] = "-f" end
        local code, out = self.runner:run(argv, "full refresh")
        if code ~= 0 then
            self.available = false
            if self.log then self.log:error("fbink full refresh failed: " .. tostring(out)) end
            return false
        end
    else
        for _, r in ipairs(regions) do
            local argv = {
                self.fbink, "-q", "-w",
                string.format("--refresh=top=%d,left=%d,width=%d,height=%d", r.y, r.x, r.w, r.h),
                "-W", opts.waveform or "GC16",
            }
            local code, out = self.runner:run(argv, "region refresh")
            if code ~= 0 then
                self.available = false
                if self.log then self.log:error("fbink refresh failed: " .. tostring(out)) end
                return false
            end
        end
    end
    self.dirty = {}
    self.ops = {}
    return true
end

function Display:clear()
    self.runner:run({ self.fbink, "-q", "-k", "-B", "WHITE" }, "clear")
end

return Display
