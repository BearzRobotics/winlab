# Deepening the lessons

Owner direction (2026-11-26), after testing the first lesson: a lesson must not show a command and move on. Every lesson needs depth, and diagrams help.

## The standard

For each command or example: **why you would run it, how to read what it prints, what is normal, and what to do next.** Add a diagram where a structure or flow is being explained (`docs/diagrams.md`). Everything in `docs/content-plan.md` still applies: run it for real, say what was and was not tested, cite official pages and check the links, keep quiz `review` headings, add questions for new material. The model is `course/foundations/architecture.md` (the owner said it looks a lot better, 2026-11-26).

## Where the lessons stand

`bash tools/lesson-depth.sh` measures each lesson. It is only a guide: it counts words and code blocks and cannot judge an explanation. A long lesson can still move past a command too fast, so **every lesson needs reading**, not just the short ones.

### Group 1: thin (under 600 words on 2026-11-26)

These are close to outlines and need to be written, not polished.

| Lesson | Words | Code blocks | Testing needs |
|---|---|---|---|
| `endpoints.protect-devices` | 339 | 2 | Windows; the Windows lab VM |
| `linux.storage-filesystems` | 359 | 5 | AlmaLinux and Ubuntu lab VMs |
| `windows-admin.registry-and-filesystems` | 368 | 3 | Windows; the Windows lab VM |
| `foundations.cmd-basics` | deepened 2026-11-26: reading dir/tree, overwrite and delete behaviour, which failures ERRORLEVEL shows, 2 diagrams, a broken line fixed (batteries `basics2.cmd`, `basics3.cmd`) |
| `foundations.cmd-variables-and-expansion` | deepened 2026-11-26: missing variables, watching expansion with echo on, silent arithmetic errors, 2 diagrams (`vars2.cmd`) |
| `foundations.cmd-control-flow` | deepened 2026-11-26: real loop output, CSV and silent-failure traps, robocopy codes, 2 diagrams (`flow2.cmd`) |
| `foundations.cmd-batch-files` | deepened 2026-11-26: the example script ran part of a folder name as a command; rewritten and tested with hostile names (`batch2.ps1`), 1 diagram |
| `foundations.cmd-text-and-files` | deepened 2026-11-26: reading fc and mirror output, findstr on LF and UTF-16 files, forfiles ages, 1 diagram (`text2.cmd`) |
| `foundations.cmd-advanced` | deepened 2026-11-26: **fixed a command injection in the input check**; array order, tasklist trap, recursion limit, 1 diagram (`adv3.cmd`, `adv4.cmd`, `adv5.ps1`). The CMD series is done |
| `foundations.powershell-basics` | deepened 2026-11-26: reading tables, Get-Member and SYNTAX, silent typo and comparison traps, the Format-Table trap shown, 2 diagrams (`basics2.ps1`) |
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
