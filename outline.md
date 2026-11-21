# WinLab course outline

Status: **draft for the course owner's review** (2026-11-08). Nothing below Part I is written yet; this
file proposes what to write and in what order. The normative coverage list is `ai/specs.md` section 4;
this outline turns it into chapters, labs and assessments. Please mark it up: add, cut, reorder, and
answer the questions at the end.

## 1. Who it is for and what it promises

The learner has some Linux familiarity and little Windows administration experience. By the end they can
operate Windows' own tools without WinLab, investigate an unfamiliar problem, repair it safely, verify
the repair and explain it. The Linux server track gives the same skills on Debian-family and RHEL-family
servers, because real IT work spans both.

## 2. Rules every chapter follows

- **Stock tools first** (ADR 0007). Core chapters teach with what ships in the operating system. External
  tools (Sysinternals) live in a separate, labelled advanced track.
- **State, not commands.** A lab check looks at the final state (a service is healthy, a permission is
  right) and never requires one particular command. Reasoning is assessed with rubrics.
- **Evidence before action.** Chapters teach to observe first, change the least possible, keep a way back,
  verify, and write it down (the eight-step method from `foundations.troubleshooting-method`).
- **Safe labs.** Anything disruptive runs in a registered, disposable lab VM from a snapshot. The host is
  never a target.
- **Offline.** Core text, exercises and references work with no network. Official documentation links are
  extra reading, never the only explanation.
- **Editions.** Each chapter states the editions it needs. Windows 11 Home cannot join a domain or edit
  Group Policy, so those chapters use Pro, Enterprise or Server.

## 3. Chapter format

Each chapter follows the lesson sequence in the spec (5.2):

1. Objectives and prerequisites
2. Theory and the Windows (or Linux) mental model
3. Demonstration in the GUI and/or a shell
4. Guided lab with hints (a **baked scenario** with a symptom report, or a **scripting lab**)
5. Independent lab with fewer prompts
6. Assessment and an explanation of the result
7. Review material and official references

A chapter is usually one to three lessons plus two to six labs. Lesson ids are `<part>.<slug>`; lab ids
are `labs.<slug>`. "Status" below: **done** (drafted and verified in this repo), **planned**.

## 4. The Windows course

### Part I: Foundations (`foundations.*`)

| # | Chapter | Lessons | Labs | Status |
| --- | --- | --- | --- | --- |
| F1 | Editions, installing, and the desktop | editions and licensing; installing Windows (what an unattended install is); navigation; the built-in consoles (Computer Management, Services, Event Viewer, Device Manager, Disk Management, Task Scheduler, regedit) | tour of the consoles (guided, on a clean VM) | planned |
| F2 | How Windows is organized | `foundations.architecture` | rename-server, user-account-disabled | **done** (draft lesson) |
| F3 | A troubleshooting method | `foundations.troubleshooting-method` | the Windows scenario set (all use the method) | **done** (draft lesson) |
| F4 | CMD fundamentals | `foundations.cmd-basics`, `foundations.cmd-control-flow` | six CMD script labs | **done** (draft lessons) |
| F5 | PowerShell fundamentals | `foundations.powershell-basics`, `foundations.powershell-control-flow` | six PowerShell script labs | **done** (draft lessons) |
| F6 | Getting help and reading documentation | `Get-Help`, `/?`, Microsoft Learn, reading an error code | find-the-answer exercises (no VM) | planned |
| F7 | Regular expressions and text tools for admins | `findstr`, `Select-String`, `-match`; reading logs | log-parsing script labs | planned |

### Part II: Local administration (`local-admin.*`)

| # | Chapter | Lessons | Lab ideas | Status |
| --- | --- | --- | --- | --- |
| L1 | File systems | NTFS and ReFS; paths, volumes, attributes; junctions and symbolic links; short names | broken junction; hidden and system attributes; path-length surprises | planned |
| L2 | The registry | hives, keys, value types; 32- and 64-bit views; permissions; export, backup, restore | wrong Run key; registry permission denied; restore from a `.reg` backup | planned |
| L3 | Processes, services and startup | processes, threads, sessions; service accounts and dependencies; startup locations; Task Scheduler | spooler-stopped, time-service-disabled, scheduled-task-disabled (**done**); service that depends on a disabled service; runaway startup item | partly done |
| L4 | Accounts and access control | local accounts, groups, SIDs; tokens and UAC; ACLs, inheritance, ownership; elevation | folder-permissions (**done**); inheritance blocked; ownership taken; UAC-prompt mystery | partly done |
| L5 | Software and package concepts | installers (MSI, EXE), uninstall, per-user versus per-machine, Windows features, winget concepts | feature turned off; installer fails with an exit code | planned |
| L6 | Scripting for administrators | modules, scheduled scripts, logging, idempotence, safe defaults | automate the account, share and task chapters | planned |

### Part III: Diagnostics (`diagnostics.*`)

| # | Chapter | Lessons | Lab ideas | Status |
| --- | --- | --- | --- | --- |
| D1 | Networking fundamentals | TCP/IP, DNS, DHCP, routing, network profiles; `ipconfig`, `nslookup`, `Test-NetConnection`; reading a trace | dns-broken, hosts-file-entry (**done**); wrong gateway; stale DHCP lease; wrong network profile | partly done |
| D2 | Windows Firewall and SMB | profiles, rules, inbound versus outbound; SMB versions, shares, ports | rdp-firewall (**done**); blocked SMB; wrong profile | partly done |
| D3 | Event logs | providers, channels, event IDs, XML filtering, correlating events | find the event that explains a service failure; custom view | planned |
| D4 | Devices and drivers | Device Manager, Plug and Play, driver store, hardware inventory, USB | disabled device; driver rolled back (VM hardware is limited; labs use what virtual devices allow) | planned |
| D5 | Storage | partitions, volumes, Storage Spaces overview, SMART limits, BitLocker fundamentals | full volume; offline disk; read-only volume | planned |
| D6 | Boot, updates and servicing | boot sequence, BCD, recovery environment; Windows Update, component store, `sfc`, `DISM` | broken BCD entry (restart-aware); corrupted system file; stuck update | planned |
| D7 | Performance investigation | Task Manager, Resource Monitor, Performance Monitor; CPU, memory, disk, startup | runaway process; memory hog; slow startup item | planned |
| D8 | Time, locale and the small things | time zone and sync, regional settings, power plans | wrong-time-zone (**done**) | partly done |

### Part IV: Repair and recovery (`recovery.*`)

| # | Chapter | Lessons | Lab ideas | Status |
| --- | --- | --- | --- | --- |
| R1 | Least-destructive repair | decision ladder, rollback, evidence, change records | choose-the-repair reasoning items; a repair with a rollback plan | planned |
| R2 | Safe Mode, WinRE and restore points | entering recovery, safe-mode services, System Restore, startup repair | boots to a black screen; a bad driver; undo a change with a restore point | planned |
| R3 | Backup and file recovery | backup types, File History, shadow copies, restoring a deleted file, recovery media | recover an overwritten file from a previous version | planned |
| R4 | Malware-response fundamentals | signs, isolation, evidence preservation, escalation (defensive only; no security bypasses) | triage a suspicious scheduled task and startup entry | planned |
| R5 | Multi-symptom cases | two or three faults at once; customer-facing diagnosis | stacked scenarios built from earlier ones | planned |

### Part V: Business IT (`business-it.*`)

| # | Chapter | Lessons | Lab ideas | Status |
| --- | --- | --- | --- | --- |
| B1 | Remote administration | Remote Assistance, RDP, WinRM, PowerShell remoting, and their security models | enable and restrict RDP; remote a command safely | planned |
| B2 | Shares, mapped drives and printing | SMB shares versus NTFS permissions, mapped drives, print queues | share reachable but access denied; spooler stuck | planned |
| B3 | Windows Server and the domain | roles, Active Directory, DNS, DHCP, Group Policy; join a client to a domain | **multi-VM:** domain controller and a client (domain join fails; policy not applying) | planned |
| B4 | Deployment | installation media, unattended installs, imaging and provisioning concepts | read and fix a broken answer file (WinLab itself uses one) | planned |
| B5 | Tickets, communication and privacy | taking a ticket, evidence, escalation, clear writing, handling personal data | write the incident note for earlier labs (rubric) | planned |

### Part VI: Capstones (`capstones.*`)

Three to five unfamiliar scenarios that combine several systems and need an independent diagnosis, a safe
remediation, verification and a **written incident report**. The final competency assessment is graded
by rubric on reasoning and outcomes, never on specific commands. Example shapes: a branch office whose
file share, printing and remote access all misbehave after a change; a "slow computer" with three causes;
a server that will not boot after an update.

## 5. The Linux server track (`linux.*`)

Two families are taught side by side: Debian-family (Ubuntu) and RHEL-family (AlmaLinux). Lessons name
the difference where there is one (`apt` versus `dnf`, `ufw` versus `firewalld`, AppArmor versus SELinux).
Labs that depend on a family say so; the rest run on either.

| # | Chapter | Lessons | Lab ideas | Status |
| --- | --- | --- | --- | --- |
| X1 | The shell and scripting | `foundations.bash-basics`, `foundations.bash-control-flow` | eight bash script labs | **done** (draft lessons) |
| X2 | Services and systemd | units, targets, enable versus start, dependencies, reading `systemctl status` and the journal | linux-service-disabled, alma-crond-disabled, alma-service-config-error (**done**); service that fails after a restart | partly done |
| X3 | Users, groups, permissions and sudo | modes, ownership, umask, `sudo`, locked accounts, ACLs | linux-file-permissions, linux-account-locked (**done**); setgid directory; sudoers typo | partly done |
| X4 | Mandatory access control | SELinux (RHEL) and AppArmor (Ubuntu) concepts, contexts, reading denials, booleans | alma-selinux-context (**done**); wrong boolean; AppArmor profile blocking a service | partly done |
| X5 | Networking | NetworkManager and netplan, name resolution order, routes, `ss`, `ip` | linux-name-resolution (**done**); wrong default route; wrong hostname resolution | partly done |
| X6 | Firewalls | firewalld and ufw/nftables concepts, zones, services versus ports | alma-firewalld-http (**done**); ufw blocking a port | partly done |
| X7 | Storage | partitions, LVM, file systems, mounts, `fstab`, inodes, full disks | missing mount after restart; full filesystem; wrong `fstab` entry (restart-aware) | planned |
| X8 | Packages and updates | `apt` and `dnf`, repositories, GPG keys, held packages, rollbacks | alma-dnf-repo-disabled (**done**); broken apt source | partly done |
| X9 | Logging and troubleshooting | journald, syslog, `auditd`, log rotation, reading evidence | find the cause in the journal | planned |
| X10 | Scheduling | cron and systemd timers, environment gotchas | linux-cron-file-ignored (**done**); a timer that never fires | partly done |
| X11 | Boot and recovery | GRUB, rescue and emergency targets, resetting a lost root password the sanctioned way | a server that drops to emergency mode (restart-aware) | planned |
| X12 | Web and network services basics | install, configure and test a web service; TLS basics; reading its logs | alma-selinux-context, alma-service-config-error (**done**) | partly done |
| X13 | Remote administration and hardening | SSH keys, `sshd_config`, fail2ban-style ideas, least privilege | locked out by an SSH setting (needs the console, so VM window only) | planned |
| X14 | Backup and automation | `tar`, `rsync`, rotation, restore tests | script-bash-backup-rotate (**done**) | partly done |
| X15 | Linux capstone | a multi-fault server | | planned |

## 6. Advanced track: Microsoft Sysinternals (`advanced.*`)

Optional, labelled as using external tools (ADR 0007). Every lesson begins with the stock-Windows way,
then shows what the tool adds. WinLab does not bundle the tools; they are downloaded on request.

| # | Chapter | Tools | Stock equivalent taught first |
| --- | --- | --- | --- |
| A1 | Getting and using the suite safely | the suite, licence, verifying downloads | n/a |
| A2 | Seeing what a process is doing | Process Explorer, Process Monitor | Task Manager, Resource Monitor, Event Tracing basics |
| A3 | Startup and persistence | Autoruns | `msconfig`, Task Scheduler, Run keys, `Get-CimInstance` |
| A4 | Network connections | TCPView | `netstat`, `Get-NetTCPConnection` |
| A5 | Remote administration | PsTools | PowerShell remoting, `sc`, `schtasks` |
| A6 | Logging for investigation | Sysmon basics | Windows event logging and auditing |

## 7. Assessment and mastery plan

Each chapter produces objective-tagged evidence of four kinds:

1. **Knowledge checks:** multiple choice and short answer (self-checking, retryable).
2. **Practical state checks:** lab Check and scripting-lab Check, which already exist and are shell- and
   command-independent.
3. **Ordered procedures:** put the troubleshooting steps in a sensible order, with explanations.
4. **Reasoning items:** write what you saw, what you concluded and why, graded against an explicit
   rubric by self-review (and optionally instructor review). No keyword matching.

Mastery is stored separately from reading progress, per objective, with attempts recorded and review
scheduled for weak objectives. Everything stays local and can be exported. Capstones add a written incident
report assessed by rubric.

## 8. Reference library (built alongside, not after)

Glossary of Windows and Linux terms (linked from lessons), a searchable command and cmdlet reference with
the stock tool first, an error-code index, and a "which console do I open" guide. All offline.

## 9. Size and order of work

Roughly: Windows **~45 lessons and ~70 labs**, Linux **~25 lessons and ~45 labs**, advanced **6 lessons**.
So far: **8 lessons, 43 labs**. Proposed writing order, each step ending with verified labs and a
checkpoint review by you:

1. Finish Part I (F1, F6, F7) and the first assessments (the model needs real content to test it).
2. Part II (L1 to L4) alongside Linux X2 to X4, since the labs for them mostly exist.
3. Part III networking, event logs, performance, boot (D1 to D3, D6, D7) with Linux X5, X6, X9.
4. Part IV recovery and the rest of Linux.
5. Part V business IT; the multi-VM domain lab needs its own design record first.
6. Capstones and the advanced track.

## 10. Decisions (2026-11-08, from the course owner)

1. **Windows 11 Pro is the default client**, with Home called out where it differs. (Needs a Pro ISO; the
   `winlab image add` path is built. Windows 11 Enterprise evaluation media is a no-cost stand-in for the
   same features if a Pro ISO is not to hand.)
2. **Domain labs are in scope now** (multi-VM: a domain controller plus clients on a private network).
   Design record 0008 covers the topology and automation.
3. **The course owner reviews every lesson**, as the first user. Lessons stay marked "draft for review"
   until reviewed.
4. **Certification alignment.** Lessons and labs are tagged with the exam domains they support, and
   `winlab coverage` shows which domains the course covers. See section 11.

Still open (not blocking): Windows 10 depth, Server 2025 as a second target, how far the Linux track goes,
and the part slugs used in lesson ids (currently `foundations`, `local-admin`, `diagnostics`, `recovery`,
`business-it`, `capstones`, `linux`, `advanced`).

## 11. Certification alignment

WinLab is not an exam-prep product and teaches no exam "dumps". Many learners, though, want to know how
the material maps to the certifications employers ask for, and shaping chapters around those domains makes
the course useful to more people. The approach:

- **Tags, not copies.** Each lesson and lab can carry `certifications = ["exam-id/domain-id", ...]`. The
  catalog of exams and their domain *titles* is `certs/catalog.toml`. Official objective wording is not
  copied; the catalog links to each vendor's own objectives page, which is the authority and changes.
- **Coverage report.** `winlab coverage [exam-id]` lists every domain of an exam with the lessons and labs
  that support it and flags domains with none. That makes gaps visible and tells us what to write next.
- **Honesty.** The tags say "this material supports that domain", not "this passes that exam". Domains that
  need things WinLab cannot provide (physical hardware, a cloud tenant) are marked as concept-only.

Targets, in rough order of fit (domain titles as reported by the vendors' published outlines at the time of
writing; **verify against the current official objectives before relying on them, because exams are revised**):

| Certification | Domains / skill areas | How WinLab fits |
| --- | --- | --- |
| **CompTIA A+ Core 2 (220-1202)** | Operating Systems; Security; Software Troubleshooting; Operational Procedures | strong: most of Parts I-IV, plus new chapters on operational procedures and security basics |
| **CompTIA A+ Core 1 (220-1201)** | Mobile Devices; Networking; Hardware; Virtualization and Cloud Computing; Hardware and Network Troubleshooting | partial: networking and virtualization are strong; physical hardware and mobile are concept lessons |
| **CompTIA Network+ (N10-009)** | Networking Concepts; Network Implementation; Network Operations; Network Security; Network Troubleshooting | good: Part III networking plus new concept chapters (OSI, addressing, switching, wireless) with Windows and Linux hands-on |
| **Microsoft MD-102 (Endpoint Administrator)** | Prepare infrastructure for devices; Manage and maintain devices; Manage applications; Protect devices | partial: Windows-side deployment, configuration, update and protection are covered; Intune and cloud management are out of scope (offline, no tenant) |
| **Windows Server administration (for example the AZ-800 skills)** | Deploy and manage Active Directory Domain Services; manage servers and workloads; networking and storage | good once the domain labs exist (Part V) |
| **Red Hat RHCSA (EX200)** | essential tools; running systems; local storage; file systems; deploy and maintain; basic networking; users and groups; security; containers (RHEL 9 list) | strong for the AlmaLinux (RHEL-compatible) track; containers (Podman) get their own chapter |
| **CompTIA Linux+ (XK0-005)** | System Management; Security; Scripting, Containers and Automation; Troubleshooting | strong: the whole Linux track, on both families |

Official objective pages (the authorities): [Microsoft MD-102 study guide](https://learn.microsoft.com/credentials/certifications/resources/study-guides/md-102),
[Red Hat EX200 objectives](https://www.redhat.com/training/courses/ex200/examobjective), and CompTIA's
objective PDFs from its certification pages.

### New chapters the alignment adds

| # | Chapter | Why | Status |
| --- | --- | --- | --- |
| O1 | Operational procedures | documentation, change management, ticketing, safety, professionalism, backup policy (A+ Core 2) | planned (extends B5) |
| S1 | Security fundamentals | authentication, least privilege, encryption basics, malware types and removal, social engineering, physical security (A+ Core 2, Network+) | planned |
| N1 | Networking concepts | OSI and TCP/IP models, addressing and subnetting, ports and protocols, switching, routing, wireless (Network+, A+ Core 1) | planned |
| N2 | Network troubleshooting | the Network+ method applied with `ping`, `tracert`, `nslookup`, `arp`, `netstat`, `ss`, `ip` | planned |
| H1 | Hardware and peripherals (concepts) | components, storage types, printers, mobile devices; labs limited to what virtual hardware allows | planned |
| V1 | Virtualization and cloud concepts | hypervisors, VM networking, snapshots, cloud service models; WinLab's own lab VMs are the demonstration | planned |
| X16 | Containers with Podman | RHCSA containers group; runs inside the AlmaLinux VM | planned |
| X17 | Shared storage and file services (NFS, Samba) | RHCSA/Linux+ file services; pairs with Windows SMB chapters | planned |

## 12. Domain lab design (Part V, B3)

Multi-VM labs need VMs that can talk to each other on a private network and a way to build and reset the
set together. The plan is recorded in `docs/decisions/0008-multi-vm-labs.md`. Summary:

- **Topology as data.** A `topology` file lists VMs (role, image, memory), the private segment they share,
  and static addresses. A lab names the topology it needs.
- **Private network.** Each QEMU process gets a second NIC on a host-local virtual switch (QEMU socket
  networking), separate from the existing NAT NIC used for SSH. No traffic leaves the host.
- **Automation.** The domain controller is promoted with the PowerShell AD DS cmdlets over the same SSH
  channel; member machines get a DNS server pointing at the controller and join with `Add-Computer`. Each
  step survives guest restarts because the session supervisor relaunches QEMU.
- **Snapshots as a set.** A `winlab-clean-domain` snapshot is taken on every VM of the set while all are
  stopped; a lab restores them together. Domain labs break domain state (a join, a policy, a DNS record)
  and are verified like every other lab.
- **Editions.** The domain controller is Windows Server; clients are Windows 11 Pro or Enterprise (Home
  cannot join).

## 13. Questions that remain

1. **Windows 10**: teach explicitly, or mention differences only?
2. **Server 2025**: add as a second target, or stay on 2022?
3. **Linux depth**: the outline now includes Podman and file services; anything to add or cut?
4. **Review workflow**: how do you want to receive chapters (the repository, a rendered page, a shared document)?
5. **Which certifications matter most to your learners?** The order above is my guess; the coverage report
   will show where the course is thin, and your answer decides what we write first.
