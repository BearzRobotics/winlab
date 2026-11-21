#!/usr/bin/env bash
# Which expansion features exist in dash and busybox ash? (portable-subset check for the expansion lesson)
BUSYBOX="$HOME/tools/busybox"
t() {
  echo "### $1"
  for sh in "bash" "dash" "$BUSYBOX ash"; do
    # shellcheck disable=SC2086
    out=$($sh -c "$2" 2>&1); rc=$?; out=${out//$'\n'/ | }
    printf '  %-14s rc=%-3s %s\n' "${sh##*/}" "$rc" "${out:0:100}"
  done
}
t 'length ${#v}'                     'v=hello; echo ${#v}'
t 'default ${v:-d}'                  'unset v; echo ${v:-d}'
t 'assign default ${v:=d}'           'unset v; echo ${v:=d} $v'
t 'error ${v:?msg}'                  'unset v; echo ${v:?need v}'
t 'alt ${v:+x}'                      'v=1; echo ${v:+x}'
t 'trim ${v#p} ${v##p} ${v%s} ${v%%s}' 'v=a.b.c; echo ${v#*.} ${v##*.} ${v%.*} ${v%%.*}'
t 'substring ${v:1:3}'               'v=hello; echo ${v:1:3}'
t 'replace ${v/l/L}'                 'v=hello; echo ${v/l/L}'
t 'upper ${v^^}'                     'v=hello; echo ${v^^}'
t 'indirect ${!n}'                   'a=1; n=a; echo ${!n}'
t 'arith $((2**3))'                  'echo $((2**3))'
t 'arith $((i++))'                   'i=1; echo $((i++)) $i'
t 'arith $((010)) octal'             'echo $((010))'
t 'arith $((0x1f))'                  'echo $((0x1f))'
t 'arith $((2#101)) base'            'echo $((2#101))'
t 'arith ternary'                    'echo $((3>2 ? 10 : 20))'
t 'arith $((a+b)) names'             'a=2 b=3; echo $((a+b))'
t 'arith float'                      'echo $((3.5+1))'
t 'arith divide by zero'             'echo $((1/0))'
t 'arith on junk string'             'v=abc; echo $((v + 1))'
t 'arith injection a[$(...)]'        'v='"'"'a[$(echo INJECTED >&2)]'"'"'; echo $((v))'
t '"$@" with no args'                'set --; for x in "$@"; do echo X; done; echo done'
t 'set -- and shift'                 'set -- a b c; shift; echo $# $*'
t 'IFS splitting'                    'IFS=:; set -- $(echo a:b::c); echo $#'
t 'command subst trailing newline'   'echo "[$(printf "a\n\n")]"'
t 'backtick vs $( ) nesting'         'echo $(echo $(echo deep))'
t 'glob no match literal'            'cd /tmp; echo /nonexistent-dir/*.x'
t 'tilde'                            'echo ~ ~root'
t 'quoted tilde'                     'echo "~"'
t 'here-doc'                         'cat <<EOF
x=$((1+1))
EOF'
t 'read -r IFS split'                'IFS=: read -r a b <<EOF
1:2
EOF
echo $a $b'
t 'arrays via set --'                'set -- "a b" c; for x in "$@"; do echo "[$x]"; done'
t 'extglob in dash'                  'echo @(a|b)'
t 'case pattern with |'              'case b in a|b) echo yes;; esac'
t 'case with [[:alpha:]]'            'case x in [[:alpha:]]) echo alpha;; esac'
t 'printf %s with no args'           'printf "[%s]\n"'
t 'printf reuse format'              'printf "[%s]" a b c; echo'
t 'unset -v / unset -f'              'v=1; unset -v v; echo "[${v-unset}]"'
t 'export var=value'                 'export V=1; sh -c "echo \$V"'
t 'readonly'                         'readonly R=1; R=2; echo after'
t 'local in a function'              'f() { local x=1; x=2; }; x=0; f; echo $x'
t 'test -n unquoted var (trap)'      'v=""; [ -n $v ] && echo "TRUE (wrong)" || echo false'
t 'test -n quoted var'               'v=""; [ -n "$v" ] && echo true || echo "false (right)"'
