#!/usr/bin/env bash
# Battery 6 for the dinit lessons: an end-to-end service, the recovery and single services, and rc.local. Run as root in the Chimera VM.
D=/etc/dinit.d
dinitctl() { timeout 20 /usr/bin/dinitctl "$@"; }
export -f dinitctl
cleanup() {
  for s in $(dinitctl list 2>/dev/null | grep -o 'wl-[A-Za-z0-9@._-]*'); do dinitctl stop --force --ignore-unstarted "$s" >/dev/null 2>&1; dinitctl disable "$s" >/dev/null 2>&1; done
  for i in 1 2 3; do for s in $(dinitctl list 2>/dev/null | grep -o 'wl-[A-Za-z0-9@._-]*' | sort -r); do dinitctl unload "$s" >/dev/null 2>&1; done; done
  rm -rf $D/wl-* $D/boot.d/wl-* /tmp/wl-* /var/log/wl-* /usr/local/bin/wl-app.sh /var/lib/wl-app
}
trap cleanup EXIT
cleanup
sh_() { echo "\$ $1"; local out rc; out=$(bash -c "$1" 2>&1); rc=$?; [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/  /'; [ "$rc" != 0 ] && echo "  [rc=$rc]"; return 0; }
echo "dinit: $(dinit --version | head -1)"; id -un

echo '### 1. recovery, single and rc.local (read only)'
sh_ 'cat /usr/lib/dinit.d/recovery; echo ---; cat /usr/lib/dinit.d/single'
sh_ 'cat /usr/lib/dinit.d/early/scripts/local.sh 2>&1 | head -20'
sh_ 'ls -l /etc/rc.local 2>&1 | head -1'
sh_ 'cat /usr/lib/dinit.d/networkmanager 2>&1 | head -12'
sh_ 'cat /usr/lib/dinit.d/dmeventd /usr/lib/dinit.d/zram-device 2>&1 | head -14'

echo '### 2. An end-to-end service: unprivileged user, own state directory, log file, network dependency, restart policy'
mkdir -p /var/lib/wl-app && chown nobody /var/lib/wl-app
cat > /usr/local/bin/wl-app.sh <<'EOF'
#!/bin/sh
echo "wl-app starting as $(id -un), state dir: $(ls -d /var/lib/wl-app)"
n=0
while :; do
  n=$((n+1))
  echo "heartbeat $n" > /var/lib/wl-app/last
  echo "heartbeat $n"
  sleep 1
done
EOF
chmod 755 /usr/local/bin/wl-app.sh
cat > $D/wl-app <<'EOF'
# WinLab example application
type = process
command = /usr/local/bin/wl-app.sh
run-as = nobody
working-dir = /var/lib/wl-app
logfile = /var/log/wl-app.log
logfile-uid = nobody
logfile-permissions = 640
restart = on-failure
smooth-recovery = true
restart-delay = 0.5
depends-on: network.target
options: no-new-privs
EOF
sh_ 'dinit-check wl-app 2>&1 | tail -4'
sh_ 'dinitctl start wl-app; dinitctl status wl-app | sed "s/Process ID: [0-9]*/Process ID: <pid>/"; sleep 2.2; cat /var/log/wl-app.log; ls -l /var/log/wl-app.log | cut -c1-34; cat /var/lib/wl-app/last'
sh_ 'dinitctl list | grep -E "wl-app|network.target|pre-network"'
sh_ 'p=$(dinitctl status wl-app | grep "Process ID" | grep -o "[0-9]*\$"); ps -o user,pid,args -p $p | tail -1 | sed "s/ $p / <pid> /"; kill -9 $p; sleep 1.5; dinitctl status wl-app | sed "s/Process ID: [0-9]*/Process ID: <pid>/" | head -4; tail -2 /var/log/wl-app.log'
sh_ 'dinitctl enable wl-app >/dev/null 2>&1; ls -l /etc/dinit.d/boot.d | grep wl-app | sed "s/.* wl-/wl-/"; dinitctl disable wl-app'
sh_ 'dinitctl stop wl-app; echo "--- stopping network.target while wl-app depends on it:"; dinitctl start wl-app >/dev/null; dinitctl stop network.target 2>&1 | head -4'
sh_ 'dinitctl stop wl-app >/dev/null 2>&1; dinitctl status network.target | sed -n "2,3p"'
echo '### done'
