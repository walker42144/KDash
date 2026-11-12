#!/bin/sh
# Name: KDash Candidate Diagnostics
# Author: KDash
# Icon: /mnt/us/kdash-candidate/package/app/assets/cover.png
# DontUseFBInk
BASE=/mnt/us/kdash-candidate
mkdir -p "$BASE/logs" || exit 1
exec /bin/sh "$BASE/package/diagnose.sh" > "$BASE/logs/diagnostics.txt" 2>&1
