#!/usr/bin/env bash
# Battery 3 for foundations.bash-robust-scripts: the robust template and a tiny test harness. bash 5.x.
D=$(mktemp -d); cd "$D" || exit 1
echo "bash $BASH_VERSION"

cat > tool.sh <<'EOF'
#!/usr/bin/env bash
# tool.sh: keep a setting line in a config file (idempotent), with a dry-run switch.
# Usage: tool.sh [-n] [-v] FILE KEY=VALUE
set -Eeuo pipefail
PATH=/usr/bin:/bin; export PATH
umask 077

prog=${0##*/}
dry=0 verbose=0
tmp=

die()     { printf '%s: %s\n' "$prog" "$*" >&2; exit 1; }
usage()   { printf 'Usage: %s [-n] [-v] FILE KEY=VALUE\n' "$prog" >&2; exit 2; }
log()     { [ "$verbose" = 1 ] && printf '%s\n' "$*" >&2 || true; }
cleanup() { if [ -n "$tmp" ]; then rm -f -- "$tmp"; fi; }
on_err()  { printf '%s: failed at line %s: %s\n' "$prog" "$1" "$2" >&2; }
trap cleanup EXIT
trap 'on_err "$LINENO" "$BASH_COMMAND"' ERR
trap 'exit 143' TERM
trap 'exit 130' INT

while getopts ':nv' opt; do
  case $opt in
    n) dry=1 ;;
    v) verbose=1 ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ $# -eq 2 ] || usage

file=$1 setting=$2
case $setting in
  [A-Za-z_]*=*) key=${setting%%=*} ;;
  *) die "bad setting '$setting' (expected KEY=VALUE)" ;;
esac
[ -e "$file" ] || die "no such file: $file"
[ -w "$file" ] || die "not writable: $file"

if grep -qxF -- "$setting" "$file"; then
  log "already set: $setting"
  exit 0
fi

if [ "$dry" = 1 ]; then
  printf 'DRY: would set %s in %s\n' "$setting" "$file"
  exit 0
fi

tmp=$(mktemp "$file.XXXXXX")
# keep every other line, replace or append the key
awk -v key="$key" -v new="$setting" '
  index($0, key "=") == 1 { if (!done) print new; done = 1; next }
  { print }
  END { if (!done) print new }' "$file" > "$tmp"
mv -f -- "$tmp" "$file"
tmp=
log "set: $setting"
EOF
chmod +x tool.sh
printf 'a=1\nb=2\n' > c.conf

run() { local out rc; out=$("$@" 2>&1); rc=$?; out=${out//$'\n'/ | }; printf '  %-38s rc=%-3s %s\n' "${*:2}" "$rc" "$out"; }

echo '### the template at work'
run ./tool.sh
run ./tool.sh -n c.conf b=9
run ./tool.sh -v c.conf b=9
echo "  file now: $(tr '\n' ' ' < c.conf)"
run ./tool.sh -v c.conf b=9
run ./tool.sh -v c.conf c=3
echo "  file now: $(tr '\n' ' ' < c.conf)"
run ./tool.sh c.conf 'bad setting'
run ./tool.sh nofile.conf x=1
run ./tool.sh -z c.conf x=1
echo "  leftover temp files: $(ls | grep -c 'c.conf\.')"
echo '-- read-only file:'; chmod 400 c.conf; run ./tool.sh c.conf z=1; chmod 600 c.conf
echo '-- killed in the middle leaves no temp file:'
cat > slow.sh <<'EOF'
tmp=$(mktemp ./slow.XXXXXX); trap 'rm -f -- "$tmp"; echo "cleaned $tmp" >&2' EXIT; trap 'exit 143' TERM
sleep 5 & wait $!
EOF
bash slow.sh & P=$!; sleep 0.7; kill -TERM $P; wait $P; echo "  rc=$? leftover: $(ls | grep -c '^slow\.[A-Za-z0-9]\{6\}$')"

echo '### the first draft of cleanup() (a bug the harness found): last command is a failing test'
sed 's/^cleanup() .*/cleanup() { [ -n "$tmp" ] \&\& rm -f -- "$tmp"; }/' tool.sh > tool-buggy.sh; chmod +x tool-buggy.sh
grep -n '^cleanup' tool-buggy.sh | sed 's/^/  /'
run ./tool-buggy.sh
run ./tool-buggy.sh -n c.conf q=1
echo '### shellcheck on the template'
SC=${SHELLCHECK:-$HOME/tools/shellcheck-v0.11.0/shellcheck}
if [ -x "$SC" ]; then "$SC" tool.sh; echo "  shellcheck rc=$? (0 = no findings)"; fi
echo '### bash -n and dash on it'
bash -n tool.sh && echo '  bash -n: ok'
dash -n tool.sh 2>&1 | head -2 | sed 's/^/  dash -n: /'

echo '### a 15-line test harness'
cat > harness.sh <<'EOF'
#!/usr/bin/env bash
pass=0 fail=0
check() {  # check NAME EXPECTED_RC EXPECTED_OUTPUT_SUBSTRING COMMAND...
  local name=$1 want_rc=$2 want_out=$3; shift 3
  local out rc; out=$("$@" 2>&1); rc=$?
  if [ "$rc" = "$want_rc" ] && [[ $out == *"$want_out"* ]]; then
    pass=$((pass+1)); printf 'ok   %s\n' "$name"
  else
    fail=$((fail+1)); printf 'FAIL %s (rc=%s, output: %s)\n' "$name" "$rc" "$out"
  fi
}
cd "$(mktemp -d)" || exit 1
cp "$TOOL" ./tool.sh; printf 'a=1\n' > f.conf
check 'usage on no arguments'      2 'Usage:'            ./tool.sh
check 'rejects a bad setting'      1 'bad setting'       ./tool.sh f.conf 'oops'
check 'dry run says what it would do' 0 'DRY: would set'  ./tool.sh -n f.conf b=2
check 'dry run changes nothing'    0 ''                  grep -qx 'a=1' f.conf
check 'sets a new key'             0 ''                  ./tool.sh f.conf b=2
check 'second run is a no-op'      0 'already set'       ./tool.sh -v f.conf b=2
check 'file has the line once'     0 '1'                 grep -cx 'b=2' f.conf
check 'deliberately wrong test'    0 'never printed'     ./tool.sh f.conf c=3
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
EOF
TOOL=$D/tool.sh bash harness.sh; echo "  harness rc=$?"

cd / && rm -rf "$D"
