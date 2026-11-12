#!/bin/sh
# Read-only OS probes. Writes only this report (entry redirection) and temporary runtime copies.
set -u
echo 'KDash Candidate diagnostics 0.1.1-candidate1'
date
cat /etc/prettyversion.txt
uname -srm
getconf GNU_LIBC_VERSION 2>/dev/null || true
for f in /lib/ld-linux.so.3 /lib/ld-linux-armhf.so.3; do ls -l "$f" 2>/dev/null; done
echo '=== framebuffer ==='
for f in virtual_size bits_per_pixel stride rotate; do echo "$f"; cat "/sys/class/graphics/fb0/$f" 2>/dev/null; done
echo '=== evdev descriptions (no input recording) ==='
cat /proc/bus/input/devices
echo '=== mount ==='
grep ' /mnt/us ' /proc/mounts
echo '=== required tools ==='
for c in setsid pidof awk lipc-get-prop lipc-set-prop; do command -v "$c" || true; done
echo '=== optional network prerequisites (no requests) ==='
command -v curl >/dev/null 2>&1 && curl --version
for ca in /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-bundle.crt /etc/ssl/cert.pem; do
 [ -f "$ca" ] && ls -l "$ca"
done
echo '=== stock UI processes ==='
for name in Xorg awesome blanket pillowd cvm KPPMainApp mesquite; do
 for p in $(pidof "$name" 2>/dev/null); do awk -v name="$name" '{print name, $1, $3, $22}' "/proc/$p/stat"; done
done
echo '=== screensaver hold ==='
lipc-get-prop -i com.lab126.powerd preventScreenSaver 2>/dev/null || true
echo '=== runtime and touch ABI ==='
PKG=/mnt/us/kdash-candidate/package
TMP=$(mktemp -d /var/tmp/kdash-probe.XXXXXX) || exit 1
trap 'rm -f "$TMP/luajit" "$TMP/fbink"; rmdir "$TMP"' EXIT
cp "$PKG/runtime/luajit" "$TMP/luajit" && cp "$PKG/runtime/fbink" "$TMP/fbink" || exit 1
chmod 755 "$TMP/luajit" "$TMP/fbink"
"$TMP/luajit" -e 'print(jit.version, jit.arch, jit.os)'
"$TMP/fbink" -e
"$TMP/luajit" "$PKG/app/main.lua" --probe-touch
echo '=== end (GUI was not paused; no touch grab) ==='
