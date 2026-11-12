# Windows 配置工具

源码运行：`python pc_tool/configurator.py`。使用 Release 中的 `KDash-Config.exe` 可无需安装 Python；也可以安装 `requirements-build.txt` 并运行 `python pc_tool/build_windows.py` 自行构建。

连接 Kindle 并选择 USB 根目录的 `kdash-candidate/config.json`。读取是只读操作；点击保存才会写入所选配置和同目录 `secrets.json`。配置与密钥备份在工具目录的 `config-backups/`，新密钥备份使用当前 Windows 用户的 DPAPI 加密。备份仍属于私密数据，不要公开。

滴答清单与高德凭据在界面中填写，不写入源码。只在授权范围内操作真实任务。功能和刷新周期说明见 [使用教程](../docs/USAGE.md)。
