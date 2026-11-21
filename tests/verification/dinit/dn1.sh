#!/usr/bin/env bash
# Battery 1 for the dinit lessons: inspection, first services, enable/disable, failures, reload, dinit-check, restart policies.
# Run as root in the Chimera Linux lab VM (tested: Chimera build 20261103, dinit 0.22.0, dinit-chimera 0.99.25). Test services are wl-*.
D=/etc/dinit.d
cleanup() {
  for s in $(dinitctl list 2>/dev/null | grep -o 'wl-[A-Za-z0-9@._-]*'); do dinitctl stop --force --ignore-unstarted "$s" >/dev/null 2>&1; done
  for s in $(dinitctl list 2>/dev/null | grep -o 'wl-[A-Za-z0-9@._-]*'); do dinitctl unload "$s" >/dev/null 2>&1; done
  rm -rf $D/wl-* $D/boot.d/wl-* /tmp/wl-* /var/log/wl-*
}
trap cleanup EXIT
dinitctl() { timeout 20 /usr/bin/dinitctl "$@"; }
export -f dinitctl
sh_() { echo "\$ $1"; local out rc; out=$(bash -c "$1" 2>&1); rc=$?; [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/  /'; [ "$rc" != 0 ] && echo "  [rc=$rc]"; return 0; }
echo "dinit: $(dinit --version | head -1)"; echo "kernel: $(uname -sr)"; id -un

echo '### 1. Inspect the running system'
sh_ 'dinitctl status boot'
sh_ 'dinitctl status sshd | sed "s/PID: [0-9]*/PID: <pid>/"'
sh_ 'dinitctl is-started sshd; dinitctl is-started no-such-service'
sh_ 'dinitctl is-failed sshd'
sh_ 'dinitctl list | grep -v "early-" | head -40 | sed "s/pid: [0-9]*/pid: <pid>/"'
sh_ 'dinitctl list | wc -l | tr -d " "'
sh_ 'ls /usr/lib/dinit.d | wc -l | tr -d " "; ls /usr/lib/dinit.d | head -30 | tr "\n" " "'
sh_ 'grep -h "^type" /usr/lib/dinit.d/* 2>/dev/null | tr -s " " | sort | uniq -c | sort -rn'
sh_ 'cat /usr/lib/dinit.d/system 2>&1 | head -20'
sh_ 'cat /usr/lib/dinit.d/agetty-service@ 2>&1 | head; ls /usr/lib/dinit.d | grep "@"'
sh_ 'cat /usr/lib/dinit.d/chrony 2>&1'
sh_ 'ls -l /lib /usr/lib/dinit.d/boot.d | head -3 | cut -c1-80'
sh_ 'tr "\0" " " < /proc/1/cmdline; echo; cat /etc/dinit/environment 2>&1 | head -3'
sh_ 'dinit-check sshd 2>&1 | tail -3'

echo '### 2. A first service'
cat > $D/wl-hello <<'EOF'
type = process
command = /bin/sh -c "while :; do echo tick; sleep 1; done"
log-type = buffer
EOF
sh_ 'dinitctl list | grep wl- ; echo "(not loaded yet: dinit reads service files on demand)"'
sh_ 'dinitctl start wl-hello; echo "rc=$?"'
sleep 2.5
sh_ 'dinitctl status wl-hello | sed "s/PID: [0-9]*/PID: <pid>/"'
sh_ 'dinitctl catlog wl-hello | head -3'
sh_ 'dinitctl list | grep wl- | sed "s/pid: [0-9]*/pid: <pid>/"'
sh_ 'dinitctl is-started wl-hello; echo "rc=$?"'
sh_ 'dinitctl stop wl-hello; echo "rc=$?"'
sh_ 'dinitctl status wl-hello; dinitctl is-started wl-hello; echo "rc=$?"'
sh_ 'dinitctl list | grep wl-'
sh_ 'dinitctl start wl-hello >/dev/null; dinitctl restart wl-hello; dinitctl status wl-hello | sed "s/PID: [0-9]*/PID: <pid>/"; dinitctl stop wl-hello >/dev/null'
sh_ 'dinitctl start wl-nonexistent; echo "rc=$?"'

echo '### 3. enable and disable'
cat > $D/wl-enab <<'EOF'
type = process
command = /bin/sleep 1000
EOF
sh_ 'dinitctl enable wl-enab; echo "rc=$?"; ls -l /etc/dinit.d/boot.d | grep wl-; dinitctl is-started wl-enab'
sh_ 'dinitctl disable wl-enab; echo "rc=$?"; ls /etc/dinit.d/boot.d | grep -c wl-; dinitctl is-started wl-enab'
sh_ 'dinitctl status wl-enab | head -3'
sh_ 'dinitctl enable wl-enab >/dev/null; dinitctl stop wl-enab; dinitctl list | grep wl-enab; ls /etc/dinit.d/boot.d | grep wl-; echo "-- stopped but still enabled (the link remains)"; dinitctl disable wl-enab >/dev/null'
echo '-- what boot does (the waits-for.d directory):'
sh_ 'grep -n "waits-for.d" /usr/lib/dinit.d/boot; ls /etc/dinit.d/boot.d'
echo '-- offline enable (no daemon contact):'
sh_ 'dinitctl --offline enable wl-enab; echo "rc=$?"; ls -l /etc/dinit.d/boot.d | grep wl- | sed "s/.* wl-/wl-/"; dinitctl --offline disable wl-enab; ls /etc/dinit.d/boot.d | grep -c wl-'
echo '-- enable-via metadata and --from'
cat > $D/wl-grpA <<'EOF'
type = internal
waits-for.d: /etc/dinit.d/wl-grpA.d
EOF
mkdir -p $D/wl-grpA.d
cat > $D/wl-member <<'EOF'
type = process
command = /bin/sleep 1000
@meta enable-via wl-grpA
EOF
echo '-- group NOT started: enable prints its message but did not return (timeout 8 s)'
sh_ 'timeout 8 dinitctl enable wl-member; echo "rc=$?"; ls -l /etc/dinit.d/wl-grpA.d | grep wl- | sed "s/.* wl-/wl-/"; dinitctl disable wl-member; ls /etc/dinit.d/wl-grpA.d | wc -l | tr -d " "'
dinitctl stop --force --ignore-unstarted wl-member wl-grpA >/dev/null 2>&1; dinitctl unload wl-member >/dev/null 2>&1; dinitctl unload wl-grpA >/dev/null 2>&1
echo '-- group started first: enable returns and starts the member'
sh_ 'dinitctl start wl-grpA; timeout 8 dinitctl enable wl-member; echo "rc=$?"; ls -l /etc/dinit.d/wl-grpA.d | grep wl- | sed "s/.* wl-/wl-/"; ls /etc/dinit.d/boot.d | grep -c wl-member; dinitctl is-started wl-member'
sh_ 'dinitctl disable wl-member; ls /etc/dinit.d/wl-grpA.d | wc -l | tr -d " "; dinitctl is-started wl-member'
cat > $D/wl-nodir <<'EOF'
type = internal
EOF
sh_ 'dinitctl enable --from wl-nodir wl-member; echo "rc=$?"'

echo '### 4. A service that cannot start'
cat > $D/wl-bad <<'EOF'
type = process
command = /usr/bin/slepe 1000
EOF
sh_ 'dinitctl start wl-bad; echo "rc=$?"'
sh_ 'dinitctl status wl-bad'
sh_ 'dinitctl is-failed wl-bad; echo "rc=$?"'
sh_ 'dinitctl list | grep wl-bad'
echo '-- fix the file; start again WITHOUT reload'
sed -i 's#/usr/bin/slepe#/usr/bin/sleep#' $D/wl-bad
sh_ 'dinitctl start wl-bad; echo "rc=$?"'
sh_ 'dinitctl reload wl-bad; echo "rc=$?"; dinitctl start wl-bad; echo "rc=$?"; dinitctl is-started wl-bad'
sh_ 'dinitctl stop wl-bad >/dev/null; dinitctl unload wl-bad; echo "rc=$?"; dinitctl list | grep -c wl-bad'
echo '-- reload of a RUNNING service: command change needs a restart'
cat > $D/wl-rl <<'EOF'
type = process
command = /bin/sh -c "echo v1; sleep 1000"
log-type = buffer
EOF
dinitctl start wl-rl >/dev/null; sleep 0.3
sed -i 's/v1/v2/' $D/wl-rl
sh_ 'dinitctl reload wl-rl; echo "rc=$?"; dinitctl catlog wl-rl --clear | tail -1; dinitctl restart wl-rl; sleep 0.3; dinitctl catlog wl-rl | tail -1'
sed -i 's/^type = process/type = scripted/' $D/wl-rl
sh_ 'dinitctl reload wl-rl; echo "rc=$?"'
dinitctl stop wl-rl >/dev/null 2>&1

echo '### 5. Broken service files'
printf 'type = process\n' > $D/wl-nocmd
sh_ 'dinitctl start wl-nocmd; echo "rc=$?"'
printf 'type = process\ncommand = /bin/sleep 5\nbogus-setting = 1\n' > $D/wl-bogus
sh_ 'dinitctl start wl-bogus; echo "rc=$?"; dinitctl stop wl-bogus >/dev/null 2>&1'
printf 'type = proces\ncommand = /bin/sleep 5\n' > $D/wl-badtype
sh_ 'dinitctl start wl-badtype; echo "rc=$?"'
printf 'type = process\ncommand = /bin/sleep 5\ndepends-on: wl-missing-dep\n' > $D/wl-baddep
sh_ 'dinitctl start wl-baddep; echo "rc=$?"'
printf 'type = process\ncommand = /bin/sleep 5\ndepends-on: wl-cyc2\n' > $D/wl-cyc1
printf 'type = process\ncommand = /bin/sleep 5\ndepends-on: wl-cyc1\n' > $D/wl-cyc2
sh_ 'dinitctl start wl-cyc1; echo "rc=$?"'
echo '-- dinit-check finds these without starting anything'
sh_ 'dinit-check wl-nocmd 2>&1 | tail -4'
sh_ 'dinit-check wl-bogus 2>&1 | tail -4'
sh_ 'dinit-check wl-badtype 2>&1 | tail -4'
sh_ 'dinit-check wl-baddep 2>&1 | tail -4'
sh_ 'dinit-check wl-cyc1 2>&1 | tail -4'
sh_ 'dinit-check wl-hello 2>&1 | tail -4; echo "rc=$?"'
sh_ 'dinit-check 2>&1 | tail -6'

echo '### 6. Restart behaviour'
cat > $D/wl-flaky <<'EOF'
type = process
command = /bin/sh -c "echo started >> /tmp/wl-flaky.log; sleep 0.1; exit 1"
restart-delay = 0.2
restart-limit-count = 3
restart-limit-interval = 10
EOF
rm -f /tmp/wl-flaky.log
sh_ 'dinitctl start wl-flaky; echo "start rc=$?"; sleep 3; wc -l < /tmp/wl-flaky.log; dinitctl status wl-flaky; dinitctl list | grep wl-flaky; dinitctl is-failed wl-flaky; echo "is-failed rc=$?"'
sh_ 'dinitctl stop wl-flaky 2>&1; dinitctl start wl-flaky; echo "restart-start rc=$?"; sleep 2; dinitctl status wl-flaky | head -3; dinitctl stop wl-flaky >/dev/null 2>&1'
echo '-- the default is restart = yes (documented); a manual stop inhibits it'
cat > $D/wl-default <<'EOF'
type = process
command = /bin/sh -c "echo run >> /tmp/wl-default.log; sleep 100"
EOF
rm -f /tmp/wl-default.log
sh_ 'dinitctl start wl-default; sleep 0.3; pid=$(dinitctl status wl-default | grep -o "PID: [0-9]*" | cut -d" " -f2); kill -9 $pid; sleep 1.5; wc -l < /tmp/wl-default.log; dinitctl status wl-default | head -3 | sed "s/PID: [0-9]*/PID: <pid>/"'
sh_ 'dinitctl stop wl-default; sleep 1.5; wc -l < /tmp/wl-default.log; dinitctl is-started wl-default'
echo '### done'
