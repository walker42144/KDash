> 历史参考：此文档来自 Trae v0.1，不能作为候选版安装／验证状态说明。当前步骤见项目根目录 README.md。

# KDash API 与数据格式

本文描述 KDash 自身的配置/缓存格式，以及外部服务适配器实际使用的接口。

## 1. 配置 `config.json`

默认值在 `config/default.json`；用户文件 `/mnt/us/kdash-candidate/config.json` 深合并覆盖（对象递归，数组整体替换）。

```json
{
  "schema_version": 1,
  "language": "zh",
  "utc_offset_minutes": 480,
  "last_page": "home",
  "ui": {
    "ink_mode": false,
    "margin": 56,
    "font_scale": 1.0,
    "font": ""
  },
  "power": {
    "keep_awake": "plugged",
    "full_refresh_every": 24
  },
  "network": {
    "sync_interval_minutes": 15,
    "insecure_tls": false
  },
  "modules": {},
  "pages": []
}
```

| 字段 | 说明 |
|---|---|
| `schema_version` | 配置迁移版本；当前 1 |
| `language` | `zh` / `en` |
| `utc_offset_minutes` | 固定 UTC 偏移；默认 480（Asia/Shanghai）。核心时间计算不依赖系统本地时区 |
| `ui.ink_mode` | 反色（黑底白字）；仍建议只用于实验 |
| `ui.margin` | 页边距（px） |
| `ui.font_scale` | 字号缩放 0.6–1.8 |
| `ui.font` | 自定义 TTF 路径；留空自动探测 |
| `power.keep_awake` | `always` / `plugged` / `never` / `battery` |
| `power.full_refresh_every` | 每 N 次局部刷新做一次全屏 GC16 |
| `network.insecure_tls` | 默认 false；仅调试用，不推荐开启 |
| `pages` | 页面数组，见下 |

页面：

```json
{
  "id": "home",
  "title": "KDASH",
  "kind": "dashboard",
  "detail": false,
  "layout": [
    { "modules": ["clock"], "weight": 28 },
    { "modules": ["dida", "weather"], "weight": 30 }
  ]
}
```

- `kind: "settings"` 使用内置设置页，忽略 `layout`。
- `layout[].modules` 1 或 2 个模块 id；2 个时自动双列。
- `weight` 相对权重；`min_height` 来自模块 manifest。
- 禁用模块会被渲染器过滤；整页为空时显示空状态。

## 2. 模块 manifest `module.json`

```json
{
  "id": "clock",
  "name": "Clock",
  "display_title": "TIME",
  "version": "1.0.0",
  "api_version": 1,
  "order": 10,
  "enabled": true,
  "permissions": [],
  "refresh": { "interval": 30, "align": "minute", "max_backoff": 3600, "on_start": true },
  "layout": { "min_height": 240, "show_title": false }
}
```

`api_version` 当前只接受 `1`。模块接口见 `docs/MODULE_DEVELOPMENT.md`。

`notes` 模块额外支持：

```json
{
  "notes": {
    "title": "NOTES",
    "file": "",
    "quotes": [
      { "text": "把每一天过成作品。", "author": "KDash" }
    ],
    "text": "# 备忘\n- ..."
  }
}
```

`quotes` 非空时按本地日期轮换每日一句，优先于 `file`/`text`。

## 3. 缓存格式

`/mnt/us/kdash-candidate/cache/<name>.json`：

```json
{
  "cache_version": 1,
  "saved_at": 1794369600,
  "fetched_at": 1794369000,
  "status": 200,
  "error": null,
  "data": {}
}
```

- `data` 由模块定义。
- 解析失败视为无缓存，不崩溃。
- 缓存可安全删除；下次联网重建。
- 天气缓存 `data` 是视图对象；Dida 缓存 `data` 是 `{ view, projects, project_data }`。

## 4. 凭证 `secrets.json`

```json
{
  "dida": {
    "client_id": "...",
    "client_secret": "...",
    "access_token": "...",
    "refresh_token": "...",
    "expires_at": 1794373200,
    "scope": "tasks:read"
  }
}
```

- 文件权限 600；不要提交到版本库。
- 设备端刷新 token 时会把新 token 写回此文件。
- `client_secret` 存在设备上，属于已知风险；如果 Dida 应用支持，尽量使用最小 scope。

## 5. Dida365 Open API

官方文档：<https://developer.dida365.com/api>（中国版）。
KDash 只使用只读接口；scope 默认 `tasks:read`。

### 5.1 OAuth

授权：

```text
GET https://dida365.com/oauth/authorize
  ?client_id=...
  &redirect_uri=http://127.0.0.1:8080/callback
  &response_type=code
  &scope=tasks:read
  &state=...
```

换取 token：

```text
POST https://dida365.com/oauth/token
Content-Type: application/x-www-form-urlencoded

client_id=...
&client_secret=...
&code=...
&grant_type=authorization_code
&redirect_uri=http://127.0.0.1:8080/callback
&scope=tasks:read
```

刷新：

```text
POST https://dida365.com/oauth/token
Content-Type: application/x-www-form-urlencoded

client_id=...
&client_secret=...
&grant_type=refresh_token
&refresh_token=...
```

响应字段使用：`access_token`、`refresh_token`、`expires_in`、`scope`。
KDash 在 `expires_at - 60s` 后视为过期。

### 5.2 读取接口

```text
GET https://api.dida365.com/open/v1/project
Authorization: Bearer <access_token>
```

返回项目数组；KDash 跳过 `closed=true` 与 `kind=NOTE` 的项目，并可用 `modules.dida.project_ids` 限定。

```text
GET https://api.dida365.com/open/v1/project/{projectId}/data
```

返回：

```json
{
  "project": { "id": "...", "name": "..." },
  "tasks": [
    {
      "id": "...",
      "projectId": "...",
      "title": "...",
      "status": 0,
      "priority": 5,
      "dueDate": "2026-11-11T10:00:00+0800",
      "isAllDay": false,
      "completedTime": "2026-11-11T09:30:00+0800",
      "timeZone": "Asia/Shanghai",
      "tags": []
    }
  ],
  "columns": []
}
```

KDash 使用字段：

| 字段 | 用途 |
|---|---|
| `id` / `title` | 任务显示 |
| `projectId` | 映射清单名 |
| `status` | 0 未完成，2 已完成 |
| `priority` | 0/1/3/5；UI 用 `!` / `·` 标记 |
| `dueDate` | 今日/逾期/即将到期 |
| `isAllDay` | 日期型任务按日期比较，避免时区误差 |
| `completedTime` | 今日完成数 |
| `tags` | 预留 |

同步策略：

- `GET /project` 一次，然后逐个启用项目 `GET /project/{id}/data`，串行以避免并发压力。
- 失败保留旧缓存；UI 显示 “OFFLINE · CACHED”。
- 401 显示 “AUTH REQUIRED”，不清空任务。
- 请求间隔默认 15 分钟；失败指数退避至 1 小时。
- 只读：不调用完成任务/创建/删除接口。

限制：

- 不同版本/账号返回的已完成任务集合可能不同；如果 `project data` 不返回已完成任务，`completed_today` 会是 0。
- 官方限流以 Dida 文档为准；KDash 不并行请求。

## 6. Open-Meteo

请求：

```text
GET https://api.open-meteo.com/v1/forecast
  ?latitude=39.9042
  &longitude=116.4074
  &current=temperature_2m,weather_code,relative_humidity_2m,apparent_temperature
  &daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max
  &timezone=Asia%2FShanghai
  &forecast_days=3
```

无需 API Key。KDash 使用：

- `current.temperature_2m` / `apparent_temperature` / `relative_humidity_2m` / `weather_code`
- `daily.time[]` / `weather_code[]` / `temperature_2m_max[]` / `temperature_2m_min[]` / `precipitation_probability_max[]`

WMO 代码映射到中英文描述（见 `services/api/weather.lua`），例如：

| code | EN | 中文 |
|---|---|---|
| 0/1 | CLEAR / MOSTLY CLEAR | 晴 / 晴间多云 |
| 2 | PARTLY CLOUDY | 多云 |
| 3 | OVERCAST | 阴 |
| 45/48 | FOG | 雾 |
| 61/63/65 | RAIN | 小雨/中雨/大雨 |
| 71/73/75 | SNOW | 小雪/中雪/大雪 |
| 95/96/99 | THUNDERSTORM | 雷阵雨 |

数据许可：Open-Meteo 数据为 CC BY 4.0；请保留来源说明。

## 7. HTTP 服务

`services/http.lua` 为每个请求生成一个临时 shell 脚本，后台执行：

```sh
curl -sS -L --connect-timeout 10 --max-time 30 \
  --max-filesize 4194304 \
  -A 'KDash/0.1 (Kindle)' \
  -H 'Authorization: Bearer ...' \
  -o out -w '%{http_code}' 'https://...' > status 2> err
echo $? > rc
echo done > done
```

主循环轮询 `done` 文件，读取 `rc/status/body`，回调模块。

- 非 2xx 或 curl 非 0 → `ok=false`。
- 超过 `timeout+20s` → 主动标记失败。
- CA：依次探测 `/etc/ssl/certs/ca-certificates.crt`、`/etc/ssl/certs/ca-bundle.crt`、`/etc/ssl/cert.pem`；找不到则不指定（由 curl 默认）。
- `network.insecure_tls=true` 才加 `-k`。
- 不支持自定义代理；如需代理，可在 launcher 中设置 `HTTPS_PROXY` 环境变量。
