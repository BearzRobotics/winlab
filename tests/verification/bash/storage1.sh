# Battery for linux.storage-filesystems. RUN ONLY IN A THROWAWAY VM as root: it makes loop devices and
# file systems and edits a copy of fstab. Started from the alma-lvm-extend lab (a full LVM volume).
export LC_ALL=C
say() { printf '\n=== %s\n' "$*"; }
run() { printf '$ %s\n' "$*"; eval "$*" 2>&1; printf '[exit %s]\n' "$?"; }
. /etc/os-release; echo "$PRETTY_NAME   kernel $(uname -r)"

say 'what is attached'
run 'lsblk'
run 'lsblk -f'
run 'df -hT -x tmpfs -x devtmpfs'
run 'findmnt --real'
run 'grep -v "^#" /etc/fstab'

say 'the LVM lab: full volume'
run 'df -h /srv/lvdata'
run 'ls -la /srv/lvdata'
run 'echo more > /srv/lvdata/more.txt; dd if=/dev/zero of=/srv/lvdata/x bs=1M count=5'
run 'rm -f /srv/lvdata/x /srv/lvdata/more.txt'
run 'findmnt /srv/lvdata'
run 'pvs'
run 'vgs'
run 'lvs'
run 'lvextend -r -L 80M /dev/labvg/data'
run 'lvs labvg/data'
run 'df -h /srv/lvdata'
run 'lvextend -r -L +500M /dev/labvg/data'
run 'du -sh /srv/lvdata'

mkdir -p /root/wl /mnt/wl
cd /root/wl || exit 1
say 'a disk made from a file'
run 'truncate -s 100M disk.img'
run 'losetup -f --show /root/wl/disk.img'
dev=$(losetup -j /root/wl/disk.img | cut -d: -f1)
run "blkid $dev"
run "mkfs.ext4 -L wldata $dev"
run "blkid $dev"
run "lsblk -f $dev"

say 'files hidden under a mount point'
run 'echo "written while NOT mounted" > /mnt/wl/under.txt'
run 'findmnt /mnt/wl'
run 'df -h /mnt/wl'
run "mount $dev /mnt/wl"
run 'findmnt /mnt/wl'
run 'df -h /mnt/wl'
run 'ls /mnt/wl'
run 'umount /mnt/wl'
run 'ls /mnt/wl'
run 'rm /mnt/wl/under.txt'
run "mount $dev /mnt/wl"

say 'target is busy'
( cd /mnt/wl && exec sleep 60 ) &
sleeper=$!
sleep 1
run 'umount /mnt/wl'
run 'command -v fuser lsof'
command -v fuser >/dev/null && run 'fuser -vm /mnt/wl'
command -v lsof >/dev/null && run 'lsof +f -- /mnt/wl'
run 'ls -l /proc/[0-9]*/cwd 2>/dev/null | grep "/mnt/wl"'
kill $sleeper; wait $sleeper 2>/dev/null

say 'a deleted file that is still open'
run 'dd if=/dev/zero of=/mnt/wl/big.log bs=1M count=50 status=none'
tail -f /mnt/wl/big.log > /dev/null &
holder=$!
sleep 1
run 'df -h /mnt/wl'
run 'rm /mnt/wl/big.log'
run 'df -h /mnt/wl'
run 'du -sh /mnt/wl'
run 'ls -l /proc/'$holder'/fd | grep deleted'
command -v lsof >/dev/null && run 'lsof +L1 /mnt/wl'
kill $holder; wait $holder 2>/dev/null
sync
run 'df -h /mnt/wl'
run 'umount /mnt/wl'

say 'out of inodes'
run "mkfs.ext4 -q -F -N 128 $dev"
run "mount $dev /mnt/wl"
run 'df -i /mnt/wl'
run 'for i in $(seq 1 200); do touch /mnt/wl/f$i 2>/root/wl/err || { echo "failed at file $i"; cat /root/wl/err; break; }; done'
run 'df -h /mnt/wl'
run 'df -i /mnt/wl'
run 'umount /mnt/wl'

say 'mkfs on a device that already has a file system, with nothing to answer a question'
run "mkfs.ext4 -L first $dev </dev/null"
run "mkfs.ext4 -L second $dev </dev/null"
run "blkid $dev"
command -v mkfs.xfs >/dev/null && run "truncate -s 400M x.img && mkfs.xfs -q x.img && mkfs.xfs x.img"
run "wipefs $dev"

say 'fstab: verify and mount -a'
uuid=$(blkid -s UUID -o value "$dev")
cp /etc/fstab /root/wl/fstab.orig
run 'findmnt --verify'
echo "UUID=$uuid /mnt/wl ext4 defaults 0 2" >> /etc/fstab
run 'tail -1 /etc/fstab'
run 'findmnt --verify'
run 'mount -a'
run 'findmnt /mnt/wl'
run 'systemctl daemon-reload'
run 'findmnt --verify'
run 'systemctl list-units --type=mount --no-pager --plain | grep mnt-wl'
run 'umount /mnt/wl'
say 'typo in the type'
cp /root/wl/fstab.orig /etc/fstab; echo "UUID=$uuid /mnt/wl etx4 defaults 0 2" >> /etc/fstab
run 'findmnt --verify'
run 'mount -a'
say 'wrong UUID'
cp /root/wl/fstab.orig /etc/fstab; echo "UUID=00000000-0000-0000-0000-000000000000 /mnt/wl ext4 defaults 0 2" >> /etc/fstab
run 'findmnt --verify'
run 'mount -a'
say 'wrong UUID with nofail'
cp /root/wl/fstab.orig /etc/fstab; echo "UUID=00000000-0000-0000-0000-000000000000 /mnt/wl ext4 nofail 0 2" >> /etc/fstab
run 'mount -a'
run 'findmnt /mnt/wl'

cp /root/wl/fstab.orig /etc/fstab
systemctl daemon-reload
losetup -d "$dev"
rm -rf /root/wl /mnt/wl
say 'done; fstab restored'
