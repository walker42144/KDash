return function(T)
    local json = require("core.json")

    T.test("json roundtrip", function()
        local value = {
            name = "KDash",
            enabled = true,
            count = 42,
            ratio = 1.5,
            list = { 1, 2, 3 },
            nested = { a = "中文", b = false },
        }
        local encoded = json.encode(value)
        local decoded = json.decode(encoded)
        T.eq(decoded.name, "KDash")
        T.eq(decoded.enabled, true)
        T.eq(decoded.count, 42)
        T.near(decoded.ratio, 1.5)
        T.eq(#decoded.list, 3)
        T.eq(decoded.nested.a, "中文")
        T.eq(decoded.nested.b, false)
    end)

    T.test("json unicode escapes and surrogate", function()
        local v = json.decode('{"s":"\\u4f60\\u597d","e":"\\ud83d\\ude00"}')
        T.eq(v.s, "你好")
        T.eq(v.e, "😀")
    end)

    T.test("json null and empty containers", function()
        local v = json.decode('{"a":null,"b":[],"c":{}}')
        T.eq(v.a, json.null)
        T.eq(type(v.b), "table")
        T.eq(#v.b, 0)
        T.eq(type(v.c), "table")
        T.eq(json.encode(v.a), "null")
        T.eq(json.encode(json.array({})), "[]")
        T.eq(json.encode(json.object({})), "{}")
    end)

    T.test("json rejects malformed input", function()
        T.falsy(pcall(json.decode, '{"a":1'))
        T.falsy(pcall(json.decode, '{"a":}'))
        T.falsy(pcall(json.decode, 'nope'))
        T.falsy(pcall(json.decode, '{"a":1} trailing'))
    end)

    T.test("json pretty and key order", function()
        local s = json.encode({ b = 2, a = 1 }, true)
        T.truthy(s:find('\n'))
        T.truthy(s:find('"a": 1'))
    end)
end
