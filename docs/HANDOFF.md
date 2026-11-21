# WinLab handoff (2026-11-21)

Read this first. It says what the project is, what was done in the long scripting-and-networking session, how to keep working, what is unfinished, and what is *not* verified. Nothing is running in the background: all VMs are stopped and restored to their clean snapshots, and QEMU has no processes.

## 1. One-paragraph status

WinLab is an offline-first Windows and Linux administration course app (Zig 0.17.1, DVUI on the dx11 backend). The GUI migration to DVUI is finished. This session added, in depth and with verified output: the **networking track** (7 lessons), the **core foundations and Windows lessons**, the **whole CMD series** (6 lessons), and **all 9 planned PowerShell lessons**, each with a **large quiz bank**. The course validates with **40 lessons, 54 labs, 9 learning paths and 28 quiz files with 1,340 questions, 0 problems** (`winlab check course`), and `zig build test` passes. All lessons are **drafts for the owner's review**; the owner has not read them through in the GUI.

## 2. Where things are

| What | Where |
|---|---|
| Project | `C:\Users\Dakota\winlab` (**not a git repository**, see section 9) |
| Lessons | `course\<area>\<id>.md` + `.toml` manifest (areas: `foundations`, `networking`, `windows-admin`, `linux`, `security`, `operations`, `hardware`, `endpoints`) |
| Quizzes | `quizzes\<lesson-id>.toml` (format and rules: `docs\quizzes.md`) |
| Labs | `labs\*.toml` (54) |
| Official docs cache | `reference\` (README has the takedown notice; `MANIFEST.md` lists what is stored; `fetch.ps1 -Check` verifies) |
| Plans and rules | `docs\content-plan.md`, `docs\scripting-curriculum.md`, `docs\quizzes.md`, `docs\decisions\0001`-`0008` |
| Verification scripts | `tests\verification\powershell\*.ps1` and `tests\verification\cmd\*.cmd` (every snippet battery I ran; see section 6) |
| Built exe | `zig-out\bin\winlab.exe` (only the exe and pdb; content is **not** copied there any more) |
| Memory notes (for the AI assistant) | `C:\Users\Dakota\.claude\projects\C--Users-Dakota-winlab\memory\` |

`winlab.exe` finds the course through, in order: the source tree around the exe (`zig-out\bin\..\..` when it has `build.zig` and `course\`), the `content-path` setting, the exe folder, `%APPDATA%\WinLab`, the current directory. `zig build -Dbundle-content=true` makes a self-contained folder.

## 3. What is done

### Application
- GUI on DVUI: sidebar grouped by area, code highlighting (PowerShell, bash, cmd), notes pane, quizzes (random subset per attempt, missed questions return first, results stored in `%APPDATA%\WinLab\progress.toml`), labs panel, links confirmed before opening.
- Reader changes this session: consecutive paragraphs, headings and simple lists share **one** text widget so a drag selects across them; selections clear when you click elsewhere; "Check yourself" answers are hidden behind a **Show answers** button; code blocks have **Copy**; Lesson menu has **Copy whole lesson (Markdown / plain text)**; View menu has **Plain-text view** (md-zig's terminal renderer).
- QEMU 11.1.0 was reinstalled with winget (`SoftwareFreedomConservancy.QEMU`, in `C:\Program Files\qemu`); the old MSYS2 copy is gone. The "QEMU not found" message now mentions winget first.

### Lessons (all drafts)
| Area | Lessons |
|---|---|
| Networking (7) | `models-and-protocols`, `addressing-and-names` (overview + bottom-up routine), `subnetting`, `dhcp`, `dns`, `routing-and-gateways`, `ports-and-firewalls` |
| Foundations, general (2) | `troubleshooting-method`, `architecture` |
| CMD (6) | `cmd-basics`, `cmd-variables-and-expansion`, `cmd-control-flow`, `cmd-batch-files`, `cmd-text-and-files`, `cmd-advanced` |
| PowerShell (9 of 9) | `ps-advanced`, `ps-system-admin-scripting`, `powershell-basics`, `ps-variables-types-operators`, `powershell-control-flow`, `ps-functions-and-scripts`, `ps-errors-and-debugging`, `ps-working-with-data`, `ps-modules-and-remoting` |
| Windows admin (2 of the Windows plan) | `accounts-and-permissions`, `services-and-startup` (rewritten in depth) |
| Older, still thin (not yet deepened) | `bash-basics`, `bash-control-flow`, `windows-admin.registry-and-filesystems`, `linux.*`, `security.*`, `operations.*`, `hardware.*`, `endpoints.*` |

Every deepened lesson has: inline official citations (each URL checked with a request), real command output, the shell route **and** the GUI route, common mistakes, a "read this script/function" exercise where relevant, practice items and check questions, and a quiz bank (about 40 to 55 questions, drawn 10 at a time).

## 4. The owner's rules (follow these; they override defaults)

**Course design**
- Windows 10 is the oldest client; Windows 11 Pro is the default. Teach every Windows topic from the **GUI and from the shell** (PowerShell and CMD). Never drop the GUI.
- **Cite official documentation inline**, verify every URL, show real output. Do not state anything unverified as fact; say what was and was not tested.
- Tracks are goal-based paths, not a forced beginning-to-end order. Hand-holding fades with level; advanced lessons point to the docs (open-book).
- Packages: touch apt, dnf, pacman and apk (apk is the owner's own distro's manager). **Limited internet**: be sparing with downloads; let the learner choose big ISOs; never bundle them.
- Lessons stay **drafts for owner review**. The reference folder mimics the `assembly-first-programming` pattern but lives **here** (do not add to that other repo).

**Scripting (the main current effort; `docs/scripting-curriculum.md`)**
- Goal: learners become "the ones script kiddies rely on": write original tools, **read and audit others' code**, understand why. Explain parsing and why; teach read-before-run; show traps with real output.
- **Never use aliases in scripts** (full cmdlet and parameter names). Aliases differ by platform; on Linux pwsh has no `ls`, `rm`, `cp`, `mv`, `cat`, `mkdir`, `ps`, `kill`, `sleep`, `sort`, `curl`, `wget`, `man`, `clear` aliases.
- **External programs in PowerShell on Windows: write `tool.exe` and keep the folder on `PATH`** so an alias or function cannot intercept it (`where` is `Where-Object`; `curl` is `Invoke-WebRequest` in 5.1 and `curl.exe` in 7). In cmd this does **not** reliably escape built-ins (`echo.exe hi` printed `exe hi`), so use full paths for colliding names. For bash the same idea is `command -v`, `type -a`, `command tool`, full paths, a safe `PATH`.
- **Bash is not a POSIX shell.** A bash script starts `#!/usr/bin/env bash`, **never** `#!/bin/sh`. A `#!/bin/sh` script must be strictly POSIX (dash, yash, util-core `sh`, FreeBSD `sh`, busybox `ash` are real `sh` on many systems). Always say which shell a snippet is for.
- **systemd is mandatory** teaching content; dinit (the owner's distro) is a short aside only.
- **ShellCheck** is an optional tip (not installed by default). PSScriptAnalyzer is its PowerShell counterpart (not installed by default; 13.98 MB from the Gallery).
- Microsoft recommends **VS Code with the PowerShell extension** for writing scripts (optional; the lesson says so). Microsoft Edit (`edit`, MIT, ships in Windows 11, `winget install Microsoft.Edit`) is the terminal-editor mention.
- Planned stretch tracks (in `docs/content-plan.md`): cybersecurity and penetration testing (defensive first, own lab only) and a **home lab** track (OPNsense or IPFire, own DNS server, Proxmox and Hyper-V, Samba and Nextcloud, document and media servers). Extra distros (FreeBSD, OPNsense, IPFire, Alpine) are opt-in catalog entries; a learner doing the install by hand is wanted. WSL is an acceptable optional dependency, like QEMU; never install software for the user.

## 5. How to work

```
cd C:\Users\Dakota\winlab
zig build                                  # installs exe only; close any WinLab window first
zig build test                             # unit tests
zig-out\bin\winlab.exe check course        # validates lessons, labs and quizzes (0 problems expected)
zig-out\bin\winlab.exe browse course       # the GUI (running with no arguments also opens it)
zig-out\bin\winlab.exe coverage [exam-id]
```

Writing a lesson, in the order I used: (1) read the existing lesson and its labs; (2) **write a test script and run it** on every relevant platform (see section 6); (3) write the lesson from the real output; (4) verify every cited URL (HEAD request, expect 200; some Microsoft `about_` and command pages 404 under other names, so check); (5) write the manifest (`.toml`: objectives, `prerequisites`, `references`, `certifications` tags that exist in `certs\catalog.toml`); (6) write the quiz bank; (7) `winlab check course`.

Quiz authoring rules (`docs/quizzes.md`): every question has an `explanation`; `review` text **must appear in the lesson** (a heading or phrase) or `check` fails; `choice` answers must equal one choice's text exactly; `multi` needs at least one wrong choice; `short` lists every accepted spelling. Banks are about 4 to 5 times the draw size.

**Shell-quoting pitfalls that bit me repeatedly** (use the Write and Edit tools instead of shell for file text): Git Bash strips or doubles backslashes in heredocs and `sed`; `perl -0pi` with `|` delimiters turns `\|` into alternation and corrupted `md_view.zig` once (it was repaired by hand; **there is no git history**); nested PowerShell here-strings end the outer one early; Git Bash mangles `/home/...` paths passed to `wsl` (run `wsl` from the PowerShell tool). After a bulk quiz append, fix `]answers = [` glued onto one line with `sed -i 's/\]answers = \[/]\nanswers = [/'`.

## 6. Test environments and how to use them

| Environment | Use |
|---|---|
| Windows host (Windows 11 Home, build 26300) | Windows PowerShell 5.1 (`powershell.exe`), PowerShell 7.6.10 (`pwsh`), cmd. This session's tool wrapper sets `NoDefaultCurrentDirectoryInExePath=1` in the process environment; clear it to test the default cmd behaviour (`Remove-Item Env:NoDefaultCurrentDirectoryInExePath`). |
| WSL2 Ubuntu 26.04 (`wsl -d Ubuntu-26.04`) | PowerShell 7.6.10 unpacked at `/home/dakota/pwsh/pwsh` (libicu78 installed with apt). Run it from the **PowerShell** tool: `wsl -d Ubuntu-26.04 -- /home/dakota/pwsh/pwsh -NoProfile -File /mnt/c/Users/Dakota/AppData/Local/Temp/wl-ps-demo/x.ps1`. The owner gave the sudo password in chat; it is **not** stored anywhere. Intended also for testing bash, dash and ShellCheck for the bash lessons (not yet used). |
| Lab VMs (QEMU, WHPX) | `winlab-lab-c` Server 2022, `winlab-linux` Ubuntu 24.04, `winlab-alma` AlmaLinux 9, spare `winlab-server2022`. Each has a `winlab-clean` snapshot. |

`tests\verification\` holds the batteries I ran (they write only to temp folders): CMD (`v.cmd`, `cf.cmd`, `bf.cmd`, `tf.cmd`, `adv.cmd` ...) and PowerShell (`data1.ps1`, `err.ps1`, `fn.ps1`, `mod1.ps1`, `rem1.ps1`, `rem2.ps1`, `sshrem.ps1`, `linux.ps1`, `curltest.ps1` ...). `srv.ps1` and `srv2.ps1` are throwaway local HTTP servers so web examples need no internet. Re-run them when a lesson changes.

### Reaching a lab VM (how I tested remoting and elevated commands)
1. `zig-out\bin\winlab.exe lab start labs\spooler-stopped.toml winlab-lab-c` boots the VM (it snapshots first). It prints a long memory-leak report on exit: see section 8, item 3. The VM keeps running.
2. SSH details are in `%LOCALAPPDATA%\WinLab\vms\winlab-lab-c\guest.toml` (`ssh_port`, `ssh_user = Administrator`), with `id_ed25519` and `known_hosts` in the same folder and the password in `credentials.txt` (clear text, throwaway VM). Example from Git Bash: `ssh -i $D/id_ed25519 -p 44024 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=$D/known_hosts Administrator@127.0.0.1 '<powershell command>'`. The guest's SSH login shell is **Windows PowerShell 5.1**, so quote for PowerShell (`;` not `&&`). Copy scripts with `scp -P <port> -i <key>`.
3. Run an **elevated** test there (the SSH Administrator session is elevated). Use an **explicit `-Credential`** for WinRM loopback (an SSH logon cannot reuse credentials: a second hop). Give remoting calls `-OperationTimeout`/`-OpenTimeout` (`$PSSessionOption = New-PSSessionOption ...`) because a stuck call otherwise hangs the whole SSH command.
4. `zig-out\bin\winlab.exe lab end labs\spooler-stopped.toml winlab-lab-c` stops the VM and **restores the pre-lab snapshot**, which also undoes anything I changed in the guest. Always end with this.

## 7. Verified findings worth knowing (they are in the lessons)

- CMD: unquoted `cd C:\Program Files` works but `dir C:\Program Files` fails; `echo 1> f` writes `ECHO is off.`; `if errorlevel N` means N or greater; a `::` comment as the **last** line of a block is a syntax error; `%ProgramFiles(x86)%` inside a block closes it; running a batch file without `call` never returns; `for /f` skips blank lines and the default `eol=;`; `findstr` silently ignores `{n}` counts; `robocopy` exit codes are a bit mask (0-7 success).
- PowerShell: aliases beat functions; `catch` misses non-terminating errors; `$x -eq` on an array filters; `[int](2.5)` is 2; `ConvertTo-Json` flattens past depth 2; `@(7) | ConvertTo-Json` gives `7`; `-Path` treats `[1]` as a wildcard; 5.1 `>` writes UTF-16, `Set-Content` writes ANSI; `curl` differs between 5.1 and 7; WinRM loopback needs an explicit credential over an SSH login; remoted and job results are serialized (no methods).
- PowerShell Gallery package sizes (read from the Gallery's own metadata, nothing downloaded): ThreadJob 0.03 MB, SecretManagement 0.08 MB, PSReadLine 0.22 MB, Pester 0.44 MB, PSResourceGet 4.09 MB, PSScriptAnalyzer 13.98 MB.

## 8. Unfinished and known problems

1. **Remoting over SSH is now verified (Windows target, 2026-11-21)**: the earlier failure was a `Subsystem powershell` line placed after the `Match Group administrators` block in `sshd_config`; placed above the `Match` block (next to the `sftp` line) `testserificationpowershellsshrem.ps1` passes. Still untested: a Linux target, and the lab VM does not keep PowerShell 7 (the snapshot restore removes it; the zip is a 109 MB download from the PowerShell GitHub release).
2. **`ps-system-admin-scripting` is written (2026-11-21, draft)**: read-only parts run on the host (5.1 and 7.6.10), elevated parts in the Server VM (5.1); batteries are `tests\verification\powershell\sysadmin1.ps1` (host), `sysadmin2.ps1` and `sysadmin3.ps1` (VM). 56-question quiz. **Untested and said so in the lesson:** Security log from a non-elevated prompt, Windows 10, Linux (n/a). **Unexplained:** `Start-Service Spooler` failed once in the VM right after `Stop-Service` (empty error text) in `sysadmin2.ps1`; later it worked, so the lesson uses `BITS` for demos. Also observed: PowerShell 7.6.10 here still has `Get-WmiObject`, `Get-EventLog` and `New-EventLog` (older docs say they are gone; recheck on another 7 install before teaching it as a rule). The lesson does not yet have a `level` field (the manifest parser has no such key; add it with the learning-paths work).
3. **`winlab lab start` leaks memory at exit** in the debug build (a `SafeAllocator` report: `leaked [len: 1312]`, allocated from a `dupe`). Harmless to behaviour but noisy; find the `dupe` in the lab-start path and free it.
4. **Unclicked GUI features**: the Copy buttons, "Copy whole lesson" menu items, Plain-text view and the Show answers button were built and seen, but I did not click Copy or the plain-text view, and not at 150%/200% DPI or with Narrator. Plain-text view shows the answers (it is one block). Multi-select quiz clicks were never driven.
5. **Unverified in the lessons** (state of knowledge, not tested): Linux commands in the networking lessons (`ss`, `firewall-cmd`, `ufw`, `resolvectl`); the GUI Environment Variables dialog steps; the cmd admin-check elevated branch; PSScriptAnalyzer and Pester runs; the debugger commands (`s`, `v`, `o`, `c`); `New-NetRoute`'s default store; whether restore points are rate limited.
6. Old lab verification backlog (appendix B): five Windows and AlmaLinux labs were never verified.
7. Certification domain titles in `certs\catalog.toml` were never checked against the vendors' current objectives.

## 9. Version control

The project is now a **local git repository** on branch `main` (created 2026-11-21 at the owner's request, after a session with no history in which one file was corrupted and repaired by hand). The first commit holds everything. There is **no remote yet**; section 13 says how to create one. Commit small and often from now on, and run `winlab check course` before each commit.

What is tracked and what is not (`.gitignore`): `.zig-cache/`, `zig-out/` and `*.pdb` are ignored. **`zig-pkg/` is tracked**, as ADR 0003 decides (offline, reproducible builds; about 127 MB and 3,357 files, the largest 22 MB, so well under GitHub's 100 MB per-file limit). The working tree is large (about 130 MB with `zig-pkg/`); the compressed `.git` folder after the first commit is about 38 MB.

The commit **author identity is set locally** (`git config user.name` and `user.email` in this repo) to the owner's name and the email address on their account. If the repository will be public, change it before the first push so the email is not published: `git config user.email "<id>+<username>@users.noreply.github.com"` and `git commit --amend --reset-author --no-edit` (only safe before anything is pushed).

## 10. What to do next, in order

0. **Learning paths: built (2026-11-21)**, see "Status" at the end of `docs/learning-paths.md`. New lessons need a `level` (1-5) in their manifest and a place in `paths/*.toml` (`winlab check` validates both; `winlab paths` lists them). Remaining: home-lab and cybersecurity paths, drive the placement quiz and path keyboard navigation in the window, DPI check.
1. **PowerShell series is complete (9 of 9)**: `ps-advanced` is written (2026-11-21, draft; battery `adv1.ps1` on 5.1, 7 Windows and 7 Linux; `adv2.ps1` script block logging in the VM; 50-question quiz). Untested and said so: App Control or AppLocker enforcing CLM, module logging, transcription by policy, macOS. Possible follow-ups: re-point the labs `script-ps-rename-files` and `script-ps-switch-classify` if they fit better elsewhere; a Linux SSH-remoting target.
2. **Bash and POSIX sh series (in progress, 2026-11-21)**: done so far, as drafts with verified output and quiz banks: `foundations.shells-and-posix` and `foundations.bash-variables-and-expansion` (both in the `bash-scripting` and `linux-admin` paths). Still to write, in order: deepen `bash-basics` (its shebang says `#!/bin/bash`, should be `#!/usr/bin/env bash`) and `bash-control-flow` (with new test runs), `bash-functions-and-scripts`, `bash-text-processing`, `bash-robust-scripts`, `bash-advanced`, `posix-sh-scripting`, then `linux.systemd`. Outline in `docs/scripting-curriculum.md`. Batteries: `tests/verification/bash/*.sh` (run from the **PowerShell** tool with `wsl -d Ubuntu-26.04 -- bash /mnt/c/Users/Dakota/winlab/tests/verification/bash/<file>.sh`). **Do not pass snippets through `wsl -- bash -c '...$var...'`: `wsl.exe` re-parses the line and empties `$var`; put the test in a script file.** Test tools live in WSL under `~/tools` (not in the repo): ShellCheck 0.11.0 (`~/tools/shellcheck-v0.11.0/shellcheck`) and busybox 1.35.0 (`~/tools/busybox`, use `busybox ash`), both static binaries downloaded from their publishers (hashes recorded in the session, not compared with a publisher list). WSL has bash 5.3.9, dash 0.5.12, gawk and mawk. `gnu.org` was unreachable from this network, so the bash manual is cited at `tiswww.case.edu/php/chet/bash/bashref.html`.
3. **Windows admin lessons**: deepen `windows-admin.registry-and-filesystems`; then event logs and monitoring, updates and manual patching, storage and disks, remote management, automated Windows install (answer files; `vm/unattend.zig` exists), program installs (msi, exe, winget, DISM), OpenSSH on Windows and Linux, System Internals (advanced, Sysinternals only in the labelled advanced track), Active Directory (needs the multi-VM lab, ADR 0008, and a Server eval ISO).
4. **App work**: a GUI **Lab machines** page (image catalog, download and build with progress, QEMU hint with winget first); FreeBSD and OPNsense catalog entries (verify image names first); optional WSL "build from ISO" path.
5. **Content still planned**: remaining core lessons (`linux.*`, `security.*`, `operations.*`, `hardware.*`, `endpoints.*`), the stretch cybersecurity and home-lab tracks, generated (fresh-number) and ordering questions for quizzes, a weak-domain view, assessments and mastery tracking.
6. **Housekeeping**: `git init`; update `reference\gen_manifest.ps1` so the docs cited by the new lessons are cached if wanted (section C of `MANIFEST.md` lists unstored URLs; downloads cost internet).

## 11. Open questions for the owner

- Should the home-lab track assume a spare physical machine or work entirely in VMs? (I assumed VMs.)
- Is Proxmox a lesson to read or a lab to run? (Nested virtualization under WHPX is unverified.)
- Publish to GitHub? Licence? Does `reference\` ship?
- Windows 10 depth, Server 2025 as a second target, which certifications matter most (still open from `outline.md`).
- Which of the "Windows tackle" items in the owner's last message was meant: the owner wrote "tackle windows" after the bash note; I read it as the Linux and bash side. Confirm.

## 12. Learning paths (built 2026-11-21)

The course is already about **39 hours** of estimated lesson time across 38 lessons (a single path is about 2 to 25 hours; paths overlap, so they do not add up), and far more is planned. A learner with a goal (help desk, networking, Windows admin, scripting, Linux, MD-102, security, home lab) should not have to do every lesson in order, and may already know some of it. The owner asked for this to be recorded; it is **designed but not implemented**.

Full design and the first ten path definitions (real lesson ids, estimated hours, entry points, planned additions) are in **`docs/learning-paths.md`**. In short:

- **Goal first.** A track picker offers paths; a path is an ordered, staged list of lessons and labs. Progress stays **per lesson**, shared across paths.
- **Prerequisites become recommendations**, shown as warnings, never locks. This fixes a current problem: `foundations.powershell-basics` requires `foundations.cmd-basics`, which forces PowerShell-only learners through CMD.
- **Test out with the quiz:** taking a lesson's quiz first (proposed 80% or more) marks it *Known* and skips it. The quiz banks already exist.
- **Levels:** add `level = 1..5` to every lesson manifest; hand-holding fades with level.
- **Data and code to build:** a `paths\<id>.toml` content folder validated by `winlab check`; a track picker; a sidebar switch between "all lessons by area" and "a path by stage"; per-lesson status (Not started, In progress, Completed, Known, Skipped); an "I already know this" button that opens the quiz.
- **Paths defined so far:** IT support (about 11 h), Networking (6 h), Windows administrator (12 h), Windows scripting CMD and PowerShell (21 h), PowerShell only (12 h), Linux administrator (8 h), bash and POSIX scripting, Endpoint management (4.5 h), Security (5.5 h), Home lab (stretch).

The design and what was built vs. changed are in `docs/learning-paths.md`. Statuses are now Not started, In progress, Completed, Known (quiz 80% or more before starting) and Skipped. The GUI was verified with screenshots using a throwaway profile (`APPDATA` pointed at a temp folder so the real progress file is untouched; the script is easy to recreate: `Start-Process`, `PostMessage` mouse messages to the main window, `PrintWindow`).

## 13. Creating the remote repository

There is no remote yet and the `gh` CLI is not installed (`winget install GitHub.cli` gives it, about the size of a normal CLI tool; it needs the owner to run `gh auth login` interactively, so do not try to do that unattended). Two routes, and the owner decides the open questions first.

**Decide first (owner):**
1. **Name and owner/organisation** of the repository (for example `<user>/winlab`).
2. **Visibility:** private while the lessons are drafts is the safe default; public later.
3. **Licence.** There is no `LICENSE` file. The project's own dependencies are MIT (md-zig, toml-zig, pdf-zig) and DVUI is its own licence; check `zig-pkg\*\LICENSE` before choosing. The lessons are written content: consider a content licence (for example CC BY-SA 4.0) separate from the code licence (for example MIT or Apache-2.0 or GPL).
4. **Does `reference\` ship?** It holds third-party documentation under mixed licences (CC-BY-4.0, CC0, GPL-2.0, IETF Trust) with a takedown notice and attribution in `reference\README.md`. Keeping it in a public repo is the owner's call; the alternative is to ignore the folder and keep only `fetch.ps1` and `MANIFEST.md`, so a clone re-downloads it.
5. **Commit author email** (see section 9): use a GitHub no-reply address if the repo is public.
6. **Large vendored folder:** `zig-pkg\` is about 127 MB. That is allowed by GitHub, but clones are slow; the alternative (ignore `zig-pkg\` and fetch with `zig build`) contradicts ADR 0003's offline-build rule, so only change it deliberately.

**Route A, the GitHub website (no extra tools):**
1. On github.com choose *New repository*. Name it, set visibility, and **do not** tick "Add a README", ".gitignore" or a licence (the local repo already has history).
2. In the project folder:
   ```
   git remote add origin https://github.com/<owner>/<repo>.git
   git branch -M main
   git push -u origin main
   ```
   Git for Windows will prompt to sign in through the browser (Git Credential Manager).

**Route B, the GitHub CLI:**
```
winget install GitHub.cli
gh auth login
gh repo create <owner>/<repo> --private --source . --remote origin --push
```
(`--private` or `--public`; `--push` pushes `main`.)

**After the first push:**
- Add a `LICENSE` and a short `README` section "Contributing / reviewing" (the owner reviews lessons as first user; consider using GitHub issues or pull requests for review comments).
- Consider a GitHub Action running `zig build test` and `winlab check course` on Windows (the build needs Zig 0.17.1 and, for the full course check, nothing else; the VM labs cannot run in CI).
- Protect `main` (require the check to pass) once someone else contributes.
- Rotate nothing: there are no secrets in the repo (a scan found only lesson text about passwords and a toy `p@ss` in a test script). The lab VM passwords live under `%LOCALAPPDATA%\WinLab\vms\*\credentials.txt`, outside the repo; **never commit that folder**.
- Releases: `zig build -Dbundle-content=true` makes a self-contained folder to zip as a release asset.

## Appendix A. Standing decisions from the earlier handoff

- Teach with stock Windows tools in the core course. Sysinternals only in a separate, labelled advanced track, never bundled (ADR 0007).
- Windows 11 **Pro** is the default client. Domain (multi-VM) labs are in scope.
- Both Ubuntu and AlmaLinux are supported. Certification tags mean "supports this domain", not "passes this exam".
- Every lab must pass `lab verify` before it is called done. Do not claim unverified results.

## Appendix B. Lab verification status (from 2026-11-08, still current)

**Verified with `lab verify` (fails broken, passes after solution, fails again after reset):** `alma-fstab-mount-missing`, `alma-lvm-extend` (threshold later lowered from 70 to 65 MB, not re-run), `linux-service-loopback-only` (Ubuntu and AlmaLinux), `alma-container-service-fails` (needs internet at build time to pull `quay.io/almalinux/almalinux:9`), `windows-updates-blocked`, `firewall-profiles-off`. Also verified this session: `labs.linux-service-disabled` self-test passed on Ubuntu with the new QEMU.

**NOT verified. Resume here:**
- `gateway-route-override` (Windows). The first version hung the build for 48 minutes because the fault script removed and re-added the adapter address over the SSH channel. Redesigned (disable DHCP, replace the default route with a bad next hop 10.0.2.99). A second run was killed with no result. If it hangs again: a static route with a metric low enough to win, applied through the persistent store, or a hosts/DNS-style fault.
- `policy-blocks-task-manager` (Windows). Setup now ends with `; exit 0`; not re-run.
- `alma-sudo-access-lost`, `alma-ssh-root-login`, `alma-journal-volatile` (AlmaLinux). Verification was interrupted.
- The `spooler-stopped` Windows self-test started on `winlab-lab-c` this session printed `[2] setup` and then its output stopped; its result was not seen. `winlab lab verify labs\spooler-stopped.toml winlab-lab-c` should settle it.

`lab verify` and `lab build` take `<lab.toml> <vm-id>` in that order. If a build was interrupted use `lab build ... --rebuild`; the `winlab-clean` snapshot is the recovery point.

## Appendix C. Lab and VM pitfalls (still current)

- A PowerShell script run in the guest reports the exit code of its **last** statement; add `; exit 0` when the last command may legitimately fail.
- Never change the guest's network address, or tear down the interface that carries SSH, in a lab fault: the control call never returns.
- Windows persistent routes: `New-NetRoute -PolicyStore PersistentStore` is invalid for a default route; a route with a worse metric than the DHCP default does not take effect.
- A lab fault must survive a guest reboot; `lab verify` proves it.
- Do not leave a `browse` window open when running `zig build` (the install step cannot overwrite the running exe).
- QEMU facts: Windows reserves moving TCP port ranges (pick ports by test-binding); a guest restart inside one QEMU process hangs SeaBIOS (so `-no-reboot` plus a relaunch supervisor); `-cpu max` for x86-64-v2 guests; use plain `-accel whpx`. See ADR 0006 and the memory file `winlab-qemu-vm-facts`.
