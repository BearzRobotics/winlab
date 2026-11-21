#!/usr/bin/env bash
# Battery 1 for foundations.bash-variables-and-expansion (bash 5.x). Writes only in a temp folder.
D=$(mktemp -d); cd "$D" || exit 1
echo "bash $BASH_VERSION"
args() { printf '%d args:' "$#"; printf ' [%s]' "$@"; echo; }

echo '### 1. quoting and word splitting'
f="my notes.txt"
echo -n 'unquoted  $f : '; args $f
echo -n 'quoted   "$f" : '; args "$f"
empty=""
echo -n 'unquoted empty : '; args $empty
echo -n 'quoted empty   : '; args "$empty"
echo -n 'unset var, unquoted: '; args $nosuchvar
touch a.txt b.txt "c d.txt"
star="*.txt"
echo -n 'glob in a variable, unquoted: '; args $star
echo -n 'glob in a variable, quoted  : '; args "$star"
echo -n 'literal glob: '; args *.txt
echo -n 'single quotes: '; args '$f *.txt'
echo -n 'double quotes keep $f but not glob: '; args "$f *.txt"
echo -n 'backslash: '; args a\ b "a\ b" 'a\ b'
echo -n '$'"'"'a\tb'"'"': '; args $'a\tb'
echo -n 'adjacent quoting a"b c"d: '; args a"b c"d

echo '### 2. $@ and $*'
set -- "one two" three "four"
echo -n '$*   : '; args $*
echo -n '"$*" : '; args "$*"
echo -n '$@   : '; args $@
echo -n '"$@" : '; args "$@"
( IFS=,; echo -n '"$*" with IFS=, : '; args "$*" )
echo -n 'no args "$@": '; set --; args "$@"
echo -n 'no args "$*": '; args "$*"

echo '### 3. IFS'
line="a:b::c"
( IFS=:; echo -n 'IFS=: unquoted: '; args $line )
( IFS=; echo -n 'IFS empty unquoted: '; args $line )
line2="  lead and  trail  "
echo -n 'default IFS, unquoted: '; args $line2
IFS=: read -r x y z <<< "p:q:r:s"; echo "read split: x=[$x] y=[$y] z=[$z]"
read -r l <<< "  keep spaces  "; echo "read without IFS=: [$l]"
IFS= read -r l <<< "  keep spaces  "; echo "IFS= read: [$l]"

echo '### 4. special parameters'
bash -c 'echo "\$0=$0 \$#=$# \$1=$1"' arg0 first second
false; echo "\$? after false = $?"
echo "\$\$ is a number: $([[ $$ =~ ^[0-9]+$ ]] && echo yes)"
sleep 0 & echo "\$! is a number: $([[ $! =~ ^[0-9]+$ ]] && echo yes)"; wait
echo "\$_ after 'echo hi' : $(echo hi >/dev/null; echo "$_")"

echo '### 5. set vs empty vs unset: the default operators'
unset u; e=""; s="val"
printf '%-18s %-10s %-10s %-10s\n' expansion unset empty set
for op in '-d' ':-d' '=d' ':=d' '+alt' ':+alt'; do
  r_u=$(unset v; eval "echo \"\${v$op}\"")
  r_e=$(v=""; eval "echo \"\${v$op}\"")
  r_s=$(v="val"; eval "echo \"\${v$op}\"")
  printf '%-18s %-10s %-10s %-10s\n' "\${v$op}" "[$r_u]" "[$r_e]" "[$r_s]"
done
echo -n '${v:?msg} unset: '; (unset v; echo "${v:?variable v is required}") 2>&1
echo -n '${v?msg} empty (no colon): '; (v=""; echo "[${v?required}]") 2>&1
echo -n 'set -u on unset: '; (set -u; echo "$undefined_name") 2>&1
echo -n 'set -u and ${v-}: '; (set -u; echo "[${undefined_name-}]") 2>&1
echo -n 'set -u with an empty array "${a[@]}": '; (set -u; a=(); echo "[${a[@]}]") 2>&1

echo '### 6. parameter expansion: length, trim, replace, case, substring'
p="/home/user/archive.tar.gz"
echo "length         \${#p}        = ${#p}"
echo "remove prefix  \${p#*/}      = ${p#*/}"
echo "longest prefix \${p##*/}     = ${p##*/}   (basename)"
echo "remove suffix  \${p%.*}      = ${p%.*}"
echo "longest suffix \${p%%.*}     = ${p%%.*}"
echo "dirname        \${p%/*}      = ${p%/*}"
echo "replace first  \${p/o/0}     = ${p/o/0}"
echo "replace all    \${p//o/0}    = ${p//o/0}"
echo "anchored       \${p/#\/home/~} = ${p/#\/home/~}"
echo "anchored end   \${p/%gz/zip} = ${p/%gz/zip}"
echo "upper first    \${p^}        = ${p^}"
w="hello world"; echo "upper all      \${w^^}       = ${w^^}"; W="HeLLo"; echo "lower all      \${W,,}       = ${W,,}"
echo "substring      \${w:6}       = ${w:6}"
echo "substring      \${w:0:5}     = ${w:0:5}"
echo "negative       \${w: -5}     = ${w: -5}   (space before the minus)"
echo "negative w/o space \${w:-5}  = ${w:-5}   (this is the DEFAULT operator!)"
echo "pattern in trim \${p#/*/}    = ${p#/*/}"
name=count_a; count_a=7; echo "indirect \${!name} = ${!name}"
prefix_one=1; prefix_two=2; echo "names with prefix: ${!prefix_*}"
n=005; echo "length of 005 is ${#n}; arithmetic: $((10#$n + 1))"

echo '### 7. arrays'
arr=(apple "banana split" cherry)
echo "count \${#arr[@]} = ${#arr[@]}"
echo -n '"${arr[@]}" : '; args "${arr[@]}"
echo -n '${arr[@]}   : '; args ${arr[@]}
echo -n '"${arr[*]}" : '; args "${arr[*]}"
echo "first = ${arr[0]}, last = ${arr[-1]}, second element's length = ${#arr[1]}"
arr+=(date); echo "after +=: ${#arr[@]} elements"
echo -n 'slice "${arr[@]:1:2}": '; args "${arr[@]:1:2}"
echo -n 'indices "${!arr[@]}": '; args "${!arr[@]}"
unset 'arr[1]'; echo -n 'after unset arr[1]: '; args "${arr[@]}"; echo "  indices still: ${!arr[@]}  count: ${#arr[@]}"
sparse=(); sparse[5]=x; sparse[10]=y; echo "sparse count: ${#sparse[@]}, indices: ${!sparse[@]}"
x=(one two); y="$x"; echo "\$x on an array gives only the first element: $y"
echo -n 'array from a command, unsafe : '; mapfile -t parts < <(printf 'a b\nc\n'); args "${parts[@]}"
echo -n 'array from word splitting    : '; words=($(printf 'a b\nc\n')); args "${words[@]}"
echo -n 'copy "${arr[@]}" keeps words : '; copy=("${arr[@]}"); args "${copy[@]}"
echo "assignment of a glob into an array expands it: $(a=(*.txt); echo ${#a[@]})"

echo '### 8. associative arrays'
declare -A color=([apple]=red [banana]=yellow)
color[cherry]=dark
echo "count ${#color[@]}; apple=${color[apple]}"
echo "keys sorted: $(printf '%s ' "${!color[@]}" | tr ' ' '\n' | sort | tr '\n' ' ')"
echo -n 'missing key: '; echo "[${color[nokey]}]"
echo "test a key: $([[ -v color[apple] ]] && echo present) / $([[ -v color[zzz] ]] && echo present || echo absent)"
echo "without declare -A, a[apple]=1 is an indexed array: $(unset q; q[apple]=1; q[banana]=2; echo "${#q[@]} element(s), q[0]=${q[0]}")"
declare -p color | sed 's/^/  /'

echo '### 9. globs'
rm -f ./*; touch a.txt b.TXT .hidden "x y.txt" -- -rf.txt file1 file10 file2
echo -n '*      : '; args *
echo -n '*.txt  : '; args *.txt
echo -n '.*     : '; args .*
echo -n 'file?  : '; args file?
echo -n 'file[0-9]* : '; args file[0-9]*
echo -n 'no match (default): '; args *.nomatch
( shopt -s nullglob; echo -n 'nullglob no match   : '; args *.nomatch )
( shopt -s failglob; echo -n 'failglob no match   : '; ( : *.nomatch ) 2>&1 )
( shopt -s dotglob; echo -n 'dotglob *           : '; args * )
( shopt -s nocaseglob; echo -n 'nocaseglob *.txt   : '; args *.txt )
echo -n "extglob enabled on the SAME line: "; bash -c 'shopt -s extglob; echo !(*.txt)' 2>&1 | head -1
shopt -s extglob
echo -n "extglob !(*.txt) : "; args !(*.txt)
echo -n "extglob file+([0-9]) : "; args file+([0-9])
echo -n "extglob @(a|b).txt : "; args @(a|b).txt
shopt -u extglob
( shopt -s globstar; mkdir -p d/e; touch d/1.log d/e/2.log; echo -n 'globstar **/*.log: '; args **/*.log )
echo -n 'a file named -rf.txt with a glob: '; args *
echo "  'ls *' would treat -rf.txt as options; use ./* or -- :"; echo -n '  ./* : '; args ./*

echo '### 10. brace expansion'
echo -n '{a,b,c}     : '; args {a,b,c}
echo -n 'file{1..3}  : '; args file{1..3}
echo -n '{01..03}    : '; args {01..03}
echo -n '{1..10..3}  : '; args {1..10..3}
echo -n '{a..e}      : '; args {a..e}
echo -n '{5..1}      : '; args {5..1}
echo -n 'pre{x,y}post: '; args pre{x,y}post
n=3; echo -n '{1..$n} (variables come AFTER braces): '; args {1..$n}
echo -n 'with eval   : '; eval "args {1..$n}"
echo -n 'in quotes "{a,b}": '; args "{a,b}"
echo -n 'cp file{,.bak} : '; args file{,.bak}

echo '### 11. command substitution'
x=$(printf 'line1\nline2\n\n\n'); echo "trailing newlines stripped: [$x]"
echo -n 'unquoted $(...) splits : '; args $(printf 'a b\nc\n')
echo -n 'quoted "$(...)"        : '; args "$(printf 'a b\nc\n')"
echo "nested: $(echo "outer $(echo inner)")"
echo "backticks nest badly; \$() does: $(echo `echo hi`)"
x=$(false); echo "x=\$(false) status: $?"
f() { local v=$(false); echo "local v=\$(false) status: $?"; }; f
f2() { local v; v=$(false); echo "declare then assign status: $?"; }; f2
echo "status of a pipeline in \$(): $(true | false; echo $?)"
echo "trailing-newline trap: [$(printf 'a\n')] vs bytes: $(printf 'a\n' | wc -c)"
echo -n 'null bytes warning: '; v=$(printf 'a\0b' 2>&1); echo "[${v}]"

echo '### 12. arithmetic'
echo "\$((7/2)) = $((7/2))   \$((-7/2)) = $((-7/2))   \$((7%3)) = $((7%3))   \$((2**10)) = $((2**10))"
echo "\$((010)) = $((010))   (octal!)   \$((0x1f)) = $((0x1f))   \$((2#101)) = $((2#101))"
echo -n '$((08)) : '; (echo $((08))) 2>&1
echo "\$((10#08)) = $((10#08))"
echo "64-bit overflow: \$((9223372036854775807 + 1)) = $((9223372036854775807 + 1))"
echo -n 'float: '; (echo $((3.5 + 1))) 2>&1
echo -n 'divide by zero: '; (echo $((1/0))) 2>&1
i=5; ((i++)); echo "i after ((i++)) = $i"
echo -n '((0)) status: '; ((0)); echo $?
echo -n '((1)) status: '; ((1)); echo $?
( set -e; ((z=0)); echo "NOT REACHED under set -e" ); echo "subshell with set -e, ((z=0)) status: $?"
echo "variable names inside: \$((a+b)) with a=2 b=3 = $(a=2 b=3; echo $((a+b)))"
echo "comparison gives 1/0: \$((3>2)) = $((3>2))"
declare -i num=2+3; echo "declare -i num=2+3 -> $num"; num="x"; echo "declare -i num=x -> $num"
echo "unset variable in arithmetic: $(echo $((undefined_var + 1)))"
echo -n 'string that looks like code: '; (v='a[$(echo INJECTED >&2)]'; echo $((v))) 2>&1 | head -2

echo '### 13. process substitution and here-strings'
diff <(printf 'a\nb\n') <(printf 'a\nc\n'); echo "diff status $?"
echo -n 'a variable set in a pipeline is lost: '; count=0; printf 'a\nb\n' | while read -r _; do ((count++)); done; echo "count=$count"
echo -n 'process substitution keeps it     : '; count=0; while read -r _; do ((count++)); done < <(printf 'a\nb\n'); echo "count=$count"
echo -n 'here-string: '; read -r a b <<< "1 2"; echo "a=$a b=$b"

echo '### 14. the order of expansion, shown with set -x'
v="a b"; ( set -x; echo {x,y}"$v"~ $((1+1)) ) 2>&1
echo -n 'tilde: '; echo ~ "~" '~' x~

echo '### 15. eval and the danger of expanding twice'
input='; echo INJECTED'
echo -n 'eval "echo $input": '; eval "echo $input"
echo -n 'safe: printf %q   : '; printf '%q\n' "$input"
echo -n 'safer: no eval at all: '; echo "$input"

cd / && rm -rf "$D"
