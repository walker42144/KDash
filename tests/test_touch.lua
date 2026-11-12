return function(T)
    local Touch = require("platform.kindle.touch")

    local function u16(n)
        if n < 0 then n = n + 65536 end
        return string.char(n % 256, math.floor(n / 256) % 256)
    end

    local function i32(n)
        if n < 0 then n = n + 4294967296 end
        return string.char(n % 256, math.floor(n / 256) % 256,
            math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
    end

    local function ev(sec, usec, typ, code, value)
        return i32(sec) .. i32(usec) .. u16(typ) .. u16(code) .. i32(value)
    end

    T.test("evdev event decode", function()
        local e = Touch.decode_event(ev(10, 20, 3, 0x35, 321))
        T.eq(e.type, 3)
        T.eq(e.code, 0x35)
        T.eq(e.value, 321)
    end)

    T.test("single tap packet decodes to down/up points", function()
        local records = {
            Touch.decode_event(ev(0, 0, 3, 0x39, 0)),
            Touch.decode_event(ev(0, 0, 3, 0x35, 120)),
            Touch.decode_event(ev(0, 0, 3, 0x36, 340)),
            Touch.decode_event(ev(0, 0, 0, 0, 0)),
            Touch.decode_event(ev(0, 0, 3, 0x39, -1)),
            Touch.decode_event(ev(0, 0, 3, 0x35, 120)),
            Touch.decode_event(ev(0, 0, 3, 0x36, 340)),
            Touch.decode_event(ev(0, 0, 0, 0, 0)),
        }
        local points = Touch.decode_packet(records)
        T.eq(#points, 2)
        T.eq(points[1].x, 120)
        T.eq(points[1].y, 340)
        T.eq(points[1].down, true)
        T.eq(points[2].down, false)
    end)

    T.test("touch instance detects tap", function()
        local t = Touch.new({ clock_ms = function() return 0 end })
        t:inject({ x = 10, y = 10, down = true })
        local out = t:inject({ x = 12, y = 12, down = false })
        T.eq(#out, 1)
        T.eq(out[1].type, "tap")
        T.eq(out[1].x, 10)
        T.eq(out[1].y, 10)
    end)

    T.test("touch instance detects swipe", function()
        local t = Touch.new({ clock_ms = function() return 0 end })
        t:inject({ x = 100, y = 100, down = true })
        t.state.x = 400
        local out = t:inject({ x = 400, y = 110, down = false })
        T.eq(#out, 1)
        T.eq(out[1].type, "swipe")
        T.eq(out[1].direction, "right")
    end)
end
