# Scripting curriculum (owner direction, 2026-11-21)

Goal: a learner finishes feeling **very competent** at Windows scripting in both **CMD** and **PowerShell**, and at **bash** and **POSIX sh** on Linux. Each language is taught in depth across several lessons, with advanced features. Every lesson cites the official documentation, shows real output, has a quiz bank, and fades hand-holding with level (see `docs/content-plan.md`).

## Rules for the bash and sh lessons (owner)

- **Bash is not a POSIX shell.** It can run POSIX scripts, but many bash features are not POSIX. A script that uses bash features must start `#!/usr/bin/env bash` (or `#!/bin/bash`), **never** `#!/bin/sh`.
- A script that starts `#!/bin/sh` must use **only POSIX features**, because `sh` on many systems is not bash: dash (Debian, Ubuntu), yash, the owner's util-core `sh`, FreeBSD's `sh`, busybox `ash` (Alpine). Do not break a system whose `sh` is a real POSIX shell by feeding it bashisms.
- The lessons must say which shell they mean at every step and teach the difference, including a bashism checklist and how to test a script against dash.
- **systemd is a must.** Every major distribution uses it. Teach units, targets, timers, `systemctl`, `journalctl`, writing and overriding units. Other init systems (the owner's dinit) get at most a short aside.

## Planned lessons

Each line is one lesson; the existing ones are deepened, not replaced. IDs are `foundations.*`.

### CMD
1. `cmd-basics` (exists): navigation, commands, redirection, pipes, environment, help.
2. `cmd-variables-and-expansion`: `set`, `%var%`, `setlocal` and delayed expansion `!var!`, substring and replace, `set /a`, `set /p`, `%~` modifiers, `errorlevel`.
3. `cmd-control-flow` (exists): `if`, `for` in all forms (`/f /l /r /d`), `goto`, `call`, `&&` and `||`.
4. `cmd-batch-files`: arguments and `shift`, subroutines with `call :label`, `exit /b`, return codes, logging, quoting and escaping (`^ & | < > %`), error handling.
5. `cmd-text-and-files`: `findstr`, `find`, `sort`, `more`, `type`, `robocopy`, `xcopy`, `forfiles`, parsing with `for /f`, dates and locale pitfalls.
6. `cmd-advanced`: delayed-expansion traps, emulated arrays, parsing tricks, calling PowerShell from batch, scheduled use, when to stop using CMD.

### PowerShell
1. `powershell-basics` (exists): cmdlets, `Get-Help`, `Get-Command`, objects in the pipeline, `Get-Member`, formatting, providers.
2. `ps-variables-types-operators`: types, strings and here-strings, arrays, hashtables, operators, `$null`, regex, casting.
3. `powershell-control-flow` (exists): `if`, `switch` (regex, wildcard), loops, `foreach` versus `ForEach-Object`.
4. `ps-functions-and-scripts`: `param`, advanced functions, `[CmdletBinding()]`, validation, pipeline input (`begin/process/end`), splatting, scope, dot-sourcing, comment-based help.
5. `ps-errors-and-debugging`: terminating versus non-terminating errors, `try/catch/finally`, `$ErrorActionPreference`, `$?` and `$LASTEXITCODE`, streams, `Set-StrictMode`, debugging, Pester basics.
6. `ps-working-with-data`: files, CSV, JSON, XML, `Select/Where/Group/Sort/Measure`, calculated properties, `Select-String`.
7. `ps-modules-and-remoting`: modules, profiles, execution policy, signing, remoting over WinRM and SSH, jobs, parallelism.
8. `ps-system-admin-scripting`: CIM, the registry provider, services, event logs, scheduled tasks, idempotent scripts, `-WhatIf` and `-Confirm`.
9. `ps-advanced`: classes, .NET interop, performance, security (constrained language mode, script block logging), Windows PowerShell 5.1 versus PowerShell 7.

### Bash and POSIX sh
1. `bash-basics` (exists).
2. `shells-and-posix`: what a shell is; bash versus POSIX sh (dash, yash, util-core sh, FreeBSD sh, busybox ash); shebang rules; a bashism checklist; testing against dash.
3. `bash-variables-and-expansion`: quoting, parameter expansion, arrays and associative arrays, brace and glob and extglob, command substitution, arithmetic, process substitution.
4. `bash-control-flow` (exists): `[[ ]]`, `case`, loops.
5. `bash-functions-and-scripts`: functions and `local`, `getopts`, here-docs, `trap`, exit codes, `mktemp`, logging, lock files.
6. `bash-text-processing`: grep, sed, awk, cut, sort, uniq, tr, find, xargs, regular expressions.
7. `bash-robust-scripts`: `set -euo pipefail` and its limits, idempotence, ShellCheck, tests, debugging with `set -x` and `PS4`, signals, security.
8. `bash-advanced`: `mapfile`, namerefs, `printf -v`, `declare`, `shopt`, completion, avoiding forks, bash 3.2 versus 4 and 5.
9. **A dedicated POSIX sh section (owner suggestion, 2026-11-21), with dash as the reference shell** and busybox ash as the second check; every command in it is run in dash, and `bash` is never used to "test" a `#!/bin/sh` script. Planned lessons: `posix-sh-basics` (the language subset: quoting, `$( )`, `$(( ))`, `case`, `[ ]`, `${v#..}` family, `set --` instead of arrays, here-documents, `getopts`, `trap`, functions without `function`; what dash does and does not accept, from the tables in `shells-and-posix`), and `posix-sh-scripting` (portable patterns: `command -v`, `printf` not `echo -e`, `. ./file`, `mktemp`, locking, text tools differences GNU/BusyBox/BSD, a project test harness that runs a script under dash and busybox ash, ShellCheck `--shell=sh`). It gets its own learning path (`posix-sh`).

### dinit and Chimera (proposed 2026-11-21, owner interest; replaces "dinit is a short aside only")

Taught on the Chimera lab VM (`docs/decisions/0009-chimera-lab.md`), version-pinned because dinit is pre-1.0 (Chimera build 20261103 ships 0.22.0; upstream's newest tag was v0.23.0 when checked):
1. `linux.dinit-basics`: `dinitctl list/status/start/stop/enable/disable`, what enabling really is (a symlink in `/etc/dinit.d/boot.d`), service states, why a base install has no network until `dhcpcd` is enabled, reading `/var/log/messages` once `syslog-ng` is enabled.
2. `linux.dinit-service-files`: types (process, bgprocess, scripted, internal), `depends-on` / `waits-for` / `before`, writing a service, why edits need `dinitctl reload` or `unload`, failure messages ("could not be launched").
3. `linux.dinit-in-practice`: user services and `turnstile`, `rc.local`, targets, troubleshooting boot order; labs `chimera-service-wont-start`, `chimera-no-system-log`.
4. `linux.init-systems-compared`: the same tasks under systemd (Ubuntu and AlmaLinux VMs) and dinit (Chimera VM).
Also candidates: a "FreeBSD userland on Linux" lesson (what differs in `ls`, `sed -i`, `grep`, `sh`, `tar` on Chimera, from the real outputs), and a lab for `apk` (lab `chimera-apk-repo-typo` exists).

### Linux system (alongside)
- `linux.systemd`: units, targets, `systemctl`, `journalctl`, timers, writing and overriding unit files, sandboxing options, `systemd-analyze`.

## Two clarifications (owner, 2026-11-21)

- **GUIs are not ignored.** Most people use the graphical tools, so every Windows topic shows the GUI route *and* the shell route (PowerShell and CMD). "Also teach it from the command line" never means "instead of the GUI".
- **ShellCheck** is an excellent static checker for sh and bash scripts. It is not installed by default on most distributions, so teach it as an **optional tip** (better errors and syntax checking before you run a script), with the install route per package manager verified at writing time. It belongs in `shells-and-posix` and `bash-robust-scripts`.

## Design goal (owner, 2026-11-21): be the one script kiddies rely on

A "script kiddie" runs scripts and tools they do not understand. The scripting lessons aim for the opposite: the learner can **write original tools, read and audit other people's code, and fix what is broken**. Consequences for every scripting lesson:

- **Explain why, not only what.** Show how the shell parses and runs a line, not just a recipe to paste.
- **Read before you run.** Teach reading an unknown script safely (what it touches, what it downloads, what rights it needs) and the tools that help (`-WhatIf`, dry-run switches, PSScriptAnalyzer, ShellCheck, `bash -n`, `set -x`).
- **Exercises that read code:** "explain this script line by line", "find the bug", "find the unsafe line", as well as "write a script".
- **Show the traps with real output**, so the learner can recognise a failure mode in the wild instead of cargo-culting a fix.
- **Labs check behaviour on fresh data**, so copied answers fail (already how the script labs work).
- Defensive framing: the same skills make the learner the person who audits a downloaded script before it runs with administrator rights.

## Testing setup and platform notes (2026-11-21)

- PowerShell lessons are verified on **Windows PowerShell 5.1**, **PowerShell 7 on Windows** and **PowerShell 7 on Linux** (WSL Ubuntu). The Linux differences are in `foundations.powershell-basics` (no `ls`/`rm`/`cp`/`mv`/`cat`/`mkdir`/`ps`/`kill`/`sleep`/`sort`/`curl`/`wget`/`man`/`clear` aliases, case-sensitive paths, no registry or Windows-only cmdlets, no enforced execution policy).
- **Never use aliases in scripts**: a boxed rule in the basics lesson, repeated in the functions lesson, with quiz questions.
- Microsoft recommends **Visual Studio Code with the PowerShell extension** for writing scripts (optional; adds completion, PSScriptAnalyzer checks, snippets, console, debugger).
- The same WSL distro is the test bed for the bash and POSIX sh lessons (bash, dash, ShellCheck availability to be checked when writing them).

## External programs in scripts (owner rule, 2026-11-21)

When a script uses a program that is not a built-in (coreutils, util-core, any installed tool), it must name the program unambiguously and make sure it is on `PATH`, so it cannot collide with an alias, function or built-in of the host environment.

- **PowerShell on Windows:** write `tool.exe` (`where.exe`, `sort.exe`, `curl.exe`, `ls.exe`), check `Get-Command tool.exe` at the top, use the call operator and a full path for certainty. Verified: bare `where` runs `Where-Object`; a function named `find` hijacks `find`, but `find.exe` reaches the program. In Windows PowerShell 5.1 `sc` is `Set-Content` and `curl` is `Invoke-WebRequest`.
- **cmd:** built-ins are matched before programs and `name.exe` does not reliably escape that (`echo.exe hi` printed `exe hi`), so give colliding tools a full path.
- **bash and POSIX sh (to be written):** the same idea applies. Aliases are not expanded in non-interactive scripts, but functions and builtins still shadow programs: teach `command -v tool`, `type -a`, `command tool` (bypass functions), full paths, and setting a safe `PATH` at the top of a privileged script.
