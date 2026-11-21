#!/usr/bin/env bash
# Runs ex7.sh under dash and bash and reports what happened (exercise 7 of foundations.shells-and-posix).
here=$(dirname "$0")
script="$here/ex7.sh"
log=/tmp/wl-out.log
file "$script" 2>/dev/null | sed 's/^/file: /'
for sh in dash bash; do
    rm -f "$log"
    echo "--- $sh:"
    "$sh" "$script"
    echo "exit status: $?"
    if [ -e "$log" ]; then echo "log file: exists, $(wc -c < "$log") bytes: [$(cat "$log")]"; else echo "log file: does not exist"; fi
done
rm -f "$log"
