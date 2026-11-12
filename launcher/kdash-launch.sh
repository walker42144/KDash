#!/bin/sh
# Detached supervisor. USB deployment does not install/register a KPM package.
set -u
umask 077
PKG=$(CDPATH='' cd "$(dirname "$0")/.." && pwd -P)
DATA=/mnt/us/kdash-candidate
BASE=/var/tmp/kdash-candidate
LOG="$DATA/logs/session.log"
mkdir -p "$DATA/logs" "$BASE" || exit 2
# Wait for an exiting session, or recover an orphan, in this same launch.
# Never kill a healthy active dashboard or blindly delete its ownership lock.
attempt=0
echo "$(date '+%Y-%m-%d %H:%M:%S') launch_requested" >> "$LOG"
while ! mkdir "$BASE/session.lock" 2>/dev/null; do
    previous=$(cat "$BASE/session.lock/run" 2>/dev/null)
    case "$previous" in "$BASE"/run.*)
        token=${previous#"$BASE"/run.}
        case "$token" in ''|*[!a-zA-Z0-9]*) previous=;; esac;;
        *) previous=;;
    esac
    if [ -n "$previous" ] && [ -d "$previous" ]; then
        (
            RUN=$previous
            . "$PKG/launcher/session-common.sh"
            if alive "$RUN/recover.pid"; then exit 10; fi
            [ ! -f "$RUN/recovery.failed" ] || exit 12
            if alive "$RUN/supervisor.pid"; then
                owner=$p
                [ -f "$RUN/stop.request" ] && exit 10
                # Preflight has no app.pid yet; it is also a healthy session.
                [ ! -f "$RUN/app.pid" ] && exit 11
                alive "$RUN/app.pid" && exit 11
                kill -TERM "$owner" 2>/dev/null || true
                exit 10
            fi
            : > "$RUN/stop.request"
            if [ -f "$RUN/recovery.done" ]; then
                # Recovery can finish just before its owner is terminated while
                # releasing the lock. Only release this exact completed owner.
                [ "$(cat "$BASE/session.lock/run" 2>/dev/null)" = "$RUN" ] || exit 10
                if command -v release_lock >/dev/null 2>&1;then release_lock || exit 10
                else rm -f "$BASE/session.lock/run";rmdir "$BASE/session.lock" 2>/dev/null || exit 10;fi
            else
                recover || exit 10
            fi
        )
        result=$?
        if [ "$result" -eq 12 ];then echo 'Recovery requires attention; use KDash Candidate Recovery.' >> "$LOG";exit 3;fi
        if [ "$result" -eq 11 ]; then
            echo 'Dashboard already running or starting; duplicate launch ignored.' >> "$LOG"
            exit 3
        fi
    fi
    attempt=$((attempt+1))
    if [ "$attempt" -ge 20 ]; then
        echo 'Session recovery timed out; use KDash Candidate Recovery.' >> "$LOG"
        exit 3
    fi
    sleep 1
done
RUN=$(mktemp -d "$BASE/run.XXXXXX") || { rmdir "$BASE/session.lock"; exit 2; }
echo "$RUN" > "$BASE/session.lock/run"
cp "$PKG/launcher/session-common.sh" "$RUN/session-common.sh" || exit 2
cp "$PKG/launcher/session-guard.sh" "$RUN/session-guard.sh" || exit 2
cp "$PKG/launcher/power-control.sh" "$RUN/power-control.sh" || exit 2
cp "$PKG/launcher/power-monitor.sh" "$RUN/power-monitor.sh" || exit 2
cp "$PKG/launcher/command-timeout.sh" "$RUN/command-timeout.sh" || exit 2
export KDASH_COMMAND_TIMEOUT="$RUN/command-timeout.sh"
. "$RUN/session-common.sh"
record_pid "$RUN/supervisor.pid" $$
RC=1
cleanup() {
    trap - EXIT INT HUP TERM
    : > "$RUN/stop.request"
    recover || log 'restore_pending: guard will retry'
    log "session_end rc=$RC run=$RUN"
    exit "$RC"
}
trap cleanup EXIT
trap 'RC=143; exit 143' INT HUP TERM
log "session_begin version=0.1.1-candidate1 revision=r19-splash-candidate lock_wait_ticks=$attempt run=$RUN"
# Temporary timing evidence: monotonic clock and shell builtins only.
trace_startup() {
 read trace_uptime trace_idle < /proc/uptime || trace_uptime=unknown
 printf '[DEBUG-startup] uptime=%s stage=%s\n' "$trace_uptime" "$1" >> "$LOG"
}
rotate_log "$DATA/logs/bootstrap.log"
# Only completed, inactive, non-symlink sessions with an exact owned basename
# are reclaimed. Failed recovery snapshots are deliberately retained.
for old in "$BASE"/run.*;do
 [ "$old" != "$RUN" ] && [ ! -L "$old" ] && [ -f "$old/recovery.done" ] || continue
 token=${old#"$BASE"/run.};case "$token" in ''|*[!a-zA-Z0-9]*) continue;;esac
 if alive "$old/supervisor.pid" || alive "$old/guard.pid" || alive "$old/recover.pid";then continue;fi
 rm -rf "$old"
done
# All compatibility checks happen before stopping the GUI.
for cmd in setsid pidof lipc-get-prop lipc-set-prop lipc-wait-event awk; do command -v "$cmd" >/dev/null 2>&1 || { log "missing $cmd"; exit 2; }; done
cp "$PKG/runtime/luajit" "$RUN/luajit" && cp "$PKG/runtime/fbink" "$RUN/fbink" || exit 2
cp "$PKG/runtime/libfreetype.so.6" "$RUN/libfreetype.so.6" && cp "$PKG/runtime/libz.so.1" "$RUN/libz.so.1" || exit 2
chmod 755 "$RUN/luajit" "$RUN/fbink" "$RUN/libfreetype.so.6" "$RUN/libz.so.1" || exit 2
export KDASH_FREETYPE="$RUN/libfreetype.so.6"
export KDASH_ZLIB="$RUN/libz.so.1"
# The touch probe already starts LuaJIT; the display probe runs and validates FBInk.
"$RUN/luajit" "$PKG/app/main.lua" --probe-touch >> "$LOG" 2>&1 || exit 2
log 'preflight_touch_ok'
firmware=$(cat /etc/prettyversion.txt 2>/dev/null)
log "firmware=$firmware kernel=$(uname -sr)"
case "$firmware" in 'Kindle 5.16.2.1.1 '*) ;; *) log 'unreviewed firmware; abort'; exit 2;; esac
"$RUN/luajit" "$PKG/app/main.lua" --probe-display --fbink "$RUN/fbink" >> "$LOG" 2>&1 || exit 2
log 'preflight_display_ok'
"$RUN/luajit" "$PKG/app/main.lua" --probe-native-display >> "$LOG" 2>&1 || exit 2
log 'preflight_native_ok'
trace_startup preflight_complete
for p in $(pidof cvm); do
    [ "$(awk '{print $3}' /proc/$p/stat)" != T ] || { log 'cvm is paused by another app'; exit 3; }
done
pidof cvm >/dev/null 2>&1 || { log 'stock framework absent'; exit 3; }
trace_startup framework_checked
# Record the exact stock UI processes, matching the on-device warm UI evidence.
# Keep init jobs alive: do not stop/restart lab126_gui.
: > "$RUN/ui.pids"
for name in Xorg awesome blanket pillowd cvm KPPMainApp mesquite; do
    for ui_pid in $(pidof "$name" 2>/dev/null); do
        state=$(awk '{print $3}' "/proc/$ui_pid/stat")
        [ "$state" != T ] && [ "$state" != t ] || { log "UI already paused: $name"; exit 3; }
        echo "$ui_pid $(pid_stamp "$ui_pid") $name" >> "$RUN/ui.pids"
    done
done
trace_startup ui_inventory_complete
saved=$(bounded lipc-get-prop -i com.lab126.powerd preventScreenSaver 2>/dev/null) || exit 2
case "$saved" in ''|*[!0-9]*) log 'invalid screensaver value'; exit 2;; esac
echo "$saved" > "$RUN/screensaver.before"
trace_startup screensaver_queried
limit=$(cat "$PKG/session-limit" 2>/dev/null)
case "$limit" in 0|180) ;; *) log 'session-limit must be 180 (trial) or 0 (accepted)'; exit 2;; esac
echo "$limit" > "$RUN/limit"
setsid /bin/sh "$RUN/session-guard.sh" "$RUN" </dev/null >> "$LOG" 2>&1 &
record_pid "$RUN/guard.pid" $!
i=0; short_sleep=1
while [ ! -f "$RUN/guard.ready" ] && [ "$i" -lt 50 ]; do
 if [ "$short_sleep" = 1 ];then
  if sleep 0.1 2>/dev/null;then i=$((i+1));continue;fi
  short_sleep=0
 fi
 sleep 1; i=$((i+10))
done
[ -f "$RUN/guard.ready" ] || { log 'watchdog handshake failed'; exit 2; }
alive "$RUN/guard.pid" || { log 'watchdog exited after handshake'; exit 2; }
trace_startup guard_ready
[ ! -f "$RUN/stop.request" ] || exit 2
: > "$RUN/ui.intent"
log 'ui_pause_begin (framework services retained)'
while read ui_pid stamp name; do
    [ "$(pid_stamp "$ui_pid")" = "$stamp" ] || { log "UI process changed: $name"; exit 4; }
    kill -STOP "$ui_pid" 2>/dev/null || { log "UI pause failed: $name"; exit 4; }
done < "$RUN/ui.pids"
verify_ui_paused() {
 while read ui_pid stamp name; do
  [ "$(pid_stamp "$ui_pid")" = "$stamp" ] || { log "UI identity changed: $name"; return 2; }
  state=$(awk '{print $3}' "/proc/$ui_pid/stat")
  case "$state" in T|t) ;; *) return 1;; esac
 done < "$RUN/ui.pids"
 return 0
}
i=0
while :; do
 verify_ui_paused; status=$?
 [ "$status" -eq 0 ] && break
 [ "$status" -eq 2 ] && exit 4
 [ "$i" -lt 50 ] || { log 'UI pause unverified: timeout'; exit 4; }
 if [ "$short_sleep" = 1 ];then
  if sleep 0.1 2>/dev/null;then i=$((i+1));continue;fi
  short_sleep=0
 fi
 sleep 1; i=$((i+10))
done
# Snapshot the reviewed KPW3 virtual Y8 framebuffer after all stock painters stop.
# 1088 byte stride * 6144 virtual rows; never restore while a KDash painter is alive.
[ "$(cat /sys/class/graphics/fb0/stride)" = 1088 ] || exit 4
[ "$(cat /sys/class/graphics/fb0/virtual_size)" = '1088,6144' ] || exit 4
dd if=/dev/fb0 of="$RUN/stock.fb" bs=4096 count=1632 2>> "$LOG" || exit 4
[ "$(wc -c < "$RUN/stock.fb")" -eq 6684672 ] || exit 4
log 'ui_paused stock_frame_saved'
trace_startup ui_snapshot_complete
[ ! -f "$RUN/stop.request" ] || exit 2
bounded lipc-set-prop -i com.lab126.powerd preventScreenSaver 1 >> "$LOG" 2>&1 || exit 4
trace_startup screensaver_disabled
# Subscribe before app start. Failure triggers the existing exact-PID recovery path.
: > "$RUN/power.events"
/bin/sh "$RUN/power-monitor.sh" "$RUN" &
monitor=$!; record_pid "$RUN/power-monitor.pid" "$monitor"
: > "$RUN/power-monitor.ready"
sleep 1
alive "$RUN/power-monitor.pid" || { cat "$RUN/power.stderr" >> "$LOG"; log 'power subscription failed'; exit 4; }
trace_startup power_monitor_ready
/bin/sh "$RUN/power-control.sh" "$RUN" >> "$LOG" 2>&1 &
controller=$!;record_pid "$RUN/power-control.pid" "$controller"
: > "$RUN/power-control.ready"
mkdir -p "$RUN/http" || exit 4
export KDASH_HTTP_DIR="$RUN/http"
export KDASH_POWER_RUN="$RUN"
export KDASH_POWER_EVENTS="$RUN/power.events"
export KDASH_FBINK="$RUN/fbink"
log 'app_start'
"$RUN/luajit" "$PKG/app/main.lua" --app-dir "$PKG/app" --data-dir "$DATA" >> "$LOG" 2>&1 &
app=$!; record_pid "$RUN/app.pid" "$app"
date +%s > "$RUN/heartbeat"
wait "$app"; RC=$?
log "app_exit rc=$RC"
exit "$RC"
