#!/bin/sh
# Canonical, bounded event stream. The writer reopens the file per event, so
# truncation cannot leave a producer writing sparse holes at an old offset.
set -u
RUN=$1
DATA=/mnt/us/kdash-candidate
LOG="$DATA/logs/session.log"
. "$RUN/session-common.sh"
fifo="$RUN/power.pipe"
mkfifo "$fifo" || exit 1
finish() {
 trap - EXIT TERM INT HUP
 if alive "$RUN/power-subscriber.pid";then kill -TERM "$p" 2>/dev/null || true;fi
 rm -f "$fifo"
}
trap finish EXIT
trap 'exit 143' TERM INT HUP
(ulimit -f 512;exec lipc-wait-event -m -s 0 com.lab126.powerd '*') > "$fifo" 2> "$RUN/power.stderr" &
subscriber=$!;record_pid "$RUN/power-subscriber.pid" "$subscriber"
while IFS= read -r line;do
 event=
 case "$line" in
  *goingToScreenSaver*) event=goingToScreenSaver;;
  *outOfScreenSaver*) event=outOfScreenSaver;;
  *readyToSuspend*) event=readyToSuspend;;
  *wakeupFromSuspend*) event=wakeupFromSuspend;;
 esac
 if [ -n "$event" ];then
  bytes=$(wc -c < "$RUN/power.events")
  if [ "$bytes" -gt 262144 ];then : > "$RUN/power.events";fi
  echo "$event" >> "$RUN/power.events"
 fi
done < "$fifo"
wait "$subscriber"
