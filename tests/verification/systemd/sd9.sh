#!/usr/bin/env bash
# Battery 9 for linux.systemd: the version-independent way to create a drop-in (no systemctl edit --stdin, which needs systemd 256).
# Run as root. Tested on systemd 252 (AlmaLinux 9.8) and 255 (Ubuntu 24.04).
export SYSTEMD_PAGER=cat SYSTEMD_COLORS=0 PAGER=cat
U=/etc/systemd/system
cleanup() { systemctl stop wl-app >/dev/null 2>&1; rm -rf $U/wl-app.service $U/wl-app.service.d; systemctl daemon-reload; }
trap cleanup EXIT
r() { echo "\$ $*"; local out rc; out=$("$@" 2>&1); rc=$?; [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/  /'; [ "$rc" != 0 ] && echo "  [rc=$rc]"; return 0; }
sh_() { echo "\$ $1"; local out rc; out=$(bash -c "$1" 2>&1); rc=$?; [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/  /'; [ "$rc" != 0 ] && echo "  [rc=$rc]"; return 0; }
echo "systemd $(systemctl --version | head -1 | cut -d' ' -f2)"
printf '[Service]\nType=oneshot\nEnvironment=GREETING=hello\nExecStart=/bin/sh -c "echo greeting=$GREETING"\n' > $U/wl-app.service
systemctl daemon-reload
sh_ 'systemctl start wl-app; journalctl -u wl-app --no-pager -o cat | grep greeting= | tail -1'
sh_ 'printf "[Service]\nEnvironment=GREETING=hola\n" | systemctl edit --stdin wl-app'
sh_ 'mkdir -p /etc/systemd/system/wl-app.service.d; printf "[Service]\nEnvironment=GREETING=hola\n" > /etc/systemd/system/wl-app.service.d/override.conf'
sh_ 'systemctl start wl-app; journalctl -u wl-app --no-pager -o cat | grep greeting= | tail -1'
sh_ 'systemctl daemon-reload; systemctl start wl-app; journalctl -u wl-app --no-pager -o cat | grep greeting= | tail -1'
r systemctl cat wl-app
r systemctl revert wl-app
sh_ 'ls /etc/systemd/system/wl-app.service.d 2>&1'
