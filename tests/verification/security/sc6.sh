#!/bin/bash
# Security lesson battery 6: failed-login report, password failures, journal queries (run as root via bash -s). REPORT is substituted by the driver.
. /etc/os-release; echo "### $PRETTY_NAME"
cat > /usr/local/bin/wl-authreport.sh <<'WLEOF'
@@REPORT@@
WLEOF
chmod 755 /usr/local/bin/wl-authreport.sh
SSHO="-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"
echo "### 1. attempts from two source addresses (loopback aliases 127.0.0.2 and 127.0.0.3)"
for u in root admin test oracle ubuntu guest; do ssh $SSHO -b 127.0.0.2 $u@127.0.0.1 true 2>/dev/null; done
for u in admin pi; do ssh $SSHO -b 127.0.0.3 $u@127.0.0.1 true 2>/dev/null; done
sleep 1
/usr/local/bin/wl-authreport.sh 5 5; echo "exit status $?"
/usr/local/bin/wl-authreport.sh 5 50; echo "exit status $?"

echo "### 2. real 'Failed password' lines: allow passwords for a moment, wrong password via SSH_ASKPASS"
mkdir -p /etc/ssh/sshd_config.d
printf 'PasswordAuthentication yes\n' > /etc/ssh/sshd_config.d/00-wl-pw.conf
sshd -t && systemctl reload $(systemctl cat sshd.service >/dev/null 2>&1 && echo sshd || echo ssh)
useradd -m wl-victim; echo 'wl-victim:right-password' | chpasswd
printf '#!/bin/sh\necho wrong-password\n' > /tmp/wl-askpass.sh; chmod 755 /tmp/wl-askpass.sh
for i in 1 2 3; do SSH_ASKPASS=/tmp/wl-askpass.sh SSH_ASKPASS_REQUIRE=force setsid ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 -b 127.0.0.4 wl-victim@127.0.0.1 true 2>&1 | tail -1; done
SSH_ASKPASS=/tmp/wl-askpass.sh SSH_ASKPASS_REQUIRE=force setsid ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 -b 127.0.0.4 nosuchuser@127.0.0.1 true 2>&1 | tail -1
sleep 1
journalctl -u $(systemctl cat sshd.service >/dev/null 2>&1 && echo sshd || echo ssh) --since "-1min" --no-pager -o cat | grep -E 'Failed password|Invalid user' | sed 's/port [0-9]* ssh2/port N ssh2/;s/port [0-9]*$/port N/'
/usr/local/bin/wl-authreport.sh 5 3; echo "exit status $?"
echo "--- lastb now lists the password failures too"
lastb -n 6 | head -7 | awk '{print $1, $2, $3}'
rm -f /etc/ssh/sshd_config.d/00-wl-pw.conf /tmp/wl-askpass.sh; systemctl reload $(systemctl cat sshd.service >/dev/null 2>&1 && echo sshd || echo ssh)

echo "### 3. journal queries worth knowing"
echo "--- by priority and time"
journalctl -p warning --since "-10min" --no-pager -o short | wc -l
echo "--- structured: the unit and the executable of an entry"
journalctl -u $(systemctl cat sshd.service >/dev/null 2>&1 && echo sshd || echo ssh) -n 1 --no-pager -o json | tr ',' '\n' | grep -E '"(_SYSTEMD_UNIT|_COMM|_EXE|SYSLOG_IDENTIFIER|_UID)"'
echo "--- field values: which programs have written to the journal?"
journalctl -F _COMM --since "-30min" 2>/dev/null | sort | head -12 | tr '\n' ' '; echo
echo "--- is the journal kept after a reboot? (Storage, and /var/log/journal)"
journalctl --disk-usage; ls -d /var/log/journal 2>&1; grep -E '^#?Storage' /etc/systemd/journald.conf
userdel -r wl-victim 2>/dev/null; echo done
