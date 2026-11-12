-- 电源策略：只控制防休眠属性，不修改系统级休眠/前光配置。
local Power = {}
Power.__index = Power

function Power.new(opts)
    local self = setmetatable({}, Power)
    self.runner = opts.runner
    self.log = opts.log
    self.applied = nil
    return self
end

function Power:read_hold()
    local code, out = self.runner:run({ "lipc-get-prop", "-i", "com.lab126.powerd", "preventScreenSaver" })
    if code ~= 0 then return nil end
    return tonumber((out or ""):match("%-?%d+"))
end

function Power:set_hold(on)
    local value = on and "1" or "0"
    local code, out = self.runner:run({ "lipc-set-prop", "com.lab126.powerd", "preventScreenSaver", value })
    if code ~= 0 then
        if self.log then self.log:warn("failed to set preventScreenSaver: " .. tostring(out)) end
        return false
    end
    self.applied = on
    return true
end

-- policy: "always" | "plugged" | "never"
function Power:want_hold(policy, charging)
    if policy == "always" then return true end
    if policy == "never" then return false end
    if policy == "battery" then return not charging end
    return charging == true
end

function Power:apply(policy, charging)
    local want = self:want_hold(policy, charging)
    if self.applied == want then return want end
    self:set_hold(want)
    return want
end

function Power:release()
    if self.applied then
        self:set_hold(false)
        self.applied = nil
    end
end

return Power
