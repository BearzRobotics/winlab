#!/usr/bin/env bash
# Battery 1 for foundations.bash-functions-and-scripts (bash 5.x, dash where noted). Temp folder only.
D=$(mktemp -d); cd "$D" || exit 1
echo "bash $BASH_VERSION"
args() { printf '%d args:' "$#"; printf ' [%s]' "$@"; echo; }

echo '### 1. defining and calling; status versus value'
greet() { echo "hello $1"; }
greet world
square() { echo $(( $1 * $1 )); }
r=$(square 7); echo "value via \$(): $r"
is_even() { (( $1 % 2 == 0 )); }
is_even 4 && echo "4 even (status 0)"; is_even 5 || echo "5 not even (status $?)"
big() { return 300; }; big; echo "return 300 gives status $?"
neg() { return -1; }; neg; echo "return -1 gives status $?"
noret() { false; echo "after false"; }; noret; echo "function status = last command = $?"
fexit() { exit 3; }; (fexit); echo "exit inside a function exits the shell/subshell: status $?"
type greet | head -1
declare -f square | head -3

echo '### 2. arguments inside functions'
show() { echo "\$#=$# \$1=$1 \$0=$0 FUNCNAME=${FUNCNAME[0]}"; args "$@"; }
show "a b" c
set -- top1 top2; show x; echo "script's own \$1 is still: $1"; set --
shifty() { shift; echo "after shift: $# left, first=$1"; }; shifty a b c
fwd() { args "$@"; }; wrap() { fwd "$@"; }; wrap "x y" z
wrapbad() { fwd $@; }; echo -n 'forwarding with unquoted $@: '; wrapbad "x y" z
echo -n 'shift with too few args: '; ( set -- a; shift 2; echo "status $?" ) 2>&1
echo -n 'default for a missing arg ${1:-none}: '; d() { echo "${1:-none}"; }; d

echo '### 3. scope: local, and bash local is DYNAMIC'
x=global
f1() { local x=inner; f2; }
f2() { echo "f2 sees x=$x (caller's local, not global)"; }
f1; echo "after: x=$x"
f3() { x=changed; }; f3; echo "no local: global changed to $x"
f4() { local y=1; }; f4; echo "local does not leak: [${y-unset}]"
f5() { local a=1 b=$a; echo "local a=1 b=\$a gives b=[$b] (same statement)"; }; unset a; f5
f6() { local -r k=1; k=2 2>&1; }; echo -n 'local -r : '; (f6) 2>&1 | head -1
f7() { local n=0; for i in 1 2 3; do n=$((n+i)); done; echo "sum $n; i leaked: $i"; }; f7
echo -n 'a function called in a pipeline cannot change variables: '; cnt=0; inc() { cnt=$((cnt+1)); }; echo | inc; echo "cnt=$cnt"
echo -n 'in $(): '; v=a; chg() { v=b; echo out; }; o=$(chg); echo "v=$v o=$o"

echo '### 4. returning values: stdout, global, nameref'
getname() { REPLY="alice"; }; getname; echo "global REPLY: $REPLY"
setvar() { local -n ref=$1; ref="via nameref"; }; setvar result; echo "nameref: $result"
echo -n 'two values via mapfile: '; pair() { printf '%s\n' one two; }; mapfile -t out < <(pair); args "${out[@]}"
echo -n 'status AND value: '; both() { echo "value"; return 4; }; val=$(both); echo "val=$val status=$?"
declare -a arr=(1 2 3); sumarr() { local -n a=$1; local s=0 e; for e in "${a[@]}"; do ((s+=e)); done; echo $s; }; echo "sum of array via nameref: $(sumarr arr)"

echo '### 5. functions vs commands'
ls() { echo "my ls function"; }
ls /; command ls / | head -1; unset -f ls; echo "unset -f restores: $(ls / | head -1)"
echo -n 'a function overrides a builtin: '; cd() { echo "my cd"; }; cd /tmp; unset -f cd; builtin cd /tmp && echo "builtin cd works"
type -t greet; type -t ls; type -t cd; type -t if

echo '### 6. recursion and export -f'
fact() { local n=$1; if (( n <= 1 )); then echo 1; else echo $(( n * $(fact $((n-1))) )); fi; }; echo "fact 10 = $(fact 10)"
hi() { echo "hi from exported function"; }; export -f hi; bash -c hi
echo -n 'sh -c does not see it: '; sh -c hi 2>&1 | head -1

echo '### 7. getopts'
parse() {
  local OPTIND=1 verbose=0 out="" opt
  while getopts ":vo:h" opt; do
    case $opt in
      v) verbose=1 ;;
      o) out=$OPTARG ;;
      h) echo "usage"; return 0 ;;
      :) echo "option -$OPTARG needs an argument" ; return 2 ;;
      \?) echo "unknown option -$OPTARG"; return 2 ;;
    esac
  done
  shift $((OPTIND - 1))
  echo "verbose=$verbose out=[$out] rest: $*"
}
parse -v -o file.txt a b
parse -vo file.txt a b
parse -ofile.txt a
parse -x a
parse -o
parse -- -v a
parse a -v b
echo -n 'without local OPTIND, a 2nd call in the same shell: '
bad() { while getopts "v" o; do :; done; echo "OPTIND=$OPTIND"; }; bad -v; bad -v
echo -n 'dash getopts: '; dash -c 'set -- -a -b x file; while getopts ab: o; do echo "$o=$OPTARG"; done; shift $((OPTIND-1)); echo "rest: $*"'
echo -n 'getopts has no long options: '; ( set -- --verbose; while getopts "v" o; do echo "o=$o"; done 2>&1 ) 2>&1 | head -2

echo '### 8. a manual argument loop with long options'
cat > args.sh <<'EOF'
#!/usr/bin/env bash
verbose=0; out=""
while [ $# -gt 0 ]; do
  case $1 in
    -v|--verbose) verbose=1 ;;
    -o|--output)  out=${2:?--output needs a value}; shift ;;
    --output=*)   out=${1#*=} ;;
    -h|--help)    echo "usage: args.sh [-v] [-o FILE] ARGS..."; exit 0 ;;
    --)           shift; break ;;
    -*)           echo "unknown option: $1" >&2; exit 2 ;;
    *)            break ;;
  esac
  shift
done
echo "verbose=$verbose out=[$out] rest: $*"
EOF
chmod +x args.sh
./args.sh -v --output a.txt x y; ./args.sh --output=b.txt -- -notopt; ./args.sh --bogus; echo "status $?"; ./args.sh -o 2>&1 | head -1

echo '### 9. here-documents'
name=world
cat <<EOF
expanded: hello $name, today is $(echo DATE), 1+1=$((1+1)), literal \$ and \`
EOF
cat <<'EOF'
quoted delimiter: hello $name $(echo DATE) \n stays
EOF
if true; then
	cat <<-EOF
	tab-indented lines lose their leading TABS with <<-
	  (but spaces are kept)
	EOF
fi
cat <<EOF | tr a-z A-Z
piped here-doc
EOF
cat > made.conf <<EOF
host=$name
EOF
echo "written file: $(cat made.conf)"
echo -n 'space before the delimiter breaks it: '
printf 'cat <<EOF\ntext\n EOF\nEOF\n' > bad-here.sh; bash bad-here.sh 2>&1 | tr '\n' '|'; echo
echo -n 'here-string: '; read -r a b <<< "x y"; echo "a=$a b=$b"
echo -n 'here-doc into a function: '; show2() { cat; }; show2 <<EOF
body
EOF

echo '### 10. exit codes'
for c in 0 1 2 126 127 130 143; do bash -c "exit $c"; echo -n "exit $c -> $? ; "; done; echo
bash -c 'exit 256'; echo "exit 256 -> $?"; bash -c 'exit -1'; echo "exit -1 -> $?"
nonexec=./nonexec.sh; printf 'echo hi\n' > $nonexec; $nonexec 2>/dev/null; echo "not executable -> $?"
nosuchcmd 2>/dev/null; echo "unknown command -> $?"
bash -c 'kill -TERM $$'; echo "killed by SIGTERM -> $?"
bash -c 'kill -INT $$'; echo "killed by SIGINT  -> $?"
echo -n 'the status of a failing test [[ ]]: '; [[ -f /nonexistent ]]; echo $?
echo -n 'status of $(false) in an assignment: '; v=$(false); echo $?
echo -n 'exit with no argument uses the last status: '; bash -c 'false; exit'; echo $?
echo -n 'exit in a pipeline stage: '; bash -c 'echo a | { exit 5; }; echo "after: $?"'
echo -n 'exit inside $( ): '; bash -c 'x=$(exit 7); echo "continued, status $?"'
