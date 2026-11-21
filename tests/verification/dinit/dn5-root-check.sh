#!/usr/bin/env bash
# Battery 5b: run as root AFTER the labadmin session has ended; checks what survived the logout.
echo "== after logout: sleep 7777 running? $(pgrep -f 'sleep 7777' | wc -l | tr -d ' ') process(es)"
echo "== labadmin's user dinit running? $(pgrep -u labadmin -x dinit | wc -l | tr -d ' ')"
echo "== /run/user: $(ls /run/user 2>&1 | tr '\n' ' ')"
echo "== linger dir: $(ls -l /var/lib/turnstiled/linger 2>&1 | tail -2 | tr '\n' ';')"
echo "== turnstiled log (last lines):"; tail -6 /var/log/turnstiled.log 2>&1 | cut -c1-140
echo "== PAM: pam_turnstile configured for sshd/system-login?"; grep -rl turnstile /etc/pam.d 2>&1 | tr '\n' ' '; echo
