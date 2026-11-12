#!/bin/sh
set -u
RUN=$1
DATA=/mnt/us/kdash-candidate
LOG="$DATA/logs/session.log"
. "$RUN/session-common.sh"
: > "$RUN/guard.ready"
read limit < "$RUN/limit"
elapsed=0
recover_wait=0
recovery_child=
while [ ! -f "$RUN/recovery.done" ]; do
    if [ -n "$recovery_child" ];then
        state=$(awk '{print $3}' "/proc/$recovery_child/stat" 2>/dev/null)
        if [ "$state" = Z ] || ! alive "$RUN/recovery-worker.pid";then
            wait "$recovery_child" 2>/dev/null || true
            recovery_child=;rm -f "$RUN/recovery-worker.pid"
        fi
    fi
    # Normal cleanup deliberately stops the subscriber; do not kill its supervisor.
    if [ -f "$RUN/recovery.failed" ]; then log 'guard stopped: recovery needs manual attention';exit 1;fi
    if alive "$RUN/recover.pid" || alive "$RUN/recovery-worker.pid"; then
        recover_wait=$((recover_wait+1))
        if [ "$recover_wait" -le 60 ]; then sleep 1;elapsed=$((elapsed+1));continue;fi
        kill -TERM "$p" 2>/dev/null || true;sleep 1
        if alive "$RUN/recover.pid" || alive "$RUN/recovery-worker.pid"; then kill -KILL "$p" 2>/dev/null || true;fi
        : > "$RUN/recovery.failed";log 'recovery watchdog deadline exceeded';exit 1
    fi
    recover_wait=0
    if { [ -f "$RUN/power-control.ready" ] && ! alive "$RUN/power-control.pid"; } || { [ -f "$RUN/power-monitor.ready" ] && ! alive "$RUN/power-monitor.pid"; } || ! alive "$RUN/supervisor.pid" || { [ "$limit" -gt 0 ] && [ "$elapsed" -ge "$limit" ]; }; then
        log "guard_recovery elapsed=$elapsed limit=$limit"
        : > "$RUN/stop.request"
        if alive "$RUN/supervisor.pid"; then kill -TERM "$p" 2>/dev/null || true; fi
        grace=0
        while alive "$RUN/supervisor.pid" && [ ! -f "$RUN/recovery.done" ] && [ "$grace" -lt 10 ]; do
            sleep 1; grace=$((grace+1))
        done
        if [ ! -f "$RUN/recovery.done" ] && alive "$RUN/supervisor.pid"; then kill -KILL "$p" 2>/dev/null || true; fi
        # Recover in a distinct shell so this watchdog can also time out its own
        # orphan-recovery attempt. $$ in a POSIX subshell is not a new PID.
        /bin/sh -c 'RUN=$1; DATA=$2; LOG=$3; . "$RUN/session-common.sh"; recover' sh "$RUN" "$DATA" "$LOG" &
        recovery_child=$!;record_pid "$RUN/recovery-worker.pid" "$recovery_child"
    fi
    sleep 1; elapsed=$((elapsed+1))
done
