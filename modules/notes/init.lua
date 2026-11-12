-- Notes 模块：本地 Markdown 子集（标题、列表、段落）。
local util = require("core.util")

local M = {}
local state = { text = "", hash = nil }

local function load_text(ctx)
    local cfg = ctx.config:module("notes")
    if type(cfg.quotes) == "table" and #cfg.quotes > 0 then
        local offset = ctx.config.data.utc_offset_minutes or 480
        local day = math.floor((ctx.now() + offset * 60) / 86400)
        local q = cfg.quotes[(day % #cfg.quotes) + 1]
        if type(q) == "table" then
            local text = q.text or ""
            if q.author and q.author ~= "" then
                text = text .. "\n— " .. q.author
            end
            return text
        end
        return tostring(q)
    end
    if cfg.file and cfg.file ~= "" then
        local data = util.read_file(cfg.file)
        if data then return data end
        return cfg.text or ""
    end
    return cfg.text or ""
end

function M.init(ctx)
    state.text = load_text(ctx)
    state.hash = util.hash(state.text)
    return true
end

function M.refresh(ctx)
    local text = load_text(ctx)
    local h = util.hash(text)
    if h ~= state.hash then
        state.text = text
        state.hash = h
        ctx.request_update()
    end
    return true
end

-- 纯函数：把 Markdown 子集解析为行描述，便于单测。
function M.parse(text)
    local out = {}
    for raw in ((text or "") .. "\n"):gmatch("(.-)\n") do
        local line = raw:gsub("%*%*(.-)%*%*", "%1")
        if line:match("^###%s+") then
            out[#out + 1] = { kind = "h3", text = line:gsub("^###%s+", "") }
        elseif line:match("^##%s+") then
            out[#out + 1] = { kind = "h2", text = line:gsub("^##%s+", "") }
        elseif line:match("^#%s+") then
            out[#out + 1] = { kind = "h1", text = line:gsub("^#%s+", "") }
        elseif line:match("^%-%s+") then
            out[#out + 1] = { kind = "li", text = line:gsub("^%-%s+", "") }
        elseif line:match("^%s*$") then
            out[#out + 1] = { kind = "blank", text = "" }
        else
            out[#out + 1] = { kind = "p", text = line }
        end
    end
    return out
end

function M.render(ctx, ui, rect, opts)
    local theme = ui.theme
    local l = ctx.config.data.language or "zh"
    local parsed = M.parse(state.text)
    local y = rect.y
    local bottom = rect.y + rect.h
    local truncated = false
    for _, item in ipairs(parsed) do
        local size = theme.type.body
        local prefix = ""
        if item.kind == "h1" then size = theme.type.title
        elseif item.kind == "h2" then size = theme.type.title - 6
        elseif item.kind == "h3" then size = theme.type.small
        elseif item.kind == "li" then prefix = "·  " end
        if item.kind == "blank" then
            y = y + math.floor(theme.space.sm / 2)
        else
            local lines = ui.typo:wrap(prefix .. item.text, rect.w, size)
            for _, line in ipairs(lines) do
                local lh = ui.typo:line_height(size)
                if y + lh > bottom then truncated = true; break end
                ui:text({
                    text = line,
                    x = rect.x, y = y, w = rect.w,
                    size = size,
                    color = item.kind == "p" and theme.colors.ink or theme.colors.ink,
                })
                y = y + lh
            end
        end
        if truncated then break end
    end
    if truncated then
        ui:text({
            text = "...",
            x = rect.x, y = bottom - ui.typo:line_height(theme.type.micro),
            w = rect.w, size = theme.type.micro, color = theme.colors.muted, align = "right",
        })
    end
    if state.text == "" then
        ui:empty(rect, l == "zh" and "无内容 · 编辑 config.json" or "EMPTY · EDIT config.json")
    end
end

return M
