return function(T)
    local Weather = require("services.api.weather")

    local payload = [[
{
  "current": {
    "temperature_2m": 18.4,
    "apparent_temperature": 17.2,
    "relative_humidity_2m": 55,
    "weather_code": 2
  },
  "daily": {
    "time": ["2026-11-11", "2026-11-12", "2026-11-13"],
    "weather_code": [2, 0, 61],
    "temperature_2m_max": [21.2, 20.4, 17.1],
    "temperature_2m_min": [13.1, 11.2, 10.3],
    "precipitation_probability_max": [20, 5, 80]
  }
}
]]

    T.test("weather parses current and daily", function()
        local view = Weather.parse(payload, { city = "北京", language = "zh" }, 1000)
        T.truthy(view)
        T.eq(view.temp, 18)
        T.eq(view.feels, 17)
        T.eq(view.desc, "多云")
        T.eq(view.icon, "partly")
        T.eq(view.high, 21)
        T.eq(view.low, 13)
        T.eq(view.rain, 20)
        T.eq(#view.days, 3)
        T.eq(view.days[1].high, 21)
        T.eq(view.days[3].desc, "小雨")
    end)

    T.test("weather builds Open-Meteo URL", function()
        local url = Weather.build_url({
            latitude = 39.9042, longitude = 116.4074,
            timezone = "Asia/Shanghai", forecast_days = 3,
        })
        T.truthy(url:find("api.open-meteo.com", 1, true))
        T.truthy(url:find("latitude=39.9042", 1, true))
        T.truthy(url:find("Asia%2FShanghai", 1, true))
        T.truthy(url:find("forecast_days=3", 1, true))
    end)

    T.test("weather rejects malformed payload", function()
        local view, err = Weather.parse("{}", {}, 0)
        T.falsy(view)
        T.truthy(err)
    end)
end
