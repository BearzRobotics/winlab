#!/usr/bin/env bash
# Battery 1 for foundations.bash-robust-scripts: what set -e, set -u, pipefail and ERR traps really do. bash 5.x.
D=$(mktemp -d); cd "$D" || exit 1
echo "bash $BASH_VERSION"
# t <label> <script text>: run the text as a script in a fresh bash and show output + exit status.
t() {
  printf '%s\n' "$2" > s.sh
  local out rc
  out=$(bash s.sh 2>&1); rc=$?
  out=${out//$'\n'/ | }
  printf '  %-46s rc=%-3s %s\n' "$1" "$rc" "$out"
}

echo '### 1. set -e: where it stops the script and where it silently does not'
t 'no set -e: carries on'                      'false; echo after'
t 'set -e: stops at a bare failure'            'set -e; false; echo after'
t 'set -e, failure on the left of &&'          'set -e; false && echo x; echo after'
t 'set -e, failure as the LAST of an && list'  'set -e; true && false; echo NOT-REACHED'
t 'set -e, failure after ||'                   'set -e; false || echo handled; echo after'
t 'set -e, failure in an if condition'         'set -e; if false; then :; fi; echo after'
t 'set -e, failure in a while condition'       'set -e; while false; do :; done; echo after'
t 'set -e, negated with !'                     'set -e; ! false; echo after; ! true; echo "after !true"'
t 'set -e, function called plainly'            'set -e; f() { false; echo inside; }; f; echo after'
t 'set -e, function called in an if'           'set -e; f() { false; echo inside; }; if f; then echo yes; fi; echo after'
t 'set -e, function called before ||'          'set -e; f() { false; echo inside; }; f || echo handled; echo after'
t 'set -e, [ ] && echo as the last line of f'  'set -e; f() { [ -f /nonexistent ] && echo yes; }; f; echo NOT-REACHED'
t 'set -e, the same with if instead'           'set -e; f() { if [ -f /nonexistent ]; then echo yes; fi; }; f; echo after'
t 'set -e, subshell failure'                   'set -e; ( false; echo in-subshell ); echo NOT-REACHED'
t 'set -e, failure inside a subshell in if'    'set -e; if ( false; echo in-subshell ); then echo yes; fi; echo after'
t 'set -e, ((i++)) when i is 0'                'set -e; i=0; ((i++)); echo NOT-REACHED'
t 'set -e, i=$((i+1)) instead'                 'set -e; i=0; i=$((i+1)); echo "after i=$i"'
t 'set -e, grep with no match'                 'set -e; grep -q zzz /etc/passwd; echo NOT-REACHED'
t 'set -e, grep no match guarded with || true' 'set -e; grep -q zzz /etc/passwd || true; echo after'
t 'set -e, read at end of file'                'set -e; read -r x < /dev/null; echo NOT-REACHED'
t 'set +e switches it off for a region'        'set -e; set +e; false; echo "survived"; set -e; false; echo NOT-REACHED'
t 'set -e inside a function called in an if: even later lines run' 'set -e; f() { false; true; echo "f continued"; }; if f; then echo ok; fi'

echo '### 2. command substitution and set -e'
t 'x=$(false) stops'                           'set -e; x=$(false); echo NOT-REACHED'
t 'echo "$(false)" does not stop'              'set -e; echo "[$(false)]"; echo after'
t 'local x=$(false) does not stop'             'set -e; f() { local x=$(false); echo "local survived rc=$?"; }; f'
t 'local x; x=$(false) stops'                  'set -e; f() { local x; x=$(false); echo NOT-REACHED; }; f; echo after'
t 'export X=$(false) does not stop'            'set -e; export X=$(false); echo after'
t 'false; true inside $( ) is not inherited'   'set -e; x=$(false; echo ran); echo "x=[$x]"'
t 'with shopt -s inherit_errexit'              'set -e; shopt -s inherit_errexit; x=$(false; echo ran); echo "x=[$x]"'

echo '### 3. set -u'
t 'unset variable, no -u'                      'echo "[$undefined]"'
t 'unset variable, set -u'                     'set -u; echo "[$undefined]"'
t 'with a default ${v-}'                       'set -u; echo "[${undefined-}]"'
t 'unset positional $1'                        'set -u; echo "[$1]"'
t 'positional with default ${1-none}'          'set -u; echo "[${1-none}]"'
t '$@ with no arguments'                       'set -u; for a in "$@"; do echo x; done; echo "[ok]"'
t 'empty array "${a[@]}"'                      'set -u; a=(); echo "[${a[@]}]"'
t 'unset array element'                        'set -u; a=(x); echo "[${a[3]}]"'
t 'declared but unset: local x'                'set -u; f() { local x; echo "[$x]"; }; f'
t 'declared with empty value'                  'set -u; f() { local x=; echo "[$x]"; }; f'
t 'a typo caught'                              'set -u; name=Bob; echo "Hi $nmae"'
t '[ -z "$v" ] on unset v'                     'set -u; [ -z "$v" ] && echo empty'
t '[[ -v v ]] is safe under set -u'            'set -u; [[ -v v ]] || echo "unset (tested safely)"'
t 'set -u in a sourced file affects the caller' 'echo "set -u" > lib.sh; . ./lib.sh; echo "[$unset_in_caller]"'

echo '### 4. pipefail'
t 'false | true'                               'false | true; echo "rc=$?"'
t 'false | true, pipefail'                     'set -o pipefail; false | true; echo "rc=$?"'
t 'PIPESTATUS keeps every stage'               'false | true | false; echo "${PIPESTATUS[*]}"'
t 'yes | head -1 under pipefail (SIGPIPE)'     'set -o pipefail; yes | head -1; echo "rc=$?  PIPESTATUS=${PIPESTATUS[*]}"'
t 'set -eo pipefail and yes | head -1'        'set -eo pipefail; yes | head -1; echo NOT-REACHED'
t 'only the pipeline you want without pipefail' 'set -o pipefail; yes | head -1 || true; echo after'
t 'turn pipefail off for one pipeline'         'set -o pipefail; set +o pipefail; yes | head -1; set -o pipefail; echo "rc=$?"'
t 'set -e with a failing early pipeline stage' 'set -eo pipefail; false | cat; echo NOT-REACHED'

echo '### 5. ERR trap, errtrace, line numbers'
t 'ERR trap in the main script'                'trap "echo ERR at line \$LINENO" ERR; false; echo after'
t 'ERR trap does not fire inside a function'   'trap "echo ERR at line \$LINENO" ERR; f() { false; }; f; echo after'
t 'with set -E it does'                        'set -E; trap "echo ERR at line \$LINENO" ERR; f() { false; }; f; echo after'
t 'ERR + set -e: report then exit'             'set -eE; trap "echo failed at line \$LINENO: \$BASH_COMMAND >&2" ERR; ls /nonexistent 2>/dev/null; echo NOT-REACHED'
t 'caller inside a function'                   'f() { caller 0; }; f'
t 'ERR trap not fired in an if condition'      'trap "echo ERR" ERR; if false; then :; fi; echo after'
t 'ERR trap not fired after ||'                'trap "echo ERR" ERR; false || true; echo after'

echo '### 6. exit status in EXIT traps and cleanup'
t 'EXIT trap sees the failing status'          'set -e; trap "echo trap-saw-rc=\$?" EXIT; false'
t 'a failing cleanup command changes nothing'  'trap "false; echo cleanup-ran" EXIT; exit 0'
t 'cleanup that overrides the status'          'trap "exit 9" EXIT; exit 0'

echo '### 7. strict-mode surprises, one table'
t 'set -euo pipefail: [[ ]] && as last line'   'set -euo pipefail; f() { [[ -n "" ]] && echo yes; }; f; echo NOT-REACHED'
t 'same, with || true'                         'set -euo pipefail; f() { [[ -n "" ]] && echo yes || true; }; f; echo after'
t 'same, with if (what to write)'              'set -euo pipefail; f() { if [[ -n "" ]]; then echo yes; fi; }; f; echo after'
t 'a loop whose last test fails'               'set -e; for i in 1 2; do [ "$i" = 1 ] && echo one; done; echo NOT-REACHED'
t 'cd failure is caught by set -e'             'set -e; cd /nonexistent; echo NOT-REACHED'
t 'without set -e cd fails and rm -n would run' 'cd /nonexistent 2>/dev/null; echo "still in: $(basename "$PWD" | cut -c1-3)..."'
t 'cd ... || exit is explicit and works anywhere' 'cd /nonexistent 2>/dev/null || { echo "cd failed" >&2; exit 1; }; echo NOT-REACHED'
t 'set -e is not inherited by a script it runs' 'echo "false; echo child-continued" > child.sh; set -e; bash child.sh; echo "parent after child rc=$?"'
t 'set -e is inherited by source'              'echo "false; echo lib-continued" > lib.sh; set -e; . ./lib.sh; echo NOT-REACHED'
t 'BASHOPTS/SHELLOPTS pass to children'        'set -e; export SHELLOPTS; bash -c "false; echo child-continued"; echo parent'

cd / && rm -rf "$D"
