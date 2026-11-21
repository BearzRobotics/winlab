*Draft for owner review.* PowerShell is a shell and a scripting language built around **objects** instead of text. That one difference changes how you filter, combine and reuse results, and it is why PowerShell scales from a one-line query to a thousand-line module. This lesson is the foundation for the whole PowerShell series: what it is, how to start it, how commands are named and discovered, how the pipeline works, how to read help, and how scripts are allowed to run. Every command here only reads information.

All output shown was produced on Windows 11 with **Windows PowerShell 5.1** and **PowerShell 7**, and where they differ the text says so.

## Two PowerShells

| | Windows PowerShell | PowerShell 7 |
|---|---|---|
| Program | `powershell.exe` | `pwsh.exe` |
| Version | **5.1**, final, only security fixes | 7.x, actively developed |
| Built on | .NET Framework (Windows only) | .NET (Windows, Linux, macOS) |
| `$PSVersionTable.PSEdition` | `Desktop` | `Core` |
| Installed | with Windows | separate install (`winget install Microsoft.PowerShell`) |
| Profile folder | `Documents\WindowsPowerShell` | `Documents\PowerShell` |
| Strengths | present on every Windows machine, many Windows-only modules | newer language features, parallelism, better defaults, cross-platform |

PowerShell 7 also runs on **Linux and macOS** (see [Installing PowerShell on Linux](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux)); a later section lists what changes there. Both Windows editions can be installed side by side. **Learn the common core first**: almost everything in this series runs in both, and the lessons say when something is 7-only. If you must write a script that runs on any Windows machine without installing anything, target **5.1**. Check what you are running:

```powershell
$PSVersionTable.PSVersion
$PSVersionTable.PSEdition
```

## Starting it

- **GUI:** Start menu, search *PowerShell* (or *Terminal*); right-click and *Run as administrator* only when a task needs it. **Windows Terminal** hosts PowerShell, Command Prompt and WSL in tabs. In **File Explorer**, type `powershell` (or `pwsh`) in the address bar to open a session in that folder.
- **Command line:** `powershell` or `pwsh` from any prompt; `powershell -Command "Get-Date"` runs one command and exits.
- **Editors:** Microsoft recommends **Visual Studio Code with the PowerShell extension** for writing scripts ([guide](https://learn.microsoft.com/powershell/scripting/dev-cross-plat/vscode/using-vscode)). It is optional, since any text editor works, but it adds what a plain editor lacks: completion and signature help for cmdlets, parameters and variables, error and style checking while you type (through PSScriptAnalyzer), snippets, an integrated PowerShell console, and a graphical debugger. The older **PowerShell ISE** ships with Windows PowerShell 5.1 but is no longer developed and does not support PowerShell 7. For a quick edit over a remote session, the terminal editor `edit` works too.

The prompt starts in your profile folder. Type commands, press **Tab** to complete names, parameters and paths, press **Up** to recall history, and press **Ctrl+R** to search it (the PSReadLine module provides these).

## Commands are named Verb-Noun

Commands, called **cmdlets** (and *functions*, *aliases*, *scripts* and programs; PowerShell runs them all the same way), follow a `Verb-Noun` pattern: `Get-Process`, `Get-Service`, `Get-ChildItem`, `Set-Location`, `New-Item`, `Remove-Item`. The verbs are standardised (`Get`, `Set`, `New`, `Remove`, `Start`, `Stop`, `Test`...), so once you know a noun you can guess the cmdlet. Discover cmdlets instead of memorising them:

```powershell
Get-Command *service*
Get-Command -Verb Get -Noun *Process*
Get-Verb
```

[`Get-Command`](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/get-command) lists commands by name, verb, noun or module. `Get-Verb` lists the approved verbs.

### Aliases

Interactive use is shortened with **aliases**:

```powershell
Get-Alias gci, ls, dir, cat, cp, mv, rm, ps, select, where, foreach, sort

Name    Definition
----    ----------
gci     Get-ChildItem
ls      Get-ChildItem
dir     Get-ChildItem
cat     Get-Content
cp      Copy-Item
mv      Move-Item
rm      Remove-Item
ps      Get-Process
select  Select-Object
where   Where-Object
foreach ForEach-Object
sort    Sort-Object
```

Many aliases mimic cmd and Linux commands (`dir`, `cat`, `ls`), which is comforting and misleading: on Windows, `ls -l` does not work, because `ls` is `Get-ChildItem` and takes PowerShell parameters. See [about_Aliases](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_aliases). `Get-Alias -Definition Get-ChildItem` shows every alias for a cmdlet.

> **Rule: never use aliases in scripts.** Aliases are for typing at the prompt. In a script, a module, a lesson answer or anything you share, write the full cmdlet name (`Get-ChildItem`, not `gci`, `ls` or `dir`; `ForEach-Object`, not `%`; `Where-Object`, not `?`) and the full parameter names. Three reasons:
> 1. **Readability.** A reader who does not know `gci` or `%` cannot search for them.
> 2. **They can be redefined.** An alias in the user's profile (or a malicious one) changes what your script runs, and an alias **beats a function or cmdlet** of the same name.
> 3. **They differ by platform.** The set of aliases is not the same everywhere. On Linux and macOS, PowerShell deliberately ships **no alias for `ls`, `cat`, `cp`, `mv`, `rm`, `mkdir`, `ps`, `kill`, `sleep`, `sort`, `curl`, `wget`, `man` or `clear`**, so typing them runs the **native programs** instead (details below). A script that uses `rm -Recurse` works on Windows and breaks on Linux. (Even on Windows the aliases are not uniform: `mkdir` is a function, and `curl` and `wget` are aliases of `Invoke-WebRequest` only in 5.1.)
>
> PSScriptAnalyzer flags aliases in scripts, and the VS Code extension shows its warnings while you type.

### The `curl` trap

`curl` is the clearest example of the same name meaning different things. I ran the same three commands against a throwaway local web server (no internet needed) in both editions:

| Command | Windows PowerShell 5.1 | PowerShell 7 |
|---|---|---|
| `curl http://localhost:8765/` | `curl` is an **alias of `Invoke-WebRequest`**. It returns a response *object* (not the page text), and without `-UseBasicParsing` it failed here with `NullReferenceException`, because it tries to use the old Internet Explorer parsing engine | there is **no alias**: it runs the real **`curl.exe`**, which prints the body (`hello from local server`) and a progress meter on stderr |
| `curl.exe -s http://localhost:8765/` | prints the body | prints the body (`-s` silences the meter) |
| `Invoke-WebRequest http://localhost:8765/` | needs `-UseBasicParsing`; then `StatusCode` 200 | works as is; `StatusCode` 200, `Content` holds the body |

So the same line is a PowerShell cmdlet on one machine and a native program on another, with different output, different options (`curl -I` means something to the program and nothing to the cmdlet) and different failure modes. In a script, **say which you mean**: `curl.exe` for the program (it exists on current Windows 10 and 11, and on Linux as `curl`), `Invoke-WebRequest` for the response object (status code, headers, content) and `Invoke-RestMethod` for APIs that return JSON or XML, which it converts to objects for you (in the test it returned the text as a string). Never write bare `curl` or `wget` in a script.

### Parameters

Parameters change what a cmdlet does. They start with a dash and you can abbreviate them if they stay unambiguous (but spell them out in scripts):

```powershell
Get-ChildItem -Path C:\Windows -Filter *.exe -File
Get-ChildItem C:\Windows *.exe -File        # positional: -Path and -Filter by position
Get-Service -Name Spooler,W32Time           # a list of values
Remove-Item .\old.txt -Force -WhatIf        # -Force and -WhatIf are switches (on/off)
```

A **switch** parameter takes no value (its presence turns it on). **Positional** parameters let you omit the name, which is fine at the prompt and confusing in a script.

### Common parameters

Every cmdlet that supports them accepts these:

| Parameter | Use |
|---|---|
| `-WhatIf` | show what the command **would** do, without doing it |
| `-Confirm` | ask before each action |
| `-Verbose`, `-Debug` | more detail from the command |
| `-ErrorAction` | what to do on a non-terminating error (`Stop`, `Continue`, `SilentlyContinue`, `Inquire`) |
| `-ErrorVariable`, `-WarningVariable` | collect errors or warnings in a variable |
| `-OutVariable`, `-PipelineVariable` | keep output, or name the current pipeline object |

```powershell
Remove-Item "$env:TEMP\wl-ps-demo\a.txt" -WhatIf
What if: Performing the operation "Remove File" on target "C:\Users\...\wl-ps-demo\a.txt".
```

**`-WhatIf` is the habit to build**: rehearse every command that changes something (the same idea as the dry-run switch in the cmd lessons). Reference: [about_CommonParameters](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters).

## Help is built in

```powershell
Get-Help Get-Process
Get-Help Get-Process -Examples
Get-Help Get-Process -Parameter Name
Get-Help about_Pipelines
Update-Help
```

[`Get-Help`](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/get-help) shows the syntax, description and examples. Help for the `about_*` topics explains concepts and language features. **`Update-Help`** downloads current help files; it needs network access and an elevated prompt, and until you run it you see abbreviated help. It is optional; the online documentation at learn.microsoft.com is the same content, and `Get-Help Get-Process -Online` opens it in a browser.

Read the **SYNTAX** block as follows: a parameter in square brackets is optional; a parameter *and* its value both in brackets is optional; `<String[]>` means a list of strings is accepted. Learning to read this block is the single most useful PowerShell skill.

## Objects, not text

```powershell
Get-Process | Get-Member
```

[`Get-Member`](https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/get-member) lists the **properties** (data) and **methods** (actions) of the objects a command outputs. A process object has `Name`, `Id`, `WorkingSet`, `CPU`, `StartTime` and many more. The screen shows only a few of them; the object carries them all. You can reach any property directly:

```powershell
(Get-Process explorer).Id
Get-Process explorer | Select-Object Name, Id, StartTime, WorkingSet
```

This is the difference from cmd: there you cut text with `for /f` and `findstr`; here you ask for a property by name, and it still works if the display format changes.

## The pipeline

A pipe passes whole objects to the next command, so you filter by property instead of cutting up text:

```powershell
Get-Process | Where-Object { $_.WorkingSet -gt 200MB }
Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 5 Name, Id, WorkingSet
```

`$_` is the current object. The workhorse cmdlets:

| Cmdlet | Job |
|---|---|
| [`Where-Object`](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/where-object) | keep objects that match a condition |
| [`Select-Object`](https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/select-object) | choose properties, or the first/last N, or unique ones |
| [`Sort-Object`](https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/sort-object) | order by one or more properties |
| [`Group-Object`](https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/group-object) | group by a property and count |
| [`Measure-Object`](https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/measure-object) | count, sum, average, minimum, maximum |
| [`ForEach-Object`](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/foreach-object) | run a script block for each object |

```powershell
Get-Process | Group-Object ProcessName | Sort-Object Count -Descending | Select-Object -First 3 Count, Name

Count Name
----- ----
   83 svchost
   22 brave
   15 msedge
```

Because the objects are real, `Measure-Object` can add a property: `Get-ChildItem C:\Windows\System32 -File | Measure-Object Length -Sum -Average -Maximum` returns an object with `Count`, `Sum`, `Average` and `Maximum`. See [about_Pipelines](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_pipelines) for how objects flow.

**Filter left, early.** Where a cmdlet has its own filter (`-Filter`, `-Name`, `-Include`), use it instead of `Where-Object` further down the pipe; it removes objects before they are created, which is much faster.

## Formatting versus data

`Format-Table`, `Format-List` and similar cmdlets turn objects into display text. Their output is for people, not for further processing. Put them **last**:

```powershell
Get-Service | Sort-Object Status | Format-Table Name, Status
```

Reversing the order breaks things, because after `Format-Table` the pipeline holds formatting instructions, not services. When you want to save data use `Export-Csv`, `ConvertTo-Json` or `Out-File` (the working-with-data lesson covers them). See [`Format-Table`](https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/format-table) and [`Out-File`](https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/out-file).

## Providers and drives

PowerShell presents several data stores as **drives** you navigate with the same cmdlets (`Get-ChildItem`, `Set-Location`, `Get-Item`, `New-Item`, `Remove-Item`):

```powershell
Get-PSProvider

Name        Drives
----        ------
Registry    {HKLM, HKCU}
Alias       {Alias}
Environment {Env}
FileSystem  {C, D, F}
Function    {Function}
Variable    {Variable}
```

| Drive | What it holds | Example |
|---|---|---|
| `C:` etc. | the file system | `Get-ChildItem C:\Windows` |
| `Env:` | environment variables | `$env:USERPROFILE`, `Get-ChildItem Env:` |
| `HKLM:` `HKCU:` | the registry | `Get-ChildItem HKCU:\Software` |
| `Cert:` | certificate stores | `Get-ChildItem Cert:\CurrentUser\My` |
| `Alias:` `Function:` `Variable:` | what is defined in this session | `Get-ChildItem Function:` |

The idea to hold on to: **one set of verbs works across all of them**, so the registry is "a folder you can list". See [about_Providers](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_providers). PowerShell 7 shows extra drives (such as `Temp:`) when they exist.

## Calling external programs safely

A script often runs a program that is not a cmdlet: `robocopy`, `curl`, `tar`, `where`, a tool from **coreutils** or from your own toolkit (for example the util-core utilities on Windows). A **bare name is ambiguous**, because PowerShell resolves it in the order *alias, function, cmdlet, external program* (see `about_Command_Precedence`), and the host environment you run in (the user's profile, a loaded module, a leftover function) may define an alias or function with that name. Check what a name means with `Get-Command -All`:

```powershell
Get-Command where -All

CommandType Name       Source
----------- ----       ------
Alias       where -> Where-Object
Application where.exe  C:\WINDOWS\system32\where.exe
```

Typing `where notepad` therefore runs **`Where-Object`**, not the program that finds files, and silently prints nothing. The same happens to `sort` (alias of `Sort-Object`), and in Windows PowerShell 5.1 to `sc` (alias of `Set-Content`) and `curl` (alias of `Invoke-WebRequest`). I also defined a function named `find`; it hijacked the name, and only `find.exe` still reached the real program.

> **Rule: when a script needs an external program, name it with its extension (`where.exe`, `sort.exe`, `curl.exe`, `tar.exe`, `ls.exe`) and make sure its folder is on `PATH`.** An alias or function can never match a name that ends in `.exe`, so the program you meant is the program that runs, whatever the host environment defines. Using the extension also tells the reader that this is a program, not a cmdlet.

```powershell
where.exe notepad          # the program: C:\Windows\System32\notepad.exe
sort.exe                   # the Windows sort program, not Sort-Object
curl.exe -I https://example.com
```

For tools that are not in `System32` (coreutils builds, util-core, anything you installed), the same rules apply:

- **Use `name.exe`** so a user's alias such as `ls` or `cp`, or a function in a loaded module, cannot intercept it.
- **Make sure the tool's folder is on `PATH`**, and check it at the top of the script instead of failing halfway: `if (-not (Get-Command ls.exe -ErrorAction SilentlyContinue)) { throw 'ls.exe not found: install the tools and add them to PATH' }`.
- For absolute certainty, use the **full path with the call operator**: `& "$env:SystemRoot\System32\where.exe" cmd`, or `& $toolDir\ls.exe`. Then even a wrong `PATH` cannot substitute another program.
- **Prefer a trusted, fixed location over `PATH`** in scripts that run elevated: a writable folder early on `PATH` lets someone plant a program with a common name.
- **Do not mix assumptions**: if you mean the cmdlet, use the cmdlet (`Sort-Object`); if you mean the program, use `sort.exe`. Never type the bare, ambiguous name in a script.
- Check the result: external programs report failure through `$LASTEXITCODE` (the errors lesson), not exceptions.

## PowerShell on Linux and macOS

PowerShell 7 is cross-platform and open source: the same `pwsh` runs on Windows, Linux and macOS, and a script that sticks to the common cmdlets runs on all three (see the [unix support notes](https://learn.microsoft.com/powershell/scripting/whats-new/unix-support)). It is not installed by default; Microsoft publishes packages and a plain archive (`powershell-<version>-linux-x64.tar.gz`) you can unpack into a folder and run without installing anything.

I ran the same checks on Windows 11 and on Ubuntu 26.04 (under WSL) with PowerShell 7.6.10. What differs:

| | Windows | Linux |
|---|---|---|
| platform variables | `$IsWindows` is `True` | `$IsLinux` is `True` (and `$IsWindows`, `$IsMacOS` are `False`) |
| `ls`, `cat`, `cp`, `mv`, `rm`, `ps`, `kill`, `sleep`, `sort`, `man`, `clear` | aliases of cmdlets (`ls` is `Get-ChildItem`, `rm` is `Remove-Item`) | **no aliases**: the native programs run (`ls` resolves to `/usr/bin/ls`) |
| `mkdir` | a **function** that wraps `New-Item` | the native `/usr/bin/mkdir` |
| `curl`, `wget` | in 5.1 both are aliases of `Invoke-WebRequest` (so `curl` is **not** the curl program, a classic surprise); in 7 `wget` does not exist and `curl` runs the real `curl.exe` | the native programs |
| aliases that stay | `dir`, `echo`, `pwd`, `cd`, `gci`, `gc`, `select`, `where`, `foreach`, `%`, `?` | the same (108 aliases in my test) |
| path separator | `\` (and `/` works) | `/` only |
| file names | not case-sensitive | **case-sensitive**: `A.txt` and `a.txt` are two files |
| home folder | `$env:USERPROFILE` | `$HOME` and `$env:HOME` (`USERPROFILE` is empty) |
| providers | FileSystem, Registry, Certificate, Environment, Alias, Function, Variable | FileSystem, Environment, Alias, Function, Variable (**no Registry or Cert**) |
| execution policy | enforced (`RemoteSigned`, `Restricted`, ...) | `Get-ExecutionPolicy` returns `Unrestricted` and it is not enforced |
| Windows-only cmdlets | present | **absent**: `Get-Service`, `Get-WinEvent`, `Get-CimInstance`, `Get-NetIPAddress`, `Get-LocalUser`, `Get-HotFix`, `Test-NetConnection` and `Get-Acl` were all missing; `Get-Process`, `Get-ChildItem` and the pipeline cmdlets work |
| default text encoding | per edition and code page | UTF-8 |
| profile folder | `Documents\PowerShell` | `~/.config/powershell` |
| running a script | `.\script.ps1` | `./script.ps1`, or `#!/usr/bin/env pwsh` on the first line, `chmod +x`, then run it directly |

Practical consequences:

- **Use `$IsWindows` / `$IsLinux` for platform branches** and avoid Windows-only cmdlets in a script meant to be portable. (In Windows PowerShell 5.1 these variables do not exist, because it only runs on Windows.)
- **Do not assume case-insensitivity** of file names, and build paths with `Join-Path`, which uses the right separator (`Join-Path 'a' 'b'` gave `a/b` on Linux).
- **Never rely on `ls`, `rm` or `cp` aliases.** On Linux, `ls -l` runs the real `ls`; on Windows it errors. Use `Get-ChildItem`, `Remove-Item` and `Copy-Item`, which behave the same everywhere.
- **Native tools combine with the pipeline.** On Linux you can run `ls -l /etc/os-release`, `uname -s` or `grep` directly from PowerShell; their output is **text**, so wrap it with `Select-String` or parse it, and check `$LASTEXITCODE` (the errors lesson).
- **A shebang line works**: a file starting `#!/usr/bin/env pwsh` is executable like any other script.
- **The `.exe` rule is a Windows rule.** Linux and macOS programs have no extension, so a function or alias can still shadow a bare name there (a function named `ls` would beat `/usr/bin/ls`). To be certain, check with `Get-Command ls -CommandType Application` or call the full path (`& /usr/bin/ls`).

## Running scripts

A script is a `.ps1` file. To run one in the current folder you must say where it is: `.\script.ps1` (PowerShell does **not** run programs from the current folder by name; this is deliberate and safer than cmd). The **call operator** `&` runs a command stored in a string or variable (`& "C:\Program Files\App\app.exe" /arg`), and **dot-sourcing** (`. .\functions.ps1`) runs a script in the current scope so its functions stay defined.

### The execution policy

The **execution policy** decides whether scripts are allowed to run:

```powershell
Get-ExecutionPolicy -List

        Scope ExecutionPolicy
        ----- ---------------
MachinePolicy       Undefined
   UserPolicy       Undefined
      Process          Bypass
  CurrentUser    RemoteSigned
 LocalMachine       Undefined
```

The effective policy is the first one set, from the top. The common values:

| Policy | Meaning |
|---|---|
| `Restricted` | no scripts at all (the usual default for Windows PowerShell on Windows client) |
| `AllSigned` | only scripts signed by a trusted publisher |
| `RemoteSigned` | local scripts run; scripts **downloaded** from the internet must be signed (the default for Windows Server, and for PowerShell 7 on Windows) |
| `Unrestricted` / `Bypass` | everything runs (Bypass without prompts) |

It is a safeguard against **accidentally** running a script, **not a security boundary**: a user can still paste the same commands into a console. Do not weaken it to solve a problem you have not diagnosed; the smallest change is for one scope: `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`. A downloaded file carries a "mark of the web"; if you have inspected it and trust it, `Unblock-File .\script.ps1` removes the mark. A one-off run without changing policy: `powershell -ExecutionPolicy Bypass -File .\script.ps1` (this applies to that process only). Reference: [about_Execution_Policies](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_execution_policies) and [`Set-ExecutionPolicy`](https://learn.microsoft.com/powershell/module/microsoft.powershell.security/set-executionpolicy).

### Profiles

A **profile** is a script that runs at start-up, for your aliases, functions and prompt. The path is in `$PROFILE`, and the two editions use different folders:

```powershell
$PROFILE | Format-List * -Force

AllUsersAllHosts       : C:\Program Files\PowerShell\7\profile.ps1
CurrentUserAllHosts    : C:\Users\student\Documents\PowerShell\profile.ps1
CurrentUserCurrentHost : C:\Users\student\Documents\PowerShell\Microsoft.PowerShell_profile.ps1
```

(The 5.1 equivalents are under `WindowsPowerShell`.) The file may not exist yet; create it with `New-Item -Path $PROFILE -Force`. Keep profiles small, because they slow every session, and use `-NoProfile` in scripts and scheduled tasks so your customisations do not change behaviour. See [about_Profiles](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_profiles).

## Errors

By default many errors are *non-terminating*: the command reports the error and carries on. To stop and handle one, use `-ErrorAction Stop` with `try`/`catch`:

```powershell
try {
    Get-Item "C:\does-not-exist" -ErrorAction Stop
} catch {
    Write-Output "Could not read it: $($_.Exception.Message)"
}
```

The errors-and-debugging lesson covers this properly.

## Recording what you did

`Start-Transcript` writes everything you type and see to a file, which is a free record of a troubleshooting session or a lab ([`Start-Transcript`](https://learn.microsoft.com/powershell/module/microsoft.powershell.host/start-transcript)); `Stop-Transcript` ends it. `Get-History` lists this session's commands and `(Get-PSReadLineOption).HistorySavePath` shows the file where PSReadLine keeps history across sessions.

## PowerShell compared with cmd

| Idea | cmd | PowerShell |
|---|---|---|
| a command's output | text | objects |
| pick a field | `for /f` + `tokens` | `Select-Object Name` or `.Name` |
| filter | `findstr` | `Where-Object` |
| variables | text in the environment, `%x%` | typed, `$x` |
| conditions | `if` with quirks | `if`, `switch`, real operators |
| errors | exit codes | exit codes **and** error objects, `try/catch` |
| help | `cmd /?`, web | `Get-Help`, `Get-Command`, `Get-Member` |
| the registry | `reg` | the `HKLM:` and `HKCU:` drives |

## Common mistakes

- **Using aliases in scripts** (`ls`, `gci`, `%`, `?`, `rm`) instead of full cmdlet names. They break on Linux, can be redefined, and are harder to read.
- **Assuming Windows aliases exist on Linux or macOS**, and assuming `curl` is the curl program in Windows PowerShell 5.1.
- **Assuming `ls -l` or `grep`** work: the names are aliases of PowerShell cmdlets, not the Linux tools.
- **Putting `Format-Table` in the middle** of a pipeline.
- **Skipping `-WhatIf`** on a command that deletes or changes something.
- **Running `Update-Help`** unelevated and wondering why it fails.
- **Setting the execution policy to `Unrestricted`** to fix one script.
- **Testing in PowerShell 7 only** and shipping a script to a machine that has just 5.1.
- **Forgetting `.\`** when running a script from the current folder.
- **Filtering late** with `Where-Object` when the cmdlet has a `-Filter`.

## Practice

1. List the five processes using the most memory, with name, ID and working set.
2. List only services that are currently running, sorted by name.
3. Find which cmdlet in your session could show you the installed hotfixes, using `Get-Command` only. Then read its help examples.
4. Use `Group-Object` to count the files in `C:\Windows\System32` by extension and show the five most common.
5. List the child keys of `HKCU:\Software` with the same cmdlet you use for folders.
6. Run `Remove-Item` on a scratch file with `-WhatIf`, then `-Confirm`, then without either.
7. Find your profile path in both editions and create a profile that sets one alias; open a new session to prove it loaded.

## Check your understanding

1. What does `Get-Member` tell you that the default display does not?
2. Why should `Format-Table` be the last command in a pipeline?
3. Is the execution policy a security boundary? Explain.
4. Which edition is `powershell.exe`, and which is `pwsh.exe`?
5. What does `-WhatIf` do, and when should you use it?
6. Why should scripts avoid aliases?
7. How do you list the registry keys under `HKCU:\Software`, and why does the same cmdlet work?
8. How do you run a script that is in the current folder?

**Expected answers:** (1) the full set of properties and methods; (2) it outputs display instructions, not the original objects; (3) no, it prevents accidental script runs but does not stop a user from running the same commands interactively; (4) Windows PowerShell 5.1 and PowerShell 7; (5) it shows what the command would do without doing it; use it before any change; (6) they are shorter but harder to read, and they can be redefined; (7) `Get-ChildItem HKCU:\Software`; providers expose different data stores through one set of cmdlets; (8) `.\script.ps1`, because PowerShell does not run from the current folder by name.
