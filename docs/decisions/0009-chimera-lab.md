# 0009: Chimera Linux lab VM, installed from the live ISO

Status: accepted (2026-11-21); the labs listed at the end are verified only as marked.

## Context

The owner asked for a Chimera Linux lab: Linux with a ported FreeBSD userland (chimerautils), musl libc, `dinit` as init
and `apk` as package manager. The owner's own distribution (FenrirOS, in development) is heavily influenced by
Chimera, and dinit is a topic they want taught. The existing Linux labs (Ubuntu, AlmaLinux) start from a vendor cloud
image configured by a cloud-init seed CD. **Chimera publishes no cloud image**: for x86_64 it publishes live ISOs
(base, GNOME, Plasma) and root filesystem tarballs (`bootstrap`, `full`). Checked 2026-11-21 at
`https://repo.chimera-linux.org/live/latest/`.

## Decision

1. **Build the VM by installing from the official base live ISO, unattended, following Chimera's own procedure**
   (docs "Installing": partition, `chimera-bootstrap -l` local install, `chimera-chroot`, fstab, initramfs, GRUB).
   `winlab vm install chimera-base <vm-id>` does it (`vmInstallLive` in `main.zig`, `src/vm/chimera.zig`).
2. **Serial console, not screen scraping.** QEMU boots the ISO's own `live/vmlinuz` and `live/initrd` directly
   (extracted with Windows' `tar.exe`, which reads ISO 9660) with the ISO's own command line plus `console=ttyS0,115200`.
   The live system then shows a login prompt on a local-only TCP serial port (`-serial tcp:127.0.0.1:N,server=on,wait=on`;
   `wait=on` holds the guest until WinLab connects, so no output is lost). A small state machine (`chimera.Driver`,
   unit-tested with a simulated transcript) logs in with the live image's documented `root`/`chimera`, runs the install
   script from a seed CD (volume label `WLSEED`, built by `iso9660.zig`) and follows its `WL: ...` progress lines.
   A watchdog thread ends QEMU after 20 minutes, because socket reads have no timeout.
3. **Install scripts are POSIX sh** (`src/vm/chimera/install.sh`, `chroot.sh`), run by Chimera's own FreeBSD `sh`.
4. **The finished VM is an ordinary registered training target**: key-only SSH to `labadmin` on a loopback port,
   `guest.toml` has `distro = "chimera"`, `shell = "bash"`, `cpu = "max"`, snapshot `winlab-clean` after the first boot.
5. **Guest control uses `doas`, not `sudo`** (`guest.escalationFor`). Chimera has no `sudo`; its documented default is
   `doas`, and the install writes `permit nopass :wheel` for non-interactive lab control.
6. **The catalog pins the dated build** (`/live/20261103/`, size and SHA-256; Chimera keeps old dated directories). New
   field `installer = "chimera"` selects the recipe. Chimera's `sha256sums.txt` is checked; its minisign signature was
   not verified.

## What was learned the hard way (each reproduced)

- **`apk del base-live` purges `bash` and `grub`**: they were only dependencies of the live package set. Add what you
  keep (`bash grub grub-i386-pc`) before deleting it (the Chimera docs say the same in one sentence).
- **`chpasswd` returns 0 and leaves the account locked** in this environment (shadow field `!`). Passwords are set as a
  SHA-512 hash with `usermod -p` (hash computed with `openssl passwd -6` in the live system).
- **A base install has no network service enabled** (the live ISO's network comes from live-only links): the NIC stays
  DOWN until `dinitctl enable dhcpcd`. The script enables `dhcpcd` and `sshd` by symlinking into `/etc/dinit.d/boot.d/`.
- **`apk` asks for confirmation and draws progress bars when stdin/stdout are a TTY.** Run in the foreground on the
  serial console the install hung forever at `apk del`; a hand-run background job had hidden this. The driver now runs the
  script with `</dev/null 2>&1 | cat`.
- **QEMU's user-mode DNS is occasionally flaky** (`apk update: DNS: transient error`). The package index refresh is
  best effort; `apk add/del --no-network` do the rest from the copied system, so the build needs no internet.
- `libkmod: ERROR: kmod_file_load_zstd: zstd: Data corruption detected` appears twice during `update-initramfs`; the
  installed system boots and reaches SSH regardless. Not investigated further.
- PowerShell trap in my scratch tooling (not in WinLab): `ssh-keygen -N '""'` sets a literal `""` passphrase.

## Facts about the installed system (build 20261103, kernel 7.3.1, tested)

`/bin/sh` is FreeBSD's sh (no `--version`); `grep` is BSD grep 2.6.0; `awk` is the one-true-awk 20250804; `tar` is bsdtar
3.8.10; `base64` is FreeBSD's (`-d` works); `ls`, `sed`, `find`, `date`, `xargs`, `cp`, `wc` reject GNU-style `--version`;
`bash` 5.3.0 (musl) is installed alongside; init is dinit **0.22.0** (upstream's newest tag is v0.23.0); apk-tools 3.0.8;
520 packages; repositories are defined in `/usr/lib/apk/repositories.d/*.list` using `set -default VAR=value` lines.
`syslog-ng` is shipped but not started, `chrony` runs, `dhcpcd` and `sshd` are enabled by the install.
`dinitctl enable` starts a service; `disable` removes the link; a changed service file is **not** re-read until
`dinitctl reload`/`unload` (start succeeds with only a warning and the old description keeps running).

## Consequences

- No Windows host dependency beyond what other Linux labs already need (QEMU, the Windows OpenSSH client, `tar.exe`).
- The recipe is reusable: another live-ISO distribution (for example FenrirOS, once it has a stable bootable image and
  documented access) needs its own install scripts and serial-login facts, not a new engine.
- Not tested: UEFI boot, the GNOME and Plasma ISOs, a second Chimera release, and building the VM with the network
  completely off (the scripts are written to allow it; the QEMU DNS failure was observed once, not forced).
