#!/usr/bin/env bash
# Battery 6a for linux.systemd-advanced: user units and linger on a REAL logind (VM, not WSL).
# Run as the normal admin user (NOT root) over ssh; set LINGER=0 or LINGER=1 in the environment (first line of this file is prepended by the driver).
# A root-owned systemd-run watcher records whether the user manager and the user service survive after this ssh session ends;
# read /tmp/wl-watch.log from a later session with sd6b.sh.
export SYSTEMD_PAGER=cat SYSTEMD_COLORS=0 PAGER=cat
: "${LINGER:=0}"
r() { echo "\$ $*"; local out rc; out=$("$@" 2>&1); rc=$?; [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/  /'; [ "$rc" != 0 ] && echo "  [rc=$rc]"; return 0; }
echo "systemd $(systemctl --version | head -1)"; id -un
echo '### 1. A user manager exists because logging in started one'
r systemctl --user is-system-running
echo "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-unset}"; ls -d /run/user/"$(id -u)"
r loginctl show-user "$USER" -p Linger -p State -p RuntimePath
echo '### 2. A user service'
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/wl-user.service <<'UNIT'
[Unit]
Description=WinLab user service
[Service]
ExecStart=/bin/sleep 3000
[Install]
WantedBy=default.target
UNIT
r systemctl --user daemon-reload
r systemctl --user enable --now wl-user
r systemctl --user is-active wl-user
r systemctl --user status wl-user --no-pager -n0
r systemctl --user list-units --type=service --no-legend
r systemctl --user is-enabled wl-user
echo "### 3. Linger=$LINGER, then leave: a root watcher records what survives the logout"
if [ "$LINGER" = 1 ]; then r sudo -n loginctl enable-linger "$USER"; else sudo -n loginctl disable-linger "$USER"; fi
r loginctl show-user "$USER" -p Linger
ls /var/lib/systemd/linger/ 2>&1 | sed 's/^/  linger-dir: /'
sudo -n systemd-run --unit=wl-watch --collect /bin/bash -c 'for i in $(seq 1 25); do echo "t=$i user-manager=$(systemctl is-active user@1000) rundir=$(ls -d /run/user/1000 2>/dev/null || echo gone) sleep=$(pgrep -u labadmin -f "sleep 3000" | wc -l)"; sleep 1; done > /tmp/wl-watch.log 2>&1' >/dev/null 2>&1
echo "watcher started; this session ends now"
