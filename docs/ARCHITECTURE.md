> 历史参考：此文档来自 Trae v0.1，不能作为候选版安装／验证状态说明。当前步骤见项目根目录 README.md。

# KDash 架构

## 1. 目标与非目标

**目标**

- 在 KPW3 上以独立应用运行，拥有书库入口，不依赖 KOReader/KUAL。
- 单进程、低内存、可长期运行；网络与 UI 解耦。
- 模块可插拔：新增功能只需增加模块目录与配置，不改核心。
- 本地优先：启动立即显示缓存，联网只做异步更新。
- 安全启停：异常退出后恢复 Kindle 原生框架。

**非目标（v0.1）**

- 不做 KOReader 插件，不嵌入 KOReader 代码。
- 不使用 WebKit/Mesquite 作为 UI 运行时。
- 不承诺休眠期间的后台定时刷新。
- 不做第三方插件商店、复杂拖拽布局、动画。

## 2. 技术选型

| 方案 | 结论 | 原因 |
|---|---|---|
| A. 原生应用 + Lua UI + FBInk | **采用** | 动态模块加载、低内存、可维护；KPW3 有成熟 LuaJIT/FBInk 运行先例 |
| B. C/C++ + FBInk | 未采用 | 性能更好，但模块扩展/迭代成本高，v0.1 不需要 |
| C. Kindle WebKit/Mesquite | 未采用 | 内存/CPU 开销大、启动依赖框架、与“长期低功耗”冲突 |
| D. 本机客户端 + 外部数据网关 | 仅作为可选架构 | 不强制 NAS/PC 常开；KDash 本机完成 OAuth/HTTPS/渲染 |

运行时：

- **LuaJIT 2.1（Lua 5.1 语义）**：模块 `loadfile` + 表接口；单进程；FFI 用于 `poll()` 等待与 evdev 读取。
- **FBInk CLI**：文本/清屏/区域刷新；不链接 FBInk，不依赖 KOReader 进程。
- **evdev**：直接读取 `/dev/input/eventX`，协议 B 多点触控；KPW3 通常为 `event1`。
- **KPM scriptlet + `kpm launch`**：书库入口；不修改 rootfs。
- **curl 子进程**：HTTPS/OAuth；后台脚本 + 完成标记，避免阻塞 UI。

## 3. 分层

```text
┌───────────────────────────────────────────────┐
│ main.lua / core.app                          │
│ lifecycle · scheduler · events · pages       │
├───────────────────────────────────────────────┤
│ ui.renderer / ui.layout / ui.components      │
│ 页眉 / 页脚 / 网格 / 卡片 / 弹窗 / 脏区域    │
├───────────────────────────────────────────────┤
│ modules/*                                     │
│ clock countdown dida weather device notes ...│
│ 只依赖 ctx 与 ui 接口，不互相引用            │
├───────────────────────────────────────────────┤
│ services/http · services/api/*                │
│ 异步 HTTP · Dida365 · Open-Meteo              │
├───────────────────────────────────────────────┤
│ platform/kindle/*                             │
│ display_fbink · touch · device · power · clock│
│ storage · paths · runner                      │
└───────────────────────────────────────────────┘
```

## 4. 生命周期

```text
KPM scriptlet
  └─ kpm launch kdash
       └─ launch.sh → launcher/kdash-launch.sh
            ├─ 单实例锁 / 前置检查（touch、字体、fbink、luajit）
            ├─ stop lab126_gui（或 /etc/init.d/framework stop）
            ├─ 复制 luajit/fbink 到 /var/tmp/kdash-bin（/mnt/us 常为 noexec）
            ├─ set preventScreenSaver 1
            ├─ luajit app/main.lua
            │     ├─ config → cache → registry → renderer → full render
            │     ├─ loop: HTTP poll / scheduler / touch / dirty render
            │     └─ exit → cleanup
            └─ trap EXIT/INT/TERM → start framework → 返回书库首页
```

正常退出与异常退出都走同一个 `cleanup`；`SIGKILL` 无法捕获，此时需要重启设备恢复框架。

## 5. 模块系统

发现：

1. `core.registry` 扫描 `modules/*/module.json`（设备上用 `ls -1`，测试可注入 storage）。
2. 校验 `id/version/api_version`，按 `order` 排序。
3. `loadfile(init.lua)`，`pcall` 执行；`init(ctx)` 失败只标记该模块错误。
4. 启用状态由 `config.modules[id].enabled` 与 manifest `enabled` 共同决定。
5. 每个模块得到独立 `ctx`（共享服务 + 自己的 module_id/manifest）。

模块接口（详见 `docs/MODULE_DEVELOPMENT.md`）：

```lua
init(ctx)                         -- 必需；返回 true
refresh_policy(ctx) -> policy     -- 可选；覆盖 manifest 刷新策略
refresh(ctx) -> true|false|nil     -- true=同步完成；false=异步，稍后 ctx.finish()
render(ctx, ui, rect, opts)       -- 必需；只读数据 + 绘制
shutdown()                        -- 可选
```

隔离：

- `init/render/refresh` 全部 `xpcall` 包裹，异常写日志。
- 渲染异常显示 “MODULE ERROR” 卡片，其他卡片继续渲染。
- 网络失败只影响对应模块；缓存保留，UI 显示离线/过期状态。
- 模块不允许调用系统级电源/框架命令；硬件能力集中在 `platform/`。

## 6. 调度与数据流

```text
module.refresh(ctx)
   ├─ 本地数据：立即更新 state，ctx.request_update()
   └─ 网络数据：ctx.http:request(opts, cb)；返回 false
        cb(ok, body)
          ├─ 解析 → cache:write → ctx.request_update()
          └─ ctx.finish(ok, err) → scheduler success/failure（指数退避）
```

- `core.scheduler` 只依赖注入的时间；到期任务在 3 秒窗口内合并。
- `align="minute"` 对齐到下一分钟；`day` 用固定 UTC 偏移对齐本地零点。
- 失败退避：`interval × 2^failures`，封顶 `max_backoff`。
- 异步超时：app 在 120 秒后判失败；模块仍可稍后完成。
- 内容未变化时模块不调用 `request_update()`，避免无意义 E Ink 刷新。

## 7. UI 与刷新

- `ui.layout` 按页面 `layout[].weight` 分配高度，支持一行两个模块；`min_height` 来自 manifest。
- `ui.renderer` 绘制页眉、页脚、卡片标题与内容；模块只负责卡片内容区。
- 全量渲染：`display:begin_frame(true)` → 清屏 + 全部绘制 → `flush(full=true)`（GC16）。
- 局部渲染：清空单个卡片区域 → 重绘该卡片 → `flush(full=false)`（A2）。
- 脏区域合并：文本/填充的 bbox 收集后按纵向邻近合并；超过 5 个区域时合并为一个大区域。
- 残影控制：每 `power.full_refresh_every` 次局部刷新做一次全屏 GC16；页面切换使用全刷。
- 文字：FBInk OTF (`-t regular=...,px=...,top/left/right/bottom`)；中文/英文同一字体。
- 居中：FBInk `-m`；右对齐由 `ui.text` 计算 x。

**没有实现裁剪（scissor）**：模块必须尊重传入的 `rect`，否则可能画到页脚。现有模块在绘制前检查边界；新增模块需遵守。

## 8. 触摸

- `platform/kindle/touch.lua` 用 FFI `poll()` 等待 fd，再 `read()` 16 字节 `input_event`（32 位 ARM）。
- 解码 `EV_ABS`：`ABS_MT_POSITION_X/Y`、`ABS_MT_TRACKING_ID`；兼容单点 `ABS_X/Y` + `BTN_TOUCH`。
- `SYN_REPORT` 产生一个点；手势层识别 tap（<40px、<900ms）和横向 swipe（>120px）。
- 命中区域在每次渲染时重建；脏渲染会移除该模块旧命中，避免重复触发。
- 触摸坐标不做旋转/缩放，假设 KPW3 竖屏原生坐标系；实机若偏移，需要在 `touch` 层加校准。

## 9. 配置、缓存、凭证

- `config/default.json` 为默认值；`/mnt/us/kdash/config.json` 深合并覆盖（对象递归、数组合并整体替换）。
- `schema_version` 支持迁移函数；当前 v1。
- 原子写：临时文件 + rename；Windows 主机测试先删除目标。
- 缓存：`cache/<name>.json`，含 `fetched_at/error/status`；解析失败视为无缓存，不崩溃。
- 凭证：`secrets.json` 单独文件，chmod 600；不写日志。
- 日志：`logs/kdash.log`，256KB 轮转为 `.1`。

## 10. 安全与系统影响

- 不写 rootfs，不 remount，不修改系统休眠文件。
- 只改变 `com.lab126.powerd preventScreenSaver`；退出时恢复 launcher 保存的原值。
- 只停止/启动 `lab126_gui`；不结束 KOReader 进程，不修改 KOReader 文件。
- 书库入口是 `/mnt/us/documents/KDash.sh` scriptlet；卸载删除该文件。
- 网络凭证最小权限：Dida scope 默认 `tasks:read`；HTTPS 优先使用系统 CA；不默认关闭证书校验。
- 单实例锁 + 前置检查：触摸/字体/运行时缺失时拒绝启动，避免“进入后无法退出”。

## 11. 已知风险（需实机确认）

1. KPM 版本/固件差异导致 `kpm launch` 或 scriptlet 行为不同。
2. `/etc/upstart` 与 `start lab126_gui` 的时序；停止框架后 Wi-Fi/powerd 行为。
3. FBInk 的 OTF 渲染质量、CJK 字重、刷新区域与残影。
4. `curl` 的 TLS/CA 能力；Dida/Open-Meteo 的证书链。
5. 触摸设备路径、坐标方向、手势阈值。
6. `preventScreenSaver` 在不同固件上是否能阻止休眠。
7. `/mnt/us` noexec 与 `/var/tmp` 空间/权限。
