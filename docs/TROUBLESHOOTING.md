> 历史参考：此文档来自 Trae v0.1，不能作为候选版安装／验证状态说明。当前步骤见项目根目录 README.md。

# 故障排查

先收集：

```sh
cat /mnt/us/kdash/logs/kdash.log
cat /mnt/us/kdash-diagnostics.txt
```

## 1. 书库没有 Kindle Dashboard

- 确认文件存在：

```sh
ls -l /mnt/us/documents/KDash.sh
```

- 触发扫描：

```sh
lipc-set-prop com.lab126.scanner reScanFile /mnt/us/documents/KDash.sh
```

- USB 弹出后通常会自动索引；如果仍没有，断开/重连 USB 或重启。
- 检查 scriptlet 前 5 行元数据是否完整（`# Name:`、`# Icon:`、`# DontUseFBInk`）。
- 封面路径 `/mnt/us/kdash/assets/cover.png` 必须存在且可读。

## 2. 点击条目无反应 / 回到书库

- 检查 KPM：

```sh
ls -l /var/local/kmc/bin/kpm
/var/local/kmc/bin/kpm launch kdash
```

- 查看日志：

```sh
tail -100 /mnt/us/kdash/logs/kdash.log
```

- 可能原因：KPM 未安装/路径不同、包未注册、launcher 前置检查失败（字体/fbink/touch）。
- 手动安装模式入口不经过 KPM；确认 scriptlet 指向 `/mnt/us/kdash/pkg/launcher/kdash-launch.sh`。

## 3. 启动后黑屏 / 冻结

- 先长按电源重启（框架开机恢复）。
- 查看日志中的最后一行：

```sh
tail -50 /mnt/us/kdash/logs/kdash.log
```

- 常见：
  - `missing fbink runtime` / `missing luajit runtime`：包不完整。
  - `missing CJK font`：`app/assets/fonts/DroidSansFallbackFull.ttf` 缺失。
  - `no touch device`：`/dev/input/event1` 不存在；不要强行启动。
  - `luajit cannot execute`：ABI/动态库不匹配；运行诊断确认设备。
- 如果 launcher 停了框架但 app 没起来，launcher 会尝试恢复；若没有，SSH：

```sh
cd / && start lab126_gui
```

## 4. 退出后仍停在 KDash / 框架没恢复

```sh
pidof cvm
cd / && start lab126_gui
# sysv:
/etc/init.d/framework start
```

- 检查 launcher 是否被 `kill -9`；SIGKILL 无法触发 trap。
- 重启设备是最可靠的恢复方式。

## 5. 触摸不准 / 无法退出

- `docs/DEVICE_DIAGNOSTICS.md` 确认触摸设备路径与名称。
- KPW3 通常是 `/dev/input/event1`；如果实际不同，修改 `platform/kindle/touch.lua` 的候选路径或 `Touch:find_device()`。
- 坐标方向不对：触摸层未做旋转/缩放；KPW3 竖屏原生坐标应一致，但需实机验证。
- 右上角 X 的命中区比视觉框大 24px；如果仍难点击，可在 `ui/renderer.lua` 增大。
- 启动前 launcher 会拒绝无触摸设备，避免无法退出。

## 6. 中文显示为方块 / 乱码

- 确认字体：

```sh
ls -l /mnt/us/kdash/assets/DroidSansFallbackFull.ttf
ls -l /var/tmp/kdash-bin/fbink
```

- `config.json` 的 `ui.font` 若指定了错误路径，会覆盖自动探测；清空后重试。
- FBInk 需要编译 OpenType 支持；当前运行时来自 KOReader 的 FBInk build，已包含 `--truetype`。

## 7. 天气/滴答清单一直离线

- 检查网络：

```sh
cat /sys/class/net/wlan0/operstate
ip addr show wlan0
curl -I https://api.open-meteo.com
```

- 检查 `curl` 与 CA：

```sh
curl --version
ls /etc/ssl/certs/ca-certificates.crt
```

- 查看日志中的 `http failed`：
  - `curl rc=6`：DNS 失败
  - `curl rc=7`：连接失败
  - `curl rc=60`：证书校验失败（检查 CA/时间）
  - `http=401`：Dida token 失效
- 离线时 UI 保留缓存；不会清空任务。

## 8. 滴答清单 AUTH REQUIRED

- 在电脑重新运行：

```sh
python tools/dida_auth.py --client-id ... --client-secret ... --out secrets.json
```

- 覆盖 `/mnt/us/kdash/secrets.json`，`chmod 600`。
- 确认 Dida 应用的回调地址与 `--redirect-uri` 完全一致。
- 设备端刷新失败会保留旧 access_token/refresh_token；不要手动清空缓存。
- scope 至少 `tasks:read`；写权限不是 v0.1 所需。

## 9. 刷新残影严重

- 降低 `power.full_refresh_every`（例如 10）。
- 检查是否频繁全屏清屏/重绘；页面切换才会全刷。
- E Ink 在低温/高对比文字下更容易残影；可接受范围内调参。

## 10. 升级后配置丢失

- 升级不应删除 `/mnt/us/kdash/config.json`。
- 如果 KPM 升级走了完整卸载流程，检查 `uninstall.sh` 是否被手动修改。
- `schema_version` 高于程序版本时，`Config.load` 会报错；回滚配置或升级程序。

## 11. 卸载后仍有条目

- 手动删除：

```sh
rm -f /mnt/us/documents/KDash.sh "/mnt/us/documents/KDash Diagnostics.sh"
lipc-set-prop com.lab126.scanner reScanFile /mnt/us/documents 2>/dev/null
```

- 重启后书库会刷新。

## 12. 需要提交哪些信息

- `kdash-diagnostics.txt`
- `logs/kdash.log`（最近 200 行）
- 设备型号/固件
- 复现步骤与屏幕照片
- 是否安装 KPM/KOReader、KPM 版本
- `runtime/luajit`、`runtime/fbink` 的 SHA-256（诊断脚本会尝试输出）
