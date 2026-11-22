#!/usr/bin/env bash
# Battery 8 for linux.systemd: SELinux (enforcing, AlmaLinux 9) and units that point at files in /tmp. Run as root on AlmaLinux (VM).
# Found while running sd1-sd5 on Alma: the same unit files that work on Ubuntu fail with "Permission denied" when they exec or read /tmp.
export SYSTEMD_PAGER=cat SYSTEMD_COLORS=0 PAGER=cat
U=/etc/systemd/system
cleanup() { systemctl stop 'wl-*' >/dev/null 2>&1; systemctl reset-failed 'wl-*' >/dev/null 2>&1; rm -rf "$U"/wl-* /tmp/wl-* /usr/local/bin/wl-* /etc/wl-env; systemctl daemon-reload; }
trap cleanup EXIT
r() { echo "\$ $*"; local out rc; out=$("$@" 2>&1); rc=$?; [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/  /'; [ "$rc" != 0 ] && echo "  [rc=$rc]"; return 0; }
sh_() { echo "\$ $1"; local out rc; out=$(bash -c "$1" 2>&1); rc=$?; [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/  /'; [ "$rc" != 0 ] && echo "  [rc=$rc]"; return 0; }
. /etc/os-release; echo "$PRETTY_NAME; systemd $(systemctl --version | head -1 | cut -d' ' -f2)"
r getenforce
echo '### 1. A script in /tmp as ExecStart'
printf '#!/bin/sh\necho hello-from-script\n' > /tmp/wl-script.sh; chmod +x /tmp/wl-script.sh
printf '[Service]\nType=oneshot\nExecStart=/tmp/wl-script.sh\n' > $U/wl-tmp.service
systemctl daemon-reload
sh_ 'systemctl start wl-tmp; echo "start rc=$?"; systemctl show wl-tmp -p Result -p ExecMainStatus'
sh_ 'journalctl -u wl-tmp --no-pager -o cat | grep -v "^Starting\|^Failed to start"'
sh_ '/tmp/wl-script.sh; echo "run by hand as root: rc=$?"'
sh_ 'ls -Z /tmp/wl-script.sh'
sh_ 'ausearch -m avc -ts recent </dev/null 2>&1 | grep -o "avc:  denied.*" | head -3'
echo '### 2. The same script in /usr/local/bin'
cp /tmp/wl-script.sh /usr/local/bin/wl-script.sh
sh_ 'ls -Z /usr/local/bin/wl-script.sh'
printf '[Service]\nType=oneshot\nExecStart=/usr/local/bin/wl-script.sh\n' > $U/wl-bin.service; systemctl daemon-reload
sh_ 'systemctl start wl-bin; echo "start rc=$?"; journalctl -u wl-bin --no-pager -o cat | grep hello'
echo '### 3. An EnvironmentFile in /tmp, then in /etc'
printf 'FOO=bar\n' > /tmp/wl-env; cp /tmp/wl-env /etc/wl-env
printf '[Service]\nType=oneshot\nEnvironmentFile=/tmp/wl-env\nExecStart=/bin/sh -c "echo FOO=$FOO"\n' > $U/wl-envtmp.service
printf '[Service]\nType=oneshot\nEnvironmentFile=/etc/wl-env\nExecStart=/bin/sh -c "echo FOO=$FOO"\n' > $U/wl-envetc.service
systemctl daemon-reload
sh_ 'systemctl start wl-envtmp 2>&1 | head -3; journalctl -u wl-envtmp --no-pager -o cat | grep -i "environment\|denied" | head -2'
sh_ 'systemctl start wl-envetc; journalctl -u wl-envetc --no-pager -o cat | grep FOO='
echo '### 4. The same /tmp unit with SELinux permissive (setenforce 0), then back to enforcing'
r setenforce 0
sh_ 'systemctl start wl-tmp; echo "start rc=$?"; journalctl -u wl-tmp --no-pager -o cat | grep hello | tail -1'
r setenforce 1
r getenforce
