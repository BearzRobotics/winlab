#!/usr/bin/env bash
# Battery 7b: after the boot that follows sd7a.sh. Run as root.
export SYSTEMD_PAGER=cat SYSTEMD_COLORS=0 PAGER=cat
echo "now: $(date -u +%T) UTC; up since $(uptime -s); boot id: $(cat /proc/sys/kernel/random/boot_id)"
echo "### after the boot"
for u in wl-on wl-off wl-masked wl-always wl-persist.timer wl-nopersist.timer; do printf '  %-18s enabled=%-9s active=%s\n' $u "$(systemctl is-enabled $u 2>&1)" "$(systemctl is-active $u 2>&1)"; done
echo "### what the timers did (the file the services append to)"
cat /var/tmp/wl-fired 2>&1 | sed 's/^/  /'
systemctl show wl-persist.timer wl-nopersist.timer -p Id -p LastTriggerUSec -p Persistent | sed 's/^/  /'
journalctl -b -u wl-persist.service -u wl-nopersist.service --no-pager -o short-precise | sed 's/^/  /'
echo "### the lingering user manager: started at boot, before any login?"
systemctl show user@1000.service -p ActiveEnterTimestamp | sed 's/^/  /'
loginctl list-sessions --no-legend | sed 's/^/  session: /'
for s in $(loginctl list-sessions --no-legend | awk '{print $1}'); do loginctl show-session "$s" -p Timestamp | sed "s/^/  session $s /"; done
systemctl --machine=labadmin@.host --user is-active wl-user 2>&1 | sed 's/^/  user wl-user: /'
echo "### cleanup"
systemctl disable --now wl-on wl-persist.timer wl-nopersist.timer >/dev/null 2>&1; systemctl stop wl-off wl-always >/dev/null 2>&1
systemctl unmask wl-masked >/dev/null 2>&1
rm -f /etc/systemd/system/wl-* /etc/systemd/system/*.wants/wl-* /usr/lib/systemd/system/wl-masked.service /var/tmp/wl-fired; systemctl daemon-reload
sudo -u labadmin XDG_RUNTIME_DIR=/run/user/1000 systemctl --user disable --now wl-user >/dev/null 2>&1; rm -f /home/labadmin/.config/systemd/user/wl-user.service
loginctl disable-linger labadmin; systemctl daemon-reload
ls /etc/systemd/system | grep -c wl- 
