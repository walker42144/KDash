-- Dida Tasks 模块：只读展示今日/逾期/即将到期任务与完成进度。
local DidaAPI = require("services.api.dida")
local timeutil = require("core.timeutil")

local M = {}
local state = {
    view = nil,
    error = nil,
    cached_at = nil,
    syncing = false,
    adapter = nil,
}

local function lang(ctx) return ctx.config.data.language or "zh" end

function M.init(ctx)
    state.adapter = DidaAPI.new({
        http = ctx.http,
        config = ctx.config,
        secrets = ctx.secrets,
        cache = ctx.cache,
        log = ctx.log,
        now = ctx.now,
        offset = ctx.config.data.utc_offset_minutes or 480,
    })
    local cached = ctx.cache:read("dida")
    if cached and cached.data and cached.data.view then
        state.view = cached.data.view
        state.cached_at = cached.fetched_at
    end
    return true
end

function M.refresh_policy(ctx)
    local cfg = ctx.config:module("dida")
    return {
        interval = math.max(300, (cfg.sync_interval_minutes or 15) * 60),
        max_backoff = 3600,
    }
end

function M.refresh(ctx)
    if state.syncing then return false end
    if state.adapter:auth_state() == "missing" then
        state.error = "AUTH_REQUIRED"
        ctx.request_update()
        return true
    end
    state.syncing = true
    state.adapter:sync(function(ok, err, view)
        state.syncing = false
        if ok then
            state.view = view
            state.cached_at = ctx.now()
            state.error = nil
        else
            state.error = tostring(err)
        end
        ctx.request_update()
        ctx.finish(ok, err)
    end)
    return false
end

local function status_text(ctx, l)
    if state.error then
        if state.error:find("AUTH", 1, true) then
            return l == "zh" and "授权失效 · 请在电脑运行 tools/dida_auth.py" or "AUTH EXPIRED · RUN tools/dida_auth.py"
        end
        return (l == "zh" and "同步失败 · 显示缓存" or "SYNC FAILED · CACHED")
    end
    if state.cached_at then
        local offset = ctx.config.data.utc_offset_minutes or 480
        return string.format("%s %s", l == "zh" and "同步于" or "SYNCED",
            timeutil.format_time(state.cached_at, offset, true))
    end
    return l == "zh" and "尚未同步" or "NOT SYNCED"
end

local function draw_task(ui, rect, task, show_project, l)
    local meta = nil
    if show_project then
        meta = task.project
    end
    local prefix = ""
    if task.priority == 5 then prefix = "!  "
    elseif task.priority == 3 then prefix = "·  " end
    ui:task_row(rect, prefix .. task.title, meta, false, { size = ui.theme.type.body })
end

function M.render(ctx, ui, rect, opts)
    local l = lang(ctx)
    local theme = ui.theme
    local detail = opts and opts.detail == true
    local view = state.view
    if not view then
        ui:empty(rect, l == "zh" and "暂无任务数据" or "NO TASK DATA")
        local y = rect.y + rect.h - ui.typo:line_height(theme.type.micro) * 2
        ui:text({
            text = status_text(ctx, l),
            x = rect.x, y = y, w = rect.w,
            size = theme.type.micro, color = theme.colors.muted, align = "center",
        })
        ui:hit(rect, "module_sync", "dida", "dida")
        return
    end
    local row_h = ui.typo:line_height(theme.type.body)
    local y = rect.y
    local total = view.total_today or 0
    local done = view.completed_today or 0
    local progress_text = string.format("%d / %d %s", done, total, l == "zh" and "完成" or "DONE")
    ui:text({
        text = progress_text,
        x = rect.x, y = y, w = rect.w,
        size = theme.type.micro, color = theme.colors.muted,
    })
    local bar_y = y + ui.typo:line_height(theme.type.micro) + theme.space.xs
    ui:progress({ x = rect.x, y = bar_y, w = rect.w, h = theme.line * 3 }, view.progress or 0)
    y = bar_y + theme.line * 3 + theme.space.sm

    local items = {}
    for _, t in ipairs(view.overdue or {}) do
        if #items < (detail and 4 or 1) then
            items[#items + 1] = { task = t, overdue = true }
        end
    end
    for _, t in ipairs(view.today or {}) do
        items[#items + 1] = { task = t, overdue = false }
    end
    if detail then
        for _, t in ipairs(view.upcoming or {}) do
            if #items < 9 then items[#items + 1] = { task = t, upcoming = true } end
        end
    end
    local max_rows = math.floor((rect.y + rect.h - y - ui.typo:line_height(theme.type.micro)) / row_h)
    max_rows = math.max(1, max_rows)
    for i = 1, math.min(#items, max_rows) do
        local it = items[i]
        local task = it.task
        local meta = nil
        if detail then
            meta = task.project
            if it.overdue then meta = (l == "zh" and "逾期 " or "OVERDUE ") .. (task.project or "")
            elseif it.upcoming then
                meta = string.format("%s %d%s", task.due_key, task.days_left or 0, l == "zh" and "天" or "D")
            end
        end
        local prefix = ""
        if task.priority == 5 then prefix = "!  " end
        ui:task_row({ x = rect.x, y = y, w = rect.w, h = row_h }, prefix .. task.title, meta, false,
            { size = theme.type.body })
        y = y + row_h
    end
    if #items == 0 then
        ui:empty({ x = rect.x, y = y, w = rect.w, h = row_h * 2 }, l == "zh" and "今日无任务" or "NO TASKS TODAY")
    end
    local status_y = rect.y + rect.h - ui.typo:line_height(theme.type.micro)
    ui:text({
        text = status_text(ctx, l),
        x = rect.x, y = status_y, w = rect.w,
        size = theme.type.micro, color = theme.colors.muted,
    })
    if detail and #items > max_rows then
        ui:text({
            text = string.format("+%d", #items - max_rows),
            x = rect.x, y = status_y, w = rect.w,
            size = theme.type.micro, color = theme.colors.muted, align = "right",
        })
    end
    ui:hit(rect, "module_sync", "dida", "dida")
end

return M
