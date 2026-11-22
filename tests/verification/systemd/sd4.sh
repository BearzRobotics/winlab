#!/usr/bin/env bash
# Battery 4 for linux.systemd: re-tests and the Restart= matrix, conditions, OnFailure. Run as root (tested: Ubuntu 26.04 WSL2, systemd 259).
# NOTE: on AlmaLinux with SELinux enforcing, units that use files in /tmp fail with "Permission denied" (see sd8.sh); run "setenforce 0" for the duration of this battery and "setenforce 1" afterwards.
export SYSTEMD_PAGER=cat SYSTEMD_COLORS=0 PAGER=cat
U=/etc/systemd/system
cleanup() { systemctl stop 'wl-*' >/dev/null 2>&1; systemctl reset-failed 'wl-*' >/dev/null 2>&1; rm -rf "$U"/wl-* "$U"/*.wants/wl-* /etc/systemd/system.control/wl-* /run/systemd/system/wl-* /tmp/wl-*; systemctl daemon-reload; }
trap cleanup EXIT
sh_() { echo "\$ $1"; local out rc; out=$(bash -c "$1" 2>&1); rc=$?; [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/  /'; [ "$rc" != 0 ] && echo "  [rc=$rc]"; return 0; }
echo "systemd $(systemctl --version | head -1)"

echo '### 1. The first ExecStart line is run as ONE command (no shell); ; separates commands'
cat > /tmp/wl-env <<'EOF'
FROMFILE=file-value
QUOTED="two words"
EOF
cat > $U/wl-noshell.service <<'EOF'
[Service]
Type=oneshot
Environment=NAME=world
EnvironmentFile=/tmp/wl-env
ExecStart=/bin/echo hello $NAME ${NAME} "$NAME" $FROMFILE [$QUOTED] | wc -l ; /bin/echo second [$HOME] 100%%
ExecStart=/bin/sh -c 'echo via-shell $NAME $FROMFILE "[$QUOTED]" $(echo sub)'
EOF
systemctl daemon-reload
sh_ 'systemctl start wl-noshell; journalctl -u wl-noshell --no-pager -o cat | grep -v "^Starting\|^Finished\|Deactivated\|Consumed"'

echo '### 2. Stop: TERM ignored, then SIGKILL after TimeoutStopSec'
cat > /tmp/wl-stubborn.sh <<'EOF'
#!/bin/bash
trap '' TERM
echo "stubborn started, ignoring TERM"
while :; do sleep 1; done
EOF
chmod +x /tmp/wl-stubborn.sh
cat > $U/wl-stubborn.service <<'EOF'
[Service]
ExecStart=/tmp/wl-stubborn.sh
TimeoutStopSec=3
EOF
systemctl daemon-reload
systemctl start wl-stubborn; sleep 0.5
sh_ 'systemctl is-active wl-stubborn; s=$(date +%s.%N); systemctl stop wl-stubborn; e=$(date +%s.%N); printf "stop took %.1f s\n" $(awk "BEGIN{print $e - $s}")'
sh_ 'journalctl -u wl-stubborn --no-pager -o cat | cut -c1-130'
sh_ 'systemctl show wl-stubborn -p Result,ActiveState'

echo '### 3. MemoryMax with and without swap'
sh_ 'free -m | sed -n "1,3p"'
sh_ 'systemd-run --wait --collect -p MemoryMax=40M -p MemorySwapMax=0 --unit=wl-mem2 bash -c "x=\$(head -c 150000000 /dev/zero | tr \"\\0\" a); echo allocated \${#x}" 2>&1 | grep -E "result|terminated|Memory peak|OOM|oom" '
sh_ 'journalctl -u wl-mem2 --no-pager -o cat | grep -i "oom\|memory\|killed" | cut -c1-130 | head -4'

echo '### 4. set-property on a persistent unit'
cat > $U/wl-prop.service <<'EOF'
[Service]
ExecStart=/bin/sleep 1000
EOF
systemctl daemon-reload; systemctl start wl-prop
sh_ 'systemctl set-property wl-prop CPUWeight=50; systemctl show wl-prop -p CPUWeight; find /etc/systemd/system.control -name "*wl-prop*" | head; cat /etc/systemd/system.control/wl-prop.service.d/*.conf 2>&1 | grep -v "^#"'
sh_ 'systemctl set-property --runtime wl-prop CPUWeight=70; systemctl show wl-prop -p CPUWeight; ls /run/systemd/system.control 2>&1 | grep wl-'
sh_ 'systemctl revert wl-prop; systemctl show wl-prop -p CPUWeight; ls /etc/systemd/system.control 2>&1 | grep -c wl-prop'
systemctl stop wl-prop

echo '### 5. Why is-system-running said degraded'
cat > $U/wl-pre.service <<'EOF'
[Service]
ExecStartPre=/bin/false
ExecStart=/bin/sleep 100
EOF
systemctl daemon-reload; systemctl start wl-pre 2>/dev/null
sh_ 'systemctl is-system-running; systemctl list-units --failed --no-legend | cut -c1-70'
systemctl reset-failed wl-pre
sh_ 'systemctl is-system-running'

echo '### 6. Restart= matrix: does the service restart after exit 0 / exit 1 / SIGKILL ?'
for pol in no on-success on-failure on-abnormal on-abort always; do
  for how in "exit 0" "exit 1" "kill -9 \$\$" "kill -TERM \$\$"; do
    id=$(echo "$pol-$how" | tr -c 'a-z0-9\n' '-' | sed 's/--*/-/g; s/-$//')
    cat > $U/wl-r-$id.service <<EOF
[Unit]
StartLimitIntervalSec=0
[Service]
Restart=$pol
RestartSec=100ms
ExecStart=/bin/bash -c 'sleep 0.1; $how'
EOF
  done
done
systemctl daemon-reload
for f in $U/wl-r-*.service; do systemctl start "$(basename "$f")" --no-block; done
sleep 3
printf '  %-12s %-10s %-10s %-10s %-12s\n' "Restart=" "exit 0" "exit 1" "SIGKILL" "SIGTERM"
for pol in no on-success on-failure on-abnormal on-abort always; do
  line=""
  for how in "exit 0" "exit 1" "kill -9 \$\$" "kill -TERM \$\$"; do
    id=$(echo "$pol-$how" | tr -c 'a-z0-9\n' '-' | sed 's/--*/-/g; s/-$//')
    n=$(systemctl show "wl-r-$id.service" -p NRestarts --value)
    [ "${n:-0}" -ge 2 ] && c=restarts || c=stays-down
    line="$line$(printf '%-11s' "$c")"
  done
  printf '  %-12s %s\n' "$pol" "$line"
done
systemctl stop 'wl-r-*' 2>/dev/null; systemctl reset-failed 'wl-r-*' 2>/dev/null
echo '-- the result of one SIGTERM case: what state does systemd record when the service dies of SIGTERM with Restart=no ?'
sh_ 'systemctl start wl-r-no-kill-term-.service 2>&1; sleep 0.5; systemctl show wl-r-no-kill-term.service -p Result,ActiveState 2>&1 | head -3; ls /etc/systemd/system | grep "wl-r-no" | head -5'

echo '### 7. Conditions, asserts, OnFailure'
cat > $U/wl-cond.service <<'EOF'
[Unit]
ConditionPathExists=/tmp/wl-flagfile
[Service]
ExecStart=/bin/sleep 100
EOF
cat > $U/wl-assert.service <<'EOF'
[Unit]
AssertPathExists=/tmp/wl-flagfile
[Service]
ExecStart=/bin/sleep 100
EOF
systemctl daemon-reload
sh_ 'systemctl start wl-cond; echo "start rc=$?"; systemctl is-active wl-cond; systemctl status wl-cond --no-pager -n0 | grep -E "Active|condition" | cut -c1-120; journalctl -u wl-cond --no-pager -o cat | tail -2 | cut -c1-120'
sh_ 'systemctl start wl-assert; echo "start rc=$?"; systemctl is-active wl-assert'
sh_ 'touch /tmp/wl-flagfile; systemctl start wl-cond; echo "start rc=$?"; systemctl is-active wl-cond; systemctl stop wl-cond'
cat > $U/wl-handler.service <<'EOF'
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo "handler ran for $MONITOR_UNIT result=$MONITOR_SERVICE_RESULT" >> /tmp/wl-handler.log'
EOF
cat > $U/wl-watched.service <<'EOF'
[Unit]
OnFailure=wl-handler.service
[Service]
ExecStart=/bin/false
EOF
cat > $U/wl-succ.service <<'EOF'
[Unit]
OnSuccess=wl-handler.service
[Service]
Type=oneshot
ExecStart=/bin/true
EOF
systemctl daemon-reload
rm -f /tmp/wl-handler.log
sh_ 'systemctl start wl-watched; sleep 0.8; cat /tmp/wl-handler.log'
sh_ 'systemctl start wl-succ; sleep 0.8; tail -1 /tmp/wl-handler.log'
sh_ 'cat > /tmp/wl-status-codes.sh <<"EOF"
exit 3
EOF
true'
cat > $U/wl-exit3.service <<'EOF'
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'exit 3'
SuccessExitStatus=3
EOF
cat > $U/wl-exit3b.service <<'EOF'
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'exit 3'
EOF
systemctl daemon-reload
sh_ 'systemctl start wl-exit3; echo "SuccessExitStatus=3: rc=$?"; systemctl start wl-exit3b; echo "default: rc=$?"'
echo '### done'
