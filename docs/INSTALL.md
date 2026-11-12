> 历史参考：此文档来自 Trae v0.1，不能作为候选版安装／验证状态说明。当前步骤见项目根目录 README.md。

# 安装、升级与卸载

## 0. 前置条件

- KPW3 已越狱，已安装 KPM。
- 已确认设备固件、ABI、触摸设备、FB 尺寸（见 `docs/DEVICE_DIAGNOSTICS.md`）。
- 不需要 KUAL；KDash 不依赖 KOReader。

## 1. 先做只读诊断

```sh
# 把 scripts/kindle-diagnose.sh 复制到 /mnt/us/ 后通过 SSH 运行
sh /mnt/us/kindle-diagnose.sh > /mnt/us/kdash-diagnostics.txt 2>&1
```

重点看：

- `virtual_size`：应为 `1072,1448`
- `/dev/input/event1` 是否存在
- `power_supply` 节点名与 `capacity/status`
- `curl`、CA、`lipc-*`、`fbink`、`sqlite3`
- upstart / sysv、`pidof cvm`
- `/mnt/us` 是否 noexec
- `/usr/java/lib/fonts`

安装后也可点击 **KDash Diagnostics** scriptlet 生成同一报告。

## 2. 构建

```sh
python scripts/build_package.py
```

产物：

```text
build/kdash_0.1.0_kindlepw2.kpkg
```

构建脚本会校验 `manifest.json`、`runtime/luajit`、`runtime/fbink`、字体、launcher 是否存在。
包是 KPM manifest v2 的 tar.gz。

## 3. KPM 安装（推荐）

1. 将 `.kpkg` 加入 KPM 软件源，或使用当前 KPM 版本支持的本地安装方式。
2. KPM 解包后执行 `install.sh`（包目录内）：
   - 创建 `/mnt/us/kdash/{cache,logs,state,assets}`
   - 首次安装复制默认配置与空 secrets
   - 复制字体/封面
   - 写 `/mnt/us/documents/KDash.sh` 与诊断 scriptlet
3. 触发书库扫描：

```sh
lipc-set-prop com.lab126.scanner reScanFile /mnt/us/documents/KDash.sh
```

4. 书库出现 **Kindle Dashboard**，点击进入。

> KPM 的本地安装 UI 随版本不同。如果找不到入口，使用手动安装；KDash 本身不依赖 KPM 运行。

## 4. 手动安装（不依赖 KPM 启动）

1. 在 PC 上把 `.kpkg` 改名为 `.tar.gz` 并解压。
2. 在 Kindle USB 根目录创建：

```text
/mnt/us/kdash/pkg/      # 放解压后的 manifest.json、app/、launcher/、runtime/...
```

3. SSH 执行：

```sh
sh /mnt/us/kdash/pkg/install.sh          # 初始化数据目录/字体（会尝试写 scriptlet）
chmod 755 /mnt/us/kdash/pkg/launcher/kdash-launch.sh
mkdir -p /mnt/us/kdash/assets
cp /mnt/us/kdash/pkg/app/assets/cover.png /mnt/us/kdash/assets/cover.png
cat > /mnt/us/documents/KDash.sh <<'EOF'
#!/bin/sh
# Name: Kindle Dashboard
# Author: KDash
# Icon: /mnt/us/kdash/assets/cover.png
# DontUseFBInk
exec /bin/sh /mnt/us/kdash/pkg/launcher/kdash-launch.sh
EOF
chmod 755 /mnt/us/documents/KDash.sh
lipc-set-prop com.lab126.scanner reScanFile /mnt/us/documents/KDash.sh
```

4. 点击书库条目。

手动模式下不要运行 `kpm launch`；入口直接执行 launcher。

## 5. 首次运行

启动时 launcher 会：

1. 检查 touch/字体/fbink/luajit；缺失则拒绝启动，避免“进入后无法退出”。
2. 获取单实例锁。
3. 停止 `lab126_gui`（或 sysv framework）。
4. 把二进制复制到 `/var/tmp/kdash-bin`（`/mnt/us` 常为 noexec）。
5. 启动 `luajit app/main.lua`。
6. 退出（正常/异常）时重启框架并回到书库首页。

如果首次启动黑屏：

```sh
cat /mnt/us/kdash/logs/kdash.log
cat /mnt/us/kdash-diagnostics.txt
```

## 6. 退出

- 界面右上角 **X** → **EXIT**。
- launcher 恢复框架并返回书库。
- 如果框架没有恢复：长按电源重启；或 SSH 执行：

```sh
cd / && start lab126_gui          # upstart
# 或
/etc/init.d/framework start       # sysv
```

- 不要 `kill -9` launcher；它会跳过恢复（SIGKILL 不可捕获）。

## 7. 升级

KPM 升级流程：

1. `uninstall.sh upgrade`（保留 scriptlet 与数据）
2. 删除旧包文件
3. 解包新包
4. `install.sh upgrade`

KDash 保留：

- `/mnt/us/kdash/config.json`
- `/mnt/us/kdash/secrets.json`
- 倒计时事件（在 config 内）
- 模块配置
- 缓存（可重建）

`config.schema_version` 变化时由 `core/config.lua` 的迁移函数升级。

手动升级：替换 `/mnt/us/kdash/pkg/` 内容，保留 `/mnt/us/kdash/*.json`，重新执行 `install.sh`。

## 8. 卸载

KPM 卸载会执行 `uninstall.sh`：

- 删除 `/mnt/us/documents/KDash.sh`
- 删除 `/mnt/us/documents/KDash Diagnostics.sh`
- 删除 `/var/tmp/kdash-bin`
- 删除运行锁
- **保留** `/mnt/us/kdash`（配置/缓存/凭证）

彻底清理：

```sh
rm -rf /mnt/us/kdash
```

不影响 KOReader、KPM 或原版系统。

## 9. 恢复与故障

| 现象 | 处理 |
|---|---|
| 书库没有条目 | 重新扫描；检查 scriptlet 是否在 `/mnt/us/documents/KDash.sh` |
| 点击无反应 | 检查 KPM 路径 `/var/local/kmc/bin/kpm`；查看 `logs/kdash.log` |
| 黑屏/冻结 | 长按电源重启；框架开机恢复 |
| 退出后仍在 KDash | 等待 launcher 重启框架；SSH `start lab126_gui` |
| 触摸无效 | 检查 `/dev/input/event1`；launcher 会拒绝启动 |
| 中文方块 | 检查字体路径/包内字体是否存在 |
| 网络模块一直离线 | 检查 `curl --version`、CA、Wi-Fi；查看日志 |

更多见 `docs/TROUBLESHOOTING.md`。

## 10. 验收时必须记录

- 设备型号、固件版本、`/etc/prettyversion.txt`
- `kdash-diagnostics.txt`
- `/mnt/us/kdash/logs/kdash.log`
- 启动/退出是否恢复书库
- 触摸是否准确（尤其右上角 X）
- 局部刷新与残影
- Wi-Fi 在休眠/唤醒后的状态
- KOReader 是否仍可正常启动

没有这些证据，不应宣称实机通过。
