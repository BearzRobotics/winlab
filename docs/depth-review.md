# Deepening the lessons

Owner direction (2026-11-26), after testing the first lesson: a lesson must not show a command and move on. Every lesson needs depth, and diagrams help.

## The standard

For each command or example: **why you would run it, how to read what it prints, what is normal, and what to do next.** Add a diagram where a structure or flow is being explained (`docs/diagrams.md`). Everything in `docs/content-plan.md` still applies: run it for real, say what was and was not tested, cite official pages and check the links, keep quiz `review` headings, add questions for new material. The model is `course/foundations/architecture.md` (the owner said it looks a lot better, 2026-11-26).

## Where the lessons stand

`bash tools/lesson-depth.sh` measures each lesson. It is only a guide: it counts words and code blocks and cannot judge an explanation. A long lesson can still move past a command too fast, so **every lesson needs reading**, not just the short ones.

### Group 1: thin (under 600 words on 2026-11-26)

These are close to outlines and need to be written, not polished.

**All of Group 1 had been rewritten by the end of 2026-11-26** (and the windows-scripting path of Group 2 reviewed); the table below records how they started. See Status for what each one now covers and what was not tested.

| Lesson | Words | Code blocks | Testing needs |
|---|---|---|---|
| `endpoints.protect-devices` | 339 | 2 | Windows; the Windows lab VM |
| `linux.storage-filesystems` | 359 | 5 | AlmaLinux and Ubuntu lab VMs |
| `windows-admin.registry-and-filesystems` | 368 | 3 | Windows; the Windows lab VM |
| `endpoints.endpoint-management` | 409 | 1 | Parts need a management service that is not set up here |
| `endpoints.update-and-policy` | 410 | 2 | Windows; the Windows lab VM |
| `linux.containers-podman` | 417 | 3 | AlmaLinux VM, internet to pull an image |
| `operations.operational-procedures` | 461 | 0 | Mostly practice and documents |
| `hardware.mobile-devices` | 503 | 0 | No test device: cite sources and say so |
| `hardware.hardware-concepts` | 557 | 2 | This PC for the commands |
| `security.security-fundamentals` | 585 | 1 | Windows and Linux |

### Group 2: the lessons being tested now

The `windows-scripting` path: the six CMD lessons and nine PowerShell lessons. They are long, but the owner is working through them, so review them in path order as feedback arrives.

### Group 3: everything else

By path, in the order the owner works through them.

## Order of work

1. Level of detail: use `foundations.architecture` (the owner said on 2026-11-26 that it looks a lot better).
2. Then, alternating so testing is never blocked: the next Group 2 lesson the owner will reach, and one Group 1 lesson (`registry-and-filesystems` first: it is next to what is being tested).
3. A few lessons at a time, each finished (tested, quizzed, checked) before the next, so the owner can review in small pieces.

## Status

| Lesson | State |
|---|---|
| `foundations.architecture` | rewritten 2026-11-26; owner: "looks a lot better", the SVG diagrams help (2026-11-26). All nine diagrams are SVG |
| `foundations.python-basics` | new 2026-11-26 to this standard, awaiting owner review |
| `windows-admin.registry-and-filesystems` | rewritten 2026-11-26 (host as standard user, Server 2022 VM elevated; 4 diagrams, 30 questions). Not tested: GUI tools, Windows 10, FAT32/exFAT/ReFS, repairs |
| `foundations.cmd-basics` | deepened 2026-11-26: reading dir/tree, overwrite and delete behaviour, which failures ERRORLEVEL shows, 2 diagrams, a broken line fixed (batteries `basics2.cmd`, `basics3.cmd`) |
| `foundations.cmd-variables-and-expansion` | deepened 2026-11-26: missing variables, watching expansion with echo on, silent arithmetic errors, 2 diagrams (`vars2.cmd`) |
| `foundations.cmd-control-flow` | deepened 2026-11-26: real loop output, CSV and silent-failure traps, robocopy codes, 2 diagrams (`flow2.cmd`) |
| `foundations.cmd-batch-files` | deepened 2026-11-26: the example script ran part of a folder name as a command; rewritten and tested with hostile names (`batch2.ps1`), 1 diagram |
| `foundations.cmd-text-and-files` | deepened 2026-11-26: reading fc and mirror output, findstr on LF and UTF-16 files, forfiles ages, 1 diagram (`text2.cmd`) |
| `foundations.cmd-advanced` | deepened 2026-11-26: **fixed a command injection in the input check**; array order, tasklist trap, recursion limit, 1 diagram (`adv3.cmd`, `adv4.cmd`, `adv5.ps1`). The CMD series is done |
| `foundations.powershell-basics` | deepened 2026-11-26: reading tables, Get-Member and SYNTAX, silent typo and comparison traps, the Format-Table trap shown, 2 diagrams (`basics2.ps1`) |
| `foundations.ps-variables-types-operators` | deepened 2026-11-26: references and clones, unset variables, regex characters, -contains, stale $Matches, one-or-many results, 1 diagram (`vars3.ps1`) |
| `foundations.powershell-control-flow` | deepened 2026-11-26: what break really does, switch over collections, streaming shown, loop traps, 1 diagram (`cflow2.ps1`) |
| `foundations.ps-functions-and-scripts` | deepened 2026-11-26: pipeline binding by property name, silent binding surprises, 1 diagram (`fn4.ps1`) |
| `foundations.ps-errors-and-debugging` | deepened 2026-11-26: reading error messages, errors that let a script continue and exit 0, 1 diagram (`err3.ps1`) |
| `foundations.ps-working-with-data` | deepened 2026-11-26: rewriting a file onto itself, what Compare-Object ignores, silent CSV problems, 1 diagram (`data3.ps1`) |
| `foundations.ps-modules-and-remoting` | deepened 2026-11-26: fixed a broken heading, reading Get-Job and module lists, 1 diagram (`jobs3.ps1`); the VM remoting results are from 2026-11-21 |
| `foundations.ps-system-admin-scripting` | deepened 2026-11-26: reading log properties and task result codes, safe-change diagram; VM results are from the earlier run |
| `foundations.ps-advanced` | deepened 2026-11-26: how to measure and read timings, logging diagram (`adv3.ps1`); VM logging results are from the earlier run |
| `endpoints.protect-devices` | rewritten 2026-11-26 (Server 2022 VM; 1 diagram; `protect1.ps1`, `protect2.ps1`); **fixed a wrong passive-mode claim**. Not tested: real traffic filtering, BitLocker, third-party antivirus, a management service, Windows 10 and 11 |
| `linux.storage-filesystems` | rewritten 2026-11-26 (AlmaLinux 9.8 VM; 2 diagrams, new LVM and 'why is it full' sections; `storage1.sh`). Not tested: a second disk, Ubuntu output, XFS growth, shrinking, boot with a broken fstab |
| `linux.containers-podman` | rewritten 2026-11-26 (AlmaLinux 9.8, Podman 5.8.2; 1 diagram; `podman1.sh`). Not tested: pulling, other distributions, user services, reboot, `--init`, `--no-cache` |
| `endpoints.endpoint-management` | rewritten 2026-11-26 (Server 2022 VM; 1 diagram; `endpoint1.ps1`). Not tested: Intune, Entra ID, Autopilot, a successful MSI install, client Windows |
| `endpoints.update-and-policy` | rewritten 2026-11-26 (Server 2022 VM; 1 diagram; `update1.ps1`). Not tested: installing updates, WSUS, MDM, domain GPOs, gpedit, client Windows |
| `operations.operational-procedures` | rewritten 2026-11-26 (worked examples, 2 diagrams; restore test `restore1.ps1` in 5.1 and 7.6). Examples are invented |
| `hardware.hardware-concepts` | rewritten 2026-11-26 (Server 2022 and AlmaLinux VMs; 1 diagram; `hw1.ps1`, `hw1.sh`). Not tested: physical hardware, RAID, SMART, POST codes |
| `hardware.mobile-devices` | rewritten 2026-11-26 (1 diagram; sources cited). **Nothing tested: no mobile device available**; needs a reviewer with real devices |
| `security.security-fundamentals` | rewritten 2026-11-26 (Server 2022 and AlmaLinux VMs; 1 diagram; `secfund1.ps1`, `secfund1.sh`). **Fixed:** 'deny wins' was too broad, and passwd -l does not stop SSH keys. Not tested: domain accounts, share permissions, POSIX ACLs, Ubuntu |
| `windows-admin.services-and-startup` | deepened 2026-11-26: every start failure reproduced with its real error and events, crash recovery, delayed start, task result codes, 1 diagram (`svc1.ps1`, `svc2.ps1`). The 'Nightly Cleanup' samples are illustrations |
| `windows-admin.accounts-and-permissions` | deepened 2026-11-26: every sign-in failure reproduced with messages and 4625 codes, lockout, what icacls changes and restores, 1 diagram (`acct1.ps1`). Not tested: domain accounts, client Windows, GUI |
| `foundations.troubleshooting-method` | deepened 2026-11-26: telling old event noise from new problems, halving a problem, 1 diagram (`method1.ps1`). The worked examples are illustrations |
| `networking.addressing-and-names` | deepened 2026-11-26: real configuration output on both systems, hosts file by tool, what refused and timed out look like (Test-NetConnection shows neither), 1 diagram (`net1.ps1`, `net1.sh`) |
| `networking.ports-and-firewalls` | deepened 2026-11-26: what each firewall action looks like to a client (**No route to host** from firewalld), UDP, rule counters (`ns1.sh`); fixed the Windows speed claim and the RDP lab's 'refused'. Windows firewall not tested from a second machine |
| `networking.routing-and-gateways` | deepened 2026-11-26: total metric versus RouteMetric (the lesson's sort was misleading), Find-NetRoute, bad gateways on both systems, which commands persist, 1 diagram (`route1.ps1`, `route1.sh`). tracert not tested |
| `networking.dns` | deepened 2026-11-26: reading dig output, the kinds of 'no' (+short and Resolve-DnsName hide them), TTL countdown, 1 diagram (`dns1.sh`, `dns2.ps1`). SERVFAIL not reproduced |
| `networking.dhcp` | deepened 2026-11-26: a real exchange from client, server log and capture; renewal; full pool and missing server look the same to the client; 1 diagram (`dhcp1.sh`). Not tested: Windows DHCP role, relay, rogue server |
| `networking.subnetting` | deepened 2026-11-26: worked answers machine-checked (5.1 and 7.6), a calculator, unequal subnet sizes, mismatched masks measured (no ARP reply), 1 diagram (`subnet1.ps1`, `mask1.sh`) |
| `networking.models-and-protocols` | deepened 2026-11-26: one request captured on both sides of a router (ARP, MACs, TTL, TCP flags, UDP), 1 diagram (`layers1.sh`) |
| `foundations.bash-basics` | deepened 2026-11-26: reading id, special permission bits, ps columns, df, free and uptime (Ubuntu 24.04 VM), 1 diagram (`basics2.sh`) |
| `foundations.bash-variables-and-expansion` | deepened 2026-11-26: reviewed (already detailed); added one line followed through every step, 1 diagram (`expand4.sh`) |
| `foundations.bash-control-flow` | reviewed 2026-11-26: already explains every trap with its output; added 1 diagram (loop input) |
| `foundations.bash-functions-and-scripts` | reviewed 2026-11-26: already detailed, with real output; added 1 diagram (lock descriptors) |
| `foundations.bash-text-processing` | reviewed 2026-11-26: already detailed; added the counting pipeline stage by stage, 1 diagram (`ts3.sh`) |
| `homelab.own-dns-and-dhcp` | reviewed 2026-11-26: already explains each result; added 1 diagram (test network). Tests are from the earlier run |
| `homelab.file-sharing-samba` | reviewed 2026-11-26: already explains each result; added 1 diagram (permission gates). Tests are from the earlier run |
| `homelab.wireguard-and-exposure` | reviewed 2026-11-26: already explains each result; its text drawing is now SVG. Tests are from the earlier run |
| `homelab.backups` | reviewed 2026-11-26: already explains each result; added 1 diagram (hard-link snapshots). Tests are from the earlier run |
| `packaging.apt-repository` | reviewed 2026-11-26: already explains each result; added 1 diagram (trust chain). Tests are from the earlier run |
| `packaging.dnf-repository` | reviewed 2026-11-26: already explains each result; added 1 diagram (two signatures). Tests are from the earlier run |
| `packaging.apk-repository` | reviewed 2026-11-26: already explains each result; added 1 diagram (layout). Tests are from the earlier run |
| `packaging.hosting-a-repository` | reviewed 2026-11-26: already explains each result; added 1 diagram (symlink swap). Tests are from the earlier run |
| `security.own-lab-recon` | reviewed 2026-11-26: already explains each result; added 1 diagram (who can reach a listener). Tests are from the earlier run |
