#!/usr/bin/env bash
doas -n rm -f /var/lib/turnstiled/linger/labadmin /tmp/wl-watch-*.sh /tmp/wl-linger-*.log
for s in wl-l7777 wl-l7778 wl-user wl-ubad; do dinitctl --user stop --ignore-unstarted $s >/dev/null 2>&1; dinitctl --user disable $s >/dev/null 2>&1; done
rm -rf ~/.config/dinit.d/wl-* ~/.config/dinit.d/boot.d/wl-*
pkill -f "sleep 777[78]" 2>/dev/null
echo "cleaned: $(ls ~/.config/dinit.d 2>/dev/null | tr '\n' ' ')"
