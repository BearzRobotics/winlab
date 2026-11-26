# Content plan: fleshing out the course

Owner direction (2026-11-21): every lesson gets fleshed out; add the networking lessons from the outline; cybersecurity and penetration testing are a stretch goal. All lessons stay **drafts for owner review** until the owner says otherwise.

## What "fleshed out" means (the standard for every lesson)

A lesson is done when it has all of these, and none of it is invented:

1. **A reason to care**: the real situation where the topic matters, in two or three sentences.
2. **The model**: the concepts, small enough to hold in your head, with a table or diagram in text where it helps.
3. **Hands-on with output**: every command shown with its real output (captured on a real machine, addresses replaced with documentation ranges such as `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`, or `192.168.1.0/24`). Read-only commands first; anything that changes state says so and says how to undo it.
4. **How it looks when it is broken**: a symptom to cause table, so the learner can work backwards.
5. **Common mistakes** and the wrong turns people take.
6. **Check yourself**: questions or small exercises, with answers at the end.
7. **Practice**: the lab(s) that go with it, linked by lesson id.
8. **Both families** where the topic exists on both: Windows (built-in tools) and Linux (Ubuntu and AlmaLinux).
9. **Official sources, cited inline** (owner rule, 2026-11-21): wherever a statement or command has an official document, link it at the point it is used, not only in the references list. Preferred sources: Microsoft Learn for Windows commands and cmdlets, the man7.org manual pages or the distribution's own docs for Linux, the RFC editor for protocols, IANA for registries, vendor documentation for products. Every URL must be fetched and return success before it goes in (a wrong link is worse than none); if no official source exists, say so rather than cite a blog. Add the same sources to the manifest `references`, plus `certifications` tags (supports the domain, not a promise of exam coverage).

Rules from earlier decisions still apply: stock Windows tools in the core (ADR 0007), no copied exam objectives, nothing unverified presented as fact. A command that was not run on a real machine says so.

## Optional external tools (advanced track, labelled, never bundled)

- **util-core** (github.com/BearzRobotics/util-core, v0.1.0, GPL-2.0-or-later): 103 coreutils-style commands (`ls`, `grep`, `sed`, `find`, `diff`, ...) as Zig, with prebuilt Windows and Linux archives. Fits the **advanced track** (owner confirmed 2026-11-21): the powerful Linux tools on Windows, in a lesson such as "Unix tools on Windows". Its README says the Windows build is tested under wine, not yet on real Windows (planned for 0.1.1), so any lesson using it must be run and verified on real Windows first.
- **dkman** (github.com/bearzrobotics/dkman, MIT): a command-line documentation reader, not a Unix-tools lesson. Per the owner it downloads and views the official open-source Microsoft docs from GitHub, with `less` or a TUI with fzf-style search over its packages: a way to look things up (RTFM). Fits the **getting-help lesson** (outline Part I) as an optional resource beside the built-in `Get-Help`, `man`, `--help` and `/?`, and as a way to read documentation offline. The lesson must teach the built-in help first. Details of how it fetches and what it searches are to be confirmed against its own README and run before the lesson states them.
- Both follow ADR 0007: the core course never depends on them, each lesson using them is labelled "uses external tools", WinLab does not bundle or redistribute them (util-core is GPL), and they are fetched on the learner's request with size and hash shown, or supplied by the learner.

## Networking track (this pass)

Order a learner should read them in. Prerequisites are in each manifest.

| Lesson id | Topic | Notes |
|---|---|---|
| `networking.models-and-protocols` | OSI and TCP/IP, encapsulation, TCP vs UDP, ports and protocols, ARP | new |
| `networking.addressing-and-names` | the bottom-up diagnosis routine | existing, deepened |
| `networking.subnetting` | binary, masks and prefixes, network/broadcast/host range, IPv6 basics | new, with worked problems |
| `networking.dhcp` | DORA, leases, scopes, options, relay, APIPA | new |
| `networking.dns` | records, resolution path, caching, tools on both OSes | new |
| `networking.routing-and-gateways` | routing table, default route, metrics, tracing | new |
| `networking.ports-and-firewalls` | listening vs reachable, refused vs timed out, host firewalls | new |

Next in this track (not yet written): switching, VLANs and trunking; wireless; network services (NTP, SMB basics); remote access (RDP, SSH, WinRM); network security basics; VPN concepts; monitoring and logs.

## Remaining areas, in the order planned

1. Windows administration (3 lessons): deepen; add event logs, performance, boot and recovery, Task Scheduler, Group Policy basics, user profiles, BitLocker/EFS concepts, backup and restore.
2. Foundations (8 lessons): deepen the shell lessons with exercises and "what the error means" sections.
3. Linux (2 lessons): systemd, permissions and ownership, SELinux and AppArmor, packages, logging, boot and recovery, SSH, backup, NFS/Samba (outline X2 to X17).
4. Endpoints, Security, Operations, Hardware (concept lessons): deepen with scenario walk-throughs.
5. **Stretch goal: cybersecurity and penetration testing.** Defensive first. The track starts with authorization, scope, rules of engagement and the law, before any technique. Hands-on work happens only on WinLab's own lab VMs on the private lab network, never against machines the learner does not own. Planned lessons: threat modelling; hardening Windows and Linux; logging and detection (Windows event IDs, auditd, journal); vulnerability scanning and reading results; password and credential hygiene; network reconnaissance on your own lab; web application basics (OWASP risks, in a deliberately vulnerable lab app); privilege-escalation misconfigurations as *defender's checks*; incident response and evidence preservation; writing a report. No weaponized exploit code, no evasion of security products, no real-world targets.
6. **Stretch goal: home lab (owner, 2026-11-21), open-source stacks first.** Planned lessons, each CLI-first, cited to the project's own docs, and built so a learner can follow it in VMs with no spend: firewall/router appliances (OPNsense, IPFire); running your own DNS server (BIND or Unbound, plus a DHCP server, tying back to the networking lessons); hypervisors (Proxmox VE, and Windows Hyper-V as the Windows side); file sharing (Samba, Nextcloud); a document server; a media server; backups, monitoring and keeping it updated; and an honest look at exposure (what to keep off the internet, VPN in instead). Needs the multi-VM lab network (ADR 0008) and the downloads are large (ISOs), so each lesson must say what to fetch and let the learner decide; no ISOs are bundled. Home lab security lessons share the defensive-first rule with the cyber stretch goal.

## How the work is paced

One area at a time, each lesson checked by `winlab check course` (manifests, prerequisites, tags) and read in the new GUI. Command output in a lesson comes from a command that was actually run. The owner reviews in the GUI; changes come back lesson by lesson.

## Cached official documents

`reference/` keeps verbatim copies of the official documents the lessons cite (RFCs, Microsoft Learn sources, iproute2 manual pages, IANA registries), with a manifest that quotes each file's licence evidence and a takedown notice for rights holders (modelled on the `assembly-first-programming` project's `reference/manuals`). When a lesson cites a new official document: add it to `reference/gen_manifest.ps1`, regenerate, and cite the official URL in the lesson. Section C of `reference/MANIFEST.md` lists every cited URL not yet stored.

## Owner rules added 2026-11-21

- Windows 10 is the oldest client supported; Windows 7 is out.
- Every Windows topic is taught from the command line (PowerShell and CMD) even where a GUI is also shown.
- **Tracks** are goal-based paths (for example "Windows administrator", "Linux administrator", "Network+ preparation") that a learner can start anywhere their prerequisites allow; they are not one long sequence from zero.
- Scripting lessons (CMD, PowerShell, bash) go deep, with advanced features.
- Package managers: apt, dnf, pacman and apk are all covered (apk is the owner's own distro's manager).
- Limited internet: avoid large downloads; reuse stored copies.
- New topics to schedule: automated Windows install (answer files), automated program installs (msi, exe, winget), OpenSSH on Windows and Linux, manual updating, System Internals (advanced), Active Directory (needs the multi-VM lab network), quizzes.

## Scaffolding fades with level (owner rule, 2026-11-21)

| Level | How much hand-holding |
|---|---|
| 1 Foundations | Step by step, exact commands, worked answers, hints freely |
| 2 Administration | Goal plus the method; commands shown but the learner adapts them; hints on request |
| 3 Security | Goal plus the relevant official docs; commands named, not spelled out |
| 4 to 5 Specialisation and Professional | Goal and constraints only. The learner is pointed to the official documentation (the lesson links it; `reference/` holds a copy) and must find the syntax. Labs give a symptom and no hints by default; quizzes can be open-book. |

Every lesson will get a `level` (1 to 5) in its manifest, used for the sidebar, tracks and this scaffolding rule. Reading the manual is itself a taught skill (`Get-Help`, `man`, `--help`, `/?`, Microsoft Learn, and the dkman reader as an optional tool).

## Quizzes

Built: format and validator (`docs/quizzes.md`), the quiz window, and results stored in `progress.toml`. Banks so far (320 questions): `networking.models-and-protocols` (44), `networking.subnetting` (67), `networking.dhcp` (36), `networking.dns` (45), `networking.routing-and-gateways` (45), `networking.ports-and-firewalls` (48), `networking.addressing-and-names` (35). Every lesson gets a bank as it is fleshed out; the bank size should be several times the `draw`, so attempts differ.

## Lab machines and distros (owner decisions, 2026-11-21)

- Existing automated paths stay as they are: Windows unattended install, Ubuntu and AlmaLinux cloud images.
- Further distros are **opt-in catalog entries**, never bundled: FreeBSD, OPNsense, IPFire and one more general Linux (Alpine for `apk`; Debian or Arch were the alternatives). Candidates are fetched on demand; sizes and names are verified before they are listed.
- **A learner walking through the install of a firewall or BSD distro is a feature, not a cost** (owner: "it's good to learn it"). Those lessons guide a manual install in a QEMU window; automated self-tested labs for them are optional later work.
- **Optional WSL builder:** for a distro that ships only an ISO with a squashfs root, WinLab may later offer "build from ISO" using WSL (`unsquashfs`, `mkfs.ext4 -d`) plus Windows `qemu-img`. WSL is a free Windows feature and is treated like QEMU: detected, never installed by WinLab, instructions shown when missing. Verified on the author's machine: Ubuntu-26.04 under WSL2 has `unsquashfs`, `mksquashfs`, `mkfs.ext4`.
- Images live in `%LOCALAPPDATA%\WinLab\images`, VMs in `%LOCALAPPDATA%\WinLab\vms\<id>`. A GUI "Lab machines" page (catalog, downloads, build, QEMU/winget hint) is planned; today it is command-line only.

## Python track (started 2026-11-26)

An optional track, **Python for administrators** (`paths/python-admin.toml`). Only the basics are general; **everything after the basics is administration-focused**. It is not a general programming course. (The owner asked on 2026-11-26 to start now rather than after the current drafts are tested.)

**Written (draft):** `foundations.python-basics`, run on 3.15.2 (Windows) and 3.14.4 (Ubuntu, WSL); **not** run on 3.9 or 3.12. It has no labs yet. **Proposed next, not yet agreed:** (2) files, CSV, JSON and logs; (3) arguments with `argparse`, errors, exit statuses and logging; (4) running other programs safely with `subprocess`; (5) reading and auditing other people's scripts; later, virtual environments and `pip`.

- **Basics, taught through admin tasks:** files and paths, text, CSV and JSON, running other programs safely, error handling and exit codes, command-line arguments.
- **Beyond the basics:** administration work, including when to choose Python over bash or PowerShell.
- **Read and audit other people's code,** as in the other scripting tracks.
- **Standard library first** (limited internet). Virtual environments and `pip` get a later lesson of their own, with the risks of installing unfamiliar packages.
- **Versions:** say which version each lesson needs and teach the differences. Lesson output so far shows 3.12.3 on Ubuntu and 3.9.25 on AlmaLinux; the owner's Windows PC has 3.15.2.
- **Labs:** script labs support CMD, PowerShell and bash; Python needs adding as a lab language. The Linux lab VMs already run Python. The Windows lab VM has not been checked.
- **Host Python is optional:** the app does not need it. If the track has learners run Python on Windows, the setup window may list it as optional, for this track only, with a command to copy. WinLab never installs it.

## Learning paths

Goal-based paths, soft prerequisites and test-out-by-quiz are designed in `docs/learning-paths.md` (not yet implemented).
