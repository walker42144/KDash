-- 事件与触控命中区域。坐标均为屏幕像素。
local Events = {}
Events.__index = Events

function Events.new()
    return setmetatable({ queue = {}, hits = {} }, Events)
end

function Events:push(ev)
    self.queue[#self.queue + 1] = ev
end

function Events:poll()
    local q = self.queue
    self.queue = {}
    return q
end

function Events:clear_hits()
    self.hits = {}
end

function Events:remove_module_hits(module_id)
    local kept = {}
    for _, h in ipairs(self.hits) do
        if h.module_id ~= module_id then kept[#kept + 1] = h end
    end
    self.hits = kept
end

-- rect = { x=, y=, w=, h=, action=, payload=, label= }
function Events:add_hit(rect)
    self.hits[#self.hits + 1] = rect
end

function Events:hit_test(x, y)
    -- 后添加的区域优先（弹窗覆盖在页面上）
    for i = #self.hits, 1, -1 do
        local r = self.hits[i]
        if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
            return r
        end
    end
    return nil
end

function Events:route_tap(ev)
    local hit = self:hit_test(ev.x, ev.y)
    if hit then
        ev.hit = hit
        ev.action = hit.action
        ev.payload = hit.payload
        return hit
    end
    return nil
end

return Events
