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

-- KPW3 evidence: max77696-onkey, /dev/input/event0, KEY_POWER=116.
-- Observe without EVIOCGRAB: powerd must still receive the physical button.
function Power:open_button()
    local f=io.open("/sys/class/input/event0/device/name","r")
    local name=f and f:read("*l");if f then f:close() end
    if name~="max77696-onkey" then return false,"unreviewed power button device" end
    local ffi=require("ffi")
    self.button_fd=ffi.C.open("/dev/input/event0",2048)
    if self.button_fd<0 then self.button_fd=nil;return false,"cannot read power button" end
    self.button_ffi=ffi
    if self.log then self.log:info("power source=evdev path=/dev/input/event0 KEY_POWER=116 (non-exclusive)") end
    return true
end
function Power:feed_button(records)
    local result={}
    for _,ev in ipairs(records) do
        if ev.type==0 and ev.code==3 then self.button_down=nil
        elseif ev.type==1 and ev.code==116 then
            if ev.value==1 then self.button_down=ev.sec+(ev.usec or 0)/1000000
            elseif ev.value==0 and self.button_down then
                local elapsed=ev.sec+(ev.usec or 0)/1000000-self.button_down
                self.button_down=nil
                if elapsed>=0 and elapsed<2 then result[#result+1]="button" end
            end
        end
    end
    return result
end
function Power:read_button()
    if not self.button_fd then return {} end
    local ffi=self.button_ffi;local b=ffi.new("unsigned char[16]");local records={}
    for _=1,64 do
        local got=tonumber(ffi.C.read(self.button_fd,b,16))
        if got<0 and ffi.errno()==11 then break end
        if got~=16 then error("power button disconnected or short read") end
        records[#records+1]=require("platform.kindle.touch").decode_event(ffi.string(b,16))
    end
    return self:feed_button(records)
end

-- The launcher owns the LIPC subscriber and its PID; Lua only consumes complete lines.
function Power:poll_events()
    if not self.events_path then return {} end
    local f=io.open(self.events_path,"rb")
    if not f then error("power event stream unavailable") end
    local size=f:seek("end")
    if size<self.event_offset then f:close();error("power event stream truncated") end
    f:seek("set",self.event_offset)
    local out=self:read_button()
    local physical=#out>0
    if physical then self.ignore_native_until=os.time()+3 end
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
        if not self.button_fd and os.time()>=(self.ignore_native_until or 0) then
            if line:find("goingToScreenSaver",1,true) then out[#out+1]="sleep"
            elseif line:find("outOfScreenSaver",1,true) then out[#out+1]="wake" end
        end
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

-- Reconcile once after a physical transition has settled; never blindly toggle twice.
function Power:reconcile(sleeping)
    local code,state=self.runner:run({"lipc-get-prop","-s","com.lab126.powerd","state"})
    if code~=0 then if self.log then self.log:warn("power state read failed") end;return end
    state=(state or ""):lower():gsub("%s+","")
    if self.log then self.log:info("power_state observed="..state:gsub("[^%w]",""):sub(1,40)) end
    local request=(sleeping and state=="active") or (not sleeping and state=="screensaver")
    if request then
        local result=self.runner:run({"lipc-set-prop","-i","com.lab126.powerd","powerButton","1"})
        if self.log then self.log:info("power_state request="..(sleeping and "sleep" or "wake").." result="..tostring(result)) end
    end
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
    if self.button_fd then self.button_ffi.C.close(self.button_fd);self.button_fd=nil end
    if self.applied then
        self:set_hold(false)
        self.applied = nil
    end
end

return Power
