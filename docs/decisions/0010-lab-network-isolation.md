# 0010: Isolating a lab VM for security labs

Status: accepted for the network part; see "Verified" for what has been tested.

## Context

Capture-the-flag and incident labs will put deliberately vulnerable or malware-like things in a lab VM. Lab VMs use QEMU user-mode networking (`-netdev user`). Measured on 2026-11-26 from an Ubuntu lab VM started the normal way (`tests/verification/containment/`), the guest could reach:

- services listening only on the host's loopback (`127.0.0.1` and `::1`, TCP and UDP) through `10.0.2.2` and `fec0::2`, confirmed on the host side;
- the host's file sharing port (SMB, 445), through `10.0.2.2` and through the host's LAN address;
- DNS and the internet (TCP and ping).

That is acceptable for the administration labs, which run only WinLab's own scripts, and not for anything hostile.

A second path runs the other way: WinLab connects INTO the guest with the host's `ssh`. Settings in the learner's `~/.ssh/config` applied to that connection, so a `Host *` entry with agent forwarding would have lent the learner's keys to the guest. Guest output was also printed as-is, including terminal control sequences.

## Decision

1. A lab declares `network = "isolated"`. The default stays `"open"`; any other value is an error.
2. An isolated VM boots with QEMU's `restrict=on`. The only way in is the existing SSH forward bound to `127.0.0.1`.
3. Isolation belongs to the disk state, not to one command (`src/vm/isolation.zig`). A per-VM record marks the current state and the snapshots taken from it. It is written before the VM boots, it is lifted only after an unmarked snapshot has been restored, and a damaged record means isolated. Every WinLab path that boots a VM from its disk reads it.
4. The SSH connection ignores all SSH config files (`-F none`) and turns off the agent and all forwarding, for every lab.
5. Control bytes in guest output are replaced before WinLab shows it.

## Not covered

- **A bug in QEMU or in the hypervisor** that lets a guest escape. Isolation limits the network; it does not make running real malware safe. WinLab ships and downloads no malware samples, and nothing here is a reason to start.
- **The VM window.** Anything the learner types or copies by hand is outside this.
- **QEMU started outside WinLab.** The record only affects WinLab.
- **Deleting the record** (or copying the disk without it) removes the mark.
- **An isolated guest still attacks what is inside it,** including its own snapshots' contents; rollback is by restoring a clean snapshot.
- Isolated labs cannot download anything, so their setup must use only what the image already has.
- Machine-to-machine labs (an attacker VM and a target VM) need a private link between two guests. That is decision 0008's open question and is not designed here.

## Verified

2026-11-26, QEMU 11.1.0 with WHPX on Windows 11 Home, guest Ubuntu 24.04 (`winlab-linux`), host OpenSSH 9.5p2. Probe: `tests/verification/containment/`. "Open" is the same probe on the same VM through a normal lab.

| What the guest tried | Open | Isolated |
|---|---|---|
| TCP to a host `127.0.0.1` listener (confirmed on the host) | reached | blocked |
| TCP to a host `::1` listener (confirmed on the host) | reached | blocked |
| UDP to a host `127.0.0.1` socket (judged on the host) | arrived | did not arrive |
| Host SMB through `10.0.2.2` and through the host's LAN address | reached | blocked |
| TCP to the internet by name and by address, ping to the internet | reached | blocked |
| Raw DNS query to `10.0.2.3` | answered | no answer |
| Raw DNS query to `fec0::3` | no answer | no answer |
| Name lookup (`getent`) | answered in the first open run, failed in the second | failed |
| Ping to `10.0.2.2` | replied | **replied** |

Notes on the table:

- The ping reply from `10.0.2.2` remains in isolated mode. It is QEMU's virtual gateway; a reply to ping does not show that anything reaches the host.
- The `fec0::3` row proves nothing: it got no answer in the open run either.
- `getent` failed once in an open run in which a TCP connection by name worked. I did not find out why. The raw `10.0.2.3` row is the better DNS evidence.
- The guest had one network interface besides loopback, and in isolated mode no default route.
- WinLab's SSH connection (with `-F none` and forwarding off) worked in isolated and open labs and with `vm resume`.
- Persistence: after the isolated lab ended, `winlab vm resume` (which knows nothing about labs) started QEMU with `restrict=on`, and an internet connection from the guest failed. A normal lab then restored the clean snapshot, started without `restrict=on`, and the record changed to `open`.
- Unit tests cover the record, the QEMU arguments, the lab setting, the SSH arguments and the output filter (`zig build test`: 122 of 122 passed).

**Not tested:** a Windows guest, the AlmaLinux and Chimera guests, a Linux host with KVM, other QEMU versions, reaching another machine on the LAN (only the host's own LAN address was tried), and a real hostile program.
