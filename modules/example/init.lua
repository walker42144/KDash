-- Hello World 示例模块：证明新增模块只需目录 + module.json + init.lua。
local timeutil = require("core.timeutil")

local M = {}

function M.init(ctx)
    return true
end

function M.refresh(ctx)
    ctx.request_update()
    return true
end

function M.render(ctx, ui, rect, opts)
    local theme = ui.theme
    local l = ctx.config.data.language or "zh"
    local cfg = ctx.config:module("example")
    local now = ctx.now()
    local offset = ctx.config.data.utc_offset_minutes or 480
    ui:text({
        text = cfg.message or (l == "zh" and "来自示例模块的问候" or "HELLO FROM THE EXAMPLE MODULE"),
        x = rect.x, y = rect.y, w = rect.w,
        size = theme.type.body, color = theme.colors.ink,
    })
    ui:text({
        text = string.format("MODULE API V1  ·  %s", timeutil.format_time(now, offset, true)),
        x = rect.x, y = rect.y + ui.typo:line_height(theme.type.body) + theme.space.xs,
        w = rect.w, size = theme.type.micro, color = theme.colors.muted,
    })
end

return M
