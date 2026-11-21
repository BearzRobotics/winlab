#!/usr/bin/env bash
# POSIX sh scripting-patterns battery (portable idioms). The DRIVER is bash; the snippets run in the shells under test.
# Usage: psh2.sh NAME=COMMAND [NAME=COMMAND ...]
D=$(mktemp -d); cd "$D" || exit 1
names=(); cmds=()
for a in "$@"; do names+=("${a%%=*}"); cmds+=("${a#*=}"); done
T=; command -v timeout >/dev/null 2>&1 && T="timeout 5"
echo "driver: bash $BASH_VERSION; shells: ${names[*]}"
n=0
s() { # label, code
  n=$((n+1))
  local label=$1 code=$2 res=() i out rc same=1
  mkdir -p "w$n" && cd "w$n" || return
  printf '%s\n' "$code" > s.sh
  for i in "${!names[@]}"; do
    rm -rf ./* 2>/dev/null; printf '%s\n' "$code" > s.sh
    out=$($T ${cmds[$i]} s.sh </dev/null 2>&1); rc=$?
    out=${out//$'\n'/ | }
    res+=("rc=$rc ${out:0:170}")
  done
  cd ..
  for i in "${!res[@]}"; do [ "${res[$i]}" = "${res[0]}" ] || same=0; done
  if [ "$same" = 1 ]; then printf '%3d %-36s ALL: %s\n' "$n" "$label" "${res[0]}"
  else
    printf '%3d %-36s DIFFER\n' "$n" "$label"
    for i in "${!names[@]}"; do printf '      %-8s %s\n' "${names[$i]}" "${res[$i]}"; done
  fi
}

echo '### 1. arguments and options'
s 'option loop with case and shift' 'verbose=0; out=
set -- -v -o result.txt -- -file
while [ $# -gt 0 ]; do
  case $1 in
    -v) verbose=1 ;;
    -o) [ $# -ge 2 ] || { echo "-o needs a value" >&2; exit 2; }; out=$2; shift ;;
    --) shift; break ;;
    -*) echo "unknown option $1" >&2; exit 2 ;;
    *) break ;;
  esac
  shift
done
echo "v=$verbose out=$out rest=$*"'
s 'getopts loop' 'set -- -v -o out.txt file1 file2
verbose=0
while getopts vo: opt; do
  case $opt in v) verbose=1;; o) out=$OPTARG;; *) exit 2;; esac
done
shift $((OPTIND - 1))
echo "v=$verbose out=$out rest=$*"'
s 'getopts: unknown option message' 'set -- -z
while getopts v opt; do :; done; echo "rc=$?"'
s 'default argument under set -u' 'set -eu; echo "${1:-none} ${2-unset-ok}"'
s 'missing argument check' 'set --; [ $# -ge 1 ] || { echo "usage: s.sh FILE" >&2; exit 2; }'
s 'arrays with set --' 'set --
for f in "a b" c "d e"; do set -- "$@" "$f"; done
printf "[%s]" "$@"; echo; echo "count=$#"'
s 'loop over files safely' "touch 'a b' ./-n x; for f in ./*; do printf '[%s]' \"\$f\"; done; echo"
s 'loop over lines (no word split)' 'printf "one two\nthree\n" > l.txt
while IFS= read -r line; do printf "[%s]" "$line"; done < l.txt; echo'
s 'read keeps leading blanks only with IFS=' 'printf "  a b  \n" | { read -r x; printf "[%s]\n" "$x"; }; printf "  a b  \n" | { IFS= read -r x; printf "[%s]\n" "$x"; }'
s 'last line without a newline' 'printf "a\nb" | while read -r l || [ -n "$l" ]; do printf "[%s]" "$l"; done; echo'
s 'counter lost in a pipeline' 'n=0; printf "a\nb\nc\n" | while read -r l; do n=$((n+1)); done; echo "n=$n"'
s 'counter kept with a here-doc' 'n=0
while read -r l; do n=$((n+1)); done <<EOF
a
b
c
EOF
echo "n=$n"'
s 'counter kept with a temp file' 'printf "a\nb\nc\n" > in.txt; n=0; while read -r l; do n=$((n+1)); done < in.txt; echo "n=$n"'
s 'counter kept with braces' 'printf "a\nb\nc\n" | { n=0; while read -r l; do n=$((n+1)); done; echo "n=$n"; }'

echo '### 2. text and strings without bashisms'
s 'string length, trim, suffix' 's=hello.txt; echo "${#s} ${s%.txt} ${s#hello} ${s%%.*}"'
s 'substring with cut' 's=hello; printf "%s\n" "$s" | cut -c2-4'
s 'upper-case with tr' 's=Hello; printf "%s\n" "$s" | tr "[:lower:]" "[:upper:]"'
s 'replace with sed' 's=a-b-c; printf "%s\n" "$s" | sed "s/-/_/g"'
s 'contains with case' 's="hello world"; case $s in *world*) echo yes;; *) echo no;; esac'
s 'starts/ends with case' 's=file.tar.gz; case $s in *.gz) echo gz;; esac; case $s in file*) echo starts;; esac'
s 'expr for arithmetic and match' 'expr 2 + 3; expr "abc" : "a\(.*\)"; expr length hello 2>&1 | head -1'
s 'printf %s of a dash value' 'v=-n; printf "%s\n" "$v"; echo "$v"'
s 'printf %b and backslashes' 'printf "%b\n" "a\tb"; printf "%s\n" "a\tb"'
s 'echo is not portable' 'echo "a\tb"; echo "-n x"; echo -n y; echo'
s 'padding numbers' 'printf "%03d %5.2f %-4s|\n" 7 3.14159 ab'
s 'return a value: print and capture' 'f() { printf "%s\n" "$(($1 * 2))"; }; r=$(f 21); echo "r=$r"'
s 'return a value: variable by name (eval)' 'setvar() { eval "$1=\$2"; }; setvar out "a b c"; echo "[$out]"'
s 'IFS splitting with set -f' 'set -f; IFS=,; v="a,b*,c"; set -- $v; echo "$# [$2]"; unset IFS; set +f'
s 'split a PATH-like list' 'p=/usr/bin:/bin:/opt/x; old=$IFS; IFS=:; set -- $p; IFS=$old; echo "$# $2"'
s 'newline in a variable' 'nl="
"; v="a${nl}b"; printf "%s\n" "$v" | wc -l | tr -d " "'
s 'ANSI-C quotes replacement' 'tab=$(printf "\t"); v="a${tab}b"; printf "%s\n" "$v" | od -An -c | tr -s " "'
s 'comparing numbers and strings' '[ 10 -gt 9 ] && echo num-gt; [ 10 \> 9 ] 2>&1 | head -1; [ "10" = "10.0" ] || echo strings-differ'
s 'arithmetic: no floats' 'echo $((7/2)) $((10%3)); echo $((1.5+1)) 2>&1 | head -1'

echo '### 3. files, temp files, locking, cleanup'
s 'mktemp file and dir' 't=$(mktemp) && [ -f "$t" ] && echo file-ok; d=$(mktemp -d) && [ -d "$d" ] && echo dir-ok; rm -rf "$t" "$d"'
s 'cleanup on EXIT, INT, TERM' 'tmp=$(mktemp); echo "$tmp" > tmpname
cleanup() { rm -f "$tmp"; }
trap cleanup EXIT
trap "exit 130" INT
trap "exit 143" TERM
kill -TERM $$'
s 'was the temp file removed?' 'sh -c '"'"'tmp=$(mktemp); echo "$tmp" > tmpname; trap "rm -f \"$tmp\"" EXIT; trap "exit 143" TERM; kill -TERM $$'"'"'; echo "rc=$?"; [ -e "$(cat tmpname)" ] && echo "LEFT BEHIND" || echo "cleaned"'
s 'lock with mkdir (atomic)' 'mkdir lock 2>/dev/null && echo got || echo busy; mkdir lock 2>/dev/null && echo got || echo busy; rmdir lock'
s 'atomic replace: temp file + mv' 'printf old > cfg; tmp=$(mktemp ./cfg.XXXXXX); printf new > "$tmp"; mv -f "$tmp" cfg; cat cfg; echo; ls | grep -c "^cfg\."'
s 'sed -i is not POSIX' 'printf "a\n" > f; sed -i "s/a/b/" f 2>&1; echo "rc=$?"; cat f'
s 'temp file instead of sed -i' 'printf "a\n" > f; sed "s/a/b/" f > f.new && mv f.new f; cat f'
s 'find -exec {} + (POSIX)' 'touch a b; find . -type f -name "[ab]" -exec echo {} + | tr " " "\n" | sort | tr "\n" " "; echo'
s 'find -print0 and xargs -0' 'touch "a b"; find . -type f -name "a b" -print0 | xargs -0 -n1 echo 2>&1 | head -2'
s 'readlink -f' 'ln -s /tmp lnk; readlink -f lnk 2>&1 | head -1'
s 'realpath' 'realpath /tmp/../tmp 2>&1 | head -1'
s 'script directory idiom' 'd=$(cd -P -- "$(dirname -- "$0")" && pwd) && [ -d "$d" ] && [ "$(basename "$d")" = "w$(ls -d ../w* | wc -l | tr -d " ")" ] || echo "dir-ok-or-name-differs"; echo done'
s 'grep -E -F -q -x -c' 'printf "a1\nb2\na1\n" > g; grep -c a1 g; grep -Eq "^[ab][0-9]$" g && echo ere; grep -Fx a1 g | head -1; grep -q zzz g || echo nomatch'
s 'date formats' 'date +%Y-%m-%d | grep -Ec "^[0-9]{4}-[0-9]{2}-[0-9]{2}$"; date -u +%H:%M | grep -Ec "^[0-9]{2}:[0-9]{2}$"'
s 'stat and ls -l parsing' 'touch f; ls -l f | cut -c1-10; stat -c %a f 2>&1 | head -1'
s 'which is not POSIX, command -v is' 'command -v ls | grep -c ls; which ls >/dev/null 2>&1 && echo which-ok || echo which-missing'
s 'test for a command' 'if command -v no_such_tool >/dev/null 2>&1; then echo have; else echo "missing: install it first"; fi'
s 'env var for one command only' 'V=one sh -c '"'"'echo "in: $V"'"'"'; echo "out: ${V-unset}"'
s 'exit status of the last pipeline stage' 'false | true; echo "rc=$?"; (exit 3); echo "rc=$?"'
s 'set -e and && lists' 'set -e; f() { [ -f /nonexistent ] && echo yes; }; f; echo not-reached'
s 'set -e with if' 'set -e; f() { if [ -f /nonexistent ]; then echo yes; fi; }; f; echo after'
s 'unset a function and variable' 'f() { :; }; v=1; unset -f f; unset v; command -v f >/dev/null || echo f-gone; echo "[${v-}]"'
s 'subshell and cd' 'mkdir sub; (cd sub && pwd | sed "s|.*/||"); pwd | sed "s|.*/||" | cut -c1-1'
s 'trap in a function and return' 'f() { trap "echo cleanup-in-f" EXIT; return 5; }; f; echo "rc=$?"'
s 'shell options listing' 'set -eu; echo "$-" | tr -d "ismc" '
s 'detect which shell is running' 'echo "bash=${BASH_VERSION:-no} ksh=${KSH_VERSION:-no} zsh=${ZSH_VERSION:-no}"'
s 'what /bin/sh is here' 'ls -l /bin/sh | tr -s " " | cut -d" " -f9-'
s 'alias needs a later line' 'alias hi="echo aliased"
hi'
s 'test -nt with a pause' 'touch a; sleep 1; touch b; [ b -nt a ] && echo newer || echo not-newer'

cd / && rm -rf "$D"
