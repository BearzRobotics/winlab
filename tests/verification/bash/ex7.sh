#!/bin/sh
set -e
logfile=/tmp/wl-out.log
ls /nonexistent &> "$logfile"
((count = count + 1))
echo -e "done: $count"
