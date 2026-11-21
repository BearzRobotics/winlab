#!/bin/sh
# WinLab: configure a freshly bootstrapped Chimera Linux (runs inside chimera-chroot). Reads /root/wl.conf
# (HOST, LABUSER, PUBKEY, HASH). Plain POSIX sh for Chimera's FreeBSD sh.
set -eu

log() { echo "WL: $*"; }

# shellcheck disable=SC1091
. /root/wl.conf

# A fresh package index is nice to have for later `apk add` practice, but the build itself must not depend on
# the network (QEMU's user-mode DNS is occasionally flaky): everything below works from the copied system.
log "refreshing the package index (best effort)"
tries=0
until apk update; do
    tries=$((tries + 1))
    if [ "$tries" -ge 3 ]; then
        log "apk update did not succeed; continuing offline (run 'apk update' in the VM later)"
        break
    fi
    sleep 3
done

# `base-live` is only the live ISO's package set. Anything we want to keep that it pulled in
# (the shell for the lab user, the BIOS bootloader) must be added explicitly BEFORE removing it,
# or apk purges those as orphans (the Chimera docs say the same). Both packages are already installed,
# so this only records them in /etc/apk/world and needs no network.
log "keeping bash and GRUB, then removing base-live"
apk add --no-network bash grub grub-i386-pc
apk del --no-network base-live

log "host name, users, privileges"
echo "$HOST" > /etc/hostname
useradd -m -G wheel -s /usr/bin/bash "$LABUSER"
usermod -p "$HASH" "$LABUSER"
usermod -p "$HASH" root
mkdir -p "/home/$LABUSER/.ssh"
printf '%s\n' "$PUBKEY" > "/home/$LABUSER/.ssh/authorized_keys"
chown -R "$LABUSER:$LABUSER" "/home/$LABUSER/.ssh"
chmod 700 "/home/$LABUSER/.ssh"
chmod 600 "/home/$LABUSER/.ssh/authorized_keys"
# Chimera's default is "permit persist :wheel" (asks for a password). Lab control is non-interactive.
printf 'permit nopass :wheel\npermit nopass root\npermit nopass keepenv setenv { PATH } root as root\n' > /etc/doas.conf

log "SSH: key-only logins, started by dinit at boot"
mkdir -p /etc/ssh
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin no\nPubkeyAuthentication yes\n' > /etc/ssh/sshd_config
ln -sf ../sshd /etc/dinit.d/boot.d/sshd

# The live ISO gets its network from live-only service links. A base install has none: the interface stays
# DOWN until a network service is enabled. dhcpcd is the light choice for a wired lab VM (NetworkManager is
# installed too, and is what the live session used).
log "network: DHCP, started by dinit at boot"
ln -sf ../dhcpcd /etc/dinit.d/boot.d/dhcpcd

log "kernel command line and initramfs"
grep -v '^GRUB_CMDLINE_LINUX_DEFAULT' /etc/default/grub > /tmp/grub.new
echo 'GRUB_CMDLINE_LINUX_DEFAULT="console=tty0 console=ttyS0,115200"' >> /tmp/grub.new
cat /tmp/grub.new > /etc/default/grub
rm -f /tmp/grub.new
update-initramfs -c -k all

log "installing the bootloader"
grub-install /dev/sda
update-grub

log "CHROOT-OK"
