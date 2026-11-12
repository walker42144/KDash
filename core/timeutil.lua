-- 时间工具：不使用系统本地时区做核心计算，统一用 UTC + 固定偏移。
local timeutil = {}

local floor = math.floor

function timeutil.days_from_civil(y, m, d)
    y = y - (m <= 2 and 1 or 0)
    local era = floor(y / 400)
    local yoe = y - era * 400
    local doy = floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
    local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

function timeutil.civil_from_days(z)
    z = z + 719468
    local era = floor(z / 146097)
    local doe = z - era * 146097
    local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
    local mp = floor((5 * doy + 2) / 153)
    local d = doy - floor((153 * mp + 2) / 5) + 1
    local m = mp + (mp < 10 and 3 or -9)
    return y + (m <= 2 and 1 or 0), m, d
end

function timeutil.parse_date(s)
    if type(s) ~= "string" then return nil end
    local y, m, d = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not y then return nil end
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if m < 1 or m > 12 or d < 1 or d > 31 then return nil end
    local yy, mm, dd = timeutil.civil_from_days(timeutil.days_from_civil(y,m,d))
    if yy ~= y or mm ~= m or dd ~= d then return nil end
    return y, m, d
end

function timeutil.parse_hhmm(s)
    if type(s) ~= "string" or s == "" then return nil end
    local h, m = s:match("^(%d%d?):(%d%d)$")
    if not h then return nil end
    h, m = tonumber(h), tonumber(m)
    if h < 0 or h > 23 or m < 0 or m > 59 then return nil end
    return h, m
end

-- 支持 2024-01-02T03:04:05+0000 / Z / 无秒 / 纯日期
function timeutil.parse_iso8601(s)
    if type(s) ~= "string" then return nil end
    local y, mo, d, rest = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)[T ]?(.*)$")
    if not y then
        y, mo, d = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
        rest = ""
    end
    if not y then return nil end
    y, mo, d = tonumber(y), tonumber(mo), tonumber(d)
    local hh, mm, ss, offset = 0, 0, 0, 0
    if rest and rest ~= "" then
        local tz = rest:match("([Zz])$")
        if not tz then
            local tail6 = rest:sub(-6)
            local tail5 = rest:sub(-5)
            if tail6:match("^[%+%-]%d%d:%d%d$") then
                tz = tail6
            elseif tail5:match("^[%+%-]%d%d%d%d$") then
                tz = tail5
            end
        end
        local time_part = rest
        if tz then time_part = rest:sub(1, #rest - #tz) end
        time_part = time_part:gsub("%.%d+$", "")
        local a, b, c = time_part:match("^(%d%d):(%d%d):(%d%d)$")
        if not a then a, b = time_part:match("^(%d%d):(%d%d)$") end
        if not a then return nil end
        hh, mm = tonumber(a), tonumber(b)
        ss = tonumber(c or 0)
        if tz and tz ~= "Z" and tz ~= "z" then
            local sign, oh, om
            sign, oh, om = tz:match("^([%+%-])(%d%d):(%d%d)$")
            if not sign then sign, oh, om = tz:match("^([%+%-])(%d%d)(%d%d)$") end
            if sign then
                offset = tonumber(oh) * 3600 + tonumber(om) * 60
                if sign == "-" then offset = -offset end
            end
        end
    end
    local days = timeutil.days_from_civil(y, mo, d)
    return days * 86400 + hh * 3600 + mm * 60 + ss - offset
end

function timeutil.date_key(ts, offset_min)
    local t = os.date("!*t", ts + (offset_min or 0) * 60)
    return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
end

function timeutil.date_key_from_civil(y, m, d)
    return string.format("%04d-%02d-%02d", y, m, d)
end

function timeutil.local_parts(ts, offset_min)
    return os.date("!*t", ts + (offset_min or 0) * 60)
end

function timeutil.start_of_local_day(ts, offset_min)
    local t = timeutil.local_parts(ts, offset_min)
    local days = timeutil.days_from_civil(t.year, t.month, t.day)
    return days * 86400 - (offset_min or 0) * 60
end

function timeutil.format_time(ts, offset_min, use_24h)
    local t = timeutil.local_parts(ts, offset_min)
    if use_24h == false then
        local h = t.hour % 12
        if h == 0 then h = 12 end
        local ampm = t.hour < 12 and "AM" or "PM"
        return string.format("%d:%02d %s", h, t.min, ampm)
    end
    return string.format("%02d:%02d", t.hour, t.min)
end

local WEEK_EN = { "SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY" }
local WEEK_EN_SHORT = { "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" }
local WEEK_CN = { "星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六" }
local MONTH_EN = { "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" }

function timeutil.weekday(ts, offset_min, lang, short)
    local t = timeutil.local_parts(ts, offset_min)
    local idx = tonumber(os.date("!%w", ts + (offset_min or 0) * 60)) + 1
    if lang == "zh" then return WEEK_CN[idx] end
    return short and WEEK_EN_SHORT[idx] or WEEK_EN[idx]
end

function timeutil.date_label(ts, offset_min, lang)
    local t = timeutil.local_parts(ts, offset_min)
    if lang == "zh" then
        return string.format("%d月%d日", t.month, t.day)
    end
    return string.format("%s %02d", MONTH_EN[t.month], t.day)
end

function timeutil.date_label_full(ts, offset_min, lang)
    local t = timeutil.local_parts(ts, offset_min)
    if lang == "zh" then
        return string.format("%04d年%d月%d日", t.year, t.month, t.day)
    end
    return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
end

-- 纯日期倒计时：目标日期 - 今天日期，按日历天计算，不受时区/时刻影响。
function timeutil.days_until_date(target_date, today_key)
    local ty, tm, td = timeutil.parse_date(target_date)
    local cy, cm, cd = timeutil.parse_date(today_key)
    if not ty or not cy then return nil end
    return timeutil.days_from_civil(ty, tm, td) - timeutil.days_from_civil(cy, cm, cd)
end

-- 事件倒计时。date 必填，time 可选。
-- 返回：days, hours, minutes, expired, target_ts
function timeutil.countdown(event, now, offset_min)
    local y, m, d = timeutil.parse_date(event.date)
    if not y then return nil end
    local hh, mm = 0, 0
    if event.time and event.time ~= "" then
        hh, mm = timeutil.parse_hhmm(event.time)
        if not hh then hh, mm = 0, 0 end
    end
    local event_offset = event.timezone_offset or offset_min or 0
    local target_ts = timeutil.days_from_civil(y, m, d) * 86400 + hh * 3600 + mm * 60 - event_offset * 60
    local diff = target_ts - now
    local expired = diff < 0
    local absdiff = math.abs(diff)
    local days = floor(absdiff / 86400)
    local hours = floor((absdiff % 86400) / 3600)
    local minutes = floor((absdiff % 3600) / 60)
    if not event.time or event.time == "" then
        -- 日期型事件按日历天差，避免“今晚 23:59 显示 0 天”这类误差
        local today_key = timeutil.date_key(now, offset_min)
        local dd = timeutil.days_until_date(event.date, today_key) or 0
        expired = dd < 0
        days = math.abs(dd)
        hours, minutes = 0, 0
    end
    return days, hours, minutes, expired, target_ts
end

function timeutil.relative_day_label(days, expired)
    if expired then
        if days == 0 then return "TODAY" end
        return string.format("%d DAYS AGO", days)
    end
    if days == 0 then return "TODAY" end
    if days == 1 then return "TOMORROW" end
    return string.format("%d DAYS", days)
end

function timeutil.uptime_string(seconds)
    seconds = math.floor(seconds or 0)
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    if days > 0 then return string.format("%dd %dh", days, hours) end
    if hours > 0 then return string.format("%dh %dm", hours, mins) end
    return string.format("%dm", mins)
end

return timeutil
