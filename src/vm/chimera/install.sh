#!/bin/sh
# WinLab: install Chimera Linux onto /dev/sda from the live ISO, following the official procedure
# (https://chimera-linux.org/docs/installation/install). Runs as root in the live system, from the seed
# CD mounted at $SEED. Progress lines start with "WL:" so WinLab can follow them over the serial console.
# This is a POSIX sh script run by Chimera's own FreeBSD sh, so it avoids bashisms on purpose.
set -eu

SEED=${1:-/seed}
DISK=/dev/sda
TARGET=/media/root

log() { echo "WL: $*"; }

# shellcheck disable=SC1091
. "$SEED/wl.conf"

log "partitioning $DISK (one bootable MBR partition)"
printf 'label: dos\n,,L,*\n' | sfdisk "$DISK"
log "creating the file system"
mkfs.ext4 -F -q -L root "${DISK}1"
mkdir -p "$TARGET"
mount "${DISK}1" "$TARGET"
chmod 755 "$TARGET"

log "copying the live system (chimera-bootstrap -l)"
chimera-bootstrap -l "$TARGET"

log "configuring the new system in a chroot"
mkdir -p "$TARGET/root"
# Passwords are applied as a SHA-512 crypt hash (chpasswd silently leaves the account locked in this environment).
# The hash contains $ characters, so it goes into the config in single quotes.
HASH=$(openssl passwd -6 "$PASS")
umask 077
cp "$SEED/wl.conf" "$TARGET/root/wl.conf"
printf "HASH='%s'\n" "$HASH" >> "$TARGET/root/wl.conf"
umask 022
cp "$SEED/chroot.sh" "$TARGET/root/wl-chroot.sh"
chimera-chroot "$TARGET" sh /root/wl-chroot.sh
rm -f "$TARGET/root/wl.conf" "$TARGET/root/wl-chroot.sh"

log "writing /etc/fstab"
genfstab -U "$TARGET" >> "$TARGET/etc/fstab"

sync
umount -R "$TARGET"
log "INSTALL-OK"
