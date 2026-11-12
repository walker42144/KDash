local util = {}

local unpack = table.unpack or unpack

function util.trim(s)
    if type(s) ~= "string" then return s end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function util.split(s, sep)
    local out = {}
    if s == nil or s == "" then return out end
    local from = 1
    while true do
        local a, b = s:find(sep, from, true)
        if not a then
            out[#out + 1] = s:sub(from)
            break
        end
        out[#out + 1] = s:sub(from, a - 1)
        from = b + 1
    end
    return out
end

function util.starts_with(s, prefix)
    return s:sub(1, #prefix) == prefix
end

function util.deep_copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, val in pairs(v) do
        out[k] = util.deep_copy(val)
    end
    return setmetatable(out, getmetatable(v))
end

-- 用户配置覆盖默认配置：对象递归合并，数组整体替换。
local function is_array_like(t)
    local mt = getmetatable(t)
    if mt and mt.__json_array then return true end
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" then return false end
        n = n + 1
    end
    return n > 0 and n == #t
end

function util.deep_merge(base, override)
    if type(base) ~= "table" or type(override) ~= "table" then
        return util.deep_copy(override)
    end
    if is_array_like(base) or is_array_like(override) then
        return util.deep_copy(override)
    end
    local out = util.deep_copy(base)
    for k, v in pairs(override) do
        if type(v) == "table" and type(out[k]) == "table" then
            out[k] = util.deep_merge(out[k], v)
        else
            out[k] = util.deep_copy(v)
        end
    end
    return out
end

function util.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function util.round(v)
    return math.floor(v + 0.5)
end

function util.shell_quote(s)
    if s == nil then return "''" end
    s = tostring(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

function util.join_path(a, b)
    if not a or a == "" then return b end
    if not b or b == "" then return a end
    return (a:gsub("/+$", "")) .. "/" .. (b:gsub("^/+", ""))
end

function util.read_file(path, max_bytes)
    local f = io.open(path, "rb")
    if not f then return nil, "cannot open " .. tostring(path) end
    local data = f:read(max_bytes and (max_bytes+1) or "*a")
    f:close()
    if max_bytes and data and #data>max_bytes then return nil,"file exceeds size limit" end
    return data
end

function util.write_file(path, data)
    local f, err = io.open(path, "wb")
    if not f then return false, err end
    local ok, werr = f:write(data)
    f:close()
    if not ok then return false, werr end
    return true
end

function util.file_size(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local size = f:seek("end")
    f:close()
    return size
end

function util.path_exists(path)
    local f = io.open(path, "rb")
    if f then f:close() return true end
    -- 目录无法用 io.open 打开，退化为 shell 检查
    local ok = os.execute("test -e " .. util.shell_quote(path))
    return ok == 0 or ok == true
end

-- UTF-8 与终端显示宽度：CJK 全角按 2 个单元计算。
-- Keep UTF-8 boundaries while limiting layout work on unexpectedly huge titles.
function util.utf8_prefix(text,limit)
 if #text<=limit then return text end
 local i=limit
 while i>0 do local b=text:byte(i);if b<128 or b>=192 then break end;i=i-1 end
 if i==0 then return '' end
 local b=text:byte(i);local n=b<128 and 1 or (b<224 and 2 or (b<240 and 3 or 4))
 return text:sub(1,i+n-1<=limit and limit or i-1)..'...'
end

function util.utf8_codepoints(s)
    local cps = {}
    local i = 1
    local len = #s
    while i <= len do
        local b = s:byte(i)
        if not b then break end
        local cp, n
        if b < 0x80 then
            cp, n = b, 1
        elseif b < 0xE0 then
            cp, n = b % 0x20, 2
        elseif b < 0xF0 then
            cp, n = b % 0x10, 3
        else
            cp, n = b % 0x08, 4
        end
        for j = 1, n - 1 do
            local cb = s:byte(i + j)
            if not cb then break end
            cp = cp * 0x40 + (cb % 0x40)
        end
        cps[#cps + 1] = { cp = cp, len = n, byte = i }
        i = i + n
    end
    return cps
end

local function is_wide(cp)
    return (cp >= 0x1100 and cp <= 0x115F)
        or (cp >= 0x2E80 and cp <= 0xA4CF)
        or (cp >= 0xAC00 and cp <= 0xD7A3)
        or (cp >= 0xF900 and cp <= 0xFAFF)
        or (cp >= 0xFE30 and cp <= 0xFE6F)
        or (cp >= 0xFF00 and cp <= 0xFF60)
        or (cp >= 0xFFE0 and cp <= 0xFFE6)
        or (cp >= 0x20000 and cp <= 0x3FFFD)
end

function util.text_width(s)
    local w = 0
    for _, ch in ipairs(util.utf8_codepoints(s)) do
        w = w + (is_wide(ch.cp) and 2 or 1)
    end
    return w
end

-- 按显示宽度截断，并追加省略号。
function util.ellipsize(s, max_cells)
    if util.text_width(s) <= max_cells then return s end
    local out = {}
    local w = 0
    local ell = "..."
    local ell_w = 3
    for _, ch in ipairs(util.utf8_codepoints(s)) do
        local cw = is_wide(ch.cp) and 2 or 1
        if w + cw > max_cells - ell_w then break end
        out[#out + 1] = s:sub(ch.byte, ch.byte + ch.len - 1)
        w = w + cw
    end
    return table.concat(out) .. ell
end

-- 按显示宽度换行（保留英文单词边界；中文按字符断行）。
function util.wrap_text(s, max_cells)
    local lines = {}
    for raw in (s .. "\n"):gmatch("(.-)\n") do
        if raw == "" then
            lines[#lines + 1] = ""
        else
            local line = {}
            local w = 0
            for _, ch in ipairs(util.utf8_codepoints(raw)) do
                local chs = raw:sub(ch.byte, ch.byte + ch.len - 1)
                local cw = is_wide(ch.cp) and 2 or 1
                if w + cw > max_cells and #line > 0 then
                    lines[#lines + 1] = table.concat(line)
                    line = {}
                    w = 0
                end
                line[#line + 1] = chs
                w = w + cw
            end
            lines[#lines + 1] = table.concat(line)
        end
    end
    return lines
end

-- 简单稳定的字符串哈希，用于判断内容是否变化。
function util.hash(s)
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + s:byte(i)) % 4294967296
    end
    return h
end

function util.table_len(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function util.map(t, fn)
    local out = {}
    for i, v in ipairs(t) do out[i] = fn(v) end
    return out
end

function util.filter(t, fn)
    local out = {}
    for _, v in ipairs(t) do
        if fn(v) then out[#out + 1] = v end
    end
    return out
end

function util.index_by(list, key)
    local out = {}
    for _, v in ipairs(list) do
        if v[key] ~= nil then out[v[key]] = v end
    end
    return out
end

function util.now_string(ts)
    return os.date("%Y-%m-%d %H:%M:%S", ts or os.time())
end

return util
