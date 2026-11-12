-- 电源策略：只控制防休眠属性，不修改系统级休眠/前光配置。
local Power = {}
Power.__index = Power

function Power.new(opts)
    local self = setmetatable({}, Power)
    self.runner = opts.runner
    self.log = opts.log
    self.applied = nil
    self.events_path = opts.events_path
    self.event_offset = 0
    return self
end

-- The launcher owns the LIPC subscriber and its PID; Lua only consumes complete lines.
function Power:poll_events()
    if not self.events_path then return {} end
    local f=io.open(self.events_path,"rb")
    if not f then error("power event stream unavailable") end
    local size=f:seek("end")
    if size<self.event_offset then f:close();error("power event stream truncated") end
    f:seek("set",self.event_offset)
    local out={}
    for _=1,256 do
        local start=f:seek();local line=f:read("*l")
        if not line then break end
        local finish=f:seek()
        -- A newline may not have arrived yet. Re-read that record on the next poll.
        f:seek("set",finish-1);local last=f:read(1)
        if last~="\n" then f:seek("set",start);break end
        self.event_offset=finish
        if self.log then
            for _,name in ipairs({"readyToSuspend","wakeupFromSuspend"}) do
                if line:find(name,1,true) then self.log:info("power_event "..name) end
            end
        end
        if line:find("goingToScreenSaver",1,true) then out[#out+1]="sleep"
        elseif line:find("outOfScreenSaver",1,true) then out[#out+1]="wake" end
    end
    f:close();return out
end

-- Reset only the idle timer, leaving physical power-button suspend available.
-- Same powerd property used by the KOReader installed on this device.
function Power:keep_active()
    if self.applied~=false and not self:set_hold(false) then return false end
    local code=self.runner:run({"lipc-set-prop","-i","com.lab126.powerd","touchScreenSaverTimeout","1"})
    if code~=0 then return false end
    return true
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
