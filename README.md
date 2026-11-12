# KDash — Kindle Paperwhite 信息面板

KDash 是一个从 Kindle 原版书库启动的独立墨水屏信息面板。首页显示时间、日期、事件倒计时、今日待办、天气和电池；支持触控退出、手动刷新、物理电源键息屏与唤醒。它与 KOReader 平行使用，不依赖 KUAL。

## 状态和兼容性

- 维护基线：R19，LuaJIT + FreeType + framebuffer/FBInk。原设备测试过 KPW3、固件 5.16.2.1.1 的启动、退出恢复、电源休眠唤醒和滴答同步。
- 此公开副本为了保护隐私，替换了个人化名称、事件、坐标和壁纸；**不是设备上经过测试的逐字节原版**，公开版打包后尚未经过 Kindle 实机测试。其他固件、硬件及长时间运行需要另外验证。
- 需要已越狱且支持原版书库 Scriptlet 的设备；仅越狱本身不保证 Scriptlet 可用。不会安装或修改 KOReader。
- 不包含番茄ToDo 同步、番茄钟或专注统计服务。

## 快速开始

1. 先阅读 [安装和回退](docs/INSTALL.md)，确认设备、备份及数据保留要求。
2. 从 Releases 下载 USB 安装包；若尚无 Release，可按 [构建指南](docs/BUILD.md) 从源码生成。解压后将 `documents` 和 `kdash-candidate` 按教程复制到 Kindle USB 存储根目录。
3. 安全弹出后从原版书库打开 `Kindle Dashboard Candidate`。遇到恢复问题可使用同包的 Recovery 和 Diagnostics 条目。
4. 在电脑运行 [配置工具](pc_tool/README.md)，设置事件、天气城市/经纬度、刷新周期和滴答清单授权。首次安装的日期只是示例，请自行修改。
5. 原版书库中点击退出回到 Kindle；短按电源键休眠，再次短按唤醒。公网 API、写入任务和不同固件需要自行验证。

完整教程：[使用与配置](docs/USAGE.md) · [故障排查](docs/TROUBLESHOOTING.md) · [构建与测试](docs/BUILD.md) · [模块开发](docs/MODULE_DEVELOPMENT.md)。

## 隐私与凭据

`config.json` 保存本地偏好；`secrets.json` 保存令牌和密钥；`cache/`、`state/`、`logs/`、配置备份和壁纸可能包含个人信息，不应上传或贴到公开 issue。公开仓库只含示例配置。配置工具在当前 Windows 用户环境中加密新密钥备份；不要依赖它代替独立、安全的备份。

## 仓库结构

- `main.lua`、`core/`、`modules/`、`services/`、`platform/`、`ui/`：设备程序及模块。
- `launcher/`：原版书库入口、诊断、恢复和会话管理脚本。
- `pc_tool/`：Windows 配置工具源码、打包脚本和测试。
- `scripts/`、`tests/`：构建、资源生成与主机测试。
- `assets/`、`screensaver/`、`vendor/`：字体与图形、通用空白屏保、设备运行依赖及其许可证。

项目代码见 [MIT License](LICENSE)；第三方字体和运行时按各自目录中的许可证分发。图形资源的使用遵循项目贡献者所提供的授权范围。

## 历史版本

查看 [版本演进与历史源码](docs/HISTORY.md)，包括 R13—R19 的隐私清理源码标签，以及 R2—R12 留存的部分代码片段。历史版本用于回顾，不应直接作为未经验证的回退包。
