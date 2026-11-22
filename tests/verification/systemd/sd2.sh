#!/usr/bin/env bash
# Battery 2 for linux.systemd: follow-ups, dependencies, targets, timers, the journal. Run as root (tested: Ubuntu 26.04 WSL2, systemd 259).
# NOTE: on AlmaLinux with SELinux enforcing, units that use files in /tmp fail with "Permission denied" (see sd8.sh); run "setenforce 0" for the duration of this battery and "setenforce 1" afterwards.
export SYSTEMD_PAGER=cat SYSTEMD_COLORS=0 PAGER=cat
U=/etc/systemd/system
cleanup() { systemctl stop 'wl-*' >/dev/null 2>&1; systemctl reset-failed 'wl-*' >/dev/null 2>&1; rm -rf "$U"/wl-* "$U"/*.wants/wl-* "$U"/*.requires/wl-* /usr/lib/systemd/system/wl-* /run/systemd/system/wl-* /tmp/wl-*; systemctl daemon-reload; }
trap cleanup EXIT
sh_() { echo "\$ $1"; local out rc; out=$(bash -c "$1" 2>&1); rc=$?; [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/  /'; [ "$rc" != 0 ] && echo "  [rc=$rc]"; return 0; }
echo "systemd $(systemctl --version | head -1)"

echo '### 1. Type=simple versus Type=exec when the program does not exist'
cat > $U/wl-simple-bad.service <<'EOF'
[Service]
Type=simple
ExecStart=/usr/bin/slepe 100
EOF
cat > $U/wl-exec-bad.service <<'EOF'
[Service]
Type=exec
ExecStart=/usr/bin/slepe 100
EOF
systemctl daemon-reload
sh_ 'systemctl start wl-simple-bad; echo "start rc=$?"; sleep 0.3; systemctl is-active wl-simple-bad'
sh_ 'systemctl start wl-exec-bad; echo "start rc=$?"; systemctl is-active wl-exec-bad'

echo '### 2. Masking a vendor unit'
cat > /usr/lib/systemd/system/wl-vendor.service <<'EOF'
[Unit]
Description=WinLab vendor-style unit
[Service]
ExecStart=/bin/sleep 1000
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
sh_ 'systemctl is-enabled wl-vendor'
sh_ 'systemctl mask wl-vendor; ls -l /etc/systemd/system/wl-vendor.service | sed "s/.* \/etc/\/etc/"'
sh_ 'systemctl is-enabled wl-vendor'
sh_ 'systemctl start wl-vendor'
sh_ 'systemctl enable wl-vendor'
sh_ 'systemctl status wl-vendor --no-pager -n0 | head -3'
sh_ 'systemctl unmask wl-vendor; systemctl is-enabled wl-vendor'
sh_ 'systemctl mask --runtime wl-vendor; ls -l /run/systemd/system/wl-vendor.service | sed "s/.* \/run/\/run/"; systemctl is-enabled wl-vendor; systemctl unmask --runtime wl-vendor'

echo '### 3. systemctl edit without a terminal'
cat > $U/wl-app.service <<'EOF'
[Service]
Environment=GREETING=hello
ExecStart=/bin/sh -c 'echo "greeting=$GREETING"; sleep 30'
EOF
systemctl daemon-reload
sh_ 'printf "[Service]\nEnvironment=GREETING=hola\n" | systemctl edit --stdin wl-app; ls /etc/systemd/system/wl-app.service.d/; cat /etc/systemd/system/wl-app.service.d/override.conf'
sh_ 'systemctl start wl-app; sleep 0.4; journalctl -u wl-app -o cat --no-pager -n1'
sh_ 'printf "[Service]\nEnvironment=GREETING=bonjour\n" | systemctl edit --stdin --drop-in=fr.conf wl-app; ls /etc/systemd/system/wl-app.service.d/'
sh_ 'systemctl cat wl-app | grep -v "^#" | sed "s/^/ /"'
sh_ 'systemctl revert wl-app; ls /etc/systemd/system/wl-app.service.d 2>&1 | head -1'
sh_ 'systemctl stop wl-app'

echo '### 4. Dependencies and ordering'
for n in db app; do :; done
cat > $U/wl-db.service <<'EOF'
[Unit]
Description=WinLab db
[Service]
ExecStart=/bin/sleep 1000
EOF
cat > $U/wl-req.service <<'EOF'
[Unit]
Description=WinLab app Requires db
Requires=wl-db.service
After=wl-db.service
[Service]
ExecStart=/bin/sleep 1000
EOF
cat > $U/wl-wants.service <<'EOF'
[Unit]
Description=WinLab app Wants db
Wants=wl-db.service
After=wl-db.service
[Service]
ExecStart=/bin/sleep 1000
EOF
cat > $U/wl-noorder.service <<'EOF'
[Unit]
Description=WinLab app Requires db but no ordering
Requires=wl-db.service
[Service]
ExecStart=/bin/sleep 1000
EOF
systemctl daemon-reload
st() { for u in "$@"; do printf '%s=%s ' "${u#wl-}" "$(systemctl is-active "$u")"; done; echo; }
echo '-- Requires: starting the app starts the db'
sh_ 'systemctl start wl-req; for u in wl-db wl-req; do printf "%s=%s " $u $(systemctl is-active $u); done; echo'
echo '-- stopping the db stops a unit that Requires it'
sh_ 'systemctl stop wl-db; for u in wl-db wl-req; do printf "%s=%s " $u $(systemctl is-active $u); done; echo'
echo '-- Wants: starts it too, but stopping the db leaves the app running'
sh_ 'systemctl start wl-wants; systemctl stop wl-db; for u in wl-db wl-wants; do printf "%s=%s " $u $(systemctl is-active $u); done; echo; systemctl stop wl-wants'
echo '-- Requires without After: both are started at the same time (no ordering)'
sh_ 'systemctl start wl-noorder; for u in wl-db wl-noorder; do printf "%s=%s " $u $(systemctl is-active $u); done; echo; systemctl stop wl-noorder wl-db'
echo '-- a failing Requires dependency stops the dependent from starting'
cat > $U/wl-dbbad.service <<'EOF'
[Service]
Type=exec
ExecStart=/usr/bin/slepe
EOF
cat > $U/wl-needbad.service <<'EOF'
[Unit]
Requires=wl-dbbad.service
After=wl-dbbad.service
[Service]
ExecStart=/bin/sleep 1000
EOF
cat > $U/wl-wantbad.service <<'EOF'
[Unit]
Wants=wl-dbbad.service
After=wl-dbbad.service
[Service]
ExecStart=/bin/sleep 1000
EOF
systemctl daemon-reload
sh_ 'systemctl start wl-needbad; echo "rc=$?"; systemctl is-active wl-needbad'
sh_ 'journalctl -u wl-needbad --no-pager -o cat -n2'
sh_ 'systemctl start wl-wantbad; echo "rc=$?"; systemctl is-active wl-wantbad; systemctl stop wl-wantbad'
sh_ 'systemctl list-dependencies wl-req --no-pager'
sh_ 'systemctl list-dependencies --reverse wl-db --no-pager'
echo '-- Conflicts'
cat > $U/wl-ca.service <<'EOF'
[Unit]
Conflicts=wl-cb.service
[Service]
ExecStart=/bin/sleep 1000
EOF
cat > $U/wl-cb.service <<'EOF'
[Unit]
Conflicts=wl-ca.service
[Service]
ExecStart=/bin/sleep 1000
EOF
systemctl daemon-reload
sh_ 'systemctl start wl-ca; systemctl start wl-cb; for u in wl-ca wl-cb; do printf "%s=%s " $u $(systemctl is-active $u); done; echo; systemctl stop wl-cb'
echo '-- PartOf: restarting the parent restarts the part'
cat > $U/wl-parent.service <<'EOF'
[Service]
ExecStart=/bin/sleep 1000
EOF
cat > $U/wl-part.service <<'EOF'
[Unit]
PartOf=wl-parent.service
After=wl-parent.service
[Service]
ExecStart=/bin/sleep 1000
EOF
systemctl daemon-reload
sh_ 'systemctl start wl-parent wl-part; a=$(systemctl show wl-part -p MainPID --value); systemctl restart wl-parent; sleep 0.3; b=$(systemctl show wl-part -p MainPID --value); [ "$a" != "$b" ] && echo "part was restarted (new PID)" || echo "part was NOT restarted"; systemctl stop wl-parent wl-part'
echo '-- ordering cycle detected by systemd-analyze verify'
cat > $U/wl-cyc1.service <<'EOF'
[Unit]
After=wl-cyc2.service
[Service]
ExecStart=/bin/true
EOF
cat > $U/wl-cyc2.service <<'EOF'
[Unit]
After=wl-cyc1.service
Wants=wl-cyc1.service
[Service]
ExecStart=/bin/true
EOF
cat > $U/wl-cyc1.service <<'EOF'
[Unit]
After=wl-cyc2.service
Wants=wl-cyc2.service
[Service]
ExecStart=/bin/true
EOF
systemctl daemon-reload
sh_ 'systemd-analyze verify wl-cyc1.service 2>&1 | head -6'

echo '### 5. Targets'
cat > $U/wl-grp.target <<'EOF'
[Unit]
Description=WinLab group target
Wants=wl-db.service wl-wants.service
EOF
systemctl daemon-reload
sh_ 'systemctl start wl-grp.target; for u in wl-db wl-wants wl-grp.target; do printf "%s=%s " $u $(systemctl is-active $u); done; echo'
sh_ 'systemctl list-dependencies wl-grp.target --no-pager'
sh_ 'systemctl stop wl-grp.target; for u in wl-db wl-wants wl-grp.target; do printf "%s=%s " $u $(systemctl is-active $u); done; echo'
sh_ 'systemctl stop wl-db wl-wants'
sh_ 'systemctl list-units --type=target --no-legend | awk "{print \$1}" | head -20 | tr "\n" " "'
sh_ 'ls -l /usr/lib/systemd/system/default.target | sed "s/.* \/usr/\/usr/"; systemctl get-default'
sh_ 'systemctl show -p Wants,Requires multi-user.target | cut -c1-200'
sh_ 'systemctl show -p AllowIsolate,Requires,Conflicts rescue.target emergency.target | cut -c1-160'

echo '### 6. Timers'
sh_ 'systemd-analyze calendar "daily" "weekly" "Mon..Fri 09:00" "*-*-* 02:30" "*:0/15" "2026-12-25" "hourly" "*-*-01 00:00:00" 2>&1 | grep -E "Original|Normalized|Next elapse" | sed "s/^ */  /"'
sh_ 'systemd-analyze calendar "Mon..Fri 09:00" --iterations=3 2>&1 | grep -E "Next|Iter" | sed "s/^ */  /"'
sh_ 'systemd-analyze calendar "funday" 2>&1 | head -3'
sh_ 'systemd-analyze timespan "1h 30min" "2d" 2>&1 | grep -E "Original|μs|Human" | sed "s/^ */  /"'
cat > $U/wl-tick.service <<'EOF'
[Unit]
Description=WinLab tick
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'date +%%s.%%N >> /tmp/wl-ticks; echo ran'
EOF
cat > $U/wl-tick.timer <<'EOF'
[Unit]
Description=WinLab tick timer
[Timer]
OnActiveSec=1
OnUnitActiveSec=2
AccuracySec=100ms
[Install]
WantedBy=timers.target
EOF
rm -f /tmp/wl-ticks; systemctl daemon-reload
sh_ 'systemctl start wl-tick.timer; sleep 7.5; awk "NR>1{printf \"gap %.1f s\n\", \$1-p} {p=\$1}" /tmp/wl-ticks; wc -l < /tmp/wl-ticks'
sh_ 'systemctl list-timers wl-tick.timer --no-pager | sed "s/[A-Z][a-z][a-z] 20[0-9-]* [0-9:]* [A-Z]*/<time>/g" | cut -c1-140'
sh_ 'systemctl show wl-tick.timer -p TimersMonotonic,AccuracyUSec,Persistent,Unit | cut -c1-200'
sh_ 'systemctl stop wl-tick.timer; systemctl is-active wl-tick.timer'
echo '-- a calendar timer every 10 s with the DEFAULT accuracy (1 min) versus AccuracySec=1s'
cat > $U/wl-cal.service <<'EOF'
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'date +%%S.%%N >> /tmp/wl-cal'
EOF
cat > $U/wl-cal.timer <<'EOF'
[Timer]
OnCalendar=*:*:0/10
[Install]
WantedBy=timers.target
EOF
cat > $U/wl-cal2.service <<'EOF'
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'date +%%S.%%N >> /tmp/wl-cal2'
EOF
cat > $U/wl-cal2.timer <<'EOF'
[Timer]
OnCalendar=*:*:0/10
AccuracySec=1s
[Install]
WantedBy=timers.target
EOF
rm -f /tmp/wl-cal /tmp/wl-cal2; systemctl daemon-reload
systemctl start wl-cal.timer wl-cal2.timer; sleep 26
sh_ 'echo "default accuracy, seconds-of-minute at each run:"; cut -c1-5 /tmp/wl-cal | tr "\n" " "; echo; echo "AccuracySec=1s:"; cut -c1-5 /tmp/wl-cal2 | tr "\n" " "; echo'
systemctl stop wl-cal.timer wl-cal2.timer
echo '-- transient units with systemd-run'
sh_ 'systemd-run --on-active=2 --unit=wl-once --property=Type=oneshot /bin/sh -c "echo transient-ran > /tmp/wl-once"; sleep 3; cat /tmp/wl-once'
sh_ 'systemd-run --unit=wl-trans --collect /bin/sleep 100 2>&1 | tail -1; systemctl is-active wl-trans; ls /run/systemd/transient | grep wl-; systemctl stop wl-trans; ls /run/systemd/transient 2>&1 | grep -c wl-'

echo '### 7. The journal'
sh_ 'systemd-cat -t wl-test -p warning echo "something looks odd"; systemd-cat -t wl-test -p info echo "just info"; sleep 0.3; journalctl -t wl-test --no-pager -o short-precise | sed "s/DESKTOP-[A-Z0-9]*/<host>/; s/[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9]*/<time>/; s/\[[0-9]*\]/[<pid>]/"'
sh_ 'journalctl -t wl-test -p warning --no-pager -o cat'
sh_ 'journalctl -t wl-test -p 0..4 --no-pager -o cat'
sh_ 'logger -t wl-logger -p user.err "from logger"; sleep 0.3; journalctl -t wl-logger --no-pager -o cat; journalctl -t wl-logger -o json --no-pager | head -1 | tr "," "\n" | grep -E "PRIORITY|SYSLOG_IDENTIFIER|MESSAGE|_TRANSPORT|SYSLOG_FACILITY" | sort'
sh_ 'journalctl --list-boots --no-pager | tail -3 | sed "s/[A-Z][a-z][a-z] 20[0-9-]* [0-9:]* [A-Z]*/<time>/g"'
sh_ 'journalctl --disk-usage'
sh_ 'ls -d /var/log/journal /run/log/journal 2>&1'
sh_ 'journalctl -k --no-pager -n2 -o cat | cut -c1-100'
sh_ 'journalctl -u systemd-journald --since "-1h" --until "now" --no-pager -o cat | wc -l | tr -d " "'
sh_ 'journalctl --since "2026-11-21 00:00:00" --until "2026-11-21 00:00:01" --no-pager 2>&1 | head -2'
sh_ 'journalctl -n 0 -o verbose --no-pager 2>&1 | head -1'
sh_ 'journalctl _SYSTEMD_UNIT=cron.service -n1 --no-pager -o cat | cut -c1-80'
sh_ 'journalctl -F _TRANSPORT --no-pager | sort | tr "\n" " "'
sh_ 'grep -E "^#?(Storage|SystemMaxUse|RuntimeMaxUse|ForwardToSyslog|MaxRetentionSec)" /etc/systemd/journald.conf 2>&1; ls /etc/systemd/journald.conf.d /usr/lib/systemd/journald.conf.d 2>&1 | head -4'
echo '### done'
