#!/usr/bin/env bash
# Small follow-up battery for foundations.posix-sh-basics: details the first table needed to get right.
D=$(mktemp -d); cd "$D" || exit 1
names=(); cmds=()
for a in "$@"; do names+=("${a%%=*}"); cmds+=("${a#*=}"); done
T=; command -v timeout >/dev/null 2>&1 && T="timeout 5"
echo "driver: bash $BASH_VERSION; shells: ${names[*]}"
n=0
s() {
  n=$((n+1)); local label=$1 code=$2 res=() i out rc same=1
  mkdir -p "w$n" && cd "w$n" || return
  for i in "${!names[@]}"; do
    rm -rf ./* 2>/dev/null; printf '%s\n' "$code" > s.sh
    out=$($T ${cmds[$i]} s.sh </dev/null 2>&1); rc=$?; out=${out//$'\n'/ | }; res+=("rc=$rc ${out:0:170}")
  done
  cd ..
  for i in "${!res[@]}"; do [ "${res[$i]}" = "${res[0]}" ] || same=0; done
  if [ "$same" = 1 ]; then printf '%3d %-34s ALL: %s\n' "$n" "$label" "${res[0]}"
  else printf '%3d %-34s DIFFER\n' "$n" "$label"; for i in "${!names[@]}"; do printf '      %-8s %s\n' "${names[$i]}" "${res[$i]}"; done; fi
}
s '$10 versus ${10}'            'set -- a b c d e f g h i j; echo "$10 ${10}"'
s '&> to a file, then look'     'echo hi &> out.txt; wait; echo "stdout-above"; ls; echo "[$(cat out.txt 2>/dev/null)]"'
s '&> to /dev/null'             'echo hi &> /dev/null; wait; echo done'
s 'read -p with input'          'echo val | { read -p "prompt: " x; echo "[$x]"; }'
s 'read -r -p ordering'         'echo val | { read -r -p "p> " x; echo "[$x]"; }'
s 'bash test with -a / -o'      '[ -n x -a -n y ] && echo and-ok; [ ! -n x -o -n y ] && echo or-ok'
s '[ -a ] ambiguous case'       'x="!"; [ "$x" -a "$x" ] && echo true || echo false'
s 'type -t'                     'type -t ls 2>&1 | head -1'
s 'alias on a later line'       'alias hi="echo aliased"
hi'
s '$(<file)'                    'echo hi > f; x=$(<f); echo "[$x]"; y=$(cat f); echo "[$y]"'
s 'set -u rc and message'       'set -u; echo "$nope"; echo not-reached'
s 'readonly assignment rc'      'readonly r=1; r=2; echo not-reached'
s 'trap SIGTERM (prefix)'       'trap "echo t" SIGTERM; kill -TERM $$; echo after'
s 'echo $((i++)) when i=1'      'i=1; echo $((i++)); echo $i'
cd / && rm -rf "$D"
