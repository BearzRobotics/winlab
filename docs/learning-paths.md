# Learning paths (owner direction, 2026-11-21)

The course is years of material. Nobody should have to do every lesson in order. A learner picks a **goal**, gets a **path** (an ordered, trimmed list of lessons and labs for that goal), and can **start anywhere** on it, **skip what they already know**, and see what they would miss. Paths are advice, not locks.

This document is the design and the first path definitions. **Implemented 2026-11-21** (see "Status" at the end): `level` in manifests, `paths/*.toml` with a validator, the track picker, the path sidebar, Known and Skipped statuses, the placement quiz and soft prerequisite advice. The lesson ids below are real except where marked *planned*.

## Principles

1. **Goal first.** The entry screen asks "what do you want to be able to do?", not "where do you want to start?". Each goal is a path.
2. **Prerequisites are recommendations, not gates.** A lesson lists what it assumes; the app **warns** ("this lesson assumes `foundations.architecture`; you have not done it") but never blocks. A hard gate would defeat the point of paths.
3. **Test out with the quiz.** Every lesson has a large quiz bank. A learner can take a lesson's quiz **first**; a high score (proposed: **80% or more on a full attempt**) marks the lesson **known** and moves them on. This is the placement test, and it already exists.
4. **Know what you are skipping.** Skipped lessons stay one click away and are shown as "skipped", so a learner can come back when a later lesson depends on them.
5. **Levels.** Each lesson gets `level = 1..5` in its manifest. A path starts at the level of its audience; hand-holding fades with level (the existing rule). The track picker shows the level range.
6. **Overlap is normal.** A lesson can appear in many paths. Progress is per lesson, never per path, so finishing a lesson on one path counts everywhere.
7. **Labs belong to paths too.** A path lists the labs that practise its lessons, and a lab can be the final check of a stage.
8. **Certification paths use the `certifications` tags** already on every lesson and the `winlab coverage` command, so a path for an exam can be generated and checked for domain gaps. A tag means "supports this domain", not "passes this exam".

## Problems the current prerequisites cause (fix when implementing)

- `foundations.powershell-basics` has the prerequisite `foundations.cmd-basics`. A learner who wants **PowerShell only** is forced through CMD. Make it a recommendation, and put CMD in the paths where it matters.
- `endpoints.*`, `windows-admin.*` assume `foundations.powershell-basics`; with soft prerequisites the app can offer "PowerShell basics (90 min) or take its quiz to skip".
- Long chains (the ten CMD and PowerShell lessons) make the first lesson on a path look far away. Paths should show **entry points** ("already know CMD: start at PowerShell basics").

## Proposed data format

One file per path in `paths\<id>.toml` (a new content folder next to `labs\` and `quizzes\`), validated by `winlab check`:

```toml
schema_version = 1
id = "windows-scripting"
title = "Windows scripting: CMD and PowerShell"
goal = "Write and maintain scripts on Windows with confidence, in both shells."
audience = "Anyone who administers Windows machines, from beginner to experienced."
order = 40                                               # picker order, lowest first
certifications = ["comptia-a-core2/operating-systems"]   # optional

[[stage]]
title = "Command Prompt"
entry_hint = "Already comfortable with CMD? Skip to the next stage."
lessons = ["foundations.cmd-basics", "foundations.cmd-variables-and-expansion", ...]
labs = ["labs.script-cmd-exit-code", ...]

[[stage]]
title = "PowerShell"
entry_hint = "New to PowerShell? Start here; no CMD needed."
lessons = ["foundations.powershell-basics", ...]
optional = ["foundations.ps-modules-and-remoting"]       # nice to have on this path
```

`check` should verify every lesson and lab id exists and that `level` and `prerequisites` are consistent with stage order (a warning, not an error, when a prerequisite is outside the path).

## App behaviour to build

- **Track picker** on first run and under a Paths menu: goal, estimated hours, level range, progress bar.
- Sidebar can switch between **All lessons (by area)** (today's view) and **a path (by stage)**.
- Per lesson: *Not started / In progress / Completed / Known (passed the quiz first) / Skipped*.
- "I already know this" button: opens the quiz as a placement test.
- The lesson header shows soft prerequisite warnings with one-click links.
- Progress file gains a per-path "last position"; per-lesson status stays global.

## First path definitions

Hours are the sum of `estimated_minutes` in the manifests (my estimates, probably optimistic for a first-time learner; treat as relative sizes). *Planned* lessons do not exist yet and are not counted.

### 1. IT support and troubleshooting (CompTIA A+ style): about 11 h
`foundations.troubleshooting-method`, `foundations.architecture`, `hardware.hardware-concepts`, `hardware.mobile-devices`, `foundations.cmd-basics`, `foundations.powershell-basics`, `windows-admin.accounts-and-permissions`, `windows-admin.services-and-startup`, `windows-admin.registry-and-filesystems`, `networking.addressing-and-names`, `security.security-fundamentals`, `operations.operational-procedures`, `endpoints.update-and-policy`.
*Planned additions:* event logs and monitoring, storage and disks, printers, remote support tools.

### 2. Networking fundamentals (Network+ style): about 6 h
`networking.models-and-protocols`, `networking.addressing-and-names`, `networking.subnetting`, `networking.dhcp`, `networking.dns`, `networking.routing-and-gateways`, `networking.ports-and-firewalls`.
*Planned additions:* switching and VLANs, wireless, network security, VPN, monitoring; a firewall appliance lab (OPNsense).
*Entry points:* already know the OSI model? Start at `networking.addressing-and-names`. Already subnet in your head? Take the `subnetting` quiz and move on.

### 3. Windows administrator: about 12 h so far
`foundations.troubleshooting-method`, `foundations.architecture`, `foundations.cmd-basics`, `foundations.powershell-basics`, `windows-admin.accounts-and-permissions`, `windows-admin.services-and-startup`, `windows-admin.registry-and-filesystems`, `networking.addressing-and-names`, `networking.dns`, `networking.ports-and-firewalls`, `endpoints.update-and-policy`, `endpoints.protect-devices`, `endpoints.endpoint-management`.
*Planned additions:* event logs, updates and manual patching, storage, remote management, automated Windows install (answer files), software installs (msi, exe, winget, DISM), OpenSSH, System Internals (advanced), Active Directory.

### 4. Windows scripting, CMD and PowerShell: about 21 h
Stage 1, **CMD** (about 8 h): `foundations.cmd-basics`, `cmd-variables-and-expansion`, `cmd-control-flow`, `cmd-batch-files`, `cmd-text-and-files`, `cmd-advanced`.
Stage 2, **PowerShell** (about 12 h): `foundations.powershell-basics`, `ps-variables-types-operators`, `powershell-control-flow`, `ps-functions-and-scripts`, `ps-errors-and-debugging`, `ps-working-with-data`, `ps-modules-and-remoting`.
*Planned:* `ps-system-admin-scripting`, `ps-advanced`.
*Entry points:* know CMD already, or only need PowerShell? Start at stage 2 (see the prerequisite problem above). Only maintain old batch files? Stage 1 alone is a complete path (about 8 h).

### 5. PowerShell only (fast track): about 12 h
The seven PowerShell lessons in order, plus the two planned ones. This is path 4, stage 2, offered on its own.

### 6. Linux administrator (RHCSA and Linux+ style): about 8 h so far
`foundations.troubleshooting-method`, `foundations.bash-basics`, `foundations.bash-control-flow`, `linux.storage-filesystems`, `linux.containers-podman`, `networking.addressing-and-names`, `networking.dns`, `networking.ports-and-firewalls`, `security.security-fundamentals`.
*Planned additions:* systemd (mandatory), users and permissions, SELinux and AppArmor, firewalls (firewalld, ufw), package management (apt, dnf, pacman, apk), logging, boot and recovery, SSH, backup, NFS and Samba.

### 7. Shell scripting on Linux: bash and POSIX sh
`foundations.bash-basics`, `foundations.bash-control-flow` (existing, to be deepened), plus the *planned* series: `shells-and-posix`, variables and expansion, functions and scripts, text processing, robust scripts, advanced bash, portable POSIX `sh`.

### 8. Endpoint management (MD-102 style): about 4.5 h
`foundations.powershell-basics`, `windows-admin.accounts-and-permissions`, `endpoints.update-and-policy`, `endpoints.protect-devices`, `endpoints.endpoint-management`.

### 9. Security fundamentals: about 5.5 h so far
`security.security-fundamentals`, `windows-admin.accounts-and-permissions`, `networking.ports-and-firewalls`, `endpoints.protect-devices`, `foundations.ps-errors-and-debugging` (reading and auditing code).
*Built 2026-11-22 (drafts):* the **cybersecurity** path, `paths/cybersecurity.toml`, defensive first and own lab only: `security.authorization-and-scope`, `security.threat-modelling`, `security.own-lab-recon`, `security.linux-logging-and-detection`, `security.linux-hardening-checks`, `security.incident-response-linux`, plus the Windows side `security.windows-logging-and-detection` and `security.windows-hardening-checks` (Server 2022 only). *Still planned:* Windows 10/11 and domain coverage, vulnerability management, web application basics.

### 10. Home lab (stretch goal)
*Built 2026-11-22 (drafts):* `paths/home-lab.toml` with `networking.*` (all seven), the Linux basics, then `homelab.own-dns-and-dhcp` (dnsmasq), `homelab.file-sharing-samba`, `homelab.backups` (rsync, tar, restic) and `homelab.wireguard-and-exposure`. *Still planned, and not testable in the current VMs:* a firewall appliance (OPNsense or IPFire), a hypervisor (Proxmox, Hyper-V), Nextcloud, document and media servers, and monitoring.

### 11. Package repositories (stretch goal, added 2026-11-22)
`paths/package-repositories.toml`: `packaging.apt-repository`, `packaging.dnf-repository`, `packaging.apk-repository` (tested on Chimera; written for the owner's FenrirOS package repository, which the author has not seen) and `packaging.hosting-a-repository` (measured repository sizes, nginx, atomic publishing, mirroring, health-check scripts for apt, dnf and apk repositories).

## Choosing a first path (a short placement flow)

1. "What is your goal?" lists the paths above.
2. "How much do you already know?" offers *Start from the beginning*, *I know some of it* (open each lesson's quiz as a placement test, skipping the ones passed), or *Show me the whole path*.
3. The app opens the first lesson not yet known, with the rest of the path visible in the sidebar.

## Open design questions

- Placement threshold (80%?) and whether a "known" lesson should still count toward certification-domain coverage.
- Whether quizzes taken as placement tests record attempts the same way as normal attempts.
- How to show paths for stretch goals that depend on lessons not yet written (hide until a minimum number exist, or show with "coming soon").
- Whether the track picker should be the default front page of the app.

## Status (2026-11-21): what is built, and where it differs from the design

**Built and checked** (unit tests, `winlab check course`, and screenshots of the running window with a throwaway profile):
- `level = 1..5` in every lesson manifest (`manifest.zig`; optional, validated). Shown in the sidebar and the lesson header.
- `paths/<id>.toml` (nine paths: it-support, networking, windows-admin, windows-scripting, powershell-only, linux-admin, bash-scripting, endpoint-management, security-fundamentals), parsed and validated by `src/content/paths.zig`. `winlab check` reports unknown lesson or lab ids, repeats and unknown certification tags as problems, and a lesson whose prerequisite is not earlier on the path as a **warning**. `winlab paths` lists them with lesson count, hours and level range.
- Prerequisites are now **advice**: the header shows "Recommended first (not required)" with a button for each lesson not yet done. `foundations.powershell-basics` no longer requires `foundations.cmd-basics` (it recommends `foundations.architecture`).
- **Track picker** (first run when there is no progress, and under *Paths*): goal, audience, lesson count, hours, levels, progress. **Path sidebar**: stages with their hints and done counts. The choice and the last lesson open on each path are saved in `progress.toml` (`[state] path`, `[paths.<id>] last`) and restored on start. `all` means "I chose to see every lesson".
- **Statuses** `known` and `skipped` join the old three. `known` counts as done. **Placement:** the quiz button on a lesson not yet started (or skipped) reads "I already know this (quiz)"; a finished attempt of **80% or more** marks the lesson Known (`Progress.markKnownIfPassed`). A lesson already in progress or completed is not re-marked.

**Differences from the design above**
- `level_range` is not in the file; it is computed from the lessons on the path, so it cannot drift.
- A stage may list `optional` lessons (shown in the stage, not counted toward "done") and `labs` (validated; not yet shown in the sidebar).
- Path files use `order` (not file name) for the picker order.
- "Skip" is a status chosen from the Lesson menu or by cycling the status button; there is no separate Skip button.

**Not built yet**
- A path-level "continue where I left off" button on the picker (the window already reopens at your last lesson on the path).
- The Windows side of the cybersecurity path, the firewall appliance and hypervisor lessons of the home-lab path, and a dnf or apk version of the repository health check.
- The "all lessons" view still orders lessons inside an area by lesson id (so `bash-basics` sorts before `cmd-basics`); paths give the teaching order. A prerequisite-based order for that view would fix it.
- Not checked: 200% scale and Narrator. Driven in the running window (2026-11-21, synthetic mouse and key messages, throwaway profile): the placement quiz end to end (100% on an unstarted lesson saved `known`, the sidebar and header updated), Down-arrow navigation in path mode (two presses moved two lessons in path order), stage labs in the sidebar, and 150% text scale (found and fixed two layout problems: the Paths button was squeezed out and the header buttons were pushed off; the buttons now sit on their own row).
- Open questions below (threshold, whether Known counts toward certification coverage, whether placement attempts are recorded as normal attempts) are still open; today a placement attempt is an ordinary attempt.
