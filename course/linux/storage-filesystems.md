*Draft for owner review.* A server's data lives on block devices that carry file systems. This lesson covers how to see what is attached, how a file system gets mounted, and how a mount survives a restart. Use only tools that ship with the system.

You will practise on a Linux lab VM. The lab for this lesson breaks one of these things for you to repair.

## Seeing the storage

```
lsblk                 # disks and partitions as a tree
lsblk -f              # add file system type, label and UUID
blkid                 # type and UUID of each block device
df -hT                # mounted file systems, size, used, free, type
findmnt               # everything mounted, as a tree
findmnt /srv/data     # is this one mounted, and from what?
```

A **block device** is anything the kernel treats as a disk: a real disk (`/dev/sda`), a partition (`/dev/sda1`), a logical volume, or a file attached through a loop device (`/dev/loop0`). A **file system** (ext4, xfs) is the structure written onto it. A **mount point** is the folder where that structure appears.

## Mounting by hand

```
sudo mount /dev/sdb1 /srv/data     # attach a file system at a folder
sudo umount /srv/data              # detach it (fails if something is using it)
```

A mount made this way is gone after a restart. If `umount` says "target is busy", `findmnt` and `lsof +D /srv/data` (or `fuser -vm /srv/data`) show who is using it.

## Making a mount persistent: /etc/fstab

Each line of `/etc/fstab` has six fields:

```
UUID=3f1c...  /srv/data  xfs  defaults  0  0
device        mountpoint type options  dump fsck-order
```

Prefer a UUID or label over `/dev/sdb1`, because device names can change between boots. Then:

```
sudo mount -a          # mount everything in fstab not yet mounted
sudo systemctl daemon-reload
```

`mount -a` is also your test. A broken line found now is an error message; found at boot it can drop the machine into emergency mode. Add `nofail` to non-essential volumes so a missing disk does not stop the boot.

## Creating a file system

```
sudo mkfs.xfs /dev/sdb1       # or mkfs.ext4
```

This **destroys** whatever was on the device. Check the device name twice with `lsblk` first. Never practise it on anything but the lab VM.

## The problem pattern

"The files are on the wrong disk" is a classic: the mount did not happen, so writes went to the folder on the root file system underneath. Evidence: `findmnt` shows nothing at the mount point, `df` shows the root volume filling. The fix is to mount it and make the fstab entry correct; the files written in the meantime need a deliberate decision, not a guess.

## Check yourself

1. What does the sixth field of an fstab line control?
2. Why is `UUID=` safer than `/dev/sdb1`?
3. A volume is mounted, but missing after a restart. Where do you look first?
