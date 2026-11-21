#!/usr/bin/env bash
# Battery 2 for foundations.bash-robust-scripts: debugging, idempotence, signals, security, ShellCheck. bash 5.x.
D=$(mktemp -d); cd "$D" || exit 1
echo "bash $BASH_VERSION"
SC=${SHELLCHECK:-$HOME/tools/shellcheck-v0.11.0/shellcheck}
t() { # label, script text; runs it in a fresh bash, prints rc and output on one line
  printf '%s\n' "$2" > s.sh
  local out rc
  out=$(bash s.sh 2>&1); rc=$?
  out=${out//$'\n'/ | }
  printf '  %-46s rc=%-3s %s\n' "$1" "$rc" "$out"
}

echo '### 1. set -x and PS4'
cat > x1.sh <<'EOF'
f() { local n=$1; echo "n=$n"; }
set -x
f 3
x=$(date +%Y | cut -c1-2)
set +x
echo done
EOF
echo '-- default PS4:'; bash x1.sh 2>&1 | sed 's/^/     /'
echo '-- PS4 with file, line, function:'
PS4='+ ${BASH_SOURCE##*/}:${LINENO}:${FUNCNAME[0]:-main}: ' bash x1.sh 2>&1 | sed 's/^/     /'
echo '-- xtrace shows secrets:'
t 'password on a command line under set -x' 'set -x; pw=hunter2; curl_stub() { :; }; curl_stub --user "bob:$pw"'
echo '-- BASH_XTRACEFD sends the trace to a file, not stderr:'
t 'trace to file' 'exec 9>trace.log; BASH_XTRACEFD=9; set -x; echo hi; set +x; echo "trace file has $(wc -l < trace.log) lines"'
echo '-- bash -n only parses:'
printf 'if true; then\n echo hi\n' > bad.sh
bash -n bad.sh 2>&1 | sed 's/^/     /'; echo "     bash -n rc=${PIPESTATUS[0]}"
printf 'rm -rf /\nthis is never run\n' > danger.sh
bash -n danger.sh; echo "     bash -n on a valid but dangerous file rc=$? (parse only, nothing ran)"
echo '-- sh/bash -x on the command line, and -v:'
printf 'a=1\necho "$a"\n' > v.sh; bash -v v.sh 2>&1 | sed 's/^/     /'

echo '### 2. idempotence: run twice, same end state'
cat > idem.sh <<'EOF'
set -eu
mkdir -p out/sub
ln -sfn out/sub link
line='setting=on'
grep -qxF "$line" conf.txt 2>/dev/null || echo "$line" >> conf.txt
[ -e flag ] || touch flag
rm -f gone.txt
echo "dirs=$(find out -type d | wc -l) conf_lines=$(wc -l < conf.txt) link=$(readlink link)"
EOF
bash idem.sh; bash idem.sh; echo '  (same line twice = idempotent)'
printf 'a\n' > naive.txt; echo 'setting=on' >> naive.txt; echo 'setting=on' >> naive.txt
echo "  naive append twice: $(grep -c setting naive.txt) copies"
t 'mkdir without -p, second run'  'mkdir d1; mkdir d1; echo after'
t 'ln -s second run'              'touch tgt; ln -s tgt l1; ln -s tgt l1; echo "rc=$?"'
t 'ln -sfn second run'            'touch tgt; ln -sfn tgt l1; ln -sfn tgt l1; echo "rc=$?"'
t 'useradd twice (guard with id)' 'id nosuchuser_x >/dev/null 2>&1 && echo exists || echo "would create"'
echo '-- atomic replace with mktemp + mv in the same directory:'
cat > atomic.sh <<'EOF'
set -eu
target=config.txt
printf 'old\n' > "$target"
tmp=$(mktemp "$target.XXXXXX")
trap 'rm -f "$tmp"' EXIT
printf 'new\n' > "$tmp"
mv -f -- "$tmp" "$target"
cat "$target"; ls | grep -c 'config.txt\.' | sed 's/^/leftover temp files: /'
EOF
bash atomic.sh 2>&1 | sed 's/^/     /'
echo '-- dry-run pattern:'
cat > dry.sh <<'EOF'
DRY=${DRY:-1}
run() { if [ "$DRY" = 1 ]; then printf 'DRY: %q\n' "$*" >&2; else "$@"; fi; }
touch "a b.txt"
run rm -- "a b.txt"
[ -e "a b.txt" ] && echo "file still there (dry run)"
DRY=0; run rm -- "a b.txt"; [ -e "a b.txt" ] || echo "file removed (real run)"
EOF
bash dry.sh 2>&1 | sed 's/^/     /'

echo '### 3. signals and cleanup'
cat > sig1.sh <<'EOF'
tmp=$(mktemp -d)
cleanup() { rm -rf "$tmp"; echo "cleanup ran, tmp gone: $([ -d "$tmp" ] && echo no || echo yes)"; }
trap cleanup EXIT
trap 'echo "caught TERM"; exit 143' TERM
sleep 30 &
wait $!
EOF
bash sig1.sh & P=$!; sleep 1; kill -TERM $P; wait $P; echo "  after kill -TERM: script rc=$?"
cat > sig2.sh <<'EOF'
trap 'echo "EXIT trap ran"' EXIT
sleep 30 &
wait $!
EOF
bash sig2.sh & P=$!; sleep 1; kill -KILL $P; wait $P 2>/dev/null; echo "  after kill -KILL: rc=$? (EXIT trap cannot run, nothing is printed above)"
cat > sig3.sh <<'EOF'
trap 'echo "EXIT trap ran"' EXIT
sleep 30 &
wait $!
EOF
bash sig3.sh & P=$!; sleep 1; kill -TERM $P; wait $P; echo "  default TERM (no TERM trap): rc=$? (128+15)"
cat > sig4.sh <<'EOF'
trap 'echo "EXIT trap ran"' EXIT
sleep 30
EOF
bash sig4.sh & P=$!; sleep 1; kill -TERM $P; wait $P; echo "  TERM while a foreground child runs, no trap: rc=$?"
t "INT delivered to itself, trapped" 'trap "echo got INT; exit 130" INT; kill -INT $$; sleep 1; echo NOT-REACHED'
t "INT ignored in a background job of a script" 'bash -c "trap \"echo got INT\" INT; sleep 2; echo finished" & p=$!; sleep 0.5; kill -INT $p; wait $p; echo "rc=$?"'
t 'a trap on EXIT also runs on normal exit' 'trap "echo bye" EXIT; echo working'
t 'trap - EXIT clears it'                   'trap "echo bye" EXIT; trap - EXIT; echo working'
t 'trap -p shows what is set'               'trap "echo bye" EXIT; trap -p EXIT'
t 'exit code 128+N for a signal'            'bash -c "kill -TERM \$\$"; echo "child rc=$?"'
echo '-- timeout and retry:'
timeout 1 sleep 5; echo "  timeout 1 sleep 5: rc=$? (124 = timed out)"
cat > retry.sh <<'EOF'
retry() { local n=$1 delay=$2; shift 2; local i=1
  until "$@"; do
    [ "$i" -ge "$n" ] && { echo "giving up after $i tries" >&2; return 1; }
    echo "try $i failed, waiting ${delay}s" >&2; sleep "$delay"; i=$((i+1)); delay=$((delay*2))
  done; }
c=0; flaky() { c=$((c+1)); [ "$c" -ge 3 ]; }
retry 5 1 flaky && echo "succeeded on try $c"
retry 2 0 false; echo "rc=$?"
EOF
bash retry.sh 2>&1 | sed 's/^/     /'

echo '### 4. security traps'
mkdir sec && cd sec || exit 1
touch ./-rf ./-n a b
echo '-- a file whose name starts with a dash:'
echo "     files: $(ls -A | tr '\n' ' ')"
echo "     rm * would see: $(echo *)"
rm -- -rf -n; echo "     rm -- removes them; left: $(ls -A | tr '\n' ' ')"
cd ..
echo '-- unset variable in a path:'
mkdir -p fake/usr_like; touch fake/keep.txt
t 'rm -rf "$dir/"* with dir unset, no -u'     'cd fake; dir=; echo "would run: rm -rf $dir/*"'
t 'same with set -u'                          'set -u; echo "would run: rm -rf $dir/*"'
t '${dir:?} aborts on unset OR empty'         'dir=; echo "rm -rf ${dir:?refusing: dir is empty}/*"'
t '${dir:?} when set'                         'dir=/tmp/x; echo "rm -rf ${dir:?refusing}/*"'
echo '-- word splitting on file names:'
mkdir ws && cd ws; touch 'my file.txt' 'plain.txt'
echo "     for f in \$(ls): $(for f in $(ls); do printf '[%s]' "$f"; done)"
echo "     for f in *:      $(for f in *; do printf '[%s]' "$f"; done)"
cd ..
echo '-- [ $x = y ] with hostile or empty input:'
t 'empty, unquoted'                           'x=; [ $x = y ] && echo same || echo "no (but bash printed an error?)"'
t 'input "-n", unquoted'                      'x="-n"; [ $x ] && echo true || echo false'
t 'input "a = a", unquoted'                   'x="a = a"; [ $x = y ] && echo same || echo different'
t 'input "-f /etc/passwd", unquoted in [ ]'   'x="-f /etc/passwd"; [ $x ] && echo true || echo false'
t 'quoted: "-f /etc/passwd"'                  'x="-f /etc/passwd"; [ -n "$x" ] && echo "non-empty (string test)"'
echo '-- eval and command substitution on untrusted text:'
t 'eval of user input'                        'in="x; echo INJECTED"; eval "echo $in"'
t 'printf %s is safe'                         'in="x; echo INJECTED"; printf "%s\n" "$in"'
t 'printf with the data as the FORMAT'        'in="%s %s %s"; printf "$in\n"; echo "rc=$?"'
t 'echo with data that looks like an option'  'in="-n"; echo "$in"; echo "(nothing printed above: -n swallowed)"'
t 'printf %s with the same data'              'in="-n"; printf "%s\n" "$in"'
t 'read without -r eats backslashes'          'printf "%s\n" "C:\\temp\\new" | { read x; echo "[$x]"; }; printf "%s\n" "C:\\temp\\new" | { read -r x; echo "[$x]"; }'
t 'unquoted $* vs "$@"'                       'f() { for a in "$@"; do printf "[%s]" "$a"; done; echo; for a in $*; do printf "[%s]" "$a"; done; echo; }; f "a b" c'
echo '-- PATH and privileged scripts:'
mkdir hijack; printf '#!/bin/sh\necho HIJACKED ls\n' > hijack/ls; chmod +x hijack/ls
t 'dot or a writable dir early in PATH'       "PATH=$D/hijack:\$PATH; ls"
t 'safe PATH at the top of a privileged script' "PATH=/usr/bin:/bin; export PATH; PATH=$D/hijack:/usr/bin; PATH=/usr/bin:/bin; ls >/dev/null && echo 'ran the real ls'"
t 'command -v tells you what will run'        "PATH=$D/hijack:\$PATH; command -v ls"
t 'command ls skips functions, not PATH'       'ls() { echo "function ls"; }; ls; command ls / >/dev/null && echo "command ls ran the program"'
echo '-- temporary files:'
t 'predictable name in /tmp (symlink attack surface)' 'echo "/tmp/myscript.$$ is guessable: $$"; '
t 'mktemp creates 0600 and a random name'     'f=$(mktemp); stat -c "%a %n" "$f" | sed "s|/tmp/tmp\.[A-Za-z0-9]*|/tmp/tmp.XXXXXXXXXX|"; rm -f "$f"'
t 'umask 077 for files you create'            'umask 077; touch p; stat -c "%a" p'
t 'secret in an environment variable leaks to children' 'export TOKEN=abc; bash -c "echo child sees: \$TOKEN"'
t 'secret on a command line is visible to others' 'bash -c "sleep 3; :" prog --token=SECRET123 & sleep 0.3; tr "\0" " " < /proc/$!/cmdline; echo; kill $! 2>/dev/null'

echo '### 5. ShellCheck on a flawed script'
cat > flawed.sh <<'EOF'
#!/bin/bash
dir=$1
cd $dir
for f in $(ls *.txt); do
  if [ $f == "a.txt" ]; then
    rm -rf $dir/tmp*
  fi
done
echo $undefined_var
cat file | grep foo | wc -l
EOF
if [ -x "$SC" ]; then
  "$SC" --version | sed -n '1,2p;/^version/p' | head -2 | sed 's/^/  /'
  "$SC" -f gcc flawed.sh | sed 's/^/     /'
  echo "  rc=$?"
  echo '-- shell dialect check:'
  printf '#!/bin/sh\nx=(1 2)\necho ${x[0]}\n[[ -n $x ]] && echo hi\n' > dial.sh
  "$SC" -f gcc dial.sh | sed 's/^/     /'
else
  echo "  ShellCheck not found at $SC"
fi

cd / && rm -rf "$D"
