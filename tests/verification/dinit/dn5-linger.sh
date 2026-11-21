#!/usr/bin/env bash
# Battery 5c: lingering. Run as labadmin over SSH with the mode as the first argument line: "nolinger" or "linger".
# Usage: the harness prepends MODE=<mode> to this script. A root watcher started here keeps logging AFTER the session ends.
MODE=${MODE:-nolinger}
N=7777; [ "$MODE" = linger ] && N=7778
doas -n rm -f /tmp/wl-linger-$MODE.log
doas -n sh -c 'rm -f /var/lib/turnstiled/linger/labadmin'
[ "$MODE" = linger ] && doas -n sh -c 'touch /var/lib/turnstiled/linger/labadmin' && echo "linger file created: $(ls /var/lib/turnstiled/linger)"
cat > ~/.config/dinit.d/wl-l$N <<EOS
type = process
command = /bin/sleep $N
EOS
dinitctl --user stop --ignore-unstarted wl-user wl-ubad >/dev/null 2>&1
dinitctl --user start wl-l$N
echo "service pid: $(dinitctl --user status wl-l$N | grep 'Process ID' | grep -o '[0-9]*$' | sed 's/.*/<pid>/')"
cat > /tmp/wl-watch-$MODE.sh <<EOS
#!/bin/sh
log() { echo "after logout +\$1 s: sleep $N procs=\$(pgrep -f '[s]leep $N' | wc -l | tr -d ' ')  user dinit=\$(pgrep -u labadmin -x dinit | wc -l | tr -d ' ')  open sessions=\$(loginctl list-sessions --no-legend 2>/dev/null | grep -vc closing)  run dir=\$(ls /run/user 2>/dev/null | tr '\n' ' ')" >> /tmp/wl-linger-$MODE.log; }
sleep 3; log 3
sleep 5; log 8
sleep 10; log 18
EOS
chmod +x /tmp/wl-watch-$MODE.sh
doas -n sh -c "setsid /tmp/wl-watch-$MODE.sh </dev/null >/dev/null 2>&1 &"
echo "watcher started; logging out now"
