#!/usr/bin/env bash
# Battery for foundations.architecture (the Linux comparison): user time against system (kernel) time.
f=$(mktemp) || exit 1
trap 'rm -f -- "$f"' EXIT
TIMEFORMAT='real %R s   user %U s   sys %S s'
uname -r
for run in 1 2; do
    echo '--- arithmetic only (1 million adds in bash)'
    time for ((i = 0; i < 1000000; i++)); do ((x += i)); done
    echo '--- 200000 writes of 16 bytes (dd)'
    time dd if=/dev/zero of="$f" bs=16 count=200000 status=none
done
