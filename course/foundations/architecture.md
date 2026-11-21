*Draft for owner review.* Every administration task in this course happens on top of the same structure. Knowing that structure tells you where to look when something goes wrong, so this lesson comes first. Each idea is paired with the command that lets you see it on your own machine, in Command Prompt and PowerShell as well as the graphical tools.

Names, IDs and addresses in the examples are samples; the layout is real output from Windows 11.

## Two modes of execution

Code on Windows runs in one of two processor modes ([User mode and kernel mode](https://learn.microsoft.com/windows-hardware/drivers/gettingstarted/user-mode-and-kernel-mode)).

- **Kernel mode** is where the operating system core and device drivers run. Code here can reach all memory and all hardware. A fault in kernel mode can stop the whole machine, which is what a blue screen is.
- **User mode** is where applications and most services run. Each process gets its own private view of memory and cannot touch hardware or other processes directly. If a user-mode process crashes, Windows keeps running.

A user-mode program asks the kernel to do privileged work (open a file, create a thread, send network data) through system calls. Applications rarely make those calls themselves. They call the **Win32 API** (and other documented APIs), and the operating system's libraries translate those calls into system calls.

**Why it matters:** a crashing application and a crashing driver are different problems. A blue screen points you at drivers, hardware and the kernel. An application that closes or freezes points you at the application, its settings and its dependencies.

### Seeing the drivers

Drivers are the kernel-mode code you add to the system. List them from Command Prompt:

```
driverquery /fo table

Module Name  Display Name           Driver Type   Link Date
============ ====================== ============= ==========
1394ohci     1394 OHCI Compliant Ho Kernel
```

See [`driverquery`](https://learn.microsoft.com/windows-server/administration/windows-commands/driverquery). After a blue screen that began with a new driver, this list and the install date of the driver are the first things to look at.

## Programs, processes and threads

- A **program** is a file on disk, usually an `.exe`.
- A **process** is a running instance of a program. It has its own memory, a security identity (the user it runs as) and at least one thread.
- A **thread** is a unit of execution inside a process. Windows schedules threads onto processor cores.

Starting the same program twice gives two processes, each with its own **process ID (PID)**. See [Processes and threads](https://learn.microsoft.com/windows/win32/procthread/processes-and-threads).

### Seeing processes from the command line

Command Prompt, with [`tasklist`](https://learn.microsoft.com/windows-server/administration/windows-commands/tasklist):

```
tasklist /fi "imagename eq explorer.exe" /v /fo list

Image Name:   explorer.exe
PID:          8852
Session Name: Console
Session#:     1
Mem Usage:    255,536 K
Status:       Running
User Name:    DESKTOP-ABC123\student
CPU Time:     0:00:22
```

PowerShell, with [`Get-Process`](https://learn.microsoft.com/powershell/module/microsoft.powershell.management/get-process):

```
Get-Process explorer | Format-List Id,SessionId,ProcessName,Path

Id          : 8852
SessionId   : 1
ProcessName : explorer
Path        : C:\WINDOWS\Explorer.EXE
```

`Get-Process` gives you the **path** of the file the process was started from, which is how you tell a genuine system process from an impostor with the same name. For the **parent** process and the full command line, ask [`Get-CimInstance`](https://learn.microsoft.com/powershell/module/cimcmdlets/get-ciminstance) for the process object:

```
Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | Format-List ProcessId,ParentProcessId,CommandLine

ProcessId       : 8852
ParentProcessId : 8760
CommandLine     : C:\WINDOWS\Explorer.EXE
```

Processes form a tree: each has a parent. A process whose parent is unexpected (a document viewer that started a command shell) is worth a second look; the security lessons return to this.

## Services

A **service** is a process that Windows starts and manages without a user needing to sign in, such as the print spooler or Windows Update ([Services](https://learn.microsoft.com/windows/win32/services/services)). Services have a start type (automatic, manual or disabled) and normally run under a service account instead of your own ([service user accounts](https://learn.microsoft.com/windows/win32/services/service-user-accounts)). The services lesson covers managing them; for now, recognise that many background processes you see are services.

```
Get-Service | Group-Object Status | Select-Object Name,Count
sc query type= service state= all        # Command Prompt equivalent (note the space after '=')
```

## Sessions, users and profiles

- A **logon session** is created each time an account signs in. Services run in their own non-interactive session (session 0), separate from the desktop sessions of signed-in users ([interactive services](https://learn.microsoft.com/windows/win32/services/interactive-services) explains why a service cannot show a window on your desktop).
- Every user has a **profile**: a folder under `C:\Users` holding documents, desktop items, application settings and that user's registry hive (`NTUSER.DAT`).
- Windows identifies accounts by a **security identifier (SID)**, not by name. Names are for people; SIDs are what permissions are actually stored against ([security identifiers](https://learn.microsoft.com/windows/win32/secauthz/security-identifiers)).

```
whoami /user

USER INFORMATION
----------------

User Name              SID
====================== ==============================================
desktop-abc123\student S-1-5-21-1111111111-2222222222-3333333333-1001
```

A SID has the form `S-1-5-21-<machine or domain identifier>-<RID>`. The last number, the **RID**, is the account's own number on that machine; 500 is the built-in Administrator and ordinary accounts start at 1000. A few SIDs are the same on every machine and are called **well-known SIDs** ([list](https://learn.microsoft.com/windows/win32/secauthz/well-known-sids)): `S-1-5-18` is the **SYSTEM** account, `S-1-5-19` Local Service, `S-1-5-20` Network Service, and `S-1-5-32-544` the local **Administrators** group. See [`whoami`](https://learn.microsoft.com/windows-server/administration/windows-commands/whoami) and [`Get-LocalUser`](https://learn.microsoft.com/powershell/module/microsoft.powershell.localaccounts/get-localuser).

Two accounts with the same display name but different SIDs are different accounts with different permissions. A deleted and re-created account with the same name gets a new SID and does **not** inherit the old one's permissions.

## What lives where

| Location | Purpose |
| --- | --- |
| `C:\Windows` | The operating system itself |
| `C:\Windows\System32` | Core system programs and libraries (64-bit on a 64-bit system) |
| `C:\Program Files` | 64-bit applications |
| `C:\Program Files (x86)` | 32-bit applications on a 64-bit system |
| `C:\ProgramData` | Application data shared by all users |
| `C:\Users\<name>` | One user's profile |

The system drive is not always `C:`. The environment variable `%SystemRoot%` always points at the Windows folder, and `%SystemDrive%` at the drive containing it. Use these in scripts instead of assuming `C:`. Environment variables are shown with `set` in Command Prompt ([`set`](https://learn.microsoft.com/windows-server/administration/windows-commands/set_1)) and as `$env:` in PowerShell:

```
echo %SystemRoot%
echo %USERPROFILE%
```

```
$env:SystemRoot
$env:USERPROFILE
Get-ChildItem Env:        # every variable
```

Special folders such as Documents and Downloads are called **known folders** and can be moved elsewhere (for example by OneDrive), so do not assume `%USERPROFILE%\Documents`; see [Known Folders](https://learn.microsoft.com/windows/win32/shell/knownfolderid).

## Which Windows is this?

Before you troubleshoot, know the edition, version and build, because documentation and behaviour differ between them.

```
Get-ComputerInfo -Property OsName,OsVersion,OsBuildNumber,OsArchitecture

OsName         : Microsoft Windows 11 Home
OsVersion      : 10.0.26300
OsBuildNumber  : 26300
OsArchitecture : 64-bit
```

From Command Prompt, `ver` prints the version and `systeminfo` prints much more. `winver` opens a window with the same facts. See [`Get-ComputerInfo`](https://learn.microsoft.com/powershell/module/microsoft.powershell.management/get-computerinfo). Windows 11 reports itself as version `10.0` with a build number of 22000 or higher; Windows 10 has builds below that. This course treats **Windows 10 as the oldest supported client** and Windows 11 Pro as its default.

## Working from the terminal

You will spend much of this course in a terminal, often a remote one with no graphical tools. Get comfortable with one text editor that works there.

- **Windows Terminal** hosts Command Prompt, PowerShell and WSL side by side in tabs ([documentation](https://learn.microsoft.com/windows/terminal/)).
- **Microsoft Edit** (`edit`) is a small, open-source (MIT) terminal text editor with a modern interface and VS Code-like controls. It ships with Windows 11, so `edit C:\path\file.txt` works on a stock install, and it can be installed on Windows 10 and other systems (for example `winget install Microsoft.Edit`), and the project publishes Linux and Windows builds on its GitHub releases page. It is a good default for editing a config file or a script over a remote session when you would otherwise reach for Notepad. Its home is [github.com/microsoft/edit](https://github.com/microsoft/edit) (see the [wiki](https://github.com/microsoft/edit/wiki)).
- On Linux the same role is played by `nano`, `vim` or `vi`; the Linux lessons introduce them.

```
edit $PROFILE            # PowerShell: open your PowerShell startup script (it may not exist yet)
notepad file.txt         # a graphical editor, for comparison
```

Install it only where you are allowed to install software; on a locked-down machine, use what is there.

## Guided exercise: observe, do not change

This exercise only looks at your system. Do each step both ways.

1. **Graphical:** press **Ctrl+Shift+Esc** to open **Task Manager**. Open the **Details** tab. Right-click a column header, choose **Select columns**, and enable **PID**, **User name** and **Session ID**.
2. **Command line:** run `tasklist /v /fo table`, and in PowerShell `Get-Process | Sort-Object Id | Select-Object -First 10 Id,SessionId,ProcessName`.
3. Find `explorer.exe`. Note its PID, the user it runs as and its session ID.
4. Find any entry whose user is `NT AUTHORITY\SYSTEM`. Note its session ID. Compare it with the one from step 3.
5. Run `whoami /user` and write down your SID, then compare the last number with what `Get-LocalUser | Select-Object Name,SID` shows.
6. Run `echo %SystemRoot%` and `echo %USERPROFILE%` and confirm the values match the table above for your machine.
7. Run `Get-ComputerInfo -Property OsName,OsVersion,OsBuildNumber` and note your build.

## Common mistakes

- **Assuming the system drive is `C:`.** Use `%SystemRoot%` and `%SystemDrive%`.
- **Judging a process by its name.** Check its path and parent.
- **Treating a name as identity.** Permissions follow the SID.
- **Reading every blue screen as a hardware fault.** Kernel mode includes drivers, and drivers are the usual cause after a change.
- **Expecting a service to show a window on your desktop.** Services run in session 0.
- **Not knowing the build.** A fix that works on one build may not apply to another.

## Check your understanding

1. A machine shows a blue screen after a new driver is installed. Which mode is most likely involved, and why?
2. You start Notepad twice. How many processes exist, and how do you tell them apart?
3. Why might two users with the same display name still have different permissions?
4. Which command shows the file path a running process was started from?
5. Which well-known SID is the SYSTEM account? What does `S-1-5-32-544` stand for?
6. A user's account was deleted and re-created with the same name, and they lost access to their old files. Why?

**Expected answers:** (1) kernel mode, because drivers run there and a fault there stops the whole system; (2) two, distinguished by PID; (3) permissions are stored against the SID, and two accounts have different SIDs even if the names look alike; (4) `Get-Process <name> | Format-List Path`, or `Get-CimInstance Win32_Process` for the command line too; (5) `S-1-5-18`; the local Administrators group; (6) the new account has a new SID, and the old permissions were stored against the old SID.
