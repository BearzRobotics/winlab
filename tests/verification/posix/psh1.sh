#!/usr/bin/env bash
# POSIX sh comparison battery. The DRIVER is bash (it only collects results); the snippets run in the shells under test.
# Usage: psh1.sh NAME=COMMAND [NAME=COMMAND ...]     e.g.  psh1.sh dash=dash ash="$HOME/tools/busybox ash"
# Optional: SHELLCHECK=/path/to/shellcheck adds a column with the first SC3xxx (POSIX) finding of `shellcheck -s sh`.
D=$(mktemp -d); cd "$D" || exit 1
names=(); cmds=()
for a in "$@"; do names+=("${a%%=*}"); cmds+=("${a#*=}"); done
T=; command -v timeout >/dev/null 2>&1 && T="timeout 5"
echo "driver: bash $BASH_VERSION; shells: ${names[*]}"
for i in "${!names[@]}"; do
  v=$(${cmds[$i]} -c 'echo "${BASH_VERSION:-no-bash} / ${KSH_VERSION:-no-ksh}"' 2>&1 | head -1)
  echo "  ${names[$i]}: ${cmds[$i]}  ($v)"
done

n=0
s() { # label, code
  n=$((n+1))
  local label=$1 code=$2 res=() i out rc
  printf '%s\n' "$code" > s.sh
  for i in "${!names[@]}"; do
    out=$($T ${cmds[$i]} s.sh </dev/null 2>&1); rc=$?
    out=${out//$'\n'/ | }
    res+=("rc=$rc ${out:0:150}")
  done
  local same=1
  for i in "${!res[@]}"; do [ "${res[$i]}" = "${res[0]}" ] || same=0; done
  local sc=
  if [ -n "${SHELLCHECK:-}" ]; then
    printf '#!/bin/sh\n%s\n' "$code" > sc.sh
    sc=$("$SHELLCHECK" -s sh -f gcc sc.sh 2>&1 | grep -o 'SC3[0-9]*' | head -1)
    sc=" [shellcheck -s sh: ${sc:-no SC3 finding}]"
  fi
  if [ "$same" = 1 ]; then
    printf '%3d %-34s ALL: %s%s\n' "$n" "$label" "${res[0]}" "$sc"
  else
    printf '%3d %-34s DIFFER%s\n' "$n" "$label" "$sc"
    for i in "${!names[@]}"; do printf '      %-8s %s\n' "${names[$i]}" "${res[$i]}"; done
  fi
}

echo '### A. POSIX core: expected to behave the same everywhere'
s 'unquoted $v splits'          'v="a b"; set -- $v; echo $#; set -- "$v"; echo $#'
s 'command substitution'        'echo "$(echo hi) $(printf x)"'
s 'arithmetic'                  'echo $((2+3*4)) $((7/2)) $((7%3)) $((-7/2)) $((1<<3)) $((5>3))'
s 'parameter trimming'          'v=/a/b.tar.gz; echo "${v#*/} ${v##*/} ${v%.*} ${v%%.*} ${#v}"'
s 'defaults :- - := :+'         'unset u; echo "${u:-d} ${u-d}"; e=; echo "[${e:-d}] [${e-d}]"; echo "${u:=set} $u"; echo "[${e:+alt}]"'
s ':? aborts a script'          'unset u; echo "${u:?missing}"; echo after'
s 'case with patterns'          'case foo.txt in *.txt|*.md) echo text;; *) echo other;; esac; case x in [a-c]) echo abc;; *) echo no;; esac'
s '[ ] numeric and string'      '[ -n "x" ] && [ 3 -gt 2 ] && [ a = a ] && [ a != b ] && echo ok'
s 'set -- and shift'            'set -- a b c; shift; echo "$# $*"; for x; do echo "arg=$x"; done'
s '${10} needs braces'          'set -- 1 2 3 4 5 6 7 8 9 10; echo "$10 ${10}"'
s '"$@" versus "$*"'            'set -- "a b" c; for x in "$@"; do printf "[%s]" "$x"; done; echo; for x in "$*"; do printf "[%s]" "$x"; done; echo'
s 'while read -r'               'printf "a b\nc d\n" | while read -r x y; do echo "$y-$x"; done'
s 'here-document'               'x=5
cat <<EOF
x=$x sum=$((1+1)) $(echo cmd)
EOF'
s 'quoted here-document'        "cat <<'EOF'
\$HOME \$(date) \\\\n
EOF"
s 'here-doc <<- strips tabs'    "cat <<-EOF
	tabbed line
	EOF"
s 'function, return status'     'f() { echo "in f: $1"; return 3; }; f x; echo "rc=$?"'
s 'getopts'                     'set -- -a -b val rest; while getopts ab: o; do echo "$o=${OPTARG:-}"; done; shift $((OPTIND-1)); echo "left: $*"'
s 'trap EXIT'                   'trap "echo bye" EXIT; echo hi'
s 'trap TERM on itself'         'trap "echo got-TERM; exit 7" TERM; kill -TERM $$; echo not-reached'
s 'printf formats'              'printf "%s|%5d|%-5s|%x|%o|%c|%%\n" a 42 ab 255 8 xyz'
s 'printf reuses the format'    'printf "[%s]" a b c; echo'
s 'echo with a backslash'       "echo 'a\\tb'"
s 'command -v'                  'command -v ls >/dev/null && echo found; command -v no_such_cmd_x || echo missing'
s 'IFS splitting'               'IFS=:; set -- a:b:c; echo $#; v="x:y z"; set -- $v; echo "$# [$1] [$2]"'
s 'IFS with read'               'IFS=: read -r a b <<EOF
1:2:3
EOF
echo "[$a] [$b]"'
s 'eval'                        'x="echo hi"; eval "$x"'
s 'exec and file descriptors'   'exec 3>&1; echo to-fd3 >&3; echo err >&2 2>/dev/null; echo done'
s 'dot sourcing with ./'        'echo "v=1" > l.sh; . ./l.sh; echo "v=$v"'
s 'redirect stderr to stdout'   '{ echo out; echo err >&2; } 2>&1 | sort | tr "\n" ,'
s 'pipeline status is the last' 'false | true; echo $?; true | false; echo $?'
s 'set -e basics'               'set -e; false; echo not-reached'
s 'set -e not in conditions'    'set -e; if false; then :; fi; false || echo handled; echo after'
s 'set -u'                      'set -u; echo "[$undefined]"; echo not-reached'
s 'unset -v and readonly'       'readonly r=1; r=2; echo after'
s 'wait for a background job'   'sleep 0.1 & wait $!; echo "rc=$?"'
s '$? after assignment'         'x=$(false); echo $?'
s 'arithmetic assignment'       'i=5; i=$((i+2)); echo $i; echo $((i*=2)) $i'
s 'string comparison in [ ]'    '[ "a b" = "a b" ] && echo same; [ "" ] || echo empty-is-false'
s 'test -e -f -d -r -w -x'      'touch f; mkdir d; [ -e f ] && [ -f f ] && [ -d d ] && [ -r f ] && [ -w f ] && [ ! -x f ] && echo ok'
s 'umask and chmod'             'umask 077; touch u; ls -l u | cut -c1-10'
s 'tilde and $HOME'             'HOME=/h; echo ~ ~/x "~"'
s 'glob no match stays literal' 'echo *.zzz [a]*.zzz'
s 'parameter expansion nesting' 'v=abc; echo "${v%c}d ${v#a}${v%%c*}"'
s 'case without a match'        'case x in y) echo y;; esac; echo "rc=$?"'
s 'exit status of case'         'case x in x) false;; esac; echo "rc=$?"'
s 'for with a list and glob'    'touch a1 a2; for f in a*; do printf "[%s]" "$f"; done; echo'
s 'positional with set --'      'set -- 1 2 3; set -- "$@" 4; echo "$# $*"'
s 'shift past the end'          'set -- a; shift 2; echo "rc=$?"'
s '$0 and $$ and $!'            'echo "$0"; [ "$$" -gt 0 ] && echo pid-ok; sleep 0.1 & [ "$!" -gt 0 ] && echo bgpid-ok; wait'
s 'local variable (not POSIX)'  'f() { local x=1; echo $x; }; x=g; f; echo $x'
s 'local with no value'         'f() { local y; echo "[${y-unset}]"; }; y=g; f'

echo '### B. Features that are NOT POSIX: which shells accept them?'
s 'echo -n'                     'echo -n x; echo y'
s 'echo -e'                     "echo -e 'a\\tb'"
s '== in [ ]'                   '[ a == a ] && echo eq'
s '[[ ]]'                       '[[ a == a ]] && echo eq'
s '[ -a ] and [ -o ]'           '[ -n x -a -n y ] && echo and; [ -z x -o -n y ] && echo or'
s 'arrays'                      'a=(1 2 3); echo "${a[1]} ${#a[@]}"'
s '${v:1:2} substring'          'v=abcdef; echo "${v:1:2}"'
s '${v/a/b} replace'            'v=banana; echo "${v/a/o} ${v//a/o}"'
s '${v^^} ${v,,} case'          'v=Hello; echo "${v^^} ${v,,}"'
s '${!name} indirection'        'a=b; b=val; echo "${!a}"'
s "\$'...' strings"             "echo \$'a\\tb'"
s '<<< here-string'             'read -r x <<< "hello"; echo "$x"'
s '<( ) process substitution'   'cat <(echo hi)'
s '&> redirect both'            'echo hi &> /dev/null; echo done'
s '|& pipe both'                'echo hi |& cat'
s '(( )) arithmetic command'    'i=1; ((i++)); echo $i'
s '$((i++)) post-increment'     'i=1; echo $((i++)) $i'
s '{1..3} brace expansion'      'echo {1..3} {a,b}x'
s 'function f { } keyword'      'function f { echo hi; }; f'
s 'source command'              'echo "v=1" > l.sh; source ./l.sh; echo "v=$v"'
s '. l.sh (no ./, not in PATH)' 'echo "v=1" > l.sh; . l.sh; echo "v=$v"'
s 'let'                         'let "i = 2 + 3"; echo $i'
s 'declare / typeset'           'declare -i n=5; echo $n'
s 'export -n / export VAR=x'    'export V=x; sh -c "echo \$V"'
s 'read -p prompt'              'read -p "q? " x </dev/null; echo "rc=$?"'
s 'read -n 1'                   'echo abc | { read -n 1 c; echo "[$c]"; }'
s 'read -a'                     'echo "a b c" | { read -a arr; echo "${arr[1]}"; }'
s 'printf -v'                   'printf -v s "%03d" 7; echo $s'
s 'printf %q'                   'printf "%q\n" "a b"'
s 'mapfile'                     'printf "a\nb\n" | { mapfile -t x; echo "${#x[@]}"; }'
s '$RANDOM'                     '[ -n "$RANDOM" ] && echo has-RANDOM || echo no-RANDOM'
s '$SECONDS'                    '[ -n "$SECONDS" ] && echo has-SECONDS || echo no-SECONDS'
s '$LINENO'                     'echo "line $LINENO"'
s '$OSTYPE'                     'echo "[${OSTYPE:-unset}]"'
s '$HOSTNAME'                   '[ -n "${HOSTNAME-}" ] && echo has || echo unset'
s '$UID and $EUID'              'echo "[${UID-unset}] [${EUID-unset}]" | sed "s/[0-9][0-9]*/N/g"'
s 'set -o pipefail'             'set -o pipefail; false | true; echo $?'
s 'trap ERR'                    'trap "echo err" ERR; false; echo after'
s 'trap with SIG prefix'        'trap "echo t" SIGTERM; kill -TERM $$; echo after'
s 'trap DEBUG / RETURN'         'trap "echo dbg" DEBUG; echo x'
s 'pushd / popd'                'pushd /tmp >/dev/null; pwd; popd >/dev/null'
s 'test -v var'                 'x=1; [ -v x ] && echo set'
s 'test with -nt (newer)'       'touch a; sleep 0.01; touch b; [ b -nt a ] && echo newer'
s 'select'                      'echo 1 | select x in a b; do echo "$x"; break; done'
s 'coproc'                      'coproc cat; echo hi >&"${COPROC[1]}"; read -r l <&"${COPROC[0]}"; echo "$l"'
s 'shopt'                       'shopt -s nullglob; echo ok'
s 'time keyword'                'time true 2>&1 | head -1; echo done'
s 'extglob @(a|b)'              'shopt -s extglob 2>/dev/null; case a in @(a|b)) echo m;; esac'
s '** recursive glob'           'mkdir -p x/y; touch x/y/f.txt; echo **/*.txt'
s 'case ;& fallthrough'         'case a in a) echo one;& b) echo two;; esac'
s 'ansi-c in case/..'           'echo ${BASH_VERSION-x}${KSH_VERSION-y}'
s '$(<file)'                    'echo hi > f; x=$(<f); echo "[$x]"'
s 'local -n nameref'            'f() { local -n r=$1; r=5; }; f v; echo "$v"'
s 'wait -n'                     'sleep 0.1 & wait -n; echo "rc=$?"'
s 'kill -l and kill -s'         'kill -l | head -c 30 | tr "\n" " "; echo; sleep 5 & kill -s TERM $!; wait $! 2>/dev/null; echo "rc=$?"'
s 'getopts with a leading colon' 'set -- -x; while getopts :a o; do echo "o=$o OPTARG=${OPTARG-}"; done'
s '$((2**3)) exponent'          'echo $((2**3))'
s 'unset -f / unset var'        'f() { :; }; unset -f f; f 2>/dev/null; echo "rc=$?"'
s 'set -- with options'         'set -- -x -- a; echo "$#: $*"'
s 'alias in a script'           'alias hi="echo aliased"; hi 2>&1 | head -1'
s 'ulimit -n'                   'ulimit -n >/dev/null && echo ok'
s 'type -t'                     'type -t ls 2>&1 | head -1'
s 'which as a builtin'          'type which 2>&1 | head -1'

echo '### C. Syntax errors and how each shell reports them'
s 'unclosed if'                 'if true; then echo hi'
s 'unexpected )'                'echo hi )'
s 'unterminated quote'          'echo "oops'
s 'bad substitution ${v:1}'     'v=abc; echo ${v:1}'
s 'bad substitution ${v//a/b}'  'v=abc; echo ${v//a/b}'
s '[[ in a sh script'           '[[ -n x ]] && echo yes'

cd / && rm -rf "$D"
