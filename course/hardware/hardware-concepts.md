*Draft for owner review.* A VM cannot teach you to seat a memory module, but it can teach you to read what a machine reports about its hardware, and the concepts behind it. This lesson covers both. Note that the lab VMs show *virtual* hardware; the commands are the same ones you will run on physical machines.

## The parts and what they do

| Part | Job | Symptom when it fails |
|---|---|---|
| CPU | Runs instructions; cores and threads run work in parallel | Sustained 100% load, throttling, crashes under load |
| RAM | Fast, temporary working space | Slowness, heavy paging, out-of-memory kills, random crashes |
| Storage (SSD/HDD/NVMe) | Permanent data | Slow reads, file system errors, SMART warnings, clicking (HDD) |
| Motherboard and firmware (UEFI/BIOS) | Connects parts; starts the machine | No POST, wrong date/time, settings lost |
| Power supply | Converts mains power to the voltages parts need | Random shutdowns, no power |
| GPU | Graphics and parallel compute | Display artefacts, driver crashes |
| NIC | Network connection | No link, drops, slow transfers |

Capacity versus speed: RAM is fast and small, storage is slow and large. When RAM runs out, the system pushes data to storage (paging or swap), and everything slows down. That is why "add RAM" fixes more slowness than "buy a faster CPU".

## Storage types and RAID

HDDs have moving parts and fail from wear and shock; SSDs have no moving parts but a finite number of writes; NVMe drives use the PCIe bus and are much faster. **RAID** combines disks:

- RAID 0 stripes for speed, with no redundancy (one failure loses everything).
- RAID 1 mirrors two disks.
- RAID 5 stripes with parity and survives one failure; RAID 6 survives two.
- RAID 10 mirrors and stripes.

RAID is availability, not backup: deleting a file, or ransomware, is copied to every disk.

## Reading the hardware with built-in tools

Windows:

```
systeminfo                                                    # OS, memory, hotfixes, boot time
Get-CimInstance Win32_Processor | Select Name, NumberOfCores, NumberOfLogicalProcessors
Get-CimInstance Win32_PhysicalMemory | Select Capacity, Speed
Get-PhysicalDisk | Select FriendlyName, MediaType, HealthStatus
Get-Volume
```

Linux:

```
lscpu            # processor model, cores, virtualization support
free -h          # memory and swap in use
lsblk -f         # disks, partitions, file systems
lsblk -d -o NAME,ROTA   # ROTA 1 = spinning disk, 0 = SSD
sudo dmidecode -t memory   # DIMM details (physical machines)
```

## Troubleshooting hardware

Apply the same method as for software. Isolate by **swapping one thing at a time**: a known-good cable, a known-good port, a different slot. Look at the evidence the machine keeps: the Windows System log and Reliability Monitor, Linux `journalctl -k` and `dmesg`. Disk errors in the log, a growing reallocated-sector count, or a machine that passes at idle and crashes under load point at different parts.

Beep codes and POST (power-on self test) tell you the machine is failing before an operating system is involved. Document the codes your vendor lists.

## Virtualization and cloud, briefly

A **hypervisor** shares physical hardware among virtual machines. Type 1 runs on the hardware (Hyper-V, KVM, ESXi); type 2 runs on top of an operating system (this course uses QEMU with the Windows hypervisor platform). Virtual hardware can be resized and snapshotted, which is why the labs use it. Cloud services (IaaS, PaaS, SaaS) differ in how much you manage yourself: IaaS gives you the virtual machine, SaaS gives you only the application.

## Check yourself

1. A machine is slow, the CPU is idle, and the disk light is solid. What do you suspect first?
2. Why is RAID 1 not a backup?
3. Name two commands that show how much RAM a machine has, one per operating system family.
