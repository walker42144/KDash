# r16 主机验证与实机边界

从源码根目录运行（LuaJIT、Python 3、Git Bash/sh、curl 在 PATH）：

```powershell
python tests/run_host.py --freetype '你的主机 FreeType 动态库绝对路径' --soak-frames 1000
```

不提供 --freetype 会明确 SKIP 原生绘制及压力测试，不应记为原生通过。Windows DLL 与 Kindle ARM .so 不能互换。例：本机已准备的主机 DLL 为工作区 `work/toolchains/freetype/freetype/libfreetype.dll`；这不是源码包自带的通用主机依赖。

入口包含 Lua 回归、PC 模型、启动锁/恢复/电源 Shell 模拟、新故障回归、真实本机 curl HTTP 假服务、可选真实 FreeType + native canvas。后者只替换最终 framebuffer sink 与 FBInk runner，不操作 /dev/fb0；检查 GC16、真实 diff 包围盒、重试、壁纸/文字兜底、内存拷贝哨兵。旧 display_fbink 的测试仍保留，但不是生产显示验证。

`tests/soak_native.lua` 放入源码，1000 次局部重绘用自然 GC、固定多页非极简页脚，检查 hit 数量；再加载4000个字形。它不是连续运行1000分钟，也不证明真实 RAM、文件描述符、僵尸进程或电量。可另用系统工具观测 RSS，主机结果不能折算为 KPW3 占用。

Shell 模拟使用假 PID/进程状态与压缩等待；不能据此判断实机恢复等待耗时、powerd 属性语义或 BusyBox 的进程组行为。command-timeout 的 Windows Shell 实测为单 PID 模式，设备使用 setsid 进程组，需要实机复测。

可选壁纸生成回归需 Pillow、fontTools：`python tests/test_wallpaper.py`。所有 launcher 脚本应在交付前运行 sh -n，USB 包必须是 LF 无 BOM。

打包：`python scripts/build_package.py`。其缺失资源测试应在临时源码副本中进行，不能移走用户原文件。源码包附带的是既有 ARM ELF；本轮没有 Go 编译，也没有重新编译 LuaJIT/FBInk/FreeType。

Windows EXE 构建：`python pc_tool/build_windows.py`（需要 PyInstaller）。可运行 `KDash-Config-r16.exe --self-test-report 电脑上的结果路径.json`：只创建临时假配置、隐藏 widgets、检查资源与加密备份，不扫描 USB、不访问个人服务。

本轮实跑数量与最后产物哈希见交付目录 `review-evidence/r16-validation.json`、`r16-host-validation.txt`。实机电源/退出恢复验收尚未进行。
