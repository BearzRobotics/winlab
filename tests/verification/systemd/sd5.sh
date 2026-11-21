#!/usr/bin/env bash
# Battery 5 for linux.systemd: the Restart= matrix redone with real signals, and the $$ escape. Run as root (Ubuntu 26.04 WSL2, systemd 259).
export SYSTEMD_PAGER=cat SYSTEMD_COLORS=0 PAGER=cat
U=/etc/systemd/system
cleanup() { systemctl stop 'wl-*' >/dev/null 2>&1; systemctl reset-failed 'wl-*' >/dev/null 2>&1; rm -rf "$U"/wl-*; systemctl daemon-reload; }
trap cleanup EXIT
sh_() { echo "\$ $1"; local out rc; out=$(bash -c "$1" 2>&1); rc=$?; [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/  /'; [ "$rc" != 0 ] && echo "  [rc=$rc]"; return 0; }
echo "systemd $(systemctl --version | head -1)"

echo '### 1. $$ in a unit file is an escaped dollar sign'
cat > $U/wl-dollar.service <<'EOF'
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo "one-dollar-pid=$BASHPID two=$$ x"'
ExecStart=/bin/sh -c 'echo "shell pid is $$"'
EOF
systemctl daemon-reload
sh_ 'systemctl start wl-dollar; journalctl -u wl-dollar --no-pager -o cat | grep -v "^Starting\|^Finished\|Deactivated\|Consumed" | sed "s/[0-9][0-9]*/<n>/g"'

echo '### 2. Restart= matrix with real exits and signals'
declare -A cmd=( [exit0]='exit 0' [exit1]='exit 1' [term]='kill -TERM $BASHPID' [kill]='kill -KILL $BASHPID' [abrt]='kill -ABRT $BASHPID' )
cols=(exit0 exit1 term kill abrt)
for pol in no on-success on-failure on-abnormal on-abort always; do
  for c in "${cols[@]}"; do
    cat > $U/wl-r-$pol-$c.service <<EOF
[Unit]
StartLimitIntervalSec=0
[Service]
Restart=$pol
RestartSec=100ms
ExecStart=/bin/bash -c 'sleep 0.1; ${cmd[$c]}'
EOF
  done
done
systemctl daemon-reload
for f in $U/wl-r-*.service; do systemctl start "$(basename "$f")" --no-block; done
sleep 4
printf '  %-12s' "Restart="; for c in "${cols[@]}"; do printf '%-12s' "$c"; done; echo
for pol in no on-success on-failure on-abnormal on-abort always; do
  printf '  %-12s' "$pol"
  for c in "${cols[@]}"; do
    n=$(systemctl show "wl-r-$pol-$c.service" -p NRestarts --value)
    [ "${n:-0}" -ge 2 ] && v=restarts || v=stays-down
    printf '%-12s' "$v"
  done; echo
done
echo '-- Result recorded for a service that ends each way with Restart=no'
for c in "${cols[@]}"; do printf '  %-6s Result=%-10s ExecMainStatus=%s\n' "$c" "$(systemctl show wl-r-no-$c.service -p Result --value)" "$(systemctl show wl-r-no-$c.service -p ExecMainStatus --value)"; done
sh_ 'journalctl -u wl-r-no-term.service --no-pager -o cat | tail -3 | cut -c1-120'
sh_ 'journalctl -u wl-r-no-kill.service --no-pager -o cat | tail -3 | cut -c1-120'
sh_ 'journalctl -u wl-r-no-abrt.service --no-pager -o cat | tail -3 | cut -c1-120'
echo '### done'
