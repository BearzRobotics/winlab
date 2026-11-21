*Draft for owner review.* The earlier CMD lessons gave you the language. This one is about writing **scripts you would trust**: ones that accept arguments, validate them, log what they do, run unattended from Task Scheduler, check for elevation, call other tools correctly, and can be debugged when they go wrong. It ends with a complete worked script. Examples were run on Windows 11; where a result depends on your machine (such as whether you are elevated), the text says so.

## A script template

A solid start for every script:

```
@echo off
setlocal EnableExtensions
rem ---- backup.cmd : copies a folder to a dated backup
rem ---- usage: backup.cmd SOURCE [DESTROOT]

set "SELF=%~nx0"
pushd "%~dp0" || exit /b 1
...
popd
exit /b 0
```

- `@echo off` and `setlocal` (previous lessons) keep output clean and variables private. Add `EnableDelayedExpansion` when a loop needs `!var!`.
- `%~nx0` is the script's own name (for usage messages) and `%~dp0` its folder.
- **`pushd`/`popd`** change directory and remember the previous one. Unlike `cd`, `pushd` also works with **UNC paths** (`\\server\share`) by mapping a temporary drive letter, and `popd` unmaps it. Use `pushd` rather than `cd /d` when a path may be a network share. See [`pushd`](https://learn.microsoft.com/windows-server/administration/windows-commands/pushd) and [`popd`](https://learn.microsoft.com/windows-server/administration/windows-commands/popd).
- Always end with an explicit `exit /b <code>`.

### The file itself

- **Line endings.** Windows text files use CR+LF. cmd tolerated an LF-only file with labels in my test on Windows 11, but save batch files with CR+LF anyway (in **Microsoft Edit** it is the line-ending setting; in VS Code it is the status bar). Scripts copied from Linux are the usual source of LF-only files.
- **Encoding.** cmd reads files in the console's code page (see `chcp`). Keep scripts to ASCII where possible, and save as ANSI or UTF-8 **without a BOM**: a byte-order mark was tolerated in my test, but it is one more thing that can corrupt the first line, so avoid it. If you need non-ASCII text, set the code page deliberately (`chcp 65001` for UTF-8) and test on a second machine.
- **Editing.** Any editor works. Windows 11 ships the terminal editor `edit` (Microsoft Edit); Notepad is fine; use an editor that shows line endings and the encoding.

## Arguments

A script sees `%1`..`%9`, `%*`, `shift` and the `%~` modifiers (variables lesson). Three habits make argument handling reliable.

**1. Quote when you use them, and strip with `%~`:** `"%~1"`.

**2. Validate before you act:**

```
if "%~1"=="" (
    echo usage: %SELF% SOURCE [DESTROOT]
    exit /b 2
)
if not exist "%~1\" (
    echo not a folder: %~1
    exit /b 3
)
```

**3. Parse options in a loop.** A small, dependable pattern: process arguments one by one, treating anything starting with `/` as a switch:

```
:parse
if "%~1"=="" goto parsed
set "a=%~1"
if "!a:~0,1!"=="/" (echo switch: %~1) else (echo positional: %~1)
shift
goto parse
:parsed
```

With `call :parse /v "/out:my file.txt" target` this printed:

```
switch: /v
switch: /out:my file.txt
positional: target
```

(The script needs `EnableDelayedExpansion` for `!a:~0,1!`.) Two traps:

- **Quote the whole argument, not part of it.** `/out:"my file.txt"` (a quote in the middle) makes `if "%~1"==...` fail with a syntax error, because the embedded quotes unbalance the test. Write `"/out:my file.txt"`, or avoid spaces in switch values.
- Characters such as `&` and `|` in an argument are special when the argument is *used* unquoted. Always use `"%~1"`, and never build a command by pasting an argument into it unquoted (see Security below).

**Help.** Make `/?` print the usage and exit 0: `if "%~1"=="/?" (call :usage & exit /b 0)`.

## Output and logging

Use `echo` for messages, and remember its quirks:

- `echo(` and `echo.` print a **blank line** (`echo(` is the more reliable spelling). `echo(text` also prints text that starts with special characters.
- A message that contains `&`, `|`, `<`, `>` or `)` needs escaping with `^` or quoting.
- Send errors to **stderr** with `echo message 1>&2`, so a caller can separate them.

**A log** is the only record of an unattended run:

```
set "LOG=%TEMP%\backup.log"
> "%LOG%" echo start
call :log "step one"
...
:log
>> "%LOG%" echo %~1
exit /b 0
```

Timestamps are awkward: `%DATE%` and `%TIME%` follow the regional settings, so parsing them breaks on another machine. The robust way is to ask PowerShell, which is on every supported Windows:

```
for /f %%a in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "ts=%%a"
echo %ts%
20261121-094500
```

(`wmic` used to be the cmd answer to this, but it is deprecated and is not even installed on the Windows 11 build used to test this lesson; do not use it in new scripts.) Rotate or limit logs: a script that appends forever fills a disk.

## Reading configuration

Keep settings out of the code in a simple `key=value` file and read it with `for /f`:

```
for /f "usebackq eol=; tokens=1,* delims==" %%k in ("app.ini") do echo key=[%%k] value=[%%l]
key=[name] value=[Demo App]
key=[path] value=[C:\Program Files\Demo]
key=[mode ] value=[ fast]
```

`eol=;` ignores comment lines starting with `;`, `delims==` splits at the first `=`, and `tokens=1,*` puts everything after the first `=` in `%%l`, including spaces and later `=` signs. Note that `mode = fast` kept the spaces: trim them yourself or write the file without spaces. Treat the file as **untrusted input** if anyone but you can edit it.

## Elevation: are we administrator?

Many tasks need an elevated prompt. Test for it instead of failing halfway:

```
net session >nul 2>&1 && (echo admin=yes) || (echo admin=no)
fltmc >nul 2>&1 && (echo fltmc-admin=yes) || (echo fltmc-admin=no)
```

Both commands fail unless the prompt is elevated (they need administrative rights). In a normal prompt my test printed `admin=no`. A script that needs elevation should check at the top and stop with a clear message and a distinct exit code, or restart itself elevated through PowerShell: `powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"`. Self-elevating loses the arguments and the working folder unless you pass them, and the user sees a UAC prompt, so for unattended jobs run the script from an already-elevated Task Scheduler task instead.

## Starting and calling things

| You want | Use |
|---|---|
| run another batch file and continue | `call other.cmd` |
| run a program and wait for it | just `program args` (console programs wait automatically) |
| run a GUI program and **wait** for it | `start /wait "" program args` |
| run a program **without** waiting | `start "" program args` |
| run in a fresh cmd with its own environment | `cmd /c other.cmd` |
| run PowerShell | `powershell -NoProfile -File script.ps1` |

```
start /wait "" cmd /c exit 5
echo start-wait-el=%errorlevel%
start-wait-el=5
```

`start /wait` returns the program's exit code. The empty `""` is the window title; without it, a quoted program path is mistaken for the title.

**Calling PowerShell from a batch file.** `-NoProfile` keeps your profile from interfering, and `-ExecutionPolicy Bypass` (or `-ExecutionPolicy RemoteSigned`) applies only to that process if the machine's policy blocks scripts:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0report.ps1" -Path "%~1"
if errorlevel 1 exit /b 1
```

**The `cmd /c` quote rule.** When the string after `/c` begins with a quote and contains more quotes, cmd's parsing of the outer quotes is unintuitive. The reliable way is to wrap the whole command in an extra pair of quotes: `cmd /c ""C:\Program Files\app.exe" "arg one""`.

## Searching text: `find` and `findstr`

`findstr` is the line-matching workhorse. It sets the exit code (`0` found, `1` not found), which makes it a test:

```
findstr /i /c:"line2" heredoc.txt
line2 & more
echo found-el=%errorlevel%
found-el=0
findstr /i "zzz" heredoc.txt >nul
echo notfound-el=%errorlevel%
notfound-el=1
```

`/i` ignores case, `/c:"two words"` searches for a literal phrase (without it, spaces separate alternatives), `/r` uses regular expressions, `/s` searches subfolders, and `/n` prints line numbers. The text-and-files lesson goes deeper.

## Unattended running

A script run by **Task Scheduler**, a service or another program has no console and a different environment from yours:

- It has **no user at the keyboard**: remove `pause`, `set /p` and `choice`, and `timeout` (it fails when input is redirected).
- **Mapped drive letters do not exist** unless the task maps them; use UNC paths with `pushd`.
- The **account differs**, so `%USERPROFILE%`, `%APPDATA%` and `%TEMP%` point somewhere else (for SYSTEM they are under `C:\Windows`), and per-user software may be absent.
- The **working directory** is usually `C:\Windows\System32`, not the script's folder. Start with `pushd "%~dp0"` and use full paths.
- **`PATH` may be shorter.** Call tools by full path or check with `where`.
- Return a meaningful **exit code**: the task's `LastTaskResult` is that code, which is how you notice a failure (see the services and tasks lesson).
- Write a **log**. It is usually the only way to find out what happened.

Test a script the way it will run: from Task Scheduler (**Run now**), as the account it will use, with the log open.

## Debugging

| Technique | How |
|---|---|
| See each command as it runs | remove `@echo off`, or switch it on for a section with `echo on` and `@echo off` |
| Keep the window open | run from an existing prompt, or `cmd /k script.cmd` |
| Dump the state | `set` (all variables), `echo %errorlevel%`, `echo !var!` |
| Stop and look | `pause` (remove it afterwards) |
| Rehearse a dangerous action | a **dry-run** variable (below) |
| Reduce the problem | comment out (`rem`) blocks until it works, then add back |

A dry-run switch prints what a script *would* do:

```
set "RUN=echo WOULD RUN:"
%RUN% del "C:\important\*.*"
WOULD RUN: del "C:\important\*.*"
```

Set `RUN=` (empty) to do the real thing. Use it for any command that deletes, moves or overwrites.

When a line misbehaves, run it **at the prompt** with the same values, or add `echo` in front to see what cmd actually built after expansion.

## Security

Batch scripts routinely run with high rights and read untrusted text (arguments, file names, files). Treat input as hostile:

- **Quote every expansion**: `"%~1"`, `"%%f"`, `"%var%"`.
- **Never run a command built from user input** without validating it: a value like `x & del ...` becomes two commands if it is pasted in unquoted.
- **Guard deletes.** Before `del` or `rd /s`, check the variable is not empty and points where you expect (`if "%target%"=="" exit /b 1`), and rehearse with the dry-run pattern.
- **Use full paths** (or `%SystemRoot%\System32\`) for system tools in privileged scripts, and be aware of the current-directory search rule from the first lesson. For tools you installed (coreutils, util-core, anything outside `System32`), keep their folder on `PATH`, and when a tool's name collides with a cmd **built-in** (`echo`, `mkdir`, `type`, `copy` and so on) call it by its **full path**: cmd matches built-ins before programs, and adding `.exe` does not reliably escape that (cmd read `echo.exe hi` as the built-in `echo` and printed `exe hi`). In PowerShell, by contrast, writing `name.exe` is the right way to stop an alias or function from intercepting a program (see the PowerShell basics lesson).
- **Do not store passwords** in a script. Use a credential store, Task Scheduler's stored account, or a secrets facility.
- **Scripts that run elevated should not be writable by standard users**: otherwise a standard user can edit the script and gain administrator rights.

## A complete script

```
@echo off
setlocal EnableExtensions
rem backup.cmd SOURCE [DESTROOT]  -- exit codes: 0 ok, 1 copy failed, 2 usage, 3 not a folder

set "SELF=%~nx0"
if "%~1"=="" (echo usage: %SELF% SOURCE [DESTROOT] & exit /b 2)
if "%~1"=="/?" (echo usage: %SELF% SOURCE [DESTROOT] & exit /b 0)
if not exist "%~1\" (echo not a folder: %~1 & exit /b 3)

set "SRC=%~1"
set "DEST=%~2"
if not defined DEST set "DEST=%TEMP%\backups"

for /f %%a in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "TS=%%a"
set "TARGET=%DEST%\backup-%TS%"
set "LOG=%DEST%\backup.log"

if not exist "%DEST%\" mkdir "%DEST%" || (echo cannot create %DEST% & exit /b 1)
>> "%LOG%" echo %TS% start %SRC% to %TARGET%

robocopy "%SRC%" "%TARGET%" /e /r:1 /w:1 >nul
if errorlevel 8 (
    >> "%LOG%" echo %TS% FAILED code %errorlevel%
    echo backup failed
    exit /b 1
)
>> "%LOG%" echo %TS% ok
echo backup ok: %TARGET%
exit /b 0
```

It validates arguments with distinct codes, builds paths from variables (quoted), uses a locale-independent timestamp, treats robocopy's success codes properly, logs, and ends with an explicit code. Compare each part with the sections above.

## Common mistakes

- **Not using `call`** for another script.
- **Unquoted `%1`**, or quotes in the middle of an argument.
- **Assuming a console and a working directory** in an unattended run.
- **Parsing `%DATE%`** and `%TIME%`.
- **Comments on the same line as a command.**
- **Saving with LF-only endings or a BOM** and meeting odd first-line errors.
- **`pause` or `timeout` in a scheduled script.**
- **Checking the wrong exit code** (`robocopy`'s are a bit mask).
- **A script that needs administrator rights but does not test for it.**
- **Building commands from untrusted input.**

## Practice

1. Take the template and write `info.cmd` that prints its own name and folder, its arguments one per line, and exits 2 with a usage message when none are given.
2. Add a `/verbose` switch using the parse loop, and a `/log:FILE` switch whose value may contain spaces when quoted as a whole.
3. Write a script that exits with a distinct code if it is not elevated, and test it from a normal and an administrator prompt.
4. Make the backup script accept `/dryrun`, and when it is set only print the robocopy command.
5. Schedule one of your scripts with Task Scheduler, run it now, and compare its environment (`set > "%TEMP%\env-task.txt"`) with your prompt's.

## Check your understanding

1. Why use `pushd` rather than `cd /d` for a path that may be a network share?
2. What breaks if you write `/out:"my file.txt"` and test it with `if "%~1"==""`?
3. How do you get a timestamp that does not depend on regional settings?
4. How does a script tell whether it is elevated?
5. What is the difference between `start "" app` and `start /wait "" app`?
6. Name four things that differ when a script runs from Task Scheduler.
7. Why should a script that runs elevated not be writable by standard users?
8. What does a dry-run variable give you?

**Expected answers:** (1) `pushd` maps a temporary drive letter for a UNC path and `popd` removes it; `cd /d` cannot change to a UNC path; (2) the embedded quotes unbalance the test and cmd reports a syntax error, so quote the whole argument; (3) ask PowerShell: `Get-Date -Format yyyyMMdd-HHmmss`; (4) run a command that needs administrator rights, such as `net session` or `fltmc`, and test its exit code; (5) the first does not wait and the second waits and returns the program's exit code; (6) no console or user, no mapped drives, a different account and profile folders, a different working directory and often `PATH`; (7) a standard user could edit it and so run their own commands with administrator rights; (8) a safe rehearsal that prints what would happen before anything is deleted or changed.
