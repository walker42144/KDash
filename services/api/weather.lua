-- Open-Meteo 天气适配器。无需 API Key，默认使用固定经纬度。
local json = require("core.json")
local timeutil = require("core.timeutil")

local Weather = {}
Weather.__index = Weather

Weather.BASE = "https://api.open-meteo.com/v1/forecast"

local WMO = {
    [0] = { en = "CLEAR", zh = "晴" },
    [1] = { en = "MOSTLY CLEAR", zh = "晴间多云" },
    [2] = { en = "PARTLY CLOUDY", zh = "多云" },
    [3] = { en = "OVERCAST", zh = "阴" },
    [45] = { en = "FOG", zh = "雾" },
    [48] = { en = "RIME FOG", zh = "雾凇" },
    [51] = { en = "LIGHT DRIZZLE", zh = "小毛毛雨" },
    [53] = { en = "DRIZZLE", zh = "毛毛雨" },
    [55] = { en = "HEAVY DRIZZLE", zh = "强毛毛雨" },
    [56] = { en = "FREEZING DRIZZLE", zh = "冻毛毛雨" },
    [57] = { en = "FREEZING DRIZZLE", zh = "强冻毛毛雨" },
    [61] = { en = "LIGHT RAIN", zh = "小雨" },
    [63] = { en = "RAIN", zh = "中雨" },
    [65] = { en = "HEAVY RAIN", zh = "大雨" },
    [66] = { en = "FREEZING RAIN", zh = "冻雨" },
    [67] = { en = "FREEZING RAIN", zh = "强冻雨" },
    [71] = { en = "LIGHT SNOW", zh = "小雪" },
    [73] = { en = "SNOW", zh = "中雪" },
    [75] = { en = "HEAVY SNOW", zh = "大雪" },
    [77] = { en = "SNOW GRAINS", zh = "雪粒" },
    [80] = { en = "LIGHT SHOWERS", zh = "小阵雨" },
    [81] = { en = "SHOWERS", zh = "阵雨" },
    [82] = { en = "HEAVY SHOWERS", zh = "强阵雨" },
    [85] = { en = "SNOW SHOWERS", zh = "阵雪" },
    [86] = { en = "HEAVY SNOW SHOWERS", zh = "强阵雪" },
    [95] = { en = "THUNDERSTORM", zh = "雷阵雨" },
    [96] = { en = "THUNDERSTORM HAIL", zh = "雷阵雨伴冰雹" },
    [99] = { en = "THUNDERSTORM HAIL", zh = "强雷阵雨伴冰雹" },
}

function Weather.describe(code, lang)
    local d = WMO[tonumber(code) or -1]
    if not d then return lang == "zh" and "未知" or "UNKNOWN" end
    return lang == "zh" and d.zh or d.en
end

function Weather.icon(code)
    code = tonumber(code) or 0
    if code == 0 or code == 1 then return "sun" end
    if code == 2 then return "partly" end
    if code == 3 then return "cloud" end
    if code == 45 or code == 48 then return "fog" end
    if code >= 51 and code <= 67 then return "rain" end
    if code >= 71 and code <= 77 then return "snow" end
    if code >= 80 and code <= 82 then return "rain" end
    if code >= 85 and code <= 86 then return "snow" end
    if code >= 95 then return "storm" end
    return "cloud"
end

function Weather.build_url(cfg)
    local lat = cfg.latitude or 39.9042
    local lon = cfg.longitude or 116.4074
    local tz = cfg.timezone or "Asia/Shanghai"
    local days = math.max(1, math.min(7, tonumber(cfg.forecast_days) or 3))
    return string.format(
        "%s?latitude=%.4f&longitude=%.4f&current=temperature_2m,weather_code,relative_humidity_2m,apparent_temperature"
        .. "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
        .. "&timezone=%s&forecast_days=%d",
        Weather.BASE, lat, lon, (tz:gsub("[^%w%-%._~]",function(c) return string.format("%%%02X",c:byte()) end)), days
    )
end

function Weather.parse(payload, cfg, now)
    local ok, data = pcall(json.decode, payload or "")
    if not ok then return nil, "invalid json" end
    if type(data) ~= "table" or type(data.current) ~= "table" then
        return nil, "unexpected weather payload"
    end
    local lang = (cfg and cfg.language) or "en"
    local cur = data.current
    local daily = data.daily or {}
    local view = {
        provider = "open-meteo",
        city = (cfg and cfg.city) or "BEIJING",
        temp = cur.temperature_2m and math.floor(cur.temperature_2m + 0.5) or nil,
        feels = cur.apparent_temperature and math.floor(cur.apparent_temperature + 0.5) or nil,
        humidity = cur.relative_humidity_2m,
        code = cur.weather_code,
        desc = Weather.describe(cur.weather_code, lang),
        icon = Weather.icon(cur.weather_code),
        high = daily.temperature_2m_max and daily.temperature_2m_max[1],
        low = daily.temperature_2m_min and daily.temperature_2m_min[1],
        rain = daily.precipitation_probability_max and daily.precipitation_probability_max[1],
        days = {},
        fetched_at = now or os.time(),
    }
    if view.high then view.high = math.floor(view.high + 0.5) end
    if view.low then view.low = math.floor(view.low + 0.5) end
    for i = 1, math.min(#(daily.time or {}), 3) do
        local date = daily.time[i]
        local y, m, d = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
        local label = date
        if y then
            label = timeutil.date_label(timeutil.days_from_civil(tonumber(y), tonumber(m), tonumber(d)) * 86400, 0,
                lang == "zh" and "zh" or "en")
        end
        view.days[#view.days + 1] = {
            date = date,
            label = label,
            code = daily.weather_code[i],
            desc = Weather.describe(daily.weather_code[i], lang),
            high = daily.temperature_2m_max[i] and math.floor(daily.temperature_2m_max[i] + 0.5),
            low = daily.temperature_2m_min[i] and math.floor(daily.temperature_2m_min[i] + 0.5),
            rain = daily.precipitation_probability_max[i],
        }
    end
    return view
end

function Weather.new(opts)
    local self = setmetatable({}, Weather)
    self.http = opts.http
    self.config = opts.config
    self.cache = opts.cache
    self.secrets = opts.secrets
    self.log = opts.log
    self.now = opts.now or os.time
    return self
end

function Weather:sync(cb)
    local cfg = {}
    for k,v in pairs(self.config:module("weather")) do cfg[k]=v end
    cfg.language = self.config.data.language or "zh"
    if cfg.provider == "amap" then return require("services.api.amap").sync(self,cfg,cb) end
    local url = Weather.build_url(cfg)
    self.http:request({
        url = url,
        method = "GET",
        headers = { ["Accept"] = "application/json" },
        timeout = 25,
        label = "weather " .. tostring(cfg.city or ""),
    }, function(res)
        if not res.ok then
            cb(false, res.error)
            return
        end
        local view, err = Weather.parse(res.body, cfg, self.now())
        if not view then
            cb(false, err)
            return
        end
        self.cache:write("weather", { data = view, fetched_at = self.now() })
        cb(true, nil, view)
    end)
end

return Weather
