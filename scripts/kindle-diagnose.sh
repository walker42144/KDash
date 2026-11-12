#!/bin/sh
# KDash 只读设备诊断。输出到 stdout；不修改系统状态。
# 在 Kindle 上通过 SSH 运行：sh /mnt/us/kdash/diagnose.sh
set -u

section() {
    echo
    echo "===== $* ====="
}

safe() {
    "$@" 2>&1 || true
}

echo "KDash diagnostics"
echo "generated: $(date 2>/dev/null || echo unknown)"

section "identity"
safe cat /etc/prettyversion.txt
safe cat /etc/version.txt
safe cat /proc/device-tree/model
safe uname -a
safe uptime

section "init / framework"
[ -d /etc/upstart ] && echo "upstart: yes" || echo "upstart: no"
[ -x /etc/init.d/framework ] && echo "sysv framework: yes" || echo "sysv framework: no"
safe pidof cvm
safe lipc-get-prop com.lab126.appmgrd getActiveApp

section "display"
safe cat /sys/class/graphics/fb0/virtual_size
safe cat /sys/class/graphics/fb0/bits_per_pixel
safe cat /sys/class/graphics/fb0/stride
safe ls -l /dev/fb0

section "input"
safe ls -l /dev/input/
safe cat /proc/bus/input/devices

section "power / battery"
for d in /sys/class/power_supply/*; do
    [ -e "$d" ] || continue
    echo "-- $d"
    safe cat "$d/name"
    safe cat "$d/capacity"
    safe cat "$d/status"
    safe cat "$d/charging"
    safe cat "$d/online"
done
for b in /sys/class/backlight/*; do
    [ -e "$b" ] || continue
    echo "-- $b"
    safe cat "$b/brightness"
    safe cat "$b/actual_brightness"
    safe cat "$b/max_brightness"
done
safe lipc-get-prop -i com.lab126.powerd battLevel
safe lipc-get-prop -i com.lab126.powerd isCharging
safe lipc-get-prop -i com.lab126.powerd preventScreenSaver
safe lipc-get-prop -i com.lab126.powerd flIntensity

section "wifi / network"
safe cat /sys/class/net/wlan0/operstate
safe cat /proc/net/route
safe lipc-get-prop -i com.lab126.wifid enable
command -v wpa_cli >/dev/null 2>&1 && safe wpa_cli -i wlan0 status
command -v ifconfig >/dev/null 2>&1 && safe ifconfig wlan0
command -v ip >/dev/null 2>&1 && safe ip addr show wlan0

section "tools"
for c in curl wget lipc-set-prop lipc-get-prop fbink eips sqlite3 mesquite luajit lua python3 busybox; do
    p=$(command -v "$c" 2>/dev/null || true)
    echo "$c: ${p:-missing}"
done
command -v curl >/dev/null 2>&1 && safe curl --version
command -v busybox >/dev/null 2>&1 && safe busybox --list

section "fonts"
safe ls -la /usr/java/lib/fonts
safe ls -la /mnt/us/fonts
safe ls -la /mnt/us/kdash/assets

section "storage / mounts"
safe df -h /mnt/us
safe cat /proc/mounts | grep ' /mnt/us '
safe free
safe ls -la /mnt/us | head -40

section "kdash / kpm / koreader"
safe ls -la /mnt/us/kdash
safe cat /mnt/us/kdash/config.json
safe ls -la /var/local/kmc/bin
safe ls -la /mnt/us/koreader | head -30
safe ls -la /mnt/us/documents | head -40

section "runtime binaries (if installed)"
if [ -f /mnt/us/kdash/../kpm/packages/kdash/runtime/fbink ]; then
    echo "package path found"
fi
safe ls -l /var/tmp/kdash-bin
if command -v sha256sum >/dev/null 2>&1; then
    for f in /mnt/us/kdash/../kpm/packages/kdash/runtime/luajit /mnt/us/kdash/../kpm/packages/kdash/runtime/fbink; do
        [ -f "$f" ] && safe sha256sum "$f"
    done
fi

section "done"
echo "Report complete. Nothing was modified."
