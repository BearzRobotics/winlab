*Draft for owner review.* This lesson turns PowerShell into an administration tool: **ask the system questions** with CIM, **read and change settings** in the registry, **control services**, **read and write event logs**, **schedule work**, and make every change **safe to repeat and safe to preview**. It is built around one habit: *before a script changes anything, it should be able to say what it would change* (`-WhatIf`) *and do nothing if the machine is already right* (idempotence).

**What was tested, and where.** Read-only commands ran on the Windows 11 host in Windows PowerShell 5.1 and PowerShell 7.6.10. Everything that changes the system ran in the **Windows Server 2022 lab VM** in Windows PowerShell 5.1, from an elevated session, and the VM was restored afterwards. Not tested: Linux (none of this exists there), Windows 10, and any domain-joined behaviour. Where an output depends on my machine (counts, times), it is only an example.

## CIM: asking the operating system questions

Windows exposes a large, structured description of itself through **WMI** (Windows Management Instrumentation). The current PowerShell interface to it is **CIM**: `Get-CimInstance`, `Get-CimClass`, `Invoke-CimMethod`. The older `Get-WmiObject` family works in 5.1; in my 7.6.10 install `Get-Command Get-WmiObject` also found it, but write new scripts with the CIM cmdlets. See [Get-CimInstance](https://learn.microsoft.com/powershell/module/cimcmdlets/get-ciminstance) and the [WMI chapter of PowerShell 101](https://learn.microsoft.com/powershell/scripting/learn/ps101/07-working-with-wmi).

```powershell
Get-CimInstance -ClassName Win32_OperatingSystem |
    Select-Object -Property Caption, Version, BuildNumber, LastBootUpTime
```

```
Caption        : Microsoft Windows 11 Home
Version        : 10.0.26300
BuildNumber    : 26300
LastBootUpTime : 11/21/2026 12:29:39 PM
```

`LastBootUpTime` is a real `System.DateTime` (I checked), so `(Get-Date) - $os.LastBootUpTime` gives a `TimeSpan`: uptime in one line, no string parsing.

### Filter at the source, not in the pipeline

`-Filter` uses **WQL** (a small SQL-like language, [WQL reference](https://learn.microsoft.com/windows/win32/wmisdk/wql-sql-for-wmi)) and is evaluated by the provider, so only matching objects are returned:

```powershell
Get-CimInstance -ClassName Win32_Service -Filter "Name = 'Spooler'" |
    Select-Object Name, State, StartMode, StartName
Get-CimInstance -Query "SELECT Name, State FROM Win32_Service WHERE State = 'Running'"
```

WQL is **not** PowerShell: equality is `=` (not `-eq`), "not equal" is `<>`, strings are in single quotes and `\` must be doubled. Splicing untrusted text into a WQL string is an injection risk exactly like SQL: validate it (`[ValidatePattern()]`, `[ValidateSet()]`) before you build the filter.

Discover what a class offers with `Get-CimClass`:

```powershell
(Get-CimClass -ClassName Win32_Service).CimClassMethods.Name | Select-Object -First 4
```

```
StartService
StopService
PauseService
ResumeService
```

[`Win32_Service`](https://learn.microsoft.com/windows/win32/cimwin32prov/win32-service) is documented property by property; read it, because CIM shows things the service cmdlets do not (for example `StartName`, the account the service runs as, and `ExitCode`). To call a method use [`Invoke-CimMethod`](https://learn.microsoft.com/powershell/module/cimcmdlets/invoke-cimmethod); I ran `ChangeStartMode` with `-Arguments @{ StartMode = 'Manual' }` and `Get-Service` then reported `Manual`.

A useful audit, **automatic services that are not running** (it finds services that failed or are legitimately delayed or triggered; judge each one):

```powershell
Get-CimInstance -ClassName Win32_Service -Filter "StartMode = 'Auto' AND State <> 'Running'" |
    Select-Object Name, State, ExitCode
```

On the lab VM this listed `BITS`, `sppsvc` and `StateRepository`, all stopped with exit code 0: they are trigger-started or on demand in practice, so "stopped" there was not a fault. **A finding is a question, not a verdict.**

## The registry provider

PowerShell mounts the registry as drives (`Get-PSDrive -PSProvider Registry`): on my machine `HKCU:` and `HKLM:`. **Keys behave like folders and values behave like properties of the key**, which is the one idea that explains all the cmdlets. Background: [registry hives](https://learn.microsoft.com/windows/win32/sysinfo/registry-hives), [registry value types](https://learn.microsoft.com/windows/win32/sysinfo/registry-value-types) and [about_Registry_Provider](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_registry_provider).

| To do this | Use |
|---|---|
| List subkeys | `Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft` |
| Create or remove a key | `New-Item`, `Remove-Item -Recurse` |
| Read all values of a key | `Get-ItemProperty -Path <key>` |
| Read one value as a plain value | `Get-ItemPropertyValue -Path <key> -Name <name>` |
| Create a value (and choose its type) | `New-ItemProperty -Path <key> -Name <n> -Value <v> -PropertyType DWord` |
| Change a value | `Set-ItemProperty` |
| Delete a value | `Remove-ItemProperty` |

```powershell
Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' |
    Select-Object ProductName, CurrentBuild, DisplayVersion
```

```
ProductName    : Windows 10 Home
CurrentBuild   : 26300
DisplayVersion : 26H2
```

That is a real result from a **Windows 11** machine: the `ProductName` value still says "Windows 10". **Never decide the Windows version from `ProductName`**; use the build number (`CurrentBuild`, or `[Environment]::OSVersion`; Windows 11 builds are 22000 and later, which I did not re-verify here). Registry data is whatever some program wrote.

`Get-ItemProperty` returns one object whose properties are the values, **plus** PowerShell's own `PSPath`, `PSParentPath`, `PSChildName`, `PSDrive` and `PSProvider`. If you loop over "all values", skip those. A value cannot be tested with `Test-Path` (`Test-Path "$key\Count"` was `False` even though the value existed): `Test-Path` tests **keys**. Test a value with `(Get-Item -LiteralPath $key).GetValueNames() -contains 'Count'`.

### Traps I reproduced (in my own `HKCU:\Software\WinLabTest` key, removed afterwards)

1. **`New-ItemProperty` refuses to overwrite.** Running it twice gives `System.IO.IOException: The property already exists.` Use `Set-ItemProperty` to change, `New-ItemProperty` to create, or `-Force` when you mean overwrite.
2. **`Set-ItemProperty` guesses the type** when the value is new: `-Value 5` created a `DWord`, `-Value '5'` created a `String`. Software that reads a DWORD will not accept your string. **Always pass `-Type`/`-PropertyType` when creating a value.** `(Get-Item -LiteralPath $key).GetValueKind('Count')` shows what is stored (`DWord`, `MultiString`, ...).
3. **`-Path` treats `[ ]` as a wildcard.** For a key named `a[1]`, `Test-Path -Path '...\a[1]'` was **False** and `Test-Path -LiteralPath '...\a[1]'` was **True**. Use `-LiteralPath` whenever the path comes from data (it is the same trap as in the file lessons).
4. **The "(default)" value** of a key is set with `Set-Item -Path $key -Value 'text'` and read as `(Get-ItemProperty $key).'(default)'`.

### Which hive, and 32 or 64 bit

`HKLM:` needs administrator rights to **write**, `HKCU:` does not. `HKLM:\SOFTWARE\WOW6432Node` is where 32-bit programs see "their" `HKLM\SOFTWARE`; a 64-bit PowerShell sees the real one. Per-user settings of *other* users are in their `NTUSER.DAT` files and are not loaded unless you load the hive (`reg.exe load`): that is advanced and easy to damage a profile with.

### Backup before change

The change that matters most is the one you can undo. `reg.exe export` writes a `.reg` file ([reg](https://learn.microsoft.com/windows-server/administration/windows-commands/reg)); I exported a test key and the file read:

```
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\WinLabTest]
"Enabled"=dword:00000001
```

**Read a `.reg` file before you double-click it:** importing merges everything in it into the live registry with no preview.

**The GUI route.** `regedit.exe` shows the same tree. Right-click a key, **Export** saves a backup; **New**, then the value type (DWORD, String...) creates a value, which is the type choice that `-PropertyType` makes in PowerShell. `regedit` has no undo, so export first.

## Services

```powershell
Get-Service -Name Spooler | Select-Object Name, Status, StartType
Start-Service -Name BITS
Stop-Service  -Name BITS
Restart-Service -Name BITS -PassThru
Set-Service   -Name BITS -StartupType Manual     # Automatic, Manual, Disabled
```

What I observed (lab VM, elevated, 5.1):

- `Start-Service` on a service that is **already running** and `Stop-Service` on one that is **already stopped** both succeed silently. That is good for scripts: they are naturally safe to repeat.
- By default these cmdlets **do not print anything**; add `-PassThru` to get the service object back, which is how you *prove* the new state (`Running`, `Stopped`).
- Stopping a service that others depend on is refused: `Cannot stop service 'Remote Procedure Call (RPC) (RPCSS)' because it has dependent services. It can only be stopped if the Force flag is set.` Read `(Get-Service X).DependentServices` first; `-Force` stops the dependents too, so say what will go down.
- `Get-Service` on a name that does not exist raises `NoServiceFoundForGivenName,Microsoft.PowerShell.Commands.GetServiceCommand`, a terminating-capable error you can catch with `-ErrorAction Stop`. Wildcards work (`Get-Service 'Spool*'`).
- `Get-Service` gives `Status`, `StartType` and dependencies; **CIM gives the account, the command line and the exit code** (`Win32_Service`). Use whichever has the property you need.

**Recovery options** (what Windows does when a service crashes) are not in `Get-Service`. `sc.exe qfailure Spooler` showed two `RESTART` actions with a 5000 ms delay; `sc.exe failure Spooler reset= 86400 actions= restart/60000/restart/60000//` changed it to 60 000 ms and a 86 400 s reset period. Write `sc.exe`, not `sc`: in PowerShell `sc` is an alias of `Set-Content`, which would "succeed" while writing a file. This is the rule from the earlier lessons.

**The GUI route.** `services.msc`: double-click a service; the General tab has Startup type and Start/Stop; Recovery tab has the failure actions; Dependencies tab shows who needs whom.

**The event trail.** Service control writes to the System log: event 7036 (`The Background Intelligent Transfer Service service entered the stopped state.`), and 7040 for a start-type change. A script that changes a service can be audited with `Get-WinEvent`.

## Event logs

Use **`Get-WinEvent`**. `Get-EventLog` only reads the classic logs and is documented under previous versions; my 5.1 and my 7.6.10 both had it, but it cannot read the modern per-application logs and I would not write new code with it. See [Get-WinEvent](https://learn.microsoft.com/powershell/module/microsoft.powershell.diagnostics/get-winevent).

```powershell
Get-WinEvent -ListLog System, Application |
    Select-Object LogName, RecordCount, MaximumSizeInBytes, LogMode
Get-WinEvent -LogName System -MaxEvents 3 |
    Select-Object TimeCreated, Id, ProviderName, LevelDisplayName
```

```
LogName     RecordCount MaximumSizeInBytes LogMode
System            23333           20971520 Circular
Application       7613            20971520 Circular
```

### Filter in the query, not afterwards

`-FilterHashtable` sends the filter to the event log service ([guide](https://learn.microsoft.com/powershell/scripting/samples/creating-get-winevent-queries-with-filterhashtable)):

```powershell
Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 6005, 6006, 6013 } -MaxEvents 3
Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Service Control Manager'; Level = 2; StartTime = (Get-Date).AddDays(-1) }
```

Keys include `LogName`, `ProviderName`, `Id`, `Level` (1 critical, 2 error, 3 warning, 4 information), `StartTime`, `EndTime`. I timed the two ways of finding event 7036 on my host: reading 3000 events and piping to `Where-Object Id -eq 7036` took **1130 ms**; the same question with `-FilterHashtable` took **32 ms**. (An example from one machine; the gap, not the numbers, is the point.)

**When nothing matches, `Get-WinEvent` raises an error**, not an empty result: `NoMatchingEventsFound,Microsoft.PowerShell.Commands.GetWinEventCommand` with `No events were found that match the specified selection criteria.` A script that looks for "any errors today" must catch this and treat it as "none", not as a failure:

```powershell
try   { $events = Get-WinEvent -FilterHashtable $filter -ErrorAction Stop }
catch [System.Exception] {
    if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { $events = @() } else { throw }
}
```

### Reading the data

`$event.Message` is human text built from a template; the values are in `$event.Properties` (an array in a fixed order) or, with names, in the XML:

```powershell
$ev = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 7036 } -MaxEvents 1
([xml]$ev.ToXml()).Event.EventData.Data | ForEach-Object { "$($_.Name)=$($_.'#text')" }
```

```
param1=Software Protection
param2=running
```

Note one more detail from my host: a 7036 `Message` read `The  service entered the Filter detach complete state.` (a missing service name). A message can be empty or wrong when the provider's message file is absent; the XML data is the reliable part.

The **Security** log needs elevation: in the elevated session `Get-WinEvent -LogName Security -MaxEvents 1` returned event 4672 (special privileges assigned to a new logon); I did not test it from a non-elevated prompt, but Microsoft documents that reading the Security log needs administrator rights.

### Writing your own events

A script that runs unattended should leave a trace where the administrator already looks. In 5.1 (and in my 7.6.10):

```powershell
New-EventLog   -LogName Application -Source WinLabTool      # needs elevation, once
Write-EventLog -LogName Application -Source WinLabTool -EventId 4001 -EntryType Warning -Message 'WinLab test event'
Remove-EventLog -Source WinLabTool                          # undo
```

I read it back: `Id: 4001, LevelDisplayName: Warning, Message: WinLab test event`. Creating a source needs administrator rights; *writing* later usually does not. Pick an event ID range of your own and document it. ([Write-EventLog](https://learn.microsoft.com/powershell/module/microsoft.powershell.management/write-eventlog), [New-EventLog](https://learn.microsoft.com/powershell/module/microsoft.powershell.management/new-eventlog).)

**The GUI route.** `eventvwr.msc` (Event Viewer): **Windows Logs, System**, then **Filter Current Log** (the same fields as the hashtable) and **Attach Task To This Event**. **Log size** and **retention** are under the log's Properties; `wevtutil.exe gl Application` showed the same settings in text.

## Scheduled tasks

A task has four parts, and PowerShell has one `New-` command for each: an **action** (what runs), a **trigger** (when), a **principal** (as whom, at what level) and **settings**. Then `Register-ScheduledTask` puts them together.

```powershell
$action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -Command "Get-Date | Out-File C:\wl-task.txt"'
$trigger = New-ScheduledTaskTrigger -Daily -At 3am
$princ   = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
$set     = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName WinLabDemo -Action $action -Trigger $trigger -Principal $princ -Settings $set
```

```
TaskName   State
WinLabDemo Ready
```

Then, in the VM:

```powershell
Start-ScheduledTask -TaskName WinLabDemo
Get-ScheduledTaskInfo -TaskName WinLabDemo | Select-Object LastTaskResult, LastRunTime
```

`LastTaskResult : 0` and the file `C:\wl-task.txt` held the date, so the task really ran as SYSTEM. Facts to remember:

- **Registering a name that exists is an error** (`Cannot create a file when that file already exists.`). For repeatable scripts, check first (`Get-ScheduledTask -TaskName X -ErrorAction SilentlyContinue`) or pass `-Force` to replace.
- `LastTaskResult` is `0` for success; other values are error codes of the action. A task that *started* is not a task that *worked*: check this value.
- `New-ScheduledTaskTrigger -Once -At ... -RepetitionInterval (New-TimeSpan -Minutes 15)` gave `Repetition.Interval : PT15M` (an ISO 8601 duration).
- `-RunLevel Highest` and `SYSTEM` mean the task runs with maximum rights: **a task you can edit that runs as SYSTEM is a way to become SYSTEM**. Audit who can modify a task's script file and the task itself. Keep tasks least-privilege.
- Remove what you made: `Disable-ScheduledTask`, `Unregister-ScheduledTask -Confirm:$false`.
- `schtasks.exe /Query /TN '\Microsoft\Windows\Defrag\ScheduledDefrag' /FO LIST` is the older tool for the same data ([schtasks](https://learn.microsoft.com/windows-server/administration/windows-commands/schtasks)); learn to read both, because many knowledge-base articles still use it.
- Cmdlets: [Register-ScheduledTask](https://learn.microsoft.com/powershell/module/scheduledtasks/register-scheduledtask), [New-ScheduledTaskAction](https://learn.microsoft.com/powershell/module/scheduledtasks/new-scheduledtaskaction), [New-ScheduledTaskTrigger](https://learn.microsoft.com/powershell/module/scheduledtasks/new-scheduledtasktrigger), [New-ScheduledTaskPrincipal](https://learn.microsoft.com/powershell/module/scheduledtasks/new-scheduledtaskprincipal), [Get-ScheduledTaskInfo](https://learn.microsoft.com/powershell/module/scheduledtasks/get-scheduledtaskinfo).

**The GUI route.** `taskschd.msc` (Task Scheduler): **Create Task** (not "Create Basic Task", which hides the principal and settings), tabs General (account, "Run with highest privileges"), Triggers, Actions, Conditions, Settings, and History (enable it first).

## Safe changes: `-WhatIf`, `-Confirm` and idempotence

Every cmdlet above that changes something supports **`-WhatIf`** (say what you would do) and **`-Confirm`** (ask first). I ran:

```
PS> Stop-Service -Name Spooler -WhatIf
What if: Performing the operation "Stop-Service" on target "Print Spooler (Spooler)".
PS> Remove-Item -Path HKLM:\SOFTWARE\WinLabTest -Recurse -WhatIf
What if: Performing the operation "Remove Key" on target "Item: HKEY_LOCAL_MACHINE\SOFTWARE\WinLabTest".
```

and each call only printed the message; the real commands that came after made the changes. See [about_CommonParameters](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters) and [Everything you wanted to know about ShouldProcess](https://learn.microsoft.com/powershell/scripting/learn/deep-dives/everything-about-shouldprocess).

**Read-before-run rule:** when you receive a script that changes the system, run it with `-WhatIf` only if it supports it *and you have read it*: a script is free to ignore the preference, and a `-WhatIf` on the script does not propagate into programs it launches (`sc.exe`, `reg.exe`). Reading is the real protection.

**Your own functions.** Add `SupportsShouldProcess` and wrap the change in `$PSCmdlet.ShouldProcess()`. Combined with a check for the current state, the function becomes **idempotent**: running it twice leaves the same result, and the second run changes nothing.

```powershell
function Set-WlServiceState {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('Running', 'Stopped')][string]$State
    )
    $service = Get-Service -Name $Name -ErrorAction Stop
    if ($service.Status -eq $State) {
        Write-Verbose "$Name is already $State"
        return 'unchanged'
    }
    if ($PSCmdlet.ShouldProcess($Name, "set $State")) {
        if ($State -eq 'Running') { Start-Service -Name $Name } else { Stop-Service -Name $Name }
        return 'changed'
    }
}
```

My run, calling it five times on the lab VM:

```
Set-WlServiceState -Name Spooler -State Running -Verbose   -> VERBOSE: Spooler is already Running  / unchanged
Set-WlServiceState -Name Spooler -State Stopped -WhatIf    -> What if: Performing the operation "set Stopped" on target "Spooler".
Set-WlServiceState -Name Spooler -State Stopped            -> changed
Set-WlServiceState -Name Spooler -State Stopped            -> unchanged
Set-WlServiceState -Name Spooler -State Running            -> changed
```

Note that the `-WhatIf` call printed the message and returned **nothing** (no output object), which is why a caller should not depend on a return value under `-WhatIf`. That is the whole pattern: **inspect, compare with the wanted state, change only the difference, report what you did.** A script built this way is safe to run from a scheduled task every hour, and a re-run after a crash finishes the job instead of damaging it.

(The Spooler is a printing service. In the lab it ran as an ordinary service; I did not diagnose a start failure I saw once on it during testing, so I used `BITS` for the start and stop demonstrations. Do not stop the Spooler on a machine where someone is printing.)

## Reading an unknown administration script

Before running any script that touches services, the registry or tasks, scan for these:

| Look for | Why it matters |
|---|---|
| `Set-ItemProperty ... HKLM:` or `reg.exe add` under `Run`, `RunOnce`, `Image File Execution Options`, `Winlogon` | persistence: code that starts at every logon or boot |
| `Register-ScheduledTask`, `schtasks /create`, `-RunLevel Highest`, `SYSTEM` | persistence with maximum rights |
| `New-Service`, `sc.exe create`, `Set-Service -StartupType Disabled` on security services | a new startup path, or switching defences off |
| `Set-MpPreference -Disable...`, `Add-MpPreference -ExclusionPath`, `netsh advfirewall ... off` | weakening protection |
| `Clear-EventLog`, `wevtutil cl` | erasing the evidence |
| `Invoke-Expression`, `-EncodedCommand`, `DownloadString` | code you cannot see before it runs |

Exercise 6 below uses these. None of them is evil by itself (an installer legitimately creates a service); the question is always **who asked for it, and does the script say why**.

## Common mistakes

- Using `Where-Object` after `Get-WinEvent -LogName`: works, was far slower in my test (1130 ms against 32 ms, though the two commands read different amounts), and may miss old events if `-MaxEvents` cut the list first. Filter in the query.
- Treating `NoMatchingEventsFound` as a crash (or hiding all errors with `SilentlyContinue`).
- Writing a registry value without a type and getting a `String` where a program wants a `DWord`.
- Using `-Path` with a path from data; use `-LiteralPath`.
- Trusting `ProductName`.
- Calling `sc` instead of `sc.exe`.
- `New-ScheduledTask...` that runs a script from a folder any user can write to.
- A script that works only when run twice because the first run fails on "already exists".
- Forgetting that an unelevated run reads fine but fails on write: check elevation at the top (`[Security.Principal.WindowsPrincipal]` with `IsInRole(Administrator)`) and say so.

## Practice

1. Print the uptime of the machine in days and hours using CIM, without text parsing.
2. List all `Running` services whose account is not `LocalSystem`, `NT AUTHORITY\LocalService` or `NT AUTHORITY\NetworkService` (use `Win32_Service` and `StartName`).
3. In `HKCU:\Software\<YourName>Test`, create a `DWord`, a `String` and a `MultiString` value, read each type back with `GetValueKind`, prove that `New-ItemProperty` refuses to overwrite, then remove the key. Export it first with `reg.exe`.
4. Find the last five **error** events from `Service Control Manager` in the System log, treating "none found" as a normal answer.
5. In a lab VM, register a task that writes the date to a file every minute, check `LastTaskResult`, then remove the task and the file.
6. **Read this script and list every change it makes and why a defender would care:**

   ```powershell
   $p = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
   Set-ItemProperty -Path $p -Name Updater -Value 'C:\ProgramData\u.ps1'
   $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-w hidden -File C:\ProgramData\u.ps1'
   Register-ScheduledTask -TaskName 'WindowsUpdateCheck' -Action $a -Trigger (New-ScheduledTaskTrigger -AtLogOn) -User SYSTEM -RunLevel Highest
   Add-MpPreference -ExclusionPath 'C:\ProgramData'
   wevtutil.exe cl Security
   ```
7. Write `Set-WlRegistryValue` (name, value, type) that does nothing when the value is already right, supports `-WhatIf`, and returns `changed` or `unchanged`. Test it three times.

## Check your understanding

1. Why use `Get-CimInstance` with `-Filter` instead of `Where-Object`?
2. Is `-Filter "State = 'Running'"` PowerShell syntax? What is it?
3. Which cmdlet creates a registry value with a chosen type, and what does `Set-ItemProperty` do about the type when the value is new?
4. Why does `Test-Path` not tell you whether a registry *value* exists?
5. Why is `-LiteralPath` needed for a key named `a[1]`?
6. What does `Get-WinEvent` do when no event matches, and how should a script treat it?
7. What does `-WhatIf` do, and what does it not protect you from?
8. What makes a script idempotent?

**Expected answers:** (1) the provider filters, so fewer objects cross the boundary and it is faster; (2) WQL, a SQL-like query language: `=`, `<>`, single-quoted strings; (3) `New-ItemProperty -PropertyType`; `Set-ItemProperty` guesses from the .NET type of the value (an integer became `DWord`, text `String`), so pass the type explicitly; (4) `Test-Path` tests items (keys), and values are properties of a key; use `GetValueNames()` or `Get-ItemProperty`; (5) `-Path` treats `[ ]` as a wildcard, so it looked for something else and returned False; (6) it raises `NoMatchingEventsFound`; catch it and treat it as an empty result; (7) it prints what it would do instead of doing it; it does not constrain a script that ignores it or the external programs it runs; (8) it checks the current state, changes only the difference and so produces the same result when run again.
