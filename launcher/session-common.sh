#!/bin/sh
# Shared process identity and recovery. Never signal a reused PID.
pid_stamp() { awk '{print $22}' "/proc/$1/stat" 2>/dev/null; }
alive() {
    [ -r "$1" ] || return 1
    read p stamp < "$1"
    case "$p:$stamp" in *[!0-9:]*|:|*:) return 1;; esac
    [ "$(pid_stamp "$p")" = "$stamp" ] && kill -0 "$p" 2>/dev/null
}
record_pid() { echo "$2 $(pid_stamp "$2")" > "$1"; }
stop_app() {
    if alive "$RUN/app.pid"; then
        kill -TERM "$p" 2>/dev/null || true
        i=0; while alive "$RUN/app.pid" && [ "$i" -lt 3 ]; do sleep 1; i=$((i+1)); done
        if alive "$RUN/app.pid"; then kill -KILL "$p" 2>/dev/null || true; fi
    fi
}
rotate_log() {
    [ -f "$1" ] || return 0
    bytes=$(wc -c < "$1" 2>/dev/null) || return 0
    if [ "$bytes" -gt 262144 ]; then mv -f "$1" "$1.1" 2>/dev/null || true;fi
}
log() { rotate_log "$LOG";echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }
bounded() {
    if [ -f "$RUN/command-timeout.sh" ]; then /bin/sh "$RUN/command-timeout.sh" 8 "$@"
    else "$@";fi
}
release_lock() {
    base=${BASE:-/var/tmp/kdash-candidate}
    [ "$(cat "$base/session.lock/run" 2>/dev/null)" = "$RUN" ] || return 0
    tomb="$base/lock-released.${RUN##*/}"
    if mv "$base/session.lock" "$tomb" 2>/dev/null; then
        rm -f "$tomb/run";rmdir "$tomb" 2>/dev/null || log "lock_residue $tomb"
    else log 'lock_release_failed';return 1;fi
}
recover() {
    [ -f "$RUN/recovery.done" ] && return 0
    if ! mkdir "$RUN/recover.lock" 2>/dev/null; then
        sleep 1
        if alive "$RUN/recover.pid"; then return 1; fi
        rmdir "$RUN/recover.lock" 2>/dev/null || return 1
        mkdir "$RUN/recover.lock" 2>/dev/null || return 1
    fi
    record_pid "$RUN/recover.pid" $$
    tries=0;[ ! -r "$RUN/recovery.attempts" ] || read tries < "$RUN/recovery.attempts"
    case "$tries" in ''|*[!0-9]*) tries=0;;esac
    if [ "$tries" -ge 3 ]; then
        : > "$RUN/recovery.failed";log 'restore_failed: retry budget exhausted; snapshot and lock retained'
        rm -f "$RUN/recover.pid";rmdir "$RUN/recover.lock" 2>/dev/null || true;return 1
    fi
    echo $((tries+1)) > "$RUN/recovery.attempts"
    stop_app
    for http_pid in "$RUN"/http/*.pid; do
        if alive "$http_pid"; then kill -TERM "$p" 2>/dev/null || true; fi
    done
    if alive "$RUN/power-control.pid"; then kill -TERM "$p" 2>/dev/null || true; fi
    if alive "$RUN/power-command.pid"; then kill -TERM "$p" 2>/dev/null || true; fi
    if alive "$RUN/power-monitor.pid"; then kill -TERM "$p" 2>/dev/null || true; fi
    if alive "$RUN/power-subscriber.pid"; then kill -TERM "$p" 2>/dev/null || true; fi
    ok=1
    if [ -f "$RUN/ui.intent" ]; then
        log 'restore_begin'
        if [ -f "$RUN/stock.fb" ]; then
            bounded /bin/sh -c 'cat "$1" > /dev/fb0' sh "$RUN/stock.fb" || ok=0
            bounded "$RUN/fbink" -q -w -s -W GC16 -f >> "$LOG" 2>&1 || ok=0
            log 'stock_frame_restored'
        fi
        # Resume only the PIDs and process start times owned by this session.
        while read ui_pid stamp name; do
            if [ "$(pid_stamp "$ui_pid")" = "$stamp" ]; then
                kill -CONT "$ui_pid" 2>/dev/null || ok=0
            fi
        done < "$RUN/ui.pids"
        if [ -f "$RUN/screensaver.before" ]; then
            read saved < "$RUN/screensaver.before"
            bounded lipc-set-prop -i com.lab126.powerd preventScreenSaver "$saved" >> "$LOG" 2>&1 || ok=0
        fi
        sleep 2
        while read ui_pid stamp name; do
            if [ "$(pid_stamp "$ui_pid")" = "$stamp" ]; then
                state=$(awk '{print $3}' "/proc/$ui_pid/stat")
                case "$state" in T|t) log "resume_failed $name"; ok=0;; esac
            fi
        done < "$RUN/ui.pids"
        if pidof cvm >/dev/null 2>&1; then
            bounded lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home >> "$LOG" 2>&1 || ok=0
        else log 'restore_failed: cvm absent'; ok=0; fi
        if [ -f "$RUN/stock.fb" ]; then
            sleep 2
            bounded "$RUN/fbink" -q -w -s -W GC16 -f >> "$LOG" 2>&1 || ok=0
        fi
    fi
    if [ "$ok" -eq 1 ]; then
        if [ -f "$RUN/power.events" ]; then
            rotate_log "$DATA/logs/power-events.log"
            awk '/goingToScreenSaver/ {print "goingToScreenSaver"} /outOfScreenSaver/ {print "outOfScreenSaver"} /readyToSuspend/ {print "readyToSuspend"} /wakeupFromSuspend/ {print "wakeupFromSuspend"}' "$RUN/power.events" >> "$DATA/logs/power-events.log" 2>/dev/null || true
        fi
        rm -f "$RUN/stock.fb" "$RUN/luajit" "$RUN/fbink" "$RUN/libfreetype.so.6" "$RUN/libz.so.1"
        : > "$RUN/recovery.done"
        release_lock || ok=0
        log 'restore_done (Home requested; visual confirmation still required)'
    fi
    rm -f "$RUN/recover.pid"; rmdir "$RUN/recover.lock" 2>/dev/null || true
    if [ "$ok" -eq 0 ] && [ "$tries" -ge 2 ]; then : > "$RUN/recovery.failed";fi
    [ "$ok" -eq 1 ]
}
