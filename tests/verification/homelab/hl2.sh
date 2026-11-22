#!/bin/bash
# Home-lab battery 2: a Samba file share, tested against itself over loopback (run as root via bash -s)
. /etc/os-release; echo "### $PRETTY_NAME"
if command -v apt-get >/dev/null; then
  apt-get update >/tmp/upd.log 2>&1
  DEBIAN_FRONTEND=noninteractive apt-get install -y samba smbclient cifs-utils >/tmp/inst.log 2>&1; tail -1 /tmp/inst.log; SVC=smbd
else
  dnf -y install samba samba-client cifs-utils policycoreutils-python-utils >/tmp/inst.log 2>&1; tail -1 /tmp/inst.log; SVC=smb
fi
smbd --version; echo "service unit: $SVC"; systemctl is-enabled $SVC; systemctl is-active $SVC

echo "### 1. user, group, directory, config"
groupadd -f wl-labfiles
useradd -m -s /usr/sbin/nologin -G wl-labfiles wl-alice 2>&1 | head -1
useradd -m -s /usr/sbin/nologin wl-bob 2>&1 | head -1
printf 'Lab-pass-1\nLab-pass-1\n' | smbpasswd -a -s wl-alice
printf 'Lab-pass-2\nLab-pass-2\n' | smbpasswd -a -s wl-bob
pdbedit -L
mkdir -p /srv/wl-share
chown root:wl-labfiles /srv/wl-share; chmod 2770 /srv/wl-share
echo "hello from the server" > /srv/wl-share/readme.txt; chown root:wl-labfiles /srv/wl-share/readme.txt; chmod 660 /srv/wl-share/readme.txt
cp /etc/samba/smb.conf /etc/samba/smb.conf.orig
cat >> /etc/samba/smb.conf <<'EOF'

[labfiles]
   comment = WinLab test share
   path = /srv/wl-share
   valid users = @wl-labfiles
   read only = no
   create mask = 0660
   directory mask = 2770
   force group = wl-labfiles
EOF
echo "--- testparm (checks syntax, prints what Samba understood)"
testparm -s 2>&1 | grep -vE '^$' | sed -n '1,4p;/\[labfiles\]/,$p'
systemctl restart $SVC; sleep 2; systemctl is-active $SVC
ss -tlnp | grep -E ':(139|445) ' | sed 's/  */ /g'

echo "### 2. list shares, then use the share"
smbclient -L 127.0.0.1 -U wl-alice%Lab-pass-1 2>&1 | head -8
echo "--- ls and put"
echo "from alice" > /tmp/wl-up.txt
smbclient //127.0.0.1/labfiles -U wl-alice%Lab-pass-1 -c 'ls; put /tmp/wl-up.txt up.txt; ls' 2>&1 | grep -vE 'blocks of size|^$'
echo "--- the file on disk"
ls -l /srv/wl-share/ ; ls -Z /srv/wl-share/up.txt 2>/dev/null | awk '{print $1}'
echo "--- wrong password, and a user who is not in the group"
smbclient //127.0.0.1/labfiles -U wl-alice%wrong -c ls 2>&1 | head -2
smbclient //127.0.0.1/labfiles -U wl-bob%Lab-pass-2 -c ls 2>&1 | head -2
echo "--- no password at all (guest)"
smbclient //127.0.0.1/labfiles -N -c ls 2>&1 | head -2
echo "--- protocol in use, and an old one refused"
smbstatus -b 2>&1 | head -1
smbclient //127.0.0.1/labfiles -U wl-alice%Lab-pass-1 -m NT1 -c ls 2>&1 | head -2
echo "--- mount it like a client would"
mkdir -p /mnt/wl-mnt
mount -t cifs //127.0.0.1/labfiles /mnt/wl-mnt -o username=wl-alice,password=Lab-pass-1 2>&1
mount | grep wl-mnt | sed 's/password=[^,]*/password=.../' | cut -c1-150
ls /mnt/wl-mnt; cat /mnt/wl-mnt/readme.txt
smbstatus -b 2>&1 | sed -n '1,8p'
umount /mnt/wl-mnt

echo "### 3. cleanup of the test objects"
cp /etc/samba/smb.conf.orig /etc/samba/smb.conf; systemctl restart $SVC
smbpasswd -x wl-alice >/dev/null; smbpasswd -x wl-bob >/dev/null
userdel -r wl-alice 2>/dev/null; userdel -r wl-bob 2>/dev/null; groupdel wl-labfiles
rm -rf /srv/wl-share /mnt/wl-mnt /tmp/wl-up.txt
echo done
