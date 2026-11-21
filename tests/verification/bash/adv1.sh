#!/usr/bin/env bash
# Battery 1 for foundations.bash-advanced: mapfile, namerefs, printf -v, declare, shopt, completion, fork avoidance. bash 5.x.
D=$(mktemp -d); cd "$D" || exit 1
echo "bash $BASH_VERSION"
t() { printf '%s\n' "$2" > s.sh; local out rc; out=$(bash s.sh 2>&1); rc=$?; out=${out//$'\n'/ | }; printf '  %-44s rc=%-3s %s\n' "$1" "$rc" "$out"; }

echo '### 1. mapfile / readarray'
printf 'one\ntwo words\nthree\n' > lines.txt
t 'mapfile without -t keeps newlines'        'mapfile a < lines.txt; printf "[%s]" "${a[@]}"; echo "n=${#a[@]}"'
t 'mapfile -t strips them'                   'mapfile -t a < lines.txt; printf "[%s]" "${a[@]}"; echo "n=${#a[@]}"'
t 'the loop it replaces, with the word-split trap' 'a=($(cat lines.txt)); echo "n=${#a[@]}"; printf "[%s]" "${a[@]}"; echo'
t 'mapfile -t -n 2 (first two lines)'        'mapfile -t -n 2 a < lines.txt; echo "${a[@]}"'
t 'mapfile -s 1 (skip one)'                  'mapfile -t -s 1 a < lines.txt; echo "${a[@]}"'
t 'NUL-separated: find -print0 into mapfile' 'touch "a b" c; mapfile -d "" -t f < <(find . -maxdepth 1 -type f -name "[ac]*" -print0 | sort -z); printf "[%s]" "${f[@]}"; echo'
t 'from a command: pipe loses it, < <() keeps it' 'echo x | mapfile -t a; echo "pipe: n=${#a[@]}"; mapfile -t a < <(echo x); echo "procsub: n=${#a[@]}"'
t 'lastpipe makes the pipe form work'        'shopt -s lastpipe; echo x | mapfile -t a; echo "lastpipe: n=${#a[@]}"'
t 'empty input'                              'mapfile -t a < /dev/null; echo "n=${#a[@]}"'
t 'file with no trailing newline'            'printf "a\nb" > nn.txt; mapfile -t a < nn.txt; echo "n=${#a[@]} last=[${a[1]}]"'
t 'while read drops the last unterminated line' 'printf "a\nb" | while read -r l; do echo "[$l]"; done; echo "--"; printf "a\nb" | while read -r l || [ -n "$l" ]; do echo "[$l]"; done'
t 'mapfile with a callback (-C -c)'          'cb() { echo "chunk at index $1"; }; mapfile -t -c 1 -C cb a < lines.txt'

echo '### 2. namerefs (declare -n / local -n)'
t 'a function that fills the caller array'   'fill() { local -n out=$1; out=(x y z); }; fill result; echo "${result[@]}"'
t 'without a nameref (eval/printf -v)'       'fill() { printf -v "$1" "%s" hello; }; fill v; echo "$v"'
t 'nameref to a scalar, modify through it'   'n=1; declare -n r=n; r=5; echo "n=$n"'
t 'a nameref to an element'                  'a=(p q r); declare -n e=a[1]; e=Q; echo "${a[@]}"'
t 'unset removes the target, unset -n the ref' 'x=1; declare -n r=x; unset r; echo "x=[${x-unset}]"; x=1; declare -n r=x; unset -n r; echo "x=[${x-unset}] r=[${r-unset}]"'
t 'name clash: local var has the same name'  'f() { local -n out=$1; out=1; }; g() { local out; f out; echo "g: out=$out"; }; g'
t 'circular nameref is an error'             'declare -n a=b; declare -n b=a; echo "[$a]"'
t 'loop over names with a nameref'           'a=(1 2); b=(3 4 5); for name in a b; do declare -n arr=$name; echo "$name has ${#arr[@]}"; unset -n arr; done'

echo '### 3. printf -v, and printf extras'
t 'printf -v builds a variable, no fork'     'printf -v s "%05d-%s" 42 ab; echo "$s"'
t 'printf -v into an array element'          'printf -v "a[2]" "%s" X; declare -p a'
t 'printf %q quotes for reuse'               'printf "%q\n" "it'"'"'s a \"test\" \$HOME" '
t 'printf %(fmt)T date without forking date' 'printf "%(%Y-%m-%d)T\n" 0; printf "%(%H:%M)T\n" -1 | grep -c ":"'
t '$EPOCHSECONDS and $SECONDS'               'echo "epoch ok: $([ "$EPOCHSECONDS" -gt 1700000000 ] && echo yes)"; SECONDS=0; sleep 1; echo "SECONDS=$SECONDS"'
t '$EPOCHREALTIME has microseconds'          'echo "$EPOCHREALTIME" | grep -Eqc "^[0-9]+\.[0-9]{6}$" && echo "format ok"'
t 'printf reuses the format for extra args'  'printf "[%s]" a b c; echo'
t '${var@Q} quotes'                          'v="a b'"'"'c"; echo "${v@Q}"'
t '${var@U} ${var@L} ${var^^} ${var,,}'      'v="Hello"; echo "${v@U} ${v@L} ${v^^} ${v,,}"'
t '${!prefix*} names'                        'app_a=1 app_b=2; echo "${!app_*}"'
t '${arr[@]:1:2} slice'                      'a=(a b c d); echo "${a[@]:1:2} / last: ${a[-1]} / indexes: ${!a[@]}"'

echo '### 4. declare'
t 'declare -p shows the type and value'      'declare -a a=(1 "b c"); declare -A m=([k]=v); declare -i n=5; declare -r r=1; declare -x e=2; declare -p a m n r e'
t 'declare -i does arithmetic on assignment' 'declare -i n; n=2+3; echo "$n"; n=abc; echo "n=$n"'
t 'declare -r cannot be changed'             'declare -r r=1; r=2; echo "rc=$?"'
t 'readonly vs unset'                        'readonly r=1; unset r; echo "rc=$?"'
t 'declare -l / -u'                          'declare -l lo=ABC; declare -u up=abc; echo "$lo $up"'
t 'declare inside a function is local'       'f() { declare v=inner; }; v=outer; f; echo "$v"'
t 'declare -g sets a global from a function' 'f() { declare -g v=inner; }; f; echo "$v"'
t 'declare -f prints a function'             'f() { echo hi; }; declare -f f'
t 'declare -F lists names only'              'f() { :; }; g() { :; }; declare -F | grep -E " (f|g)$" | tr "\n" ";"'
t 'associative array: no order guarantee'    'declare -A m=([b]=2 [a]=1 [c]=3); for k in "${!m[@]}"; do printf "%s " "$k"; done; echo; for k in $(printf "%s\n" "${!m[@]}" | sort); do printf "%s=%s " "$k" "${m[$k]}"; done; echo'
t 'assoc array without declare -A is indexed' 'm[b]=2; m[a]=1; echo "${#m[@]} ${m[0]}"'
t 'key tests with -v'                        'declare -A m=([k]=v); [[ -v m[k] ]] && echo "k set"; [[ -v m[zz] ]] || echo "zz unset"'
t 'array copy'                               'a=(1 2 3); b=("${a[@]}"); b[0]=X; echo "${a[*]} / ${b[*]}"'
t 'sparse array and length'                  'a=(); a[5]=x; a[9]=y; echo "len=${#a[@]} idx=${!a[@]}"'

echo '### 5. shopt'
mkdir g; touch g/a.txt g/B.TXT g/.hid g/c.log
t 'no match: the glob stays literal'         'cd g; echo *.zzz'
t 'nullglob: no match -> nothing'            'cd g; shopt -s nullglob; echo "[*.zzz]" "[$(echo *.zzz)]"; for f in *.zzz; do echo loop; done; echo done'
t 'failglob: no match -> error'              'cd g; shopt -s failglob; echo *.zzz; echo "rc=$?"'
t 'dotglob: * includes dotfiles'             'cd g; echo *; shopt -s dotglob; echo *'
t 'nocaseglob'                               'cd g; shopt -s nocaseglob; echo *.txt'
t 'extglob: !(*.txt) (shopt on its own line)' "cd g
shopt -s extglob
echo !(*.txt)"
t 'extglob: @(a|B)* and +([ac])*'            "cd g
shopt -s extglob
echo @(a|B)*
echo +([ac])*
echo ?(a).txt a?(.txt)"
t 'extglob: shopt on the line BEFORE (case)'  "shopt -s extglob
case abc in +([a-c])) echo 'all letters a-c';; esac"
t 'extglob inside [[ ]]'                      "shopt -s extglob
[[ report.txt == *.@(txt|log) ]] && echo yes"
t 'globstar: **'                             'mkdir -p g/d/e; touch g/d/e/deep.txt; cd g; shopt -s globstar; echo **/*.txt'
t 'nocasematch in [[ ]] and case'            'shopt -s nocasematch; [[ ABC == abc ]] && echo "match"; case HELLO in hello) echo "case match";; esac'
t 'extglob needs to be on BEFORE the line is parsed' 'shopt -s extglob; echo !(a)'
t 'extglob on the same line: syntax error'   'shopt -s extglob; f() { echo !(a); }; echo ok'
t 'checkwinsize/expand_aliases defaults'     'shopt expand_aliases checkwinsize | tr -s " " | tr "\n" ";"'
t 'shopt -p prints re-usable settings'       'shopt -s nullglob; shopt -p nullglob'
t 'shopt -o is the set -o options'           'shopt -o pipefail errexit | tr -s " " | tr "\n" ";"'
t 'lastpipe with a while loop'               'shopt -s lastpipe; n=0; printf "a\nb\nc\n" | while read -r l; do n=$((n+1)); done; echo "n=$n"; n=0; printf "a\nb\nc\n" | { while read -r l; do n=$((n+1)); done; }; echo "braces: n=$n"'
t 'without lastpipe the counter is lost'     'n=0; printf "a\nb\nc\n" | while read -r l; do n=$((n+1)); done; echo "n=$n"'
t 'process substitution keeps the loop in the shell' 'n=0; while read -r l; do n=$((n+1)); done < <(printf "a\nb\nc\n"); echo "n=$n"'

echo '### 6. completion (compgen works non-interactively)'
t 'compgen -W: words matching a prefix'      'compgen -W "start stop status restart" -- st'
t 'compgen -c: command names'                'compgen -c ls | grep -cx ls'
t 'compgen -A function'                      'myfn() { :; }; compgen -A function my'
t 'compgen -f: files'                        'cd g; compgen -f -- a'
t 'compgen -v: variable names'               'MYVAR=1; compgen -v MYV'
t 'compgen -b: builtins'                     'compgen -b | head -3 | tr "\n" " "'
t 'complete -p is empty in a script'         'complete -W "a b" mytool; complete -p mytool'
t 'COMP_WORDS exists only in a completion function' 'echo "[${COMP_WORDS[*]-unset}]"'
cat > comp-test.sh <<'EOF'
_mytool() {
  local cur=${COMP_WORDS[COMP_CWORD]}
  COMPREPLY=( $(compgen -W "start stop status restart" -- "$cur") )
}
complete -F _mytool mytool
# simulate what readline does when you press TAB after "mytool st"
COMP_WORDS=(mytool st); COMP_CWORD=1
_mytool
echo "candidates: ${COMPREPLY[*]}"
COMP_WORDS=(mytool); COMP_CWORD=1; COMP_WORDS+=("")
_mytool
echo "candidates for empty word: ${COMPREPLY[*]}"
complete -p mytool
EOF
echo '  -- completion function, simulated:'; bash comp-test.sh 2>&1 | sed 's/^/     /'

echo '### 7. avoiding forks (the same task, timed)'
TIMEFORMAT=%R
echo "  default PATH has $(echo "$PATH" | tr ':' '\n' | wc -l) entries; $(echo "$PATH" | tr ':' '\n' | grep -c '^/mnt/') of them are Windows directories (/mnt/...)"
bmp() { local s; s=$( { time (for ((i=0;i<500;i++)); do /usr/bin/basename /a/b >/dev/null; done) ; } 2>&1 ); echo "  500 x /usr/bin/basename (absolute path):  $s s"; }
bmp
s=$( { time (for ((i=0;i<500;i++)); do basename /a/b >/dev/null; done) ; } 2>&1 ); echo "  500 x basename (found via PATH, default PATH): $s s"
OLDPATH=$PATH; PATH=/usr/bin:/bin
s=$( { time (for ((i=0;i<500;i++)); do basename /a/b >/dev/null; done) ; } 2>&1 ); echo "  500 x basename (found via PATH, PATH=/usr/bin:/bin): $s s"
echo '  (the rest of this section runs with PATH=/usr/bin:/bin)'
N=2000
bm() { local label=$1; shift; local s; s=$( { time "$@" >/dev/null; } 2>&1 ); printf '  %-48s %6s s\n' "$label" "$s"; }
f_basename_ext() { local i p=/usr/local/lib/file.tar.gz; for ((i=0;i<N;i++)); do x=$(basename "$p"); done; }
f_basename_bi()  { local i p=/usr/local/lib/file.tar.gz; for ((i=0;i<N;i++)); do x=${p##*/}; done; }
f_expr_ext()     { local i; for ((i=0;i<N;i++)); do x=$(expr "$i" + 1); done; }
f_expr_bi()      { local i; for ((i=0;i<N;i++)); do x=$((i+1)); done; }
f_date_ext()     { local i; for ((i=0;i<N;i++)); do x=$(date +%Y); done; }
f_date_bi()      { local i; for ((i=0;i<N;i++)); do printf -v x '%(%Y)T' -1; done; }
f_upper_ext()    { local i; for ((i=0;i<N;i++)); do x=$(echo "hello" | tr a-z A-Z); done; }
f_upper_bi()     { local i v=hello; for ((i=0;i<N;i++)); do x=${v^^}; done; }
f_cat_ext()      { local i; for ((i=0;i<N;i++)); do x=$(cat lines.txt); done; }
f_cat_bi()       { local i; for ((i=0;i<N;i++)); do x=$(<lines.txt); done; }
f_wc_ext()       { local i; for ((i=0;i<N;i++)); do x=$(echo "$i" | wc -c); done; }
f_len_bi()       { local i; for ((i=0;i<N;i++)); do x=${#i}; done; }
f_grep_ext()     { local i s="hello world"; for ((i=0;i<N;i++)); do echo "$s" | grep -q world; done; }
f_grep_bi()      { local i s="hello world"; for ((i=0;i<N;i++)); do [[ $s == *world* ]]; done; }
f_sed_ext()      { local i s="a-b-c"; for ((i=0;i<N;i++)); do x=$(echo "$s" | sed "s/-/_/g"); done; }
f_sed_bi()       { local i s="a-b-c"; for ((i=0;i<N;i++)); do x=${s//-/_}; done; }
bm 'basename (external)'  f_basename_ext;  bm '${p##*/} (builtin)'       f_basename_bi
bm 'expr (external)'      f_expr_ext;      bm '$(( )) (builtin)'          f_expr_bi
bm 'date +%Y (external)'  f_date_ext;      bm 'printf %(%Y)T (builtin)'   f_date_bi
bm 'echo|tr (2 processes)' f_upper_ext;    bm '${v^^} (builtin)'          f_upper_bi
bm '$(cat file)'          f_cat_ext;       bm '$(<file)'                  f_cat_bi
bm 'echo|wc -c'           f_wc_ext;        bm '${#var}'                   f_len_bi
bm 'echo|grep -q'         f_grep_ext;      bm '[[ == *glob* ]]'           f_grep_bi
bm 'echo|sed s///'        f_sed_ext;       bm '${s//-/_}'                 f_sed_bi
echo '-- builtin or program? type -a:'
t 'type -a echo / printf / test / kill'      'type -a echo printf test kill | tr "\n" ";"'
t 'time of a loop vs one awk on 50000 lines' 'seq 1 50000 > big.txt; TIMEFORMAT=%R; echo "bash loop: $( { time (n=0; while read -r l; do n=$((n+l)); done < big.txt; echo $n) >/dev/null; } 2>&1 ) s"; echo "awk:       $( { time awk "{s+=\$1} END{print s}" big.txt >/dev/null; } 2>&1 ) s"'

echo '### 8. other advanced features'
t 'BASHPID vs $$ in a subshell'              'echo "main: $$=$BASHPID"; ( echo "sub: \$\$=$$ BASHPID differs: $([ "$BASHPID" != "$$" ] && echo yes)" )'
t 'wait -n: first job to finish'             '(sleep 1; exit 3) & (sleep 0.2; exit 4) & wait -n; echo "first finished rc=$?"; wait; echo "all done"'
t 'coproc'                                   'coproc W { cat; }; echo hello >&"${W[1]}"; read -r -t 2 line <&"${W[0]}"; echo "got: $line"; kill $W_PID 2>/dev/null'
t 'read -t timeout'                          'read -t 1 x < <(sleep 3); echo "rc=$? (>128 = timed out)"'
t 'read -n 1 / -s / -p only on a terminal'   'echo abc | { read -n 1 c; echo "[$c]"; }'
t 'trap DEBUG and FUNCNAME stack'            'a() { b; }; b() { echo "${FUNCNAME[*]}"; }; a'
t 'BASH_REMATCH capture groups'              '[[ "2026-11-21" =~ ^([0-9]+)-([0-9]+)-([0-9]+)$ ]] && echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"'
t 'regex in a variable (do not quote it)'    'p="^a.c$"; [[ abc =~ $p ]] && echo unquoted-match; [[ abc =~ "$p" ]] || echo quoted-no-match'
t 'select needs a terminal; PS3'             'PS3="pick: "; echo 2 | select x in a b c; do echo "chose $x"; break; done'
t 'bash --version first line'                'bash --version | head -1'
t 'BASH_VERSINFO'                            'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"'
t 'guard a feature by version'               '[ "${BASH_VERSINFO[0]}" -ge 4 ] && echo "associative arrays ok" || echo "need bash 4"'

cd / && rm -rf "$D"
