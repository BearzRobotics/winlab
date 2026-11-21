#!/usr/bin/env bash
# Battery 2 for foundations.bash-functions-and-scripts: getopts redo, trap, mktemp, logging, locks, script dir, sourcing.
D=$(mktemp -d); cd "$D" || exit 1
echo "bash $BASH_VERSION"

echo '### 1. getopts redo'
count_opts() { local n=0 o; while getopts "v" o; do n=$((n+1)); done; echo "options parsed: $n (OPTIND=$OPTIND)"; }
echo -n 'first call : '; count_opts -v -v
echo -n 'second call: '; count_opts -v -v
lcount() { local OPTIND=1 n=0 o; while getopts "v" o; do n=$((n+1)); done; echo "options parsed: $n"; }
echo -n 'with local OPTIND=1, twice: '; lcount -v -v; echo -n '                            '; lcount -v -v
echo -n 'long option to getopts: '; ( getopts "v" o 2>&1 <<<"" ; true ) >/dev/null; set -- --verbose; getopts v o 2>&1; echo "o=[$o] status=$? OPTIND=$OPTIND"; OPTIND=1; set --

echo '### 2. trap EXIT'
cat > t1.sh <<'EOF'
#!/usr/bin/env bash
trap 'echo "cleanup ran, \$? was $?"' EXIT
echo "working"
exit 3
EOF
bash t1.sh; echo "script status: $?"
cat > t2.sh <<'EOF'
#!/usr/bin/env bash
trap 'echo "cleanup"; exit 9' EXIT
echo "working"
exit 3
EOF
bash t2.sh; echo "status when the trap calls exit 9: $?"
cat > t3.sh <<'EOF'
#!/usr/bin/env bash
set -e
trap 'echo "EXIT trap, status $?"' EXIT
echo start
false
echo "not reached"
EOF
bash t3.sh; echo "status: $?"
cat > t4.sh <<'EOF'
#!/usr/bin/env bash
x=before
trap 'echo "single quotes: x=$x"' EXIT
trap "echo \"double quotes: x=$x\"" EXIT 2>/dev/null
x=after
EOF
echo -n 'last trap replaces the first (one EXIT trap): '; bash t4.sh
cat > t5.sh <<'EOF'
#!/usr/bin/env bash
x=before
trap "echo \"double quotes, expanded when set: x=$x\"" EXIT
x=after
EOF
bash t5.sh
cat > t6.sh <<'EOF'
#!/usr/bin/env bash
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "$tmp" > tmpname.txt
touch "$tmp/work"
exit 0
EOF
bash t6.sh; echo "temp dir exists after the script? $([ -e "$(cat tmpname.txt)" ] && echo yes || echo no)"
echo -n 'trap is not inherited by a subshell: '; bash -c 'trap "echo parent-trap" EXIT; ( echo in-subshell )'
echo -n 'trap -p shows traps: '; bash -c 'trap "echo bye" EXIT INT; trap -p' | tr '\n' ' '; echo

echo '### 3. signals'
cat > s1.sh <<'EOF'
#!/usr/bin/env bash
cleanup() { echo "caught TERM, cleaning up"; exit 143; }
trap cleanup TERM
trap 'echo "EXIT trap"' EXIT
echo "pid $$ ready"
sleep 30 &
wait $!
EOF
bash s1.sh & pid=$!
sleep 1; kill -TERM "$pid"; wait "$pid"; echo "status after TERM: $?"
cat > s2.sh <<'EOF'
#!/usr/bin/env bash
trap 'echo "EXIT trap ran"' EXIT
sleep 30
EOF
bash s2.sh & pid=$!; sleep 1; kill -KILL "$pid"; wait "$pid" 2>/dev/null; echo "status after KILL: $? (the EXIT trap could not run)"
cat > s3.sh <<'EOF'
#!/usr/bin/env bash
trap 'echo "got INT, ignoring"' INT
echo ready
sleep 3 &
wait
echo "finished"
EOF
bash s3.sh & pid=$!; sleep 1; kill -INT "$pid"; wait "$pid"; echo "status: $?"
echo -n 'ignoring a signal with an empty trap: '; bash -c 'trap "" TERM; kill -TERM $$; echo "still alive"'

echo '### 4. trap ERR needs -E for functions'
cat > e1.sh <<'EOF'
#!/usr/bin/env bash
trap 'echo "ERR trap at line $LINENO"' ERR
f() { false; echo "after false in f"; }
f
echo "done"
EOF
bash e1.sh
sed -i 's/^trap/set -E\ntrap/' e1.sh; echo "-- with set -E:"; bash e1.sh

echo '### 5. mktemp'
f=$(mktemp); d=$(mktemp -d)
echo "file: $(stat -c '%a %U' "$f") $(basename "$f" | wc -c) chars; dir: $(stat -c '%a' "$d")"
t=$(mktemp "$d/report.XXXXXX"); echo "template: $(basename "$t")"
t2=$(mktemp --suffix=.log "$d/x.XXXX"); echo "suffix:   $(basename "$t2")"
echo -n 'a template without X: '; mktemp "$d/noX" 2>&1
echo -n 'TMPDIR is honoured: '; TMPDIR=$d mktemp | sed "s#$d#\$d#"
echo -n 'two calls differ: '; [ "$(mktemp -u)" != "$(mktemp -u)" ] && echo yes
rm -rf "$f" "$d"
echo '--- predictable names are an attack surface (done in my own temp folder)'
victim="$D/victim.txt"; echo "precious data" > "$victim"
ln -s "$victim" "$D/report.$$"
echo "attacker planted: report.\$\$ -> victim.txt"
echo "script writes its report:"; echo "report text" > "$D/report.$$"
echo "victim now holds: $(cat "$victim")"
echo -n 'with set -C (noclobber): '; echo "precious data" > "$victim"; ( set -C; echo "report text" > "$D/report.$$" ) 2>&1
echo "victim still holds: $(cat "$victim")"
rm -f "$D/report.$$"

echo '### 6. logging'
log() { printf '%s [%s] %s\n' "$(date '+%F %T')" "$1" "$2" >&2; }
log INFO "started"; log ERROR "something failed"
echo -n 'builtin timestamp printf %(...)T: '; printf '%(%F %T)T\n' -1
echo -n 'date is an external command; printf %T is not: '
t1=$(date +%s%N); for i in $(seq 300); do x=$(date +%T); done; t2=$(date +%s%N); a=$(( (t2-t1)/1000000 ))
t1=$(date +%s%N); for i in $(seq 300); do printf -v x '%(%T)T' -1; done; t2=$(date +%s%N); b=$(( (t2-t1)/1000000 ))
echo "300 calls: date=${a} ms, printf=${b} ms"
echo -n 'logger present? '; command -v logger >/dev/null && echo yes || echo no
cat > l1.sh <<'EOF'
#!/usr/bin/env bash
exec > >(tee -a run.log) 2>&1
echo "to screen and log"
echo "error text" >&2
EOF
bash l1.sh; echo "log file: $(wc -l < run.log) lines"
echo -n 'stdout vs stderr when captured: '; bash -c 'echo out; echo err >&2' 2>/dev/null | tr '\n' ' '; echo

echo '### 7. lock files'
echo -n 'noclobber lock (atomic create): '
lock=job.lock
( set -C; echo $$ > "$lock" ) 2>/dev/null && echo "got lock" ; ( set -C; echo $$ > "$lock" ) 2>&1 | sed 's/^.*: //' ; rm -f "$lock"
echo -n 'mkdir lock: '; mkdir job.lockd && echo "got lock"; mkdir job.lockd 2>&1 | sed 's/^.*: //'; rmdir job.lockd
echo -n 'flock available? '; command -v flock >/dev/null && echo yes || echo no
cat > k1.sh <<'EOF'
#!/usr/bin/env bash
exec 9>/tmp/wl-test.lock
if ! flock -n 9; then echo "$1: another instance is running"; exit 1; fi
echo "$1: got the lock"
sleep 2
echo "$1: done"
EOF
bash k1.sh first & sleep 0.5; bash k1.sh second; wait
echo "-- stale lock files: a killed process"
cat > k2.sh <<'EOF'
#!/usr/bin/env bash
lock=/tmp/wl-stale.lock
if ! ( set -C; echo $$ > "$lock" ) 2>/dev/null; then echo "locked by PID $(cat "$lock")"; exit 1; fi
trap 'rm -f "$lock"' EXIT
sleep 30
EOF
bash k2.sh & p=$!; sleep 0.5; kill -KILL "$p"; wait "$p" 2>/dev/null
echo -n 'after kill -9, the next run: '; bash k2.sh
echo -n 'the old PID is alive? '; kill -0 "$(cat /tmp/wl-stale.lock)" 2>/dev/null && echo yes || echo no
rm -f /tmp/wl-stale.lock /tmp/wl-test.lock
cat > k3.sh <<'EOF'
#!/usr/bin/env bash
exec 9>/tmp/wl-test2.lock
flock -n 9 || { echo "busy"; exit 1; }
sleep 30
EOF
bash k3.sh & p=$!; sleep 0.5; kill -KILL "$p"; wait "$p" 2>/dev/null
echo -n 'flock after kill -9: '; bash -c 'exec 9>/tmp/wl-test2.lock; flock -n 9 && echo "lock was released by the kernel"'; rm -f /tmp/wl-test2.lock

echo '### 8. where is the script? sourcing and the main guard'
mkdir -p "dir with spaces/bin"; cat > "dir with spaces/bin/where.sh" <<'EOF'
#!/usr/bin/env bash
echo "\$0=$0"
echo "BASH_SOURCE=${BASH_SOURCE[0]}"
echo "dirname:    $(dirname "$0")"
echo "abs dir:    $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "realpath:   $(realpath "${BASH_SOURCE[0]}")"
EOF
chmod +x "dir with spaces/bin/where.sh"
echo "-- run by relative path:"; ( cd "dir with spaces" && ./bin/where.sh | sed "s#$D#\$D#" )
ln -s "$D/dir with spaces/bin/where.sh" link.sh
echo "-- run through a symlink:"; ./link.sh | sed "s#$D#\$D#"
echo "-- sourced:"; ( cd "dir with spaces" && . ./bin/where.sh | sed "s#$D#\$D#" ) | head -3
echo "-- without quotes, cd \$(dirname \$0) with a space in the path:"
printf '#!/usr/bin/env bash\ncd $(dirname $0) && pwd\n' > "dir with spaces/bin/bad.sh"; chmod +x "dir with spaces/bin/bad.sh"; "dir with spaces/bin/bad.sh" 2>&1 | sed "s#$D#\$D#" | head -2
cat > lib.sh <<'EOF'
helper() { echo "helper called"; }
main() { echo "main running with: $*"; helper; }
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
EOF
echo -n 'executed: '; bash lib.sh a b | tr '\n' ' '; echo
echo -n 'sourced (no main): '; bash -c '. ./lib.sh; echo -n "functions available: "; helper'
echo -n 'dot with a bare name in bash: '; bash -c '. lib.sh >/dev/null 2>&1 && echo found in the current folder'
echo -n 'dot with a bare name in dash: '; dash -c '. lib.sh' 2>&1 | head -1
echo -n 'dot with ./name in dash     : '; dash -c '. ./lib.sh; helper'

echo '### 9. exec redirections and file descriptors'
exec 3> fd3.txt; echo "to fd 3" >&3; echo "second" >&3; exec 3>&-
echo "fd3.txt: $(tr '\n' '|' < fd3.txt)"
exec 4< fd3.txt; read -r l1 <&4; read -r l2 <&4; exec 4<&-; echo "read from fd 4: $l1, $l2"
echo -n 'redirect a whole block: '; { echo one; echo two; } > block.txt; wc -l < block.txt
echo -n 'both streams of a group to one file: '; { echo out; echo err >&2; } > both.txt 2>&1; wc -l < both.txt

echo '### 10. usage and die helpers'
cat > u1.sh <<'EOF'
#!/usr/bin/env bash
usage() { printf 'usage: %s [-v] FILE\n' "${0##*/}" >&2; exit 2; }
die()   { printf '%s: %s\n' "${0##*/}" "$*" >&2; exit 1; }
[ $# -ge 1 ] || usage
[ -r "$1" ] || die "cannot read '$1'"
echo "processing $1"
EOF
bash u1.sh; echo "status: $?"; bash u1.sh /nonexistent; echo "status: $?"; bash u1.sh u1.sh; echo "status: $?"

cd / && rm -rf "$D"
