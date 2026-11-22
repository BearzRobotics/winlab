#!/bin/bash
# Security lesson battery 8: does locking an account stop an SSH key login? (run as root via bash -s)
. /etc/os-release; echo "### $PRETTY_NAME"
W=/var/tmp/wl-lock; rm -rf $W; mkdir -p $W; userdel -r wl-svc 2>/dev/null
ssh-keygen -q -t ed25519 -N '' -f $W/key
useradd -m -s /bin/bash wl-svc
install -d -m 700 -o wl-svc -g wl-svc /home/wl-svc/.ssh
cp $W/key.pub /home/wl-svc/.ssh/authorized_keys; chown wl-svc:wl-svc /home/wl-svc/.ssh/authorized_keys; chmod 600 /home/wl-svc/.ssh/authorized_keys
SSHO="-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -o ConnectTimeout=5 -i $W/key"
try() { printf "%-42s -> " "$1"; ssh -n $SSHO wl-svc@127.0.0.1 'echo logged-in as $(id -un)' 2>&1 | tail -1; }
echo "UsePAM: $(sshd -T | awk '/^usepam/ {print $2}')"
try "1. before anything"
passwd -S wl-svc | awk '{print "   passwd -S:", $2}'
usermod -L wl-svc
passwd -S wl-svc | awk '{print "   after usermod -L, passwd -S:", $2}'
try "2. password locked (usermod -L)"
journalctl -u $(systemctl cat sshd.service >/dev/null 2>&1 && echo sshd || echo ssh) --since "-20sec" --no-pager -o cat | grep -E 'wl-svc' | tail -2 | sed 's/port [0-9]*/port N/' | cut -c1-140
usermod -s /usr/sbin/nologin wl-svc
try "3. + shell set to nologin"
usermod -s /bin/bash wl-svc
usermod -e 1 wl-svc
chage -l wl-svc | grep -i 'Account expires'
try "4. account expired (usermod -e 1), shell bash"
journalctl -u $(systemctl cat sshd.service >/dev/null 2>&1 && echo sshd || echo ssh) --since "-20sec" --no-pager -o cat | grep -E 'wl-svc' | tail -2 | sed 's/port [0-9]*/port N/' | cut -c1-140
usermod -e '' wl-svc
usermod -U wl-svc
mv /home/wl-svc/.ssh/authorized_keys $W/authorized_keys.evidence
try "5. authorized_keys moved away (evidence kept)"
userdel -r wl-svc 2>/dev/null; rm -rf $W; echo done
