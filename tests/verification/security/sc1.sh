#!/bin/bash
# Security lesson battery 1: logging and detection on Linux (run as root via bash -s)
. /etc/os-release; echo "### $PRETTY_NAME  kernel $(uname -r)  systemd $(systemctl --version | head -1)"
if command -v apt-get >/dev/null; then SSHU=ssh; AUTHLOG=/var/log/auth.log; else SSHU=sshd; AUTHLOG=/var/log/secure; fi
echo "ssh unit: $SSHU   auth log file: $AUTHLOG"

echo "### 1. generate failures: bad user, and a real user without a key"
for u in admin oracle test; do
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 $u@127.0.0.1 true 2>&1 | tail -1
done
useradd -m wl-victim 2>/dev/null
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null wl-victim@127.0.0.1 true 2>&1 | tail -1
sleep 2

echo "### 2. the journal: failed or invalid attempts for the ssh unit"
journalctl -u $SSHU --since "-2min" --no-pager -o short | grep -Ei 'invalid user|failed|authentication|preauth' | sed 's/^[A-Z][a-z][a-z] [0-9 ]*[0-9:]* [^ ]* //' | head -12

echo "### 3. the same events in the text log file"
grep -Ei 'invalid user' $AUTHLOG | tail -3 | sed 's/^[0-9T:.+-]* //;s/^[A-Z][a-z][a-z] [0-9 ]*[0-9:]* //'

echo "### 4. lastb (failed logins, /var/log/btmp) and last"
lastb -n 5 2>&1 | head -8
echo "--"
last -n 4 | head -6

echo "### 5. count failures per name and per source with a small pipeline"
journalctl -u $SSHU --since "-5min" --no-pager -o cat | grep -E 'Invalid user' | awk '{print $3, $5}' | sort | uniq -c | sort -rn | head

echo "### 6. a login that worked leaves 'Accepted' (this script arrived over one)"
journalctl -u $SSHU --since "-30min" --no-pager -o cat | grep -m2 Accepted | sed 's/ssh2.*/ssh2 .../'

echo "### 7. sudo is logged"
sudo -u wl-victim true 2>/dev/null
su -s /bin/bash -c 'sudo -n true' wl-victim 2>&1 | head -2
journalctl _COMM=sudo --since "-2min" --no-pager -o cat | head -4

echo "### 8. auditd"
if ! command -v auditctl >/dev/null; then apt-get install -y auditd >/tmp/apt-audit.log 2>&1; tail -2 /tmp/apt-audit.log; fi
systemctl is-active auditd; auditctl -s | head -3
auditctl -D >/dev/null
auditctl -w /etc/passwd -p wa -k wl-passwd
auditctl -w /etc/sudoers.d -p wa -k wl-sudo
auditctl -l
useradd wl-newuser
echo 'wl-victim ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/wl-evil
sleep 1
echo "--- ausearch -k wl-passwd (first event)"
ausearch -k wl-passwd -i </dev/null | grep -E '^type=(SYSCALL|PATH)' | head -4 | cut -c1-230
echo "--- aureport key summary"
aureport --key --summary -i </dev/null | head -8
echo "--- ausearch sudoers"
ausearch -k wl-sudo -i </dev/null | grep -E 'type=PATH' | head -2 | cut -c1-200
echo "--- rules do not survive a restart unless saved in /etc/audit/rules.d"
ls /etc/audit/rules.d/ /etc/audit/audit.rules 2>&1 | head
auditctl -D >/dev/null
rm -f /etc/sudoers.d/wl-evil; userdel -r wl-newuser 2>/dev/null; userdel -r wl-victim 2>/dev/null
echo done
