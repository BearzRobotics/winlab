#!/usr/bin/env bash
# Battery for foundations.bash-text-processing: one "top addresses" pipeline, shown after every stage.
export LC_ALL=C
d=$(mktemp -d); cd "$d" || exit 1
printf '%s\n' '10.0.0.7 GET /a 200' '10.0.0.2 GET /b 404' '10.0.0.7 GET /c 200' '10.0.0.9 GET /a 200' '10.0.0.7 GET /a 500' '10.0.0.2 GET /a 200' > access.log
stage() { printf '\n--- %s\n' "$1"; eval "$1"; }
stage 'cat access.log'
stage "awk '{print \$1}' access.log"
stage "awk '{print \$1}' access.log | sort"
stage "awk '{print \$1}' access.log | sort | uniq -c"
stage "awk '{print \$1}' access.log | sort | uniq -c | sort -rn"
stage "awk '{print \$1}' access.log | sort | uniq -c | sort -rn | head -2"
printf '\n--- without the first sort\n'; awk '{print $1}' access.log | uniq -c
cd /; rm -rf "$d"
