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
   if [ -f "$RUN/command-timeout.sh" ];then
    /bin/sh "$RUN/command-timeout.sh" 2 lipc-get-prop -s com.lab126.powerd state > "$RUN/power.state" 2>/dev/null &
   else lipc-get-prop -s com.lab126.powerd state > "$RUN/power.state" 2>/dev/null & fi
   child=$!;record_pid "$RUN/power-command.pid" "$child"
   wait "$child"; result=$?
   rm -f "$RUN/power-command.pid"
   read newest ignored < "$RUN/power.desired"
   if [ "$result" -eq 0 ] && [ "$newest" = "$seq" ] && [ ! -f "$RUN/stop.request" ]; then
    state=$(tr -cd '[:alnum:]' < "$RUN/power.state" | tr '[:upper:]' '[:lower:]')
    log "power_state observed=$state target=$target"
    case "$target:$state" in sleep:active|wake:screensaver)
     if [ -f "$RUN/command-timeout.sh" ];then
      /bin/sh "$RUN/command-timeout.sh" 2 lipc-set-prop -i com.lab126.powerd powerButton 1 >/dev/null 2>&1 &
     else lipc-set-prop -i com.lab126.powerd powerButton 1 >/dev/null 2>&1 & fi
     child=$!;record_pid "$RUN/power-command.pid" "$child"
     # A later physical press invalidates an in-flight reconciliation too.
     # Signal only the PID/starttime recorded above; the timeout wrapper owns
     # the command process group and cancels it on TERM.
     (
      while [ ! -f "$RUN/stop.request" ];do
       read latest ignored < "$RUN/power.desired" || exit 0
       if [ "$latest" != "$seq" ];then
        if alive "$RUN/power-command.pid";then kill -TERM "$p" 2>/dev/null || true;fi
        exit 0
       fi
       sleep 1
      done
     ) & watcher=$!
     wait "$child"; result=$?
     kill "$watcher" 2>/dev/null || true;wait "$watcher" 2>/dev/null || true
     log "power_state request=$target result=$result"
     rm -f "$RUN/power-command.pid";;
    esac
   fi
  fi
 fi
 sleep 1
done
