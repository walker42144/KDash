#!/bin/sh
# Name: KDash Candidate Recovery
# Author: KDash
# Icon: /mnt/us/kdash-candidate/package/app/assets/cover-recovery-v2.png
# DontUseFBInk
# Keep recovery alive when requesting the stock Home app closes the Scriptlet.
if [ "${1:-}" != --recovery-worker ];then
 command -v setsid >/dev/null 2>&1 || exit 2
 setsid /bin/sh "$0" --recovery-worker </dev/null >/dev/null 2>&1 &
 exit 0
fi
DATA=/mnt/us/kdash-candidate
LOG="$DATA/logs/session.log"
owner=$(cat /var/tmp/kdash-candidate/session.lock/run 2>/dev/null)
for RUN in /var/tmp/kdash-candidate/run.*; do
 [ -z "$owner" ] || [ "$RUN" = "$owner" ] || continue
 [ -f "$RUN/session-common.sh" ] || continue
 [ -f "$RUN/recovery.done" ] && continue
 . "$RUN/session-common.sh"
 if alive "$RUN/supervisor.pid" && [ ! -f "$RUN/stop.request" ]; then
  if [ ! -f "$RUN/app.pid" ];then log 'manual recovery skipped starting session';continue;fi
  if alive "$RUN/app.pid";then
   heartbeat=0;[ ! -r "$RUN/heartbeat" ] || read heartbeat < "$RUN/heartbeat"
   case "$heartbeat" in ''|*[!0-9]*) heartbeat=0;;esac
   now=$(date +%s)
   if [ "$heartbeat" -gt 0 ] && [ $((now-heartbeat)) -lt 30 ];then log 'manual recovery skipped healthy active session';continue;fi
  fi
 fi
 rm -f "$RUN/recovery.failed" "$RUN/recovery.attempts"
 : > "$RUN/stop.request"
 if alive "$RUN/supervisor.pid"; then kill -TERM "$p" 2>/dev/null || true; sleep 3; fi
 if alive "$RUN/supervisor.pid"; then kill -KILL "$p" 2>/dev/null || true; fi
 recover || log 'manual recovery incomplete'
done
# A crash between mkdir(session.lock) and publishing run has no owned recovery
# script. Only an explicit Recovery action may quarantine that empty lock.
lock=/var/tmp/kdash-candidate/session.lock
if [ -d "$lock" ] && [ -z "$(cat "$lock/run" 2>/dev/null)" ];then
 live=0
 for RUN in /var/tmp/kdash-candidate/run.*;do
  [ -f "$RUN/session-common.sh" ] || continue
  . "$RUN/session-common.sh"
  if alive "$RUN/supervisor.pid" || alive "$RUN/recover.pid";then live=1;fi
 done
 if [ "$live" -eq 0 ];then mv "$lock" "$lock.abandoned.$(date +%s)" 2>/dev/null || true;fi
fi
