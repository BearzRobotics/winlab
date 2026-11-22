#!/bin/bash
# Home-lab battery 2b: Samba and SELinux on AlmaLinux (run as root via bash -s)
. /etc/os-release; echo "### $PRETTY_NAME  SELinux $(getenforce)"
groupadd -f wl-labfiles
useradd -m -s /usr/sbin/nologin -G wl-labfiles wl-alice 2>&1 | head -1
printf 'Lab-pass-1\nLab-pass-1\n' | smbpasswd -a -s wl-alice
mkdir -p /srv/wl-share; chown root:wl-labfiles /srv/wl-share; chmod 2770 /srv/wl-share
echo "hello from the server" > /srv/wl-share/readme.txt; chown root:wl-labfiles /srv/wl-share/readme.txt; chmod 660 /srv/wl-share/readme.txt
cp /etc/samba/smb.conf /etc/samba/smb.conf.orig
cat >> /etc/samba/smb.conf <<'EOF'

[labfiles]
   path = /srv/wl-share
   valid users = @wl-labfiles
   read only = no
   create mask = 0660
   directory mask = 2770
   force group = wl-labfiles
EOF
systemctl enable --now smb 2>&1 | tail -1; sleep 2

echo "### 1. the failure, with correct Unix permissions"
echo "from alice" > /tmp/wl-up.txt
smbclient //127.0.0.1/labfiles -U wl-alice%Lab-pass-1 -c 'ls; put /tmp/wl-up.txt up.txt' 2>&1 | grep -vE '^$|blocks of size'
echo "--- the label on the directory and file"
ls -dZ /srv/wl-share /srv/wl-share/readme.txt
echo "--- the denials"
ausearch -m avc -c smbd -ts recent -i </dev/null | grep -E '^type=AVC' | sed 's/.*denied/denied/' | cut -c1-200 | sort | uniq -c | head -5
echo "--- which label may Samba use?"
semanage fcontext -l | grep -E 'samba_share_t' | head -3
echo "--- Samba booleans"
getsebool -a | grep -E 'samba_(export_all|enable_home)'

echo "### 2. fix the label (not the mode, and not setenforce 0)"
semanage fcontext -a -t samba_share_t '/srv/wl-share(/.*)?'
restorecon -Rv /srv/wl-share
ls -dZ /srv/wl-share /srv/wl-share/readme.txt
semanage fcontext -l -C
smbclient //127.0.0.1/labfiles -U wl-alice%Lab-pass-1 -c 'ls; put /tmp/wl-up.txt up.txt; ls' 2>&1 | grep -vE '^$|blocks of size'
ls -lZ /srv/wl-share

echo "### 3. firewall"
systemctl is-active firewalld
firewall-cmd --get-active-zones 2>&1 | head -3
firewall-cmd --list-services 2>&1
firewall-cmd --info-service=samba 2>&1 | head -6
firewall-cmd --permanent --add-service=samba 2>&1; firewall-cmd --reload 2>&1
firewall-cmd --list-services
firewall-cmd --permanent --remove-service=samba >/dev/null; firewall-cmd --reload >/dev/null; firewall-cmd --list-services

echo "### 4. cleanup"
systemctl disable --now smb 2>&1 | tail -1
cp /etc/samba/smb.conf.orig /etc/samba/smb.conf
smbpasswd -x wl-alice >/dev/null; userdel -r wl-alice 2>/dev/null; groupdel wl-labfiles
semanage fcontext -d '/srv/wl-share(/.*)?'; rm -rf /srv/wl-share /tmp/wl-up.txt
echo done
