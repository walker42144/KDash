#!/bin/sh
set -u
RUN=$1
DATA=/mnt/us/kdash-candidate
LOG="$DATA/logs/session.log"
. "$RUN/session-common.sh"
: > "$RUN/guard.ready"
read limit < "$RUN/limit"
elapsed=0
while [ ! -f "$RUN/recovery.done" ]; do
    # Normal cleanup deliberately stops the subscriber; do not kill its supervisor.
    if alive "$RUN/recover.pid"; then sleep 1; continue; fi
    if { [ -f "$RUN/power-control.ready" ] && ! alive "$RUN/power-control.pid"; } || { [ -f "$RUN/power-monitor.ready" ] && ! alive "$RUN/power-monitor.pid"; } || ! alive "$RUN/supervisor.pid" || { [ "$limit" -gt 0 ] && [ "$elapsed" -ge "$limit" ]; }; then
        log "guard_recovery elapsed=$elapsed limit=$limit"
        : > "$RUN/stop.request"
        if alive "$RUN/supervisor.pid"; then kill -TERM "$p" 2>/dev/null || true; fi
        grace=0
        while alive "$RUN/supervisor.pid" && [ ! -f "$RUN/recovery.done" ] && [ "$grace" -lt 10 ]; do
            sleep 1; grace=$((grace+1))
        done
        if [ ! -f "$RUN/recovery.done" ] && alive "$RUN/supervisor.pid"; then kill -KILL "$p" 2>/dev/null || true; fi
        recover || true
    fi
    sleep 1; elapsed=$((elapsed+1))
done
