# Windows 配置工具

双击交付目录 KDash-Config.exe，无需安装 Python。

源码运行：`python pc_tool/configurator.py`。模型测试：`python pc_tool/test_model.py`。构建前安装 requirements-build.txt，运行 `python pc_tool/build_windows.py`。

只读启动，用户点击保存才写所选配置与同目录 secrets.json。备份存于 EXE 同目录的 config-backups。滴答／高德实际凭据请在界面中填写，不写入源码。

接口测试使用模拟响应；OAuth callback 用本地回环和随机 state 测试，不代表真实 Dida365 授权已成功。
