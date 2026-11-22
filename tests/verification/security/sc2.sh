#!/bin/bash
# Security lesson battery 2: hardening checks (run as root via bash -s). BASELINE is prepended by the driver.
. /etc/os-release; echo "### $PRETTY_NAME"
cat > /usr/local/bin/wl-baseline.sh <<'WLEOF'
@@BASELINE@@
WLEOF
chmod 755 /usr/local/bin/wl-baseline.sh

echo "### 1. baseline on the clean machine"
/usr/local/bin/wl-baseline.sh; echo "exit status $?"

userdel -f -r wl-rootalias 2>/dev/null; userdel -r wl-nopass 2>/dev/null
echo "### 2. plant weaknesses"
mkdir -p /etc/ssh/sshd_config.d
printf 'PermitRootLogin yes\nPasswordAuthentication yes\nMaxAuthTries 10\n' > /etc/ssh/sshd_config.d/00-wl-weak.conf
useradd -m -o -u 0 -g 0 wl-rootalias 2>&1
useradd -m wl-nopass; passwd -d wl-nopass
echo 'wl-nopass ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/wl-weak
touch /usr/local/share/wl-open.conf; chmod 666 /usr/local/share/wl-open.conf
mkdir /srv/wl-shared; chmod 777 /srv/wl-shared
sshd -t && echo "sshd -t ok"
echo "### 3. baseline again"
/usr/local/bin/wl-baseline.sh; echo "exit status $?"
echo "--- why did sshd say that? sshd -T shows the first value read wins:"
sshd -T | grep -iE '^(permitrootlogin|passwordauthentication|maxauthtries) '
ls /etc/ssh/sshd_config.d/

echo "### 4. fix"
rm -f /etc/ssh/sshd_config.d/00-wl-weak.conf /etc/sudoers.d/wl-weak /usr/local/share/wl-open.conf
rmdir /srv/wl-shared
userdel -f -r wl-rootalias 2>&1 | head -2; userdel -r wl-nopass 2>&1 | head -2
grep -c ':0:' /etc/passwd
echo "### 5. baseline after the fix"
/usr/local/bin/wl-baseline.sh; echo "exit status $?"

echo "### 6. a persistent audit rule, loaded without a reboot"
printf -- '-w /etc/passwd -p wa -k wl-passwd\n-w /etc/shadow -p wa -k wl-shadow\n' > /etc/audit/rules.d/wl.rules
augenrules --load 2>&1 | tail -3
auditctl -l
echo "--- same watch on /etc/sudoers.d, then create a file there (does ausearch see it?)"
auditctl -w /etc/sudoers.d -p wa -k wl-sudo
echo 'x ALL=(ALL) ALL' > /etc/sudoers.d/wl-evil
sleep 1
ausearch -k wl-sudo -i </dev/null | grep -E '^type=PATH' | cut -c1-170
rm -f /etc/sudoers.d/wl-evil
rm -f /etc/audit/rules.d/wl.rules; augenrules --load >/dev/null 2>&1; auditctl -l
echo done
