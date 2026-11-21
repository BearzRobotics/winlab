#!/usr/bin/env bash
# Battery for foundations.shells-and-posix: run each snippet under several shells and print what happened.
# Run from WSL:  bash shells1.sh      (needs ~/tools/busybox; see docs/HANDOFF.md)
BUSYBOX="$HOME/tools/busybox"
SHDIR=$(mktemp -d)
ln -s "$(command -v bash)" "$SHDIR/sh"      # bash invoked as "sh": POSIX mode, like /bin/sh on some distributions

declare -A SHELLS=(
  [bash]="bash"
  [dash]="dash"
  [ash]="$BUSYBOX ash"
  [bash-as-sh]="$SHDIR/sh"
)
ORDER=(bash dash ash bash-as-sh)

run() {   # run <name> <snippet>
  local name=$1 snippet=$2 out rc
  # shellcheck disable=SC2086
  out=$(${SHELLS[$name]} -c "$snippet" 2>&1)
  rc=$?
  out=${out//$'\n'/ | }
  printf '  %-11s rc=%-3s %s\n' "$name" "$rc" "${out:0:110}"
}

try() {   # try <label> <snippet>
  echo "### $1"
  echo "    $2"
  for s in "${ORDER[@]}"; do run "$s" "$2"; done
}

echo "bash:  $(bash --version | head -1)"
echo "dash:  $(dash -c 'echo dash present')"
echo "ash:   $($BUSYBOX | head -1)"
echo "/bin/sh on this machine -> $(readlink -f /bin/sh)"
echo

try '[[ ]]'                       '[[ abc == a* ]] && echo match'
try '== inside [ ]'               '[ a == a ] && echo equal'
try '= inside [ ]'                '[ a = a ] && echo equal'
try 'arrays'                      'a=(x y z); echo ${a[1]}'
try 'brace expansion'             'echo {1..3}'
try 'echo -e'                     'echo -e "a\tb"'
try 'echo -n'                     'echo -n hi; echo'
try 'printf (portable)'           'printf "%s\n" "a\tb" ; printf "a\tb\n"'
try '$'"'"'...'"'"' quoting'      'echo $'"'"'a\tb'"'"
try 'process substitution'        'cat <(echo hi)'
try '${var//a/b}'                 'v=banana; echo ${v//a/o}'
try '${var,,}'                    'v=ABC; echo ${v,,}'
try '${var#prefix} (POSIX)'       'v=foo.txt; echo ${v%.txt} ${v#foo}'
try 'function keyword'            'function f { echo hi; }; f'
try 'f() { } (POSIX)'             'f() { echo hi; }; f'
try 'local'                       'f() { local x=1; echo $x; }; f'
try 'source'                      'echo "echo sourced" > /tmp/wl-src.sh; source /tmp/wl-src.sh'
try '. (POSIX dot)'               'echo "echo sourced" > /tmp/wl-src.sh; . /tmp/wl-src.sh'
try '&> redirect'                 'ls /nonexistent &> /tmp/wl-both.txt; echo rc=$?; ls /tmp/wl-both.txt'
try '>file 2>&1 (POSIX)'          'ls /nonexistent > /tmp/wl-both2.txt 2>&1; echo rc=$?'
try '(( )) arithmetic'            '((x = 2 + 3)); echo $x'
try '$(( )) arithmetic (POSIX)'   'echo $((2 + 3))'
try 'let'                         'let x=2+3; echo $x'
try 'pipefail'                    'set -o pipefail; false | true; echo rc=$?'
try '$RANDOM'                     'echo ${RANDOM:+has RANDOM}'
try 'read -p'                     'echo abc | read -p "q: " v; echo done'
try 'select'                      'echo 1 | select x in a b; do echo $x; break; done'
try 'indirect ${!v}'              'a=b; b=c; echo ${!a}'
try 'printf %q'                   'printf "%q\n" "a b"'
try '$BASH_VERSION'               'echo ${BASH_VERSION:-unset}'
try '$0 and $LINENO'              'echo $0 $LINENO'
try 'test -a/-o (obsolete)'       '[ -n a -a -n b ] && echo both'
try 'string compare < in [[ ]]'   '[[ a < b ]] && echo lt'
try 'local -r / declare'          'declare -i n=3; echo $n'
try 'typeset (ksh/bash)'          'typeset v=1; echo $v'
try 'trap ERR'                    'trap "echo ERR" ERR; false; echo end'
try 'trap EXIT (POSIX)'           'trap "echo bye" EXIT; echo hi'
try 'here-string <<<'             'cat <<< hi'
try 'time keyword'                'time true 2>&1 | head -1'
try 'command -v (POSIX)'          'command -v ls >/dev/null && echo found'
try 'type -a'                     'type -a ls | head -1'
try 'which'                       'which ls >/dev/null && echo found'
try 'unset var, set -u'           'set -u; echo ${undefined}'
try 'getopts (POSIX)'             'set -- -a -b x; while getopts ab: o; do echo "$o=$OPTARG"; done'
try 'shopt'                       'shopt -s nullglob; echo ok'
try 'mapfile'                     'printf "a\nb\n" | { mapfile -t arr; echo ${#arr[@]}; }'
try 'case with ;&'                'case a in a) echo one ;& b) echo two ;; esac'
try '[ -v var ]'                  'x=1; [ -v x ] && echo set'
try 'echo with -- and -n -e mix'  'echo -ne "x\n"'
try 'which shell? $0 in -c'       'echo "$0"'

echo
echo "### sh -> which shell, and what the shebang decides"
printf '#!/bin/sh\n[[ a == a ]] && echo "bashism ran"\n' > /tmp/wl-sh-shebang.sh
printf '#!/usr/bin/env bash\n[[ a == a ]] && echo "bashism ran"\n' > /tmp/wl-bash-shebang.sh
chmod +x /tmp/wl-sh-shebang.sh /tmp/wl-bash-shebang.sh
echo "  #!/bin/sh script:   $(/tmp/wl-sh-shebang.sh 2>&1 | head -1)   (rc=$?)"
echo "  #!/usr/bin/env bash: $(/tmp/wl-bash-shebang.sh 2>&1 | head -1)"
echo "  running a #!/bin/sh file with 'bash file': $(bash /tmp/wl-sh-shebang.sh 2>&1 | head -1)"
echo "  shebang is ignored when you type 'bash script' or 'dash script': the shell you typed wins"
rm -rf "$SHDIR" /tmp/wl-src.sh /tmp/wl-both*.txt /tmp/wl-*shebang.sh
