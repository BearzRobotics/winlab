#!/usr/bin/env bash
# Battery 3 for linux.systemd: timer accuracy, sandboxing, resource control, socket/path activation, templates, stop/kill, analyze, user units.
# Run as root (tested: Ubuntu 26.04 WSL2, systemd 259).
export SYSTEMD_PAGER=cat SYSTEMD_COLORS=0 PAGER=cat
U=/etc/systemd/system
cleanup() { systemctl stop 'wl-*' >/dev/null 2>&1; systemctl reset-failed 'wl-*' >/dev/null 2>&1; rm -rf "$U"/wl-* "$U"/*.wants/wl-* /run/systemd/system/wl-* /tmp/wl-* /etc/wl-test*; rm -rf /root/.config/systemd/user/wl-*; systemctl daemon-reload; }
trap cleanup EXIT
sh_() { echo "\$ $1"; local out rc; out=$(bash -c "$1" 2>&1); rc=$?; [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/  /'; [ "$rc" != 0 ] && echo "  [rc=$rc]"; return 0; }
echo "systemd $(systemctl --version | head -1)"

echo '### 1. Timer accuracy: default (1 min) versus AccuracySec=1s, seconds between the scheduled time and the run'
for n in a b; do
cat > $U/wl-acc$n.service <<EOF
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'date +%%s.%%N > /tmp/wl-acc$n.ran'
EOF
done
cat > $U/wl-acca.timer <<'EOF'
[Timer]
OnActiveSec=2
EOF
cat > $U/wl-accb.timer <<'EOF'
[Timer]
OnActiveSec=2
AccuracySec=1s
EOF
systemctl daemon-reload
sh_ 'systemctl show wl-acca.timer -p AccuracyUSec; systemctl show wl-accb.timer -p AccuracyUSec'
rm -f /tmp/wl-acca.ran /tmp/wl-accb.ran
t0=$(date +%s.%N); systemctl start wl-acca.timer wl-accb.timer
for i in $(seq 1 80); do [ -e /tmp/wl-acca.ran ] && [ -e /tmp/wl-accb.ran ] && break; sleep 1; done
for n in a b; do [ -e /tmp/wl-acc$n.ran ] && printf '  timer %s: ran %.1f s after it was started (OnActiveSec=2)\n' "$n" "$(echo "$(cat /tmp/wl-acc$n.ran) - $t0" | bc -l)" || echo "  timer $n: did not run within 80 s"; done
systemctl stop wl-acca.timer wl-accb.timer 2>/dev/null

echo '### 2. Sandboxing'
cat > $U/wl-open.service <<'EOF'
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo "uid=$(id -u) euid-user=$(id -un)"; touch /etc/wl-test-open && echo "write /etc: yes" || echo "write /etc: NO"; ls /root >/dev/null 2>&1 && echo "read /root: yes" || echo "read /root: NO"; touch /tmp/wl-test-tmp && echo "write /tmp: yes" || echo "write /tmp: NO"; echo "net links: $(ls /sys/class/net | tr "\n" " ")"; grep CapEff /proc/self/status'
EOF
cat > $U/wl-closed.service <<'EOF'
[Service]
Type=oneshot
DynamicUser=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateNetwork=yes
NoNewPrivileges=yes
CapabilityBoundingSet=
ReadWritePaths=/var/tmp
ExecStart=/bin/sh -c 'echo "uid=$(id -u) euid-user=$(id -un)"; touch /etc/wl-test-closed && echo "write /etc: yes" || echo "write /etc: NO"; ls /root >/dev/null 2>&1 && echo "read /root: yes" || echo "read /root: NO"; touch /tmp/wl-test-tmp && echo "write /tmp: yes" || echo "write /tmp: NO"; touch /var/tmp/wl-test-vartmp && echo "write /var/tmp: yes" || echo "write /var/tmp: NO"; echo "net links: $(ls /sys/class/net | tr "\n" " ")"; grep CapEff /proc/self/status'
EOF
systemctl daemon-reload
sh_ 'systemctl start wl-open; journalctl -u wl-open --no-pager -o cat -n8 | grep -v "^Starting\|^Finished\|Deactivated\|Consumed"'
sh_ 'systemctl start wl-closed; journalctl -u wl-closed --no-pager -o cat -n12 | grep -v "^Starting\|^Finished\|Deactivated\|Consumed"'
sh_ 'ls -l /tmp/wl-test-tmp /etc/wl-test-open 2>&1 | sed "s/ [0-9].* \// \//"; ls /var/tmp | grep wl-test; ls /etc | grep wl-test'
sh_ 'systemd-analyze security wl-open.service --no-pager 2>&1 | tail -2'
sh_ 'systemd-analyze security wl-closed.service --no-pager 2>&1 | tail -2'
sh_ 'systemd-analyze security wl-closed.service --no-pager 2>&1 | head -14 | cut -c1-110'

echo '### 3. Resource control'
sh_ 'cat /sys/fs/cgroup/cgroup.controllers; stat -fc %T /sys/fs/cgroup'
sh_ 'systemd-run --wait --collect -p MemoryMax=40M --unit=wl-mem bash -c "x=\$(head -c 150000000 /dev/zero | tr \"\\0\" a); echo allocated \${#x}" 2>&1 | grep -v "^Running as"'
sh_ 'systemd-run --wait --collect -p CPUQuota=20% --unit=wl-cpu -p RuntimeMaxSec=4 sh -c "while :; do :; done" 2>&1 | grep -E "CPU time|Finished|result|Service runtime" | head -4'
sh_ 'systemd-run --scope --unit=wl-scope -p TasksMax=5 bash -c "for i in 1 2 3 4 5 6 7 8; do sleep 3 & done 2>&1; echo \$?" 2>&1 | tail -3'
sh_ 'systemd-run --unit=wl-prop --collect /bin/sleep 100 >/dev/null 2>&1; systemctl set-property wl-prop MemoryMax=64M CPUWeight=50; systemctl show wl-prop -p MemoryMax,CPUWeight; ls /etc/systemd/system.control | grep wl-; systemctl set-property --runtime wl-prop MemoryMax=32M; systemctl show wl-prop -p MemoryMax; systemctl stop wl-prop'

echo '### 4. Socket activation (Accept=yes: one service instance per connection)'
cat > $U/wl-echo.socket <<'EOF'
[Socket]
ListenStream=127.0.0.1:47651
Accept=yes
[Install]
WantedBy=sockets.target
EOF
cat > $U/wl-echo@.service <<'EOF'
[Service]
ExecStart=-/bin/cat
StandardInput=socket
EOF
systemctl daemon-reload
sh_ 'systemctl start wl-echo.socket; systemctl is-active wl-echo.socket; systemctl list-units "wl-echo@*" --no-legend | wc -l | tr -d " "'
sh_ 'ss -ltn 2>/dev/null | grep 47651 | tr -s " " | cut -d" " -f1,4'
sh_ 'exec 3<>/dev/tcp/127.0.0.1/47651; echo hello-socket >&3; read -r -t 3 line <&3; echo "got: $line"; systemctl list-units "wl-echo@*" --no-legend | awk "{print \$1, \$3, \$4}" | sed "s/@[0-9]*-[0-9.:]*-[0-9.:]*/@<conn>/"'
sh_ 'sleep 0.5; systemctl list-units "wl-echo@*" --no-legend | wc -l | tr -d " "; systemctl show wl-echo.socket -p NAccepted,NConnections,Accept'
sh_ 'systemctl stop wl-echo.socket; ss -ltn 2>/dev/null | grep -c 47651'

echo '### 5. Path units'
cat > $U/wl-watch.service <<'EOF'
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo "triggered at $(date +%%S)" >> /tmp/wl-watch.log; rm -f /tmp/wl-trigger'
EOF
cat > $U/wl-watch.path <<'EOF'
[Path]
PathExists=/tmp/wl-trigger
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
rm -f /tmp/wl-watch.log /tmp/wl-trigger
sh_ 'systemctl start wl-watch.path; systemctl is-active wl-watch.path wl-watch.service; touch /tmp/wl-trigger; sleep 1; cat /tmp/wl-watch.log | sed "s/at [0-9]*/at <s>/"; ls /tmp/wl-trigger 2>&1 | sed "s/.*cannot access.*/trigger file consumed/"'
sh_ 'systemctl stop wl-watch.path'

echo '### 6. Templates, instances and specifiers'
cat > $U/wl-inst@.service <<'EOF'
[Unit]
Description=WinLab instance %i
[Service]
ExecStart=/bin/sh -c 'echo "i=%i n=%n N=%N p=%p H=%H"; sleep 30'
[Install]
WantedBy=multi-user.target
DefaultInstance=main
EOF
systemctl daemon-reload
sh_ 'systemctl start wl-inst@alpha wl-inst@beta; sleep 0.4; journalctl -u "wl-inst@*" --no-pager -o cat | sed "s/H=.*/H=<host>/" | sort'
sh_ 'systemctl list-units "wl-inst@*" --no-legend | awk "{print \$1, \$3, \$4}"'
sh_ 'systemctl enable wl-inst@ 2>&1 | sed "s/ → .*//"'
sh_ 'systemctl is-enabled wl-inst@main; systemctl disable wl-inst@main >/dev/null 2>&1; systemctl stop wl-inst@alpha wl-inst@beta'
sh_ 'systemd-escape "my dir/with space"; systemd-escape --path /var/lib/my-app; systemd-escape -u "var-lib-my\\x2dapp"; systemd-escape --template=wl-inst@.service "a/b"'

echo '### 7. ExecStart is not a shell; environment; ExecReload; stop and kill'
cat > /tmp/wl-env <<'EOF'
FROMFILE=file-value
QUOTED="two words"
EOF
cat > $U/wl-noshell.service <<'EOF'
[Service]
Type=oneshot
Environment=NAME=world
EnvironmentFile=/tmp/wl-env
EnvironmentFile=-/tmp/wl-does-not-exist
ExecStart=/bin/echo hello $NAME ${NAME} "$NAME" $FROMFILE [$QUOTED] | wc -l ; echo second $HOME %%h
ExecStart=/bin/sh -c 'echo via-shell $NAME $FROMFILE "[$QUOTED]" $(echo sub)'
EOF
systemctl daemon-reload
sh_ 'systemctl start wl-noshell; journalctl -u wl-noshell --no-pager -o cat -n4 | grep -v "^Starting\|^Finished\|Deactivated\|Consumed"'
cat > $U/wl-stubborn.service <<'EOF'
[Service]
ExecStart=/bin/sh -c 'trap "" TERM; while :; do sleep 1; done'
TimeoutStopSec=3
EOF
cat > $U/wl-polite.service <<'EOF'
[Service]
ExecStart=/bin/sleep 1000
EOF
systemctl daemon-reload
sh_ 'systemctl start wl-stubborn; s=$(date +%s.%N); systemctl stop wl-stubborn; e=$(date +%s.%N); printf "stop took %.0f s\n" $(echo "$e - $s" | bc -l); journalctl -u wl-stubborn --no-pager -o cat | grep -i "timed out\|killing\|SIGKILL\|Failed with" | cut -c1-120'
sh_ 'systemctl start wl-polite; s=$(date +%s.%N); systemctl stop wl-polite; e=$(date +%s.%N); printf "polite stop took %.1f s\n" $(echo "$e - $s" | bc -l)'
sh_ 'systemctl show -p KillMode,KillSignal,TimeoutStopUSec,SendSIGKILL wl-polite'
cat > $U/wl-reload.service <<'EOF'
[Service]
ExecStart=/bin/sh -c 'trap "echo got-HUP" HUP; while :; do sleep 0.2; done'
ExecReload=/bin/kill -HUP $MAINPID
EOF
systemctl daemon-reload
sh_ 'systemctl start wl-reload; sleep 0.4; systemctl reload wl-reload; sleep 0.5; journalctl -u wl-reload --no-pager -o cat | grep -E "got-HUP|Reload"; systemctl stop wl-reload'
cat > $U/wl-pre.service <<'EOF'
[Service]
ExecStartPre=/bin/false
ExecStart=/bin/sleep 100
EOF
systemctl daemon-reload
sh_ 'systemctl start wl-pre; echo "rc=$?"; systemctl show wl-pre -p Result,ActiveState'

echo '### 8. systemd-analyze'
cat > $U/wl-typo.service <<'EOF'
[Unit]
Descrption=typo in a key name
After=nonexistent-unit.service
[Service]
Execstart=/bin/true
ExecStart=/usr/bin/slepe
EOF
sh_ 'systemd-analyze verify wl-typo.service 2>&1 | cut -c1-150'
sh_ 'systemd-analyze blame --no-pager 2>&1 | head -4 | cut -c1-100'
sh_ 'systemd-analyze critical-chain --no-pager 2>&1 | head -6 | cut -c1-100'
sh_ 'systemd-analyze time 2>&1 | head -3 | cut -c1-140'
sh_ 'systemd-analyze unit-paths 2>&1 | head -4'

echo '### 9. User units (as root: user@0.service is running here)'
sh_ 'systemctl --user is-system-running 2>&1; echo "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-unset}"; ls -d /run/user/0 2>&1'
mkdir -p /root/.config/systemd/user
cat > /root/.config/systemd/user/wl-user.service <<'EOF'
[Service]
ExecStart=/bin/sleep 1000
EOF
sh_ 'export XDG_RUNTIME_DIR=/run/user/0; systemctl --user daemon-reload 2>&1; systemctl --user start wl-user 2>&1; systemctl --user is-active wl-user 2>&1; systemctl --user stop wl-user 2>&1; loginctl show-user root -p Linger 2>&1'

echo '### 10. Misc status commands'
sh_ 'systemctl is-system-running'
sh_ 'systemctl list-jobs --no-pager 2>&1 | head -2'
sh_ 'hostnamectl 2>&1 | head -4 | cut -c1-70; timedatectl 2>&1 | head -3 | cut -c1-70'
sh_ 'systemctl show --property=Version,Architecture,Virtualization,SystemState 2>&1'
echo '### done'
