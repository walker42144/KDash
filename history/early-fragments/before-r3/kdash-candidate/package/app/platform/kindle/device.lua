-- Kindle 设备状态读取：所有路径均做存在性探测，找不到时降级为“未知”。
local util = require("core.util")

local Device = {}
Device.__index = Device

local function read_trim(path)
    local data = util.read_file(path)
    if not data then return nil end
    return util.trim(data)
end

local function first_line(path)
    local data = util.read_file(path)
    if not data then return nil end
    return util.trim((data:gsub("\n.*$", "")))
end

function Device.new(opts)
    local self = setmetatable({}, Device)
    self.storage = opts.storage
    self.runner = opts.runner
    self.log = opts.log
    self.cache = nil
    self.cache_at = 0
    self.cache_ttl = 20
    return self
end

function Device:_battery_from_power_supply()
    local base = "/sys/class/power_supply"
    local entries = self.storage:list_dir(base)
    local candidates = {}
    for _, name in ipairs(entries) do
        local cap = read_trim(base .. "/" .. name .. "/capacity")
        if cap and tonumber(cap) then
            candidates[#candidates + 1] = { name = name, capacity = tonumber(cap) }
        end
    end
    if #candidates == 0 then return nil end
    table.sort(candidates, function(a, b)
        local function score(n)
            if n:find("battery") or n:find("bat") then return 1 end
            return 2
        end
        return score(a.name) < score(b.name)
    end)
    local chosen = candidates[1]
    local dir = base .. "/" .. chosen.name
    local status = read_trim(dir .. "/status")
    local charging = read_trim(dir .. "/charging")
    local online = read_trim(dir .. "/online")
    local is_charging = false
    if charging == "1" then is_charging = true end
    if online == "1" then is_charging = true end
    if status and (status:lower():find("charging") or status:lower():find("full")) then
        is_charging = true
    end
    return {
        level = chosen.capacity,
        charging = is_charging,
        status = status or (is_charging and "Charging" or "Discharging"),
        source = "sysfs:" .. chosen.name,
    }
end

function Device:_battery_from_lipc()
    local code, out = self.runner:run({ "lipc-get-prop", "-i", "com.lab126.powerd", "battLevel" })
    if code ~= 0 then return nil end
    local n = tonumber(util.trim(out))
    if not n then return nil end
    local ccode, cout = self.runner:run({ "lipc-get-prop", "-i", "com.lab126.powerd", "isCharging" })
    local charging = false
    if ccode == 0 then
        local v = util.trim(cout):lower()
        charging = (v == "1" or v == "true" or v == "yes")
    end
    return { level = n, charging = charging, status = charging and "Charging" or "Discharging", source = "lipc" }
end

function Device:battery()
    local b = self:_battery_from_power_supply()
    if not b then b = self:_battery_from_lipc() end
    if b then
        b.level = util.clamp(b.level, 0, 100)
    end
    return b
end

function Device:wifi()
    local iface = nil
    for _, name in ipairs({ "wlan0", "eth0" }) do
        if util.path_exists("/sys/class/net/" .. name) then iface = name; break end
    end
    if not iface then
        return { connected = false, iface = nil, label = "NO WIFI" }
    end
    local state = read_trim("/sys/class/net/" .. iface .. "/operstate") or "unknown"
    local route = util.read_file("/proc/net/route")
    local has_route = false
    if route then
        for line in route:gmatch("[^\n]+") do
            if line:find("^" .. iface) then has_route = true; break end
        end
    end
    local connected = (state == "up") and has_route
    return {
        connected = connected,
        iface = iface,
        state = state,
        label = connected and "WIFI" or (state == "up" and "WIFI NO ROUTE" or "WIFI OFF"),
    }
end

function Device:firmware()
    return first_line("/etc/prettyversion.txt")
        or first_line("/etc/version.txt")
        or "unknown"
end

function Device:uptime()
    local data = read_trim("/proc/uptime")
    if not data then return nil end
    local sec = tonumber(data:match("^([%d%.]+)"))
    return sec
end

function Device:storage()
    local code, out = self.runner:run_shell("df -k /mnt/us 2>/dev/null | tail -n 1")
    if code ~= 0 or not out or out == "" then return nil end
    local total, used, avail = out:match("^(%d+)%s+(%d+)%s+(%d+)")
    if not total then return nil end
    return {
        total_kb = tonumber(total),
        used_kb = tonumber(used),
        free_kb = tonumber(avail),
    }
end

function Device:frontlight()
    local code, out = self.runner:run({ "lipc-get-prop", "-i", "com.lab126.powerd", "flIntensity" })
    if code ~= 0 then return nil end
    return tonumber(util.trim(out))
end

function Device:info(now)
    if self.cache and (now or os.time()) - self.cache_at < self.cache_ttl then
        return self.cache
    end
    local info = {
        battery = self:battery() or { level = nil, charging = false, status = "unknown" },
        wifi = self:wifi(),
        firmware = self:firmware(),
        uptime = self:uptime(),
        storage = self:storage(),
        frontlight = self:frontlight(),
        model = first_line("/proc/device-tree/model") or "Kindle",
        timestamp = now or os.time(),
    }
    self.cache = info
    self.cache_at = now or os.time()
    return info
end

return Device
