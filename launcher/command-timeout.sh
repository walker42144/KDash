#!/bin/sh
# Bounded owned process group for local FBInk/LIPC commands, never HTTP secrets.
seconds=$1;shift
case "$seconds" in ''|*[!0-9]*) exit 125;; esac
if [ "${KDASH_TIMEOUT_SINGLE_PID:-0}" = 1 ]; then "$@" &
else setsid "$@" &
fi
child=$!
stamp=$(awk '{print $22}' "/proc/$child/stat" 2>/dev/null)
signal_child() {
 [ -n "$stamp" ] && [ "$(awk '{print $22}' "/proc/$child/stat" 2>/dev/null)" = "$stamp" ] || return 0
 if [ "${KDASH_TIMEOUT_SINGLE_PID:-0}" = 1 ]; then kill "-$1" "$child" 2>/dev/null || true
 else kill "-$1" -- "-$child" 2>/dev/null || true;fi
}
(
 timer=
 trap '[ -z "$timer" ] || kill "$timer" 2>/dev/null; exit 0' TERM INT HUP
 sleep "$seconds" & timer=$!;wait "$timer";timer=
 signal_child TERM
 sleep 1 & timer=$!;wait "$timer";timer=
 signal_child KILL
) &
watchdog=$!
stop() { signal_child TERM;signal_child KILL;kill "$watchdog" 2>/dev/null || true;wait "$watchdog" 2>/dev/null; }
trap 'stop; exit 124' TERM INT HUP
wait "$child";rc=$?
kill "$watchdog" 2>/dev/null || true
wait "$watchdog" 2>/dev/null
exit "$rc"
