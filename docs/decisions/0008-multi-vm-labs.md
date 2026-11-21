# 0008: Multi-VM labs (domain controller plus members)

Status: proposed (2026-11-08). Nothing here is implemented or verified yet.

## Context

Active Directory, DNS, DHCP, Group Policy and domain join cannot be taught on one
machine. Domain labs are in scope (project owner, 2026-11). Today a lab targets
one registered VM, reached through a loopback SSH port forward (ADR 0006).

## Decision

1. **Topology is data.** A `topologies/<id>.toml` file lists the VMs of a set
   (role, image, memory, cpus), the private segment, and each VM's static
   address. A lab names the topology it needs instead of a single VM.
2. **Private network.** Each QEMU process keeps its NAT NIC (used for SSH and
   downloads) and gains a second NIC joined to a host-local QEMU socket network
   (`-netdev socket`, loopback only). No lab traffic leaves the host. The
   private NIC gets a static address inside the guest; the NAT NIC is never used
   for domain traffic.
3. **Automation over the existing channel.** The controller is promoted with
   the AD DS PowerShell cmdlets over SSH. Members get the controller as DNS
   server and join with `Add-Computer`. Steps that restart a guest rely on the
   supervisor relaunching QEMU (ADR 0006).
4. **Snapshots as a set.** A `winlab-clean-domain` snapshot is taken on every VM
   of the set while all are stopped; a lab restores them together. A baked
   scenario for a domain lab is likewise one snapshot per VM.
5. **Editions.** The controller is Windows Server. Clients are Windows 11 Pro or
   Enterprise, because Home cannot join a domain.
6. **Order of work.** First prove two Server 2022 VMs (controller plus member)
   end to end, then add a Windows 11 Pro client from a learner-supplied ISO.

## Consequences

- Memory use multiplies by the number of VMs; the topology file states the
  total so the app can warn before starting a set.
- Start order and readiness checks matter (controller before members); the
  supervisor needs a per-set "all ready" wait.
- Domain labs break domain state (a join, a policy, a DNS record) and are
  verified like every other lab with `lab verify`; none of this is verified yet.
- Promotion takes several restarts and is slow, so the clean domain snapshot is
  built once and reused.

## Open questions

- Whether a QEMU socket network is reliable enough on Windows with WHPX, or a
  host-side virtual switch is needed. This must be tested before building more.
