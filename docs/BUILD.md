# 构建与测试

公开源码是基于 R19 的隐私清理副本；构建产物与设备上实测的原版不逐字节相同。

## 环境

Windows 或 Linux：Python 3、LuaJIT、Git Bash 或兼容 POSIX shell；Windows 配置工具需要 Tkinter。生成壁纸需要 Pillow 和 fontTools；生成 Windows EXE 需要 PyInstaller。`vendor/` 中的 ARM 可执行程序和动态库用于 Kindle，不是本机原生依赖；相关许可见 `vendor/THIRD_PARTY.md`。

## 主机测试

从源码根目录执行：

```powershell
luajit tests/run.lua
python -m unittest discover -s pc_tool -p "test*.py"
python tests/test_wallpaper.py
python tests/run_host.py
```

`tests/run_host.py` 还会执行 shell 和 HTTP 模拟测试；主机缺少的组件会导致相应测试失败。原生绘制测试需要使用本机平台的 FreeType 动态库并传入 `--freetype`；没有该参数时显示跳过。不要把跳过或主机模拟算作 Kindle 实测。

## USB 包

```powershell
python scripts/build_package.py
```

脚本在项目父目录生成 `KDash-0.1.1-candidate1-USB.zip`、校验文件和临时构建目录；它会删除并重建项目父目录中名为 `KDash-USB-candidate` 的目录，请在独立源码目录构建，不要把个人文件放在那里。安装前阅读 [安装教程](INSTALL.md)。

## Windows 配置工具

安装 `pc_tool/requirements-build.txt` 后执行：

```powershell
python pc_tool/build_windows.py
```

输出在源码父目录。可用 `KDash-Config.exe --self-test-report <临时路径>` 运行工具自检；自检和真实设备操作属于不同验证。脚本也会在父目录生成构建工作文件。
