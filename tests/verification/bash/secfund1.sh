# Battery for security.security-fundamentals. THROWAWAY VM ONLY, as root: makes two temporary users and
# files, tests permissions, account locking against an SSH key, and SELinux labels, then removes them.
export LC_ALL=C
say() { printf '\n=== %s\n' "$*"; }
run() { printf '$ %s\n' "$*"; eval "$*" 2>&1 </dev/null; printf '[exit %s]\n' "$?"; }
. /etc/os-release; echo "$PRETTY_NAME"
useradd -m wlalice; useradd -m wlbob
as() { runuser -u "$1" -- sh -c "$2"; }
d=/srv/wlsec; mkdir -p $d; chmod 755 $d

say 'who am I'
run 'id wlalice'

say 'the owner class is the one that counts'
echo secret > $d/o.txt; chown wlalice:wlalice $d/o.txt; chmod 044 $d/o.txt
run "ls -l $d/o.txt"
run "as wlalice 'cat $d/o.txt'"
run "as wlbob 'cat $d/o.txt'"

say 'directories: r and x are different'
mkdir -p $d/dir; echo inside > $d/dir/known.txt; chmod 644 $d/dir/known.txt
chmod 744 $d/dir
run "ls -ld $d/dir"
run "as wlbob 'ls $d/dir'"
run "as wlbob 'cat $d/dir/known.txt'"
chmod 711 $d/dir
run "ls -ld $d/dir"
run "as wlbob 'ls $d/dir'"
run "as wlbob 'cat $d/dir/known.txt'"

say 'deleting depends on the directory'
mkdir -p $d/share; chmod 777 $d/share; echo keep > $d/share/roots.txt; chmod 400 $d/share/roots.txt
run "ls -l $d/share/roots.txt"
run "as wlbob 'rm -f $d/share/roots.txt; echo removed-status:\$?'"
run "ls $d/share"
echo keep > $d/share/roots.txt; chmod 1777 $d/share
run "ls -ld $d/share /tmp"
run "as wlbob 'rm -f $d/share/roots.txt'"

say 'locking a password versus an SSH key'
mkdir -p /root/wlkey; ssh-keygen -q -t ed25519 -N '' -f /root/wlkey/id
install -d -m 700 -o wlalice -g wlalice /home/wlalice/.ssh
install -m 600 -o wlalice -g wlalice /root/wlkey/id.pub /home/wlalice/.ssh/authorized_keys
restorecon -R /home/wlalice/.ssh
S='ssh -n -i /root/wlkey/id -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR wlalice@127.0.0.1 whoami'
echo 'wlalice:Wl-battery-9f3k2!x' | chpasswd
run 'passwd -S wlalice'
run "$S"
run 'passwd -l wlalice'
run 'passwd -S wlalice'
run "$S"
run 'usermod --expiredate 1 wlalice'
run 'chage -l wlalice | head -4'
run "$S"
run 'journalctl -u sshd --no-pager -n 4 -o cat'
run 'usermod --expiredate "" wlalice'
run "$S"

say 'listening ports'
run 'ss -tlnp | cut -c1-150'
run 'firewall-cmd --list-all'

say 'SELinux labels follow the way a file arrives'
run 'getenforce'
mkdir -p /var/www/html
echo a > /tmp/wl-moved.html; echo b > /tmp/wl-copied.html
mv /tmp/wl-moved.html /var/www/html/; cp /tmp/wl-copied.html /var/www/html/
run 'ls -Z /var/www/html/'
run 'matchpathcon /var/www/html/wl-moved.html'
run 'restorecon -nv /var/www/html/wl-moved.html'
run 'restorecon -v /var/www/html/wl-moved.html'
run 'ls -Z /var/www/html/'
run 'chcon -t user_tmp_t /var/www/html/wl-copied.html && ls -Z /var/www/html/wl-copied.html && restorecon -v /var/www/html/wl-copied.html'
run 'command -v semanage ausearch'

rm -f /var/www/html/wl-moved.html /var/www/html/wl-copied.html /tmp/wl-copied.html
userdel -r wlalice 2>/dev/null; userdel -r wlbob 2>/dev/null; rm -rf $d /root/wlkey
say done
