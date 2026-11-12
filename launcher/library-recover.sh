#!/bin/sh
# Name: KDash Candidate Recovery
# Author: KDash
# Icon: /mnt/us/kdash-candidate/package/app/assets/cover-recovery-v2.png
# DontUseFBInk
DATA=/mnt/us/kdash-candidate
LOG="$DATA/logs/session.log"
for RUN in /var/tmp/kdash-candidate/run.*; do
 [ -f "$RUN/session-common.sh" ] || continue
 [ -f "$RUN/recovery.done" ] && continue
 . "$RUN/session-common.sh"
 : > "$RUN/stop.request"
 if alive "$RUN/supervisor.pid"; then kill -TERM "$p" 2>/dev/null || true; sleep 3; fi
 if alive "$RUN/supervisor.pid"; then kill -KILL "$p" 2>/dev/null || true; fi
 recover || log 'manual recovery incomplete'
done
