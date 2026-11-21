#!/usr/bin/env bash
# Battery 1 for linux.systemd: inspecting units, writing services, enable/mask, failures, restart limits, types, overrides.
# Run as root on a systemd machine (tested: Ubuntu 26.04 in WSL2, systemd 259). All test units are named wl-*; cleanup removes them.
export SYSTEMD_PAGER=cat SYSTEMD_COLORS=0 PAGER=cat
U=/etc/systemd/system
cleanup() { systemctl stop 'wl-*' >/dev/null 2>&1; systemctl reset-failed 'wl-*' >/dev/null 2>&1; rm -rf "$U"/wl-* "$U"/*.wants/wl-* /run/systemd/system/wl-* ; systemctl daemon-reload; }
trap cleanup EXIT
r() { echo "\$ $*"; local out rc; out=$("$@" 2>&1); rc=$?; [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/  /'; [ "$rc" != 0 ] && echo "  [rc=$rc]"; return 0; }
sh_() { echo "\$ $1"; local out rc; out=$(bash -c "$1" 2>&1); rc=$?; [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/  /'; [ "$rc" != 0 ] && echo "  [rc=$rc]"; return 0; }
echo "systemd $(systemctl --version | head -1)"; echo "kernel $(uname -r)"; id -un

echo '### 1. Inspect a unit that ships with the system'
sh_ 'systemctl status systemd-journald --no-pager -n0 | head -14'
sh_ 'systemctl show systemd-journald -p Id,Type,ActiveState,SubState,UnitFileState,FragmentPath,MainPID | sed "s/MainPID=[0-9]*/MainPID=<pid>/"'
sh_ 'systemctl cat systemd-journald | head -30'
r systemctl is-active systemd-journald
r systemctl is-enabled systemd-journald
r systemctl is-active no-such-unit
r systemctl is-failed systemd-journald
sh_ 'systemctl list-unit-files | awk "NR>1 && NF==3 {print \$2}" | sort | uniq -c | sort -rn'
sh_ 'systemctl list-units --type=service --state=running --no-legend | awk "{print \$1}" | head -20'
sh_ 'systemctl list-units --failed --no-legend | wc -l'
r systemctl get-default
sh_ 'systemctl list-dependencies multi-user.target --no-pager | head -14'
sh_ 'systemctl show -p UnitPath | tr " " "\n" | head -12'

echo '### 2. A first service'
cat > $U/wl-hello.service <<'EOF'
[Unit]
Description=WinLab hello ticker

[Service]
ExecStart=/bin/sh -c 'while :; do echo tick; sleep 1; done'

[Install]
WantedBy=multi-user.target
EOF
r systemctl is-enabled wl-hello
r systemctl start wl-hello
sleep 2.2
sh_ 'systemctl status wl-hello --no-pager -n3 | sed "s/[0-9]\{4\}-[0-9-]* [0-9:]*/<time>/; s/Main PID: [0-9]* /Main PID: <pid> /; s/since [^;]*;/since <time>;/; s/[0-9]*ms/<ms>/; s/Tasks: .*/Tasks: <n>/; s/Memory: .*/Memory: <m>/; s/CPU: .*/CPU: <c>/; s/├─[0-9]*/├─<pid>/; s/└─[0-9]*/└─<pid>/" | cut -c1-120'
sh_ 'journalctl -u wl-hello --no-pager -o cat -n 3'
r systemctl is-active wl-hello
r systemctl stop wl-hello
r systemctl is-active wl-hello
echo '-- enable / disable are symlinks'
r systemctl enable wl-hello
sh_ 'ls -l /etc/systemd/system/multi-user.target.wants/ | grep wl- | sed "s/.* wl-/wl-/"'
r systemctl is-enabled wl-hello
sh_ 'systemctl is-active wl-hello'
r systemctl enable --now wl-hello
sh_ 'systemctl is-active wl-hello'
r systemctl disable --now wl-hello
sh_ 'systemctl is-enabled wl-hello; systemctl is-active wl-hello'
echo '-- mask'
r systemctl mask wl-hello
sh_ 'ls -l /etc/systemd/system/wl-hello.service | sed "s/.* \/etc/\/etc/"'
r systemctl start wl-hello
r systemctl is-enabled wl-hello
r systemctl unmask wl-hello
sh_ 'ls -l /etc/systemd/system/wl-hello.service | cut -c1-10'

echo '### 3. A service that cannot start (wrong path)'
cat > $U/wl-bad.service <<'EOF'
[Unit]
Description=WinLab broken service

[Service]
ExecStart=/usr/bin/slepe 1000
EOF
r systemctl daemon-reload
r systemctl start wl-bad
sh_ 'systemctl status wl-bad --no-pager -n5 | sed "s/[0-9]\{4\}-[0-9-]* [0-9:]*/<time>/; s/since [^;]*;/since <time>;/; s/[0-9]*ms ago/<ms> ago/; s/ [0-9]*\(ms\|s\) ago/ <t> ago/; s/wl-bad\[[0-9]*\]/wl-bad[<pid>]/" | cut -c1-150'
sh_ 'systemctl show wl-bad -p Result,ExecMainStatus,ExecMainCode,ActiveState,SubState'
sh_ 'journalctl -u wl-bad --no-pager -o cat | cut -c1-140 | head -6'
r systemctl is-failed wl-bad
sh_ 'systemctl list-units --failed --no-legend | cut -c1-80'
echo '-- fix the file WITHOUT daemon-reload'
sed -i 's#/usr/bin/slepe#/usr/bin/sleep#' $U/wl-bad.service
r systemctl start wl-bad
r systemctl daemon-reload
r systemctl start wl-bad
r systemctl is-active wl-bad
r systemctl stop wl-bad

echo '### 4. Restart policies and the start limit'
cat > $U/wl-flaky.service <<'EOF'
[Unit]
Description=WinLab flaky service
StartLimitIntervalSec=10
StartLimitBurst=3

[Service]
ExecStart=/bin/sh -c 'echo started; exit 1'
Restart=on-failure
RestartSec=200ms
EOF
r systemctl daemon-reload
r systemctl start wl-flaky
sleep 2
sh_ 'systemctl show wl-flaky -p Result,NRestarts,ActiveState,SubState'
sh_ 'systemctl status wl-flaky --no-pager -n0 | head -8 | sed "s/[0-9]\{4\}-[0-9-]* [0-9:]*/<time>/; s/since [^;]*;/since <time>;/; s/ [0-9]*\(ms\|s\) ago/ <t> ago/; s/wl-flaky\[[0-9]*\]/wl-flaky[<pid>]/"'
sh_ 'journalctl -u wl-flaky --no-pager -o cat | sort | uniq -c | sort -rn | head -6'
r systemctl start wl-flaky
r systemctl reset-failed wl-flaky
sh_ 'systemctl show wl-flaky -p Result,NRestarts,ActiveState'
r systemctl stop wl-flaky
echo '-- Restart= values and what each restarts on (table from the manual, not run): see lesson'

echo '### 5. Service types'
cat > $U/wl-oneshot.service <<'EOF'
[Unit]
Description=WinLab oneshot
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo working; sleep 1; echo done'
RemainAfterExit=yes
EOF
cat > $U/wl-oneshot2.service <<'EOF'
[Unit]
Description=WinLab oneshot without RemainAfterExit
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo working; sleep 1; echo done'
EOF
cat > $U/wl-notify.service <<'EOF'
[Unit]
Description=WinLab notify type
[Service]
Type=notify
NotifyAccess=all
ExecStart=/bin/sh -c 'sleep 2; systemd-notify --ready; sleep 30'
EOF
cat > $U/wl-simple.service <<'EOF'
[Unit]
Description=WinLab simple type
[Service]
Type=simple
ExecStart=/bin/sh -c 'sleep 2; sleep 30'
EOF
cat > $U/wl-forking.service <<'EOF'
[Unit]
Description=WinLab forking type
[Service]
Type=forking
PIDFile=/run/wl-forking.pid
ExecStart=/bin/sh -c 'sleep 30 & echo $! > /run/wl-forking.pid'
EOF
r systemctl daemon-reload
echo '-- oneshot: start blocks until the command ends'
sh_ 'time -p systemctl start wl-oneshot 2>&1 | head -1; systemctl is-active wl-oneshot; systemctl show wl-oneshot -p SubState,Result'
sh_ 'systemctl start wl-oneshot2; systemctl is-active wl-oneshot2; systemctl show wl-oneshot2 -p SubState,Result'
echo '-- notify: start blocks until READY=1 (about 2 s); simple: returns at once'
sh_ 's=$(date +%s.%N); systemctl start wl-notify; e=$(date +%s.%N); echo "notify start took $(echo "$e - $s" | bc -l | cut -c1-3) s"; systemctl show wl-notify -p Type,SubState'
sh_ 's=$(date +%s.%N); systemctl start wl-simple; e=$(date +%s.%N); echo "simple start took $(echo "$e - $s" | bc -l | cut -c1-4) s"; systemctl show wl-simple -p Type,SubState'
sh_ 'systemctl start wl-forking; systemctl show wl-forking -p Type,SubState,MainPID | sed "s/MainPID=[0-9]*/MainPID=<pid>/"; cat /run/wl-forking.pid | grep -c "^[0-9]"'
r systemctl stop wl-notify wl-simple wl-forking wl-oneshot

echo '### 6. Drop-in overrides'
cat > $U/wl-app.service <<'EOF'
[Unit]
Description=WinLab app
[Service]
Environment=GREETING=hello
ExecStart=/bin/sh -c 'echo "greeting=$GREETING"; sleep 30'
EOF
r systemctl daemon-reload
r systemctl start wl-app
sleep 0.5
sh_ 'journalctl -u wl-app --no-pager -o cat -n1'
mkdir -p $U/wl-app.service.d
cat > $U/wl-app.service.d/override.conf <<'EOF'
[Service]
Environment=GREETING=hola
EOF
sh_ 'systemctl restart wl-app 2>&1; sleep 0.5; journalctl -u wl-app --no-pager -o cat -n1'
sh_ 'systemctl cat wl-app | sed "s/^/ /"'
echo '-- EXTRA ExecStart= without a reset line is an error for Type=simple'
cat > $U/wl-app.service.d/override.conf <<'EOF'
[Service]
ExecStart=/bin/sh -c 'echo "second"; sleep 30'
EOF
r systemctl daemon-reload
r systemctl restart wl-app
echo '-- reset the list first, then give the new command'
cat > $U/wl-app.service.d/override.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/bin/sh -c 'echo "replaced"; sleep 30'
EOF
r systemctl daemon-reload
r systemctl restart wl-app
sleep 0.5
sh_ 'journalctl -u wl-app --no-pager -o cat -n1'
sh_ 'systemctl show wl-app -p DropInPaths'
sh_ 'systemd-delta --type=extended,overridden 2>&1 | grep wl- | head -3'
echo '-- systemctl edit with a scripted editor (no terminal): the drop-in lands in /etc/systemd/system/NAME.d/override.conf'
cat > /tmp/wl-editor.sh <<'EOF'
#!/bin/sh
printf '[Service]\nEnvironment=FROM=edit\n' >> "$1"
EOF
chmod +x /tmp/wl-editor.sh
rm -rf $U/wl-app.service.d
r systemctl daemon-reload
sh_ 'EDITOR=/tmp/wl-editor.sh SYSTEMD_EDITOR=/tmp/wl-editor.sh systemctl edit wl-app; ls /etc/systemd/system/wl-app.service.d/; cat /etc/systemd/system/wl-app.service.d/override.conf'
r systemctl revert wl-app
sh_ 'ls /etc/systemd/system/wl-app.service.d 2>&1 | head -1; ls /etc/systemd/system/wl-app.service'
r systemctl stop wl-app
rm -f /tmp/wl-editor.sh
echo '### done'
