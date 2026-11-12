> 历史参考：此文档来自 Trae v0.1，不能作为候选版安装／验证状态说明。当前步骤见项目根目录 README.md。

# 设备诊断（Phase 0）

在写任何“实机通过”的结论前，先完成只读诊断。KDash 不假设固件版本、ABI、图形环境或可用命令。

## 1. 运行方式

方式 A：SSH

```sh
cp /mnt/us/kindle-dashboard/scripts/kindle-diagnose.sh /mnt/us/
sh /mnt/us/kindle-diagnose.sh > /mnt/us/kdash-diagnostics.txt 2>&1
```

方式 B：安装后点击书库 **KDash Diagnostics** scriptlet，报告写到：

```text
/mnt/us/kdash-diagnostics.txt
```

脚本只读；除报告文件外不修改系统。

## 2. 报告重点

| 项目 | 期望/判断 |
|---|---|
| `/etc/prettyversion.txt` | 记录实际固件；不要猜 |
| `uname -a` | ARMv7 / 内核版本；确认 armhf |
| `virtual_size` | `1072,1448`；不是则布局/坐标需调整 |
| `bits_per_pixel` | 通常 8/16；FBInk 会处理 |
| `/dev/input/event1` | KPW3 常见触摸设备；以实际 `input/devices` 为准 |
| `power_supply/*` | 记录 battery 节点名、`capacity/status/charging` |
| `lipc-get-prop ... battLevel` | 验证 LIPC 降级路径 |
| `pidof cvm` | 框架是否运行；launcher 启动前要求存在 |
| `/etc/upstart` | upstart 或 sysv |
| `/mnt/us` mount | 是否 noexec；运行时必须复制二进制到 `/var/tmp` |
| `curl --version` | 是否有 TLS、支持的协议 |
| CA 路径 | `/etc/ssl/certs/...` 是否存在 |
| `/usr/java/lib/fonts` | 备用字体；KDash 自带字体不依赖它 |
| `free` / `df` | 内存与存储余量 |
| `kpm` | `/var/local/kmc/bin/kpm` 是否存在 |
| `fbink` | 是否已有可执行（KDash 自带） |

## 3. 决策门

在以下问题回答前，不进入实机安装：

1. 设备是否 armhf、内核/glibc 能否运行 KOReader 同款 LuaJIT/FBInk？
2. `/mnt/us` 是否 noexec？`/var/tmp` 是否有足够空间？
3. 触摸设备路径与坐标方向是否明确？
4. 框架是 upstart 还是 sysv？`start lab126_gui` 是否可用？
5. `curl` 是否支持 HTTPS 与系统 CA？
6. `preventScreenSaver` 是否可读写？原值是多少？
7. 电池节点名称是什么？LIPC `battLevel` 是否有效？
8. KPM 版本与 `kpm launch` 路径是否可用？

## 4. 需要在实机确认的验收项

- 书库出现 KDash，点击可进入（不需要 KOReader/KUAL/SSH）。
- 右上角 X 可退出，返回书库；KOReader 仍可独立启动。
- launcher 异常退出后框架恢复。
- 触摸坐标与命中区域一致（尤其 X、底部导航）。
- 中文/英文渲染正常；大字号不溢出。
- 局部刷新残影可接受；全刷不频繁闪烁。
- 天气/Dida 联网、缓存、断网状态正确。
- 休眠/唤醒后的屏幕、CPU、Wi-Fi 行为记录。
- 升级保留配置/倒计时/Token；卸载不影响 KOReader。

## 5. 记录模板

```text
Model:
Firmware:
Kernel:
Init:
Touch device:
FB:
Battery node:
LIPC battLevel:
curl/TLS/CA:
KPM version:
KDash package:
Test time:
Steps:
Observed:
Logs attached: yes/no
```

没有这些证据时，只能写“主机侧通过 / 实机未验证”。
