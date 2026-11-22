#!/usr/bin/env bash
# Battery 7a for linux.systemd / linux.systemd-advanced: what a REAL shutdown and boot does to enabled, disabled, masked units,
# Restart=always, Persistent= timers and a lingering user service. Run as root in a VM (not WSL). It ends with a poweroff;
# the driver waits past the timer time, boots the VM again and runs sd7b.sh.
export SYSTEMD_PAGER=cat SYSTEMD_COLORS=0 PAGER=cat
U=/etc/systemd/system
mk() { printf '[Unit]\nDescription=WinLab %s\n[Service]\nExecStart=/bin/sleep 5000\n%s\n[Install]\nWantedBy=multi-user.target\n' "$1" "$2" > $U/$1.service; }
mk wl-on ""; mk wl-off ""; mk wl-always "Restart=always"
# a masked unit must be a VENDOR unit: masking a file that lives in /etc fails ("already exists")
cat > /usr/lib/systemd/system/wl-masked.service <<'UNIT'
[Unit]
Description=WinLab vendor
[Service]
ExecStart=/bin/sleep 5000
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now wl-on 2>&1 | sed 's/^/  /'
systemctl start wl-off wl-always            # running now, but NOT enabled
systemctl daemon-reload; systemctl enable wl-masked >/dev/null 2>&1; systemctl mask wl-masked 2>&1 | sed 's/^/  /'
T=$(date -u -d '+3 min' '+%H:%M:00')
for p in persist:true nopersist:false; do n=${p%%:*}; v=${p##*:}
  printf '[Unit]\nDescription=WinLab timer %s\n[Service]\nType=oneshot\nExecStart=/bin/sh -c "echo fired-%s $(date -u +%%%%T) >> /var/tmp/wl-fired"\n' "$n" "$n" > $U/wl-$n.service
  printf '[Timer]\nOnCalendar=*-*-* %s UTC\nPersistent=%s\n[Install]\nWantedBy=timers.target\n' "$T" "$v" > $U/wl-$n.timer
done
rm -f /var/tmp/wl-fired
systemctl daemon-reload; systemctl enable --now wl-persist.timer wl-nopersist.timer 2>&1 | sed 's/^/  /'
echo "timer time: $T UTC; now: $(date -u +%T)"
echo "### before the shutdown"
for u in wl-on wl-off wl-masked wl-always wl-persist.timer wl-nopersist.timer; do printf '  %-18s enabled=%-9s active=%s\n' $u "$(systemctl is-enabled $u 2>&1)" "$(systemctl is-active $u 2>&1)"; done
systemctl show wl-persist.timer -p NextElapseUSecRealtime -p LastTriggerUSec | sed 's/^/  /'
sudo -u labadmin true 2>/dev/null; loginctl show-user labadmin -p Linger | sed 's/^/  /'
echo "boot id: $(cat /proc/sys/kernel/random/boot_id)"
echo "powering off now"; (sleep 2; systemctl poweroff) >/dev/null 2>&1 &
