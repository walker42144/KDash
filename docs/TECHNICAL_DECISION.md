> 历史参考：此文档来自 Trae v0.1，不能作为候选版安装／验证状态说明。当前步骤见项目根目录 README.md。

# 技术决策记录（Phase 0）

日期：2026-11-11
状态：**已选定并实现 v0.1；设备侧待验证**

## 1. 目标约束

- KPW3（armhf，1072×1448，300 PPI，触摸）上独立运行
- 书库入口，不依赖 KOReader/KUAL，不修改 rootfs
- 模块可插拔，新增功能不改核心
- 低内存、低功耗、长期运行
- 中英文清晰，E Ink 局部刷新
- 不承诺硬件无法实现的后台刷新

## 2. 候选方案

### A. 原生应用 + Lua UI + FBInk（选定）

- 运行时：LuaJIT 2.1（Lua 5.1），单进程。
- 绘制：FBInk CLI，OTF/TTF 文本 + 区域刷新。
- 输入：直接读 evdev。
- 启动：KPM scriptlet → launcher。
- 优点：模块加载简单、内存低、迭代快；KOReader 已验证 LuaJIT/FBInk 在 Kindle 上可行。
- 缺点：FBInk 进程调用开销、无裁剪、LuaJIT 需要我们自带运行时。

### B. C/C++ + FBInk

- 优点：性能/内存最可控。
- 缺点：模块动态加载、配置/JSON/网络/UI 开发成本高；v0.1 不需要。
- 结论：保留为未来性能敏感模块（如图片/复杂排版）的选项。

### C. Kindle WebKit / Mesquite

- 优点：HTML/CSS 开发快，原生标题栏/X。
- 缺点：内存/CPU 高、启动依赖框架、WebKit 版本/兼容性不可控、与低功耗目标冲突。
- 结论：不采用。

### D. 本机客户端 + 外部数据网关

- 优点：可在 NAS 渲染 PNG/OAuth。
- 缺点：强制外部服务常开，违背“本地优先、不强制 NAS/PC”。
- 结论：不作为默认；KDash 本机完成 OAuth/HTTPS/渲染。

## 3. 关键决策

| 决策 | 选择 | 理由 |
|---|---|---|
| 语言/运行时 | LuaJIT 2.1 | 动态模块、低内存、KPW3 先例；自带二进制避免依赖 KOReader |
| UI | FBInk OTF | 成熟、支持区域刷新、无需自写字体栅格化 |
| 输入 | evdev + FFI poll | 无 fork 等待、精确手势、避免 busy loop |
| 启动 | KPM scriptlet + `kpm launch` | 官方推荐路径；书库条目；不写 rootfs |
| 退出 | launcher trap + start framework | 正常/异常都恢复；互斥前台会话 |
| 网络 | 后台 curl + 完成标记 | 不阻塞 UI；复用系统 TLS/CA |
| 数据 | 本地缓存 + 异步刷新 | 启动即显示；离线可用 |
| 模块 | manifest + init.lua + 表接口 | 新目录即可扩展；核心隔离错误 |
| 配置 | JSON 深合并 + schema 迁移 | 可读、可持久化、升级保留 |

## 4. 调研依据

- KPM 包：manifest v2 + `install.sh/launch.sh/uninstall.sh`；`.kpkg` 是 tar.gz；scriptlet 放 `/mnt/us/documents`，推荐 `kpm launch`。
- Kindle Scriptlets：`.sh` + `# Name:`/`# Icon:`/`# DontUseFBInk` 元数据；书库索引。
- KOReader `koreader.sh`：`stop lab126_gui` / `start lab126_gui`、`preventScreenSaver`、输出日志、trap 清理；KDash 只借鉴启停模式，不调用 KOReader。
- FBInk CLI：`-t regular=...,px=...,top/left/right/bottom`、`-m` 居中、`-k` 区域清屏、`-s` 区域刷新、`-W A2/GC16`、`-b` 批量不刷新。
- KPW3：触摸 `/dev/input/event1`；电池候选 `max77696-battery` / `max77796-battery` 等，另有 LIPC `battLevel` 降级。
- Dida365：官方 OAuth2 + `GET /open/v1/project` + `GET /open/v1/project/{id}/data`；只读。
- Open-Meteo：无需 Key；current+daily 字段；时区参数。

## 5. 运行时二进制

- `vendor/luajit`、`vendor/fbink` 来自公开 KOReader v2026.07.1 `kindlepw2` 包，作为通用运行时打包。
- KDash 不加载 KOReader 代码，不依赖其安装路径。
- SHA-256、许可证、源码链接、GPL 源提供方式见 `vendor/THIRD_PARTY.md`。
- 可替换：`runtime/luajit`、`runtime/fbink`。

## 6. 后果与风险

正面：

- 模块开发只需 Lua；配置/缓存/网络/UI 分层清晰。
- 单进程、无 WebKit、无 rootfs 修改。
- 启动/退出有明确恢复路径。

风险：

- KPM/固件差异；KPM 本地安装入口不确定。
- FBInk OTF/CJK 在 KPW3 的实际效果。
- 框架停止后 Wi-Fi/powerd 行为未知。
- `curl` TLS/CA、Dida OAuth 真实环境。
- 触摸坐标/刷新残影需调参。
- `SIGKILL`/断电无法 trap，需重启恢复。

## 7. 未决问题（需实机）

1. KPW3 固件是否使用 upstart，`start lab126_gui` 是否可靠？
2. 停止框架后 Wi-Fi 是否保持？休眠后是否自动重连？
3. `preventScreenSaver=1` 能否阻止休眠？电池策略的实际效果？
4. FBInk `-t` 的垂直定位/行高与 Droid Sans Fallback 的匹配？
5. 局部刷新 A2 的残影程度与全刷频率？
6. `curl` 是否带 CA、是否支持 TLS1.2？
7. KPM 版本是否支持本地 `.kpkg` 安装？

这些问题不阻塞代码交付，但决定 v0.2 的调参与兼容层。
