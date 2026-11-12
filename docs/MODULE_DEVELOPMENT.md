> 历史参考：此文档来自 Trae v0.1，不能作为候选版安装／验证状态说明。当前步骤见项目根目录 README.md。

# 模块开发指南

KDash 的目标是：**新增一个模块时，只增加模块目录和配置，不修改核心代码。**

## 1. 最小 Hello World

创建 `modules/hello/module.json`：

```json
{
  "id": "hello",
  "name": "Hello",
  "display_title": "HELLO",
  "version": "1.0.0",
  "api_version": 1,
  "order": 95,
  "enabled": true,
  "permissions": [],
  "refresh": { "interval": 600, "align": "minute" },
  "layout": { "min_height": 90, "show_title": true }
}
```

创建 `modules/hello/init.lua`：

```lua
local M = {}

function M.init(ctx)
    return true
end

function M.refresh(ctx)
    -- 本地模块无需网络；返回 true 表示本次刷新完成
    return true
end

function M.render(ctx, ui, rect, opts)
    local theme = ui.theme
    ui:text({
        text = "Hello from a KDash module.",
        x = rect.x, y = rect.y, w = rect.w,
        size = theme.type.small,
        color = theme.colors.ink,
    })
end

return M
```

在 `config/default.json` 的某个页面中加入：

```json
{ "modules": ["hello"], "weight": 10 }
```

重新启动或切换页面即可看到；不需要改 `core/`、`ui/` 或主循环。

## 2. manifest 字段

| 字段 | 必填 | 说明 |
|---|---|---|
| `id` | 是 | 唯一 ID，小写；与目录名建议一致 |
| `name` | 是 | KPM/设置页显示名称 |
| `display_title` | 否 | 卡片标题（默认 `name`） |
| `version` | 是 | 模块版本字符串 |
| `api_version` | 是 | 当前只支持 `1`；核心拒绝未知版本 |
| `order` | 否 | 发现顺序，越小越前 |
| `enabled` | 否 | 默认启用；用户配置可覆盖 |
| `permissions` | 否 | `network` / `secrets` / `device`，用于声明意图 |
| `refresh.interval` | 否 | 秒；默认 300 |
| `refresh.align` | 否 | `minute` / `hour` / `day` |
| `refresh.max_backoff` | 否 | 失败退避上限，默认 3600 |
| `refresh.on_start` | 否 | 默认 true；启动即刷新 |
| `layout.min_height` | 否 | 像素基准（按屏幕比例缩放），默认 80 |
| `layout.show_title` | 否 | 是否由渲染器绘制卡片标题 |

`module.json` 由 `core/registry.lua` 解析；损坏或版本不支持时只显示该模块错误。

## 3. 模块接口

### 3.1 `init(ctx)`

- 必需；返回 `true` 或 `nil`。
- 只做初始化：读取配置、加载缓存、创建 adapter；不要做长网络请求。
- 抛错会被捕获，模块被标记为错误卡片，应用继续运行。

### 3.2 `refresh_policy(ctx)`

可选；返回：

```lua
{
  interval = 900,        -- 秒
  align = "minute",      -- 可选
  max_backoff = 3600,
  on_start = true,
}
```

覆盖 manifest 的刷新策略。

### 3.3 `refresh(ctx)`

- 返回 `true`：同步完成，调度器立即安排下一次。
- 返回 `false`：异步进行中；必须在回调中调用 `ctx.finish(ok, err)`。
- 返回 `nil`：视为完成。
- 数据变化时调用 `ctx.request_update()`；没有变化则不要调用，避免无意义 E Ink 刷新。
- 失败时调用 `ctx.finish(false, err)`，并保留旧缓存。

### 3.4 `render(ctx, ui, rect, opts)`

- 只读 `state`；不要在这里发网络请求。
- `rect` 是卡片内容区（标题已由渲染器绘制，若 `show_title=false` 则是整个卡片）。
- `opts`：`page_id`、`detail`（页面标记）、`language`。
- 必须尊重 `rect` 边界；KDash 没有裁剪。
- 触控用 `ui:hit(rect, action, payload, label)` 注册。

### 3.5 `shutdown()`

可选；释放文件/进程/定时器。应用退出时调用。

## 4. ctx 参考

| 字段/方法 | 说明 |
|---|---|
| `ctx.now()` | 当前 Unix 时间（受预览 `--now` 影响） |
| `ctx.config` | 完整 Config 对象；`ctx.config:module(id)` 取模块配置 |
| `ctx.manifest` | 当前 manifest |
| `ctx.cache` | `read(name)` / `write(name, payload)` |
| `ctx.http` | 异步 HTTP（见下） |
| `ctx.secrets` | 独立 secrets（600） |
| `ctx.device_info()` | 电池/网络/固件等（带 20s 缓存） |
| `ctx.log` | `debug/info/warn/error` |
| `ctx.request_update()` | 标记本模块脏，触发局部重绘 |
| `ctx.finish(ok, err)` | 异步刷新结束 |
| `ctx.set_page(id)` | 切换页面（谨慎使用） |
| `ctx.save_config()` | 持久化配置 |

## 5. UI 参考

`ui` 由 `ui/components.lua` 创建：

```lua
ui:text{ text, x, y, w, size, align, color, bg, weight }
ui:fill(rect, color)
ui:hline(x, y, w, color)
ui:vline(x, y, h, color)
ui:box(rect, filled, color)
ui:checkbox(x, y, checked, size)
ui:progress(rect, 0..100)
ui:label(text, x, y, w, opts)
ui:section(title, rect)         -- 返回内容起始 y
ui:empty(rect, text)
ui:error(rect, err)
ui:task_row(rect, title, meta, checked, opts)
ui:button(rect, label, inverted, action, payload)
ui:hit(rect, action, payload, label)
```

主题：`ui.theme.colors`（paper/ink/muted/faint/inverse_bg/inverse_fg）、`ui.theme.type`（hero/display/title/body/small/micro）、`ui.theme.space`。
排版：`ui.typo:measure(text, size)`、`ui.typo:fit(...)`、`ui.typo:wrap(...)`、`ui.typo:line_height(size)`。

设计约束：

- 只用黑白灰 token，不硬编码颜色。
- 大字号、清晰层级、足够留白。
- 不使用动画/渐变/装饰插画。
- 中文和英文共用一个字体；文本尽量单行截断，长文本用 `wrap` 并检查高度。

## 6. 异步 HTTP + 自定义 API 模块

示例：调用一个 JSON API，缓存结果并在卡片显示。

```lua
local json = require("core.json")

local M = {}
local state = { value = nil, error = nil, syncing = false }

function M.init(ctx)
    local cached = ctx.cache:read("myapi")
    if cached and cached.data then state.value = cached.data end
    return true
end

function M.refresh_policy(ctx)
    return { interval = 1800, align = "minute" }
end

function M.refresh(ctx)
    if state.syncing then return false end
    state.syncing = true
    ctx.http:request({
        url = "https://example.com/api/status",
        method = "GET",
        headers = { ["Accept"] = "application/json" },
        timeout = 30,
        label = "myapi",
    }, function(res)
        state.syncing = false
        if not res.ok then
            state.error = res.error
            ctx.request_update()
            ctx.finish(false, res.error)
            return
        end
        local ok, data = pcall(json.decode, res.body)
        if not ok or type(data) ~= "table" then
            state.error = "invalid json"
            ctx.request_update()
            ctx.finish(false, "invalid json")
            return
        end
        state.value = data
        state.error = nil
        ctx.cache:write("myapi", { data = data, fetched_at = ctx.now() })
        ctx.request_update()
        ctx.finish(true)
    end)
    return false
end

function M.render(ctx, ui, rect, opts)
    local theme = ui.theme
    if not state.value then
        ui:empty(rect, "NO DATA")
        return
    end
    ui:text({
        text = tostring(state.value.status or "OK"),
        x = rect.x, y = rect.y, w = rect.w,
        size = theme.type.title, color = theme.colors.ink,
    })
    if state.error then
        ui:text({
            text = "CACHED / " .. state.error,
            x = rect.x, y = rect.y + ui.typo:line_height(theme.type.title),
            w = rect.w, size = theme.type.micro, color = theme.colors.muted,
        })
    end
end

return M
```

规则：

- UI 层不直接发网络请求。
- API 变化时改 adapter，不改渲染。
- 超时、非 2xx、JSON 错误都要走 `ctx.finish(false, err)`。
- 缓存先读、网络后更新；离线时保留旧数据并显示状态。

## 7. 错误处理与容错

- `init/render/refresh` 抛错会被隔离；但不要依赖它做正常控制流。
- 网络错误用指数退避；不要写无限重试循环。
- 不要把 Token 写进日志或缓存。
- 不要修改 `/mnt/us/kdash-candidate/secrets.json` 的权限；它由核心创建为 600。
- 不要在模块中 `os.execute` 系统级命令；需要设备能力时扩展 `platform/`。

## 8. 版本与兼容

- `api_version = 1` 是当前稳定接口。
- 新增可选字段不升版本；删除/重命名接口必须升版本并在核心中保留兼容或明确拒绝。
- 模块自身 `version` 独立；升级时配置与缓存保留。
- 未知 `api_version` 的模块会显示错误卡片，不影响其他模块。

## 9. 测试模块

在 `tests/` 增加测试，至少覆盖：

- manifest 加载与启用/禁用。
- 数据处理纯函数（不依赖 UI/网络）。
- 离线缓存分支。

`tests/test_registry.lua` 已经验证“新增目录 + manifest 即可加载”的路径。
`modules/example/` 是内置的 Hello World 验收模块。

## 10. 布局与页面

页面配置示例：

```json
{
  "id": "home",
  "title": "KDASH",
  "kind": "dashboard",
  "layout": [
    { "modules": ["clock"], "weight": 28 },
    { "modules": ["countdown"], "weight": 24 },
    { "modules": ["dida"], "weight": 28 },
    { "modules": ["weather"], "weight": 20 }
  ]
}
```

- 一行 `modules` 有 2 个 id 时自动双列。
- 行高按 weight 分配；`min_height` 是下限。
- 模块被禁用时该行自动过滤；如果整页为空，显示空状态。
- `detail: true` 会传给模块 `opts.detail`，用于同模块的详细页展示。
