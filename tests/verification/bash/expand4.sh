#!/usr/bin/env bash
# Battery for foundations.bash-variables-and-expansion: one line followed through every expansion step.
d=$(mktemp -d); cd "$d" || exit 1
touch app.log 'old app.log' notes.txt
args() { printf '%d args:' "$#"; printf ' [%s]' "$@"; echo; }
who='my report'; ext='*.log'
echo "bash $BASH_VERSION"
echo '=== the line:  args {a,b}.txt ~ "$who" $who $ext "$ext" $((2+3))'
args {a,b}.txt ~ "$who" $who $ext "$ext" $((2+3)) | sed "s|$HOME|/home/you|"
echo '=== the same with set -x'
( set -x; : {a,b}.txt "$who" $who $ext "$ext" $((2+3)) ) 2>&1
echo '=== no match'
rm -- *.log
args $ext
( shopt -s nullglob; printf 'with nullglob: '; args $ext )
cd /; rm -rf "$d"
