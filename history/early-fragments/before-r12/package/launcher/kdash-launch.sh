#!/bin/sh
# Detached supervisor. USB deployment does not install/register a KPM package.
set -u
PKG=$(CDPATH='' cd "$(dirname "$0")/.." && pwd -P)
DATA=/mnt/us/kdash-candidate
BASE=/var/tmp/kdash-candidate
LOG="$DATA/logs/session.log"
mkdir -p "$DATA/logs" "$BASE" || exit 2
if ! mkdir "$BASE/session.lock" 2>/dev/null; then
    echo 'Session lock exists; use KDash Candidate Recovery before retrying.' >> "$LOG"
    exit 3
fi
RUN=$(mktemp -d "$BASE/run.XXXXXX") || { rmdir "$BASE/session.lock"; exit 2; }
echo "$RUN" > "$BASE/session.lock/run"
cp "$PKG/launcher/session-common.sh" "$RUN/session-common.sh" || exit 2
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
log "session_begin version=0.1.1-candidate1 revision=r11-power-weather-battery run=$RUN"
# All compatibility checks happen before stopping the GUI.
for cmd in setsid pidof lipc-get-prop lipc-set-prop lipc-wait-event awk; do command -v "$cmd" >/dev/null 2>&1 || { log "missing $cmd"; exit 2; }; done
cp "$PKG/runtime/luajit" "$RUN/luajit" && cp "$PKG/runtime/fbink" "$RUN/fbink" || exit 2
chmod 755 "$RUN/luajit" "$RUN/fbink" || exit 2
"$RUN/luajit" -e 'os.exit(0)' >> "$LOG" 2>&1 || exit 2
"$RUN/fbink" -e >> "$LOG" 2>&1 || exit 2
"$RUN/luajit" "$PKG/app/main.lua" --probe-touch >> "$LOG" 2>&1 || exit 2
firmware=$(cat /etc/prettyversion.txt 2>/dev/null)
log "firmware=$firmware kernel=$(uname -sr)"
case "$firmware" in 'Kindle 5.16.2.1.1 '*) ;; *) log 'unreviewed firmware; abort'; exit 2;; esac
"$RUN/luajit" "$PKG/app/main.lua" --probe-display --fbink "$RUN/fbink" >> "$LOG" 2>&1 || exit 2
for p in $(pidof cvm); do
    [ "$(awk '{print $3}' /proc/$p/stat)" != T ] || { log 'cvm is paused by another app'; exit 3; }
done
pidof cvm >/dev/null 2>&1 || { log 'stock framework absent'; exit 3; }
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
saved=$(lipc-get-prop -i com.lab126.powerd preventScreenSaver 2>/dev/null) || exit 2
case "$saved" in ''|*[!0-9]*) log 'invalid screensaver value'; exit 2;; esac
echo "$saved" > "$RUN/screensaver.before"
limit=$(cat "$PKG/session-limit" 2>/dev/null)
case "$limit" in 0|180) ;; *) log 'session-limit must be 180 (trial) or 0 (accepted)'; exit 2;; esac
echo "$limit" > "$RUN/limit"
setsid /bin/sh "$PKG/launcher/session-guard.sh" "$RUN" </dev/null >> "$LOG" 2>&1 &
i=0; while [ ! -f "$RUN/guard.ready" ] && [ "$i" -lt 5 ]; do sleep 1; i=$((i+1)); done
[ -f "$RUN/guard.ready" ] || { log 'watchdog handshake failed'; exit 2; }
[ ! -f "$RUN/stop.request" ] || exit 2
: > "$RUN/ui.intent"
log 'ui_pause_begin (framework services retained)'
while read ui_pid stamp name; do
    [ "$(pid_stamp "$ui_pid")" = "$stamp" ] || { log "UI process changed: $name"; exit 4; }
    kill -STOP "$ui_pid" 2>/dev/null || { log "UI pause failed: $name"; exit 4; }
done < "$RUN/ui.pids"
sleep 1
while read ui_pid stamp name; do
    state=$(awk '{print $3}' "/proc/$ui_pid/stat")
    [ "$(pid_stamp "$ui_pid")" = "$stamp" ] && [ "$state" = T ] || { log "UI pause unverified: $name state=$state"; exit 4; }
done < "$RUN/ui.pids"
# Snapshot the reviewed KPW3 virtual Y8 framebuffer after all stock painters stop.
# 1088 byte stride * 6144 virtual rows; never restore while a KDash painter is alive.
[ "$(cat /sys/class/graphics/fb0/stride)" = 1088 ] || exit 4
[ "$(cat /sys/class/graphics/fb0/virtual_size)" = '1088,6144' ] || exit 4
dd if=/dev/fb0 of="$RUN/stock.fb" bs=4096 count=1632 2>> "$LOG" || exit 4
[ "$(wc -c < "$RUN/stock.fb")" -eq 6684672 ] || exit 4
log 'ui_paused stock_frame_saved'
[ ! -f "$RUN/stop.request" ] || exit 2
lipc-set-prop -i com.lab126.powerd preventScreenSaver 1 >> "$LOG" 2>&1 || exit 4
# Subscribe before app start. Failure triggers the existing exact-PID recovery path.
: > "$RUN/power.events"
lipc-wait-event -m -s 0 com.lab126.powerd '*' > "$RUN/power.events" 2> "$RUN/power.stderr" &
monitor=$!; record_pid "$RUN/power-monitor.pid" "$monitor"
: > "$RUN/power-monitor.ready"
sleep 1
alive "$RUN/power-monitor.pid" || { cat "$RUN/power.stderr" >> "$LOG"; log 'power subscription failed'; exit 4; }
export KDASH_POWER_EVENTS="$RUN/power.events"
export KDASH_FBINK="$RUN/fbink"
log 'app_start'
"$RUN/luajit" "$PKG/app/main.lua" --app-dir "$PKG/app" --data-dir "$DATA" >> "$LOG" 2>&1 &
app=$!; record_pid "$RUN/app.pid" "$app"
wait "$app"; RC=$?
log "app_exit rc=$RC"
exit "$RC"
