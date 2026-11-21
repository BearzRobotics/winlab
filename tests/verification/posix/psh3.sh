#!/usr/bin/env bash
# Battery 3 for foundations.posix-sh-scripting: a POSIX sh template and a test harness that runs it under several shells.
# Usage: psh3.sh NAME=COMMAND [NAME=COMMAND ...]   (the driver is bash; the template and harness are POSIX sh)
D=$(mktemp -d); cd "$D" || exit 1
names=(); cmds=()
for a in "$@"; do names+=("${a%%=*}"); cmds+=("${a#*=}"); done
echo "driver: bash $BASH_VERSION; shells under test: ${names[*]}"

cat > tool.sh <<'EOF'
#!/bin/sh
# tool.sh: keep a KEY=VALUE line in a config file (idempotent, atomic), POSIX sh only.
# Usage: tool.sh [-n] [-v] FILE KEY=VALUE
set -eu
PATH=/usr/bin:/bin; export PATH
umask 077

prog=${0##*/}
dry=0 verbose=0
tmp=

die()     { printf '%s: %s\n' "$prog" "$*" >&2; exit 1; }
usage()   { printf 'Usage: %s [-n] [-v] FILE KEY=VALUE\n' "$prog" >&2; exit 2; }
log()     { if [ "$verbose" = 1 ]; then printf '%s\n' "$*" >&2; fi; }
cleanup() { if [ -n "$tmp" ]; then rm -f -- "$tmp"; fi; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

while getopts nv opt; do
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
awk -v key="$key" -v new="$setting" '
  index($0, key "=") == 1 { if (!done) print new; done = 1; next }
  { print }
  END { if (!done) print new }' "$file" > "$tmp"
mv -f -- "$tmp" "$file"
tmp=
log "set: $setting"
EOF
chmod +x tool.sh

# The harness is POSIX sh too: SH_UNDER_TEST is the shell that runs tool.sh; the harness itself runs under the same shell.
cat > harness.sh <<'EOF'
#!/bin/sh
# harness.sh: tests tool.sh. Run it as:  SUT="dash" dash harness.sh   (SUT = the shell command that runs tool.sh)
pass=0 fail=0
check() { # check NAME WANT_RC WANT_SUBSTRING COMMAND...
  name=$1 want_rc=$2 want_out=$3; shift 3
  out=$("$@" 2>&1); rc=$?
  case $out in *"$want_out"*) found=1 ;; *) found=0 ;; esac
  if [ "$rc" = "$want_rc" ] && [ "$found" = 1 ]; then
    pass=$((pass + 1)); printf 'ok   %s\n' "$name"
  else
    fail=$((fail + 1)); printf 'FAIL %s (rc=%s, output: %s)\n' "$name" "$rc" "$out"
  fi
}
work=$(mktemp -d) && cd "$work" || exit 1
cp "$TOOL" tool.sh; printf 'a=1\n' > f.conf
check 'usage on no arguments'        2 'Usage:'          $SUT tool.sh
check 'rejects a bad setting'        1 'bad setting'     $SUT tool.sh f.conf oops
check 'dry run reports'              0 'DRY: would set'  $SUT tool.sh -n f.conf b=2
check 'dry run changes nothing'      0 ''                grep -qx 'a=1' f.conf
check 'sets a new key'               0 ''                $SUT tool.sh f.conf b=2
check 'second run is a no-op'        0 'already set'     $SUT tool.sh -v f.conf b=2
check 'replaces an existing key'     0 ''                $SUT tool.sh f.conf a=9
check 'old value is gone'            1 ''                grep -qx 'a=1' f.conf
check 'file has the new value once'  0 '1'               grep -cx 'a=9' f.conf
check 'missing file'                 1 'no such file'    $SUT tool.sh nofile.conf x=1
chmod 400 f.conf
check 'read-only file'               1 'not writable'    $SUT tool.sh f.conf z=1
chmod 600 f.conf
check 'no temp file left behind'     0 '0'               sh -c 'ls | grep -c "^f.conf\."; true'
check 'unknown option'               2 'Usage:'          $SUT tool.sh -z f.conf x=1
printf '%s passed, %s failed\n' "$pass" "$fail"
cd / && rm -rf "$work"
[ "$fail" -eq 0 ]
EOF

echo '### the template under each shell (the harness runs under the same shell)'
for i in "${!names[@]}"; do
  echo "--- ${names[$i]}"
  TOOL=$D/tool.sh SUT="${cmds[$i]}" ${cmds[$i]} harness.sh 2>&1 | sed 's/^/  /'
done
echo '### the same template, one scenario shown'
printf 'a=1\nb=2\n' > c.conf
for i in "${!names[@]}"; do
  out=$( ${cmds[$i]} tool.sh -v c.conf b=9 2>&1; echo "rc=$?"; ${cmds[$i]} tool.sh -v c.conf b=9 2>&1; echo "rc=$?"; tr '\n' ' ' < c.conf )
  printf '  %-8s %s\n' "${names[$i]}" "${out//$'\n'/ | }"
  printf 'a=1\nb=2\n' > c.conf
done
echo '### killed in the middle (TERM) leaves no temp file'
for i in "${!names[@]}"; do
  cat > slow.sh <<'EOF'
tmp=$(mktemp ./slow.XXXXXX); trap 'rm -f -- "$tmp"' EXIT; trap 'exit 143' TERM
sleep 5 & wait $!
EOF
  ${cmds[$i]} slow.sh & P=$!; sleep 0.7; kill -TERM $P; wait $P; rc=$?
  printf '  %-8s rc=%s leftover=%s\n' "${names[$i]}" "$rc" "$(ls | grep -c '^slow\.[A-Za-z0-9]\{6\}$')"
done
echo '### ShellCheck -s sh on the template, and on a bashism-laden variant'
SC=${SHELLCHECK:-}
if [ -n "$SC" ] && [ -x "$SC" ]; then
  "$SC" -s sh tool.sh; echo "  template: shellcheck rc=$? (0 = no findings)"
  sed 's/^set -eu$/set -euo pipefail/; s/^tmp=$/tmp=; arr=(1 2)/' tool.sh > tool-bashism.sh
  "$SC" -s sh -f gcc tool-bashism.sh | sed 's/^/  /'
  echo '--- the bashism variant under each shell:'
  for i in "${!names[@]}"; do
    out=$(${cmds[$i]} tool-bashism.sh 2>&1 | head -2); printf '  %-8s %s\n' "${names[$i]}" "${out//$'\n'/ | }"
  done
fi
cd / && rm -rf "$D"
