# r16 USB 候选安装与回退

本轮只交付本地候选，没有写入 Kindle。首次部署前仍应确认实际盘符和替换清单。以设备 system/version.txt、documents 和 Kindle USB 标识为准，不能假定永远是 K:。

1. 先让当前 KDash 正常退出，确认已回原版界面，再连接 USB。`session-limit=0` 不能靠“等待三分钟”代替退出。
2. 完整备份 Kindle 的 `kdash-candidate/package`、三个书库 Scriptlet 和 `kdash-candidate/screensaver`；配置/密钥另作私密备份，不上传。
3. 在电脑解压 USB 包到新目录。核对 manifest.json 的文件及 SHA-256。建议把完整 package 先复制为 `kdash-candidate/package-r16-staged`，逐文件核对后把旧 package 改名 `package-before-r16-日期`，再将 staged 改名 package。不要直接覆盖正在运行的目录。
4. 更新 documents 中同名的 `Kindle Dashboard Candidate.sh`、`KDash Candidate Recovery.sh`、`KDash Candidate Diagnostics.sh`。应用仍是同一个书库条目；若 Kindle 显示旧封面缓存，须另查书库注册机制，不重新安装 KUAL。
5. 核对 `kdash-candidate/screensaver/wallpaper.y8` 为 1,552,256 字节；本轮壁纸内容不变，已有文件哈希相同不需要替换。wallpaper.ttf 是旧路径兼容资源。首次安装可复制包中两者。
6. **保留已有根目录 config.json、secrets.json、cache、state、logs**。根 config 是默认模板，覆盖会丢失事件、刷新周期、城市/经纬度和清单选择。不要动 KOReader、微信读书或系统文件。
7. 安全弹出 USB，在 Kindle 原版书库点 `Kindle Dashboard Candidate`。

新 package 内包括 app、runtime、launcher、session-limit。launcher 新增 `command-timeout.sh`、`power-monitor.sh`，不能只挑 Lua 文件升级。运行时仍拷贝到独立 `/var/tmp/kdash-candidate/run.*`；升级的 ELF 与 r15 相同，不因主机测试成功而推定新的 ARM ABI 兼容。

## 本次实机测试顺序

1. 打开一次，检查同屏布局、标签/时间框和右侧优先级；不勾选真实任务作破坏性试验。
2. 短按电源键：应显示给定壁纸；停留超过一个显示周期，确认无界面叠画；再短按一次，回面板且只有一次唤醒重绘。重复 5 次，记录是否有额外闪屏或延迟。
3. 手动刷新一次；确认可退出且返回原版。退出后等待原版完全恢复，再打开；再做一次“退出后立即打开”，用于区分锁等待与启动耗时。
4. 收集 `kdash-candidate/logs/session.log`（`launch_requested`、`session_begin ... lock_wait_ticks`、`app_start`、`app_exit rc`、`restore_begin/done`）及 `kdash.log`（电源、刷新、同步代码）。日志对外分享前删去账号、任务私密内容和令牌；本版主动日志不输出令牌。
5. 最后做长时间静置与电池/前光观察；主机千帧测试不代表 24～72 小时实机稳定性或续航。

## 回退

先退出 r16 并连接 USB。将新 package 改名保留，将完整的 `package-before-r16-日期` 改回 package；恢复备份的三个 documents Scriptlet。只有壁纸实际换过才恢复壁纸。config、secrets、cache、state 保持，勿用新安装模板覆盖。安全弹出，再从书库启动旧版。

## 配置工具保存中断

普通打开/读取不会自动恢复或写入 Kindle。发现 `.kdash-save.pending` 时，先保持 USB 连接，在新版配置工具点击“恢复未完成保存”，选择配置所在目录并确认回退上次未完成保存，再重新读取。恢复失败要保留 pending 文件，不要手动删除后继续启动：设备端会拒绝读取半套配置。

单个文件用原子替换，但 FAT/USB 不能实现两个文件同时提交；中断可能留下新旧混合，依靠 journal 回退，不承诺拔盘瞬间两者永远同版。DPAPI 密钥备份只可由原 Windows 用户解密；“读取备份”只是载入表单，点击保存后才写当前目标。旧版明文备份不自动删除。
