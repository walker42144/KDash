#!/bin/sh
# Slow powerd IPC is isolated from the touch/render loop. Exact PIDs are recovered.
set -u
RUN=$1
DATA=/mnt/us/kdash-candidate
LOG="$DATA/logs/session.log"
. "$RUN/session-common.sh"
last=0
while [ ! -f "$RUN/stop.request" ]; do
 if [ -r "$RUN/power.desired" ]; then
  read seq target < "$RUN/power.desired"
  if [ "$seq" != "$last" ] && [ "$target" != ignore ]; then
   last=$seq
   lipc-get-prop -s com.lab126.powerd state > "$RUN/power.state" 2>/dev/null &
   child=$!;record_pid "$RUN/power-command.pid" "$child"
   wait "$child"; result=$?
   rm -f "$RUN/power-command.pid"
   read newest ignored < "$RUN/power.desired"
   if [ "$result" -eq 0 ] && [ "$newest" = "$seq" ] && [ ! -f "$RUN/stop.request" ]; then
    state=$(tr -cd '[:alnum:]' < "$RUN/power.state" | tr '[:upper:]' '[:lower:]')
    log "power_state observed=$state target=$target"
    case "$target:$state" in sleep:active|wake:screensaver)
     lipc-set-prop -i com.lab126.powerd powerButton 1 >/dev/null 2>&1 &
     child=$!;record_pid "$RUN/power-command.pid" "$child"
     wait "$child"; log "power_state request=$target result=$?"
     rm -f "$RUN/power-command.pid";;
    esac
   fi
  fi
 fi
 sleep 1
done
