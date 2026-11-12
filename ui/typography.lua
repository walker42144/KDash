-- 字体度量：基于字符类别的近似宽度，足以做截断、换行和居中。
-- 实际绘制交给 FBInk + stb_truetype；这里只负责布局预算。
local util = require("core.util")

local Typo = {}
Typo.__index = Typo

function Typo.new(opts)
    local self = setmetatable({}, Typo)
    self.measure_fn=opts and opts.measure
    self.latin_ratio = opts and opts.latin_ratio or 0.53
    self.digit_ratio = opts and opts.digit_ratio or 0.57
    self.space_ratio = opts and opts.space_ratio or 0.28
    self.cjk_ratio = 1.0
    self.line_ratio = 1.28
    return self
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

function Typo:char_width(cp, size)
    if cp == 32 then return size * self.space_ratio end
    if is_wide(cp) then return size * self.cjk_ratio end
    if cp >= 48 and cp <= 57 then return size * self.digit_ratio end
    if cp >= 33 and cp <= 126 then
        if cp >= 65 and cp <= 90 then return size * 0.62 end
        if cp >= 97 and cp <= 122 then return size * 0.52 end
        return size * 0.38
    end
    return size * 0.55
end

function Typo:measure(text, size)
    if self.measure_fn then return self.measure_fn(text or "",size) end
    local w = 0
    for _, ch in ipairs(util.utf8_codepoints(text or "")) do
        w = w + self:char_width(ch.cp, size)
    end
    return math.ceil(w)
end

function Typo:line_height(size)
    return util.round(size * self.line_ratio)
end

function Typo:fit(text, max_px, size)
    text = text or ""
    if self:measure(text, size) <= max_px then return text end
    local chars = util.utf8_codepoints(text)
    local ell_w = self:measure("...", size)
    local budget = max_px - ell_w
    if budget <= 0 then return "" end
    local out = {}
    local w = 0
    for _, ch in ipairs(chars) do
        local cw = self:char_width(ch.cp, size)
        if w + cw > budget then break end
        out[#out + 1] = text:sub(ch.byte, ch.byte + ch.len - 1)
        w = w + cw
    end
    return table.concat(out) .. "..."
end

-- 长文本换行：优先英文单词边界，中文按字符；返回行数组。
function Typo:wrap(text, max_px, size)
    local lines = {}
    for raw in ((text or "") .. "\n"):gmatch("(.-)\n") do
        if raw == "" then
            lines[#lines + 1] = ""
        else
            local words = {}
            local buf = {}
            for _, ch in ipairs(util.utf8_codepoints(raw)) do
                local chs = raw:sub(ch.byte, ch.byte + ch.len - 1)
                if ch.cp == 32 then
                    words[#words + 1] = table.concat(buf)
                    buf = {}
                    words[#words + 1] = " "
                else
                    buf[#buf + 1] = chs
                end
            end
            if #buf > 0 then words[#words + 1] = table.concat(buf) end
            local line = ""
            for _, word in ipairs(words) do
                if word == " " then
                    if line ~= "" then
                        local test = line .. " "
                        if self:measure(test, size) <= max_px then line = test end
                    end
                else
                    local test = line == "" and word or (line .. word)
                    if self:measure(test, size) <= max_px then
                        line = test
                    else
                        if line ~= "" then lines[#lines + 1] = line end
                        -- 单个英文单词过长时按字符硬切
                        if self:measure(word, size) > max_px then
                            local chunk = {}
                            for _, ch in ipairs(util.utf8_codepoints(word)) do
                                local chs = word:sub(ch.byte, ch.byte + ch.len - 1)
                                local test2 = table.concat(chunk) .. chs
                                if self:measure(test2, size) > max_px and #chunk > 0 then
                                    lines[#lines + 1] = table.concat(chunk)
                                    chunk = { chs }
                                else
                                    chunk[#chunk + 1] = chs
                                end
                            end
                            line = table.concat(chunk)
                        else
                            line = word
                        end
                    end
                end
            end
            if line ~= "" then lines[#lines + 1] = line end
        end
    end
    return lines
end

return Typo
