# WinLab on Linux

This folder is self-contained: run `./winlab` (the lessons are in the folders beside it). It needs only glibc 2.31 or newer
and a desktop (X11 or Wayland); SDL is built in.

For the hands-on labs install QEMU and the OpenSSH client (WinLab never installs software itself):

    sudo apt install qemu-system-x86 qemu-utils openssh-client curl      # Debian, Ubuntu
    sudo dnf install qemu-system-x86 qemu-img openssh-clients curl       # Fedora, RHEL, Alma
    sudo pacman -S qemu-full openssh curl                                # Arch
    sudo apk add qemu-system-x86_64 qemu-img openssh-client curl         # Alpine

For fast labs your user needs access to KVM: `sudo usermod -aG kvm $USER`, then log out and in again. Without it labs still run,
only slowly. Optional: `pwsh` (PowerShell 7) for the PowerShell lessons, `bsdtar` for the Chimera Linux lab.

Check what WinLab found: `./winlab status`. Settings: `~/.config/WinLab/settings.toml`. Lab VMs: `~/.local/share/WinLab/`.
Verify the download against `SHA256SUMS` from the release page. Licence: GPL-2.0, see `LICENSE`.
