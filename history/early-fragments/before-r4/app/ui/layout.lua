-- 配置驱动的网格布局：行权重、最小高度、双列、页边距。
local util = require("core.util")

local Layout = {}
Layout.__index = Layout

function Layout.new(opts)
    local self = setmetatable({}, Layout)
    self.theme = opts.theme
    self.registry = opts.registry
    return self
end

function Layout:manifest_for(id)
    local record = self.registry:get(id)
    return record and record.manifest or nil
end

-- 将页面内容区域切分为行；每行包含一个或两个模块。
function Layout:compute(page, content_rect)
    local rows = {}
    local spec = {}
    for _, row in ipairs(page.layout or {}) do
        local active = {}
        for _, id in ipairs(row.modules or {}) do
            if self.registry:is_enabled(id) then active[#active + 1] = id end
        end
        if #active > 0 then
            spec[#spec + 1] = { modules = active, weight = row.weight or 10 }
        end
    end
    local weights = 0
    for _, row in ipairs(spec) do
        weights = weights + (row.weight or 10)
    end
    if weights <= 0 then return rows end
    local available = content_rect.h
    local gap = self.theme.space.md
    local total_gap = gap * math.max(0, #spec - 1)
    local usable = available - total_gap
    if usable < 100 then usable = available end
    local y = content_rect.y
    local min_total = 0
    local mins = {}
    for i, row in ipairs(spec) do
        local min_h = 0
        for _, id in ipairs(row.modules) do
            local m = self:manifest_for(id)
            local lh = m and m.layout and m.layout.min_height or 80
            min_h = math.max(min_h, util.round(lh * (self.theme.scale or 1)))
        end
        mins[i] = min_h
        min_total = min_total + min_h
    end
    local height_scale = 1
    if min_total > usable and min_total > 0 then
        height_scale = usable / min_total
    end
    for i, row in ipairs(spec) do
        local h = math.floor(usable * ((row.weight or 10) / weights))
        if h < mins[i] then h = math.floor(mins[i] * height_scale) end
        h = math.max(24, h)
        local rect = { x = content_rect.x, y = y, w = content_rect.w, h = h }
        local cells = {}
        local mods = row.modules
        if #mods == 1 then
            cells[1] = { x = rect.x, y = rect.y, w = rect.w, h = rect.h }
        elseif #mods >= 2 then
            local col_gap = self.theme.space.lg
            local cw = math.floor((rect.w - col_gap) / 2)
            cells[1] = { x = rect.x, y = rect.y, w = cw, h = rect.h }
            cells[2] = { x = rect.x + cw + col_gap, y = rect.y, w = rect.w - cw - col_gap, h = rect.h }
        end
        rows[#rows + 1] = {
            rect = rect,
            cells = cells,
            modules = mods,
            first = (i == 1),
        }
        y = y + h + gap
    end
    return rows
end

return Layout
