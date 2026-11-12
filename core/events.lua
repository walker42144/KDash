-- 事件与触控命中区域。坐标均为屏幕像素。
local Events = {}
Events.__index = Events

function Events.new(width,height)
    return setmetatable({ queue = {}, hits = {},width=width,height=height }, Events)
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
    if type(rect)~='table' then return false end
    local r={};for k,v in pairs(rect) do r[k]=v end
    for _,k in ipairs({'x','y','w','h'}) do if type(r[k])~='number' or r[k]~=r[k] or math.abs(r[k])==math.huge then return false end end
    if r.w<=0 or r.h<=0 then return false end
    if self.width and self.height then
        local x,y=math.max(0,r.x),math.max(0,r.y)
        r.w,r.h=math.min(self.width,r.x+r.w)-x,math.min(self.height,r.y+r.h)-y;r.x,r.y=x,y
        if r.w<=0 or r.h<=0 then return false end
    end
    if #self.hits>=512 then return false end
    self.hits[#self.hits + 1] = r
    return true
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
