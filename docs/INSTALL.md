# USB 安装与回退

## 条件

适用基础：已越狱的 KPW3，原版系统已支持书库 Scriptlet，能通过 USB 访问 `documents`。已知设备基线是固件 5.16.2.1.1；不承诺其他固件兼容。本公开构建使用通用名称、示例配置和空白壁纸，尚未在设备上验证。请先自行保存现有系统与用户数据的备份。

## 首次安装

1. 从 [构建指南](BUILD.md) 生成 USB ZIP，或下载项目 Release。先在电脑解压到一个空目录，检查压缩包和 `manifest.json`。
2. Kindle 连接电脑并处于 USB 驱动器模式，确认盘符实际属于 Kindle。不要假定任何固定盘符。
3. 将解压包内 `documents/` 和 `kdash-candidate/` 合并复制到 Kindle 存储根目录。首次安装前先检查是否已有同名文件，避免覆盖其他内容。
4. 首次安装根目录 `kdash-candidate/config.json` 为示例。后续用电脑配置工具设置事件、天气、授权和刷新时间。密钥写入设备的 `kdash-candidate/secrets.json`，不应公开。
5. 安全弹出设备，等待原版书库刷新，点击 `Kindle Dashboard Candidate`。首次可能需等待数秒。右上角退出并等待系统界面完全恢复。

## 已安装版本的更新

先退出 KDash 并确认回到原版界面，再连接 USB。私下备份 `kdash-candidate/package/`、`screensaver/`、`config.json`、`secrets.json` 和三个 KDash 书库入口；不要分享包含密钥的备份。先把新 `package` 放到另一个目录并核对哈希，备份旧版后再切换。只有你明确选择换壁纸时才替换壁纸；**不要用新包里的默认 `config.json` 覆盖既有配置，也不要覆盖 `secrets.json`、`cache/`、`state/` 或其他应用文件**。

## 回退和恢复

退出应用、连接 USB，将当前 `package` 保留为另一个名称，恢复你的旧 `package` 和备份的书库入口。配置及私密数据保留；仅在确实更换壁纸后恢复其备份。安全弹出并测试书库入口。本教程不等于所有固件上的回退已实测。

如果界面未正常恢复，使用书库中的 `KDash Candidate Recovery` 并等待完成；`KDash Candidate Diagnostics` 会生成诊断信息。分享日志前请检查并删除任务内容、账号和密钥。无法操作时不要反复启动或盲目替换系统文件。
