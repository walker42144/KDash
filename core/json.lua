-- KDash JSON 编解码器（Lua 5.1 / LuaJIT 兼容）
-- 仅支持标准 JSON；空表默认编码为数组，需要空对象时使用 json.object()。
local json = {}

json.null = setmetatable({}, {
    __tostring = function() return "null" end,
})

local array_mt = { __json_array = true }
local object_mt = { __json_object = true }

function json.array(t)
    t = t or {}
    return setmetatable(t, array_mt)
end

function json.object(t)
    t = t or {}
    return setmetatable(t, object_mt)
end

local escapes = {
    ['"'] = '\\"',
    ['\\'] = '\\\\',
    ['\b'] = '\\b',
    ['\f'] = '\\f',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
}

local function encode_string(s)
    return '"' .. s:gsub('[%z\1-\31\\"]', function(c)
        local e = escapes[c]
        if e then return e end
        return string.format('\\u%04x', string.byte(c))
    end) .. '"'
end

local function is_array(t)
    if getmetatable(t) == object_mt then return false end
    if getmetatable(t) == array_mt then return true end
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" then return false end
        n = n + 1
    end
    -- 空表按数组处理；配置中的空对象请用 json.object()
    if n == 0 then return true end
    return n == #t
end

local function encode_value(v, out, depth, pretty)
    local tv = type(v)
    if v == json.null or v == nil then
        out[#out + 1] = "null"
    elseif tv == "boolean" then
        out[#out + 1] = v and "true" or "false"
    elseif tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            error("cannot encode non-finite number")
        end
        if v == math.floor(v) and math.abs(v) < 1e15 then
            out[#out + 1] = string.format("%d", v)
        else
            out[#out + 1] = string.format("%.14g", v)
        end
    elseif tv == "string" then
        out[#out + 1] = encode_string(v)
    elseif tv == "table" then
        local indent = pretty and string.rep("  ", depth + 1) or ""
        local newline = pretty and "\n" or ""
        local close_indent = pretty and string.rep("  ", depth) or ""
        if is_array(v) then
            if #v == 0 then
                out[#out + 1] = "[]"
                return
            end
            out[#out + 1] = "[" .. newline
            for i = 1, #v do
                if pretty then out[#out + 1] = indent end
                encode_value(v[i], out, depth + 1, pretty)
                if i < #v then out[#out + 1] = "," .. newline else out[#out + 1] = newline end
            end
            out[#out + 1] = close_indent .. "]"
        else
            local keys = {}
            for k in pairs(v) do
                if type(k) ~= "string" then
                    error("object keys must be strings")
                end
                keys[#keys + 1] = k
            end
            table.sort(keys)
            if #keys == 0 then
                out[#out + 1] = "{}"
                return
            end
            out[#out + 1] = "{" .. newline
            for i, k in ipairs(keys) do
                if pretty then out[#out + 1] = indent end
                out[#out + 1] = encode_string(k)
                out[#out + 1] = pretty and ": " or ":"
                encode_value(v[k], out, depth + 1, pretty)
                if i < #keys then out[#out + 1] = "," .. newline else out[#out + 1] = newline end
            end
            out[#out + 1] = close_indent .. "}"
        end
    else
        error("cannot encode type " .. tv)
    end
end

function json.encode(v, pretty)
    local out = {}
    encode_value(v, out, 0, pretty and true or false)
    return table.concat(out)
end

-- ===== 解码 =====

local function utf8_char(cp)
    if cp < 0x80 then
        return string.char(cp)
    elseif cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
    elseif cp < 0x10000 then
        return string.char(
            0xE0 + math.floor(cp / 0x1000),
            0x80 + math.floor(cp / 0x40) % 0x40,
            0x80 + cp % 0x40
        )
    elseif cp <= 0x10FFFF then
        return string.char(
            0xF0 + math.floor(cp / 0x40000),
            0x80 + math.floor(cp / 0x1000) % 0x40,
            0x80 + math.floor(cp / 0x40) % 0x40,
            0x80 + cp % 0x40
        )
    end
    error("invalid codepoint")
end

local function parse_string(s, pos)
    -- 跳过起始引号
    local buf = {}
    local i = pos + 1
    local len = #s
    while i <= len do
        local c = s:sub(i, i)
        if c == '"' then
            return table.concat(buf), i + 1
        elseif c == '\\' then
            local e = s:sub(i + 1, i + 1)
            if e == '"' or e == '\\' or e == '/' then
                buf[#buf + 1] = e
                i = i + 2
            elseif e == 'b' then
                buf[#buf + 1] = '\b'; i = i + 2
            elseif e == 'f' then
                buf[#buf + 1] = '\f'; i = i + 2
            elseif e == 'n' then
                buf[#buf + 1] = '\n'; i = i + 2
            elseif e == 'r' then
                buf[#buf + 1] = '\r'; i = i + 2
            elseif e == 't' then
                buf[#buf + 1] = '\t'; i = i + 2
            elseif e == 'u' then
                local hex = s:sub(i + 2, i + 5)
                if not hex:match("^%x%x%x%x$") then error("invalid unicode escape") end
                local cp = tonumber(hex, 16)
                i = i + 6
                if cp >= 0xD800 and cp <= 0xDBFF then
                    local hex2 = s:sub(i + 2, i + 5)
                    if s:sub(i, i + 1) ~= "\\u" or not hex2:match("^%x%x%x%x$") then
                        error("invalid surrogate pair")
                    end
                    local low = tonumber(hex2, 16)
                    if low < 0xDC00 or low > 0xDFFF then error("invalid surrogate pair") end
                    cp = 0x10000 + (cp - 0xD800) * 0x400 + (low - 0xDC00)
                    i = i + 6
                end
                buf[#buf + 1] = utf8_char(cp)
            else
                error("invalid escape \\" .. e)
            end
        elseif c:byte() < 0x20 then
            error("control character in string")
        else
            buf[#buf + 1] = c
            i = i + 1
        end
    end
    error("unterminated string")
end

local function skip_ws(s, i)
    while true do
        local c = s:sub(i, i)
        if c == ' ' or c == '\t' or c == '\r' or c == '\n' then
            i = i + 1
        else
            return i
        end
    end
end

local parse_value

local function parse_array(s, i, depth)
    local arr = json.array({})
    i = skip_ws(s, i + 1)
    if s:sub(i, i) == ']' then return arr, i + 1 end
    while true do
        local v
        v, i = parse_value(s, i, depth+1)
        arr[#arr + 1] = v
        i = skip_ws(s, i)
        local c = s:sub(i, i)
        if c == ',' then
            i = skip_ws(s, i + 1)
        elseif c == ']' then
            return arr, i + 1
        else
            error("expected ',' or ']' at " .. i)
        end
    end
end

local function parse_object(s, i, depth)
    local obj = json.object({})
    i = skip_ws(s, i + 1)
    if s:sub(i, i) == '}' then return obj, i + 1 end
    while true do
        if s:sub(i, i) ~= '"' then error("expected object key at " .. i) end
        local key
        key, i = parse_string(s, i)
        i = skip_ws(s, i)
        if s:sub(i, i) ~= ':' then error("expected ':' at " .. i) end
        i = skip_ws(s, i + 1)
        local v
        v, i = parse_value(s, i, depth+1)
        obj[key] = v
        i = skip_ws(s, i)
        local c = s:sub(i, i)
        if c == ',' then
            i = skip_ws(s, i + 1)
        elseif c == '}' then
            return obj, i + 1
        else
            error("expected ',' or '}' at " .. i)
        end
    end
end

parse_value = function(s, i, depth)
    depth=depth or 0
    if depth>64 then error("JSON nesting exceeds 64 levels") end
    i = skip_ws(s, i)
    local c = s:sub(i, i)
    if c == '{' then
        return parse_object(s, i, depth)
    elseif c == '[' then
        return parse_array(s, i, depth)
    elseif c == '"' then
        return parse_string(s, i)
    elseif c == 't' then
        if s:sub(i, i + 3) == "true" then return true, i + 4 end
        error("invalid token at " .. i)
    elseif c == 'f' then
        if s:sub(i, i + 4) == "false" then return false, i + 5 end
        error("invalid token at " .. i)
    elseif c == 'n' then
        if s:sub(i, i + 3) == "null" then return json.null, i + 4 end
        error("invalid token at " .. i)
    elseif c == '-' or c:match("%d") then
        local start = i
        if c == '-' then i = i + 1 end
        if not s:sub(i, i):match("%d") then error("invalid number at " .. start) end
        while s:sub(i, i):match("%d") do i = i + 1 end
        if s:sub(i, i) == '.' then
            i = i + 1
            if not s:sub(i, i):match("%d") then error("invalid number at " .. start) end
            while s:sub(i, i):match("%d") do i = i + 1 end
        end
        local e = s:sub(i, i)
        if e == 'e' or e == 'E' then
            i = i + 1
            local sign = s:sub(i, i)
            if sign == '+' or sign == '-' then i = i + 1 end
            if not s:sub(i, i):match("%d") then error("invalid exponent at " .. start) end
            while s:sub(i, i):match("%d") do i = i + 1 end
        end
        local num = tonumber(s:sub(start, i - 1))
        if num == nil then error("invalid number at " .. start) end
        return num, i
    else
        error("unexpected character at " .. i)
    end
end

function json.decode(s)
    if type(s) ~= "string" then error("json.decode expects string") end
    local value, i = parse_value(s, 1)
    i = skip_ws(s, i)
    if i <= #s then error("trailing data at " .. i) end
    return value
end

return json
