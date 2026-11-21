#!/usr/bin/env bash
# Exercises skeleton.sh: no args, bad option, missing file, normal run, verbose, a concurrent second copy, temp cleanup.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
S="$here/skeleton.sh"
cd "$(mktemp -d)" || exit 1
printf 'a\nb\nc\n' > data.txt
echo -n 'no arguments        : '; bash "$S" 2>&1; echo "  status $?"
echo -n '-h                  : '; bash "$S" -h 2>&1; echo "  status $?"
echo -n 'unknown option -x   : '; bash "$S" -x data.txt 2>&1; echo "  status $?"
echo -n 'missing file        : '; bash "$S" /nonexistent 2>&1; echo "  status $?"
echo -n 'normal              : '; bash "$S" data.txt 2>&1; echo "  status $?"
echo -n 'verbose             : '; bash "$S" -v data.txt 2>&1 | sed 's#/tmp/tmp\.[A-Za-z0-9]*#/tmp/tmp.XXXX#'
before=$(ls /tmp | grep -c '^tmp\.' )
WL_SLEEP=2 bash "$S" data.txt > first.out 2>&1 &
sleep 0.5
echo -n 'second copy at once : '; bash "$S" data.txt 2>&1; echo "  status $?"
wait; echo "first copy finished: $(cat first.out)"
after=$(ls /tmp | grep -c '^tmp\.')
echo "temp dirs left behind by the script: $((after - before))"
echo -n 'local outside a function: '; bash -c 'local x=1; echo "x=$x"' 2>&1; echo "  status $?"
echo -n 'sourced: '; bash -c ". '$S'; type main | head -1"
