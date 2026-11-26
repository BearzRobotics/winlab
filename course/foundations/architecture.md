*Draft for owner review.* Every administration task in this course happens on top of the same structure. Knowing that structure tells you where to look when something goes wrong, so this lesson comes first. Each idea is paired with commands that let you see it on your own machine, and with **how to read what they print**: why you would run it, what is normal, and what to do next.

**What was tested, and where.** The new measurements and driver, service and process results were run on **one Windows 11 Home PC (build 26300)** in Windows PowerShell 5.1 as a standard (not elevated) user (`tests/verification/powershell/arch1.ps1`). The Linux comparison ran in Ubuntu 26.04 under WSL2 (`tests/verification/bash/arch-usersys.sh`). Names, user IDs and SIDs in a few examples are samples; the layout is real output. Your numbers **will** differ. The graphical Task Manager steps were not exercised by these scripts, and Windows 10 was not tested.

## Two modes of execution

The processor can run code with **more or less power**, and Windows uses two levels ([User mode and kernel mode](https://learn.microsoft.com/windows-hardware/drivers/gettingstarted/user-mode-and-kernel-mode)):

- **Kernel mode** is where the operating system core and most device drivers run. Code here can reach all memory and all hardware. A fault here can stop the whole machine: that is what a blue screen is.
- **User mode** is where your applications and most services run. Each process gets its own private view of memory and cannot touch hardware or another process's memory directly. If a user-mode program crashes, Windows keeps running.

You will also hear **user space** and **kernel space**. People often use them for the same split. Strictly, the *mode* is how much power the processor has while code runs, and the *space* is the area of memory that code lives in.

```text
 +--------------------------------------------------------------------+
 |  USER MODE          (each process walled off from the others)      |
 |                                                                    |
 |   +-----------+   +-----------+   +-------------+   +-----------+  |
 |   | notepad   |   | browser   |   | powershell  |   | a service |  |
 |   +-----------+   +-----------+   +-------------+   +-----------+  |
 |        |               |                |                |         |
 |        +---------------+--------+-------+----------------+         |
 |                                 |                                  |
 |            system libraries (kernel32.dll, ..., ntdll.dll)         |
 +=================================|==================================+
 |  KERNEL MODE                    |  system call: the only way down  |
 |                                 v                                  |
 |   +-------------------------------------------------------------+  |
 |   | Windows kernel and executive: processes, memory, files,     |  |
 |   | security checks, I/O                                        |  |
 |   +-------------------------------------------------------------+  |
 |   | drivers: disk, file system, network, USB, graphics ...      |  |
 |   +-------------------------------------------------------------+  |
 +=================================|==================================+
                                   v
        HARDWARE:   processor    memory    disks    network    USB
```

(The parts inside kernel mode are described in [Overview of Windows components](https://learn.microsoft.com/windows-hardware/drivers/kernel/overview-of-windows-components). The diagram is simplified: part of the graphics system and some drivers do not sit exactly where drawn.)

### Why have two levels

Think about what would happen **without** the wall: any program with a bug could overwrite another program's memory, or Windows itself, or write straight to the disk and ignore file permissions. The split gives you three things you rely on as an administrator:

1. **Stability.** A crashing program takes only itself down.
2. **Security.** A program cannot simply read a file it has no right to. It has to **ask** the kernel, and the kernel checks permissions first.
3. **One door.** Because requests go through the kernel, that is where Windows can check, count and record them.

### Private memory: each process has its own map

Each user-mode process gets its own **virtual address space**: its own numbering of memory, which the system maps to real memory. The same address in two processes usually means two different places. Kernel-mode code shares **one** address space ([Virtual address spaces](https://learn.microsoft.com/windows-hardware/drivers/gettingstarted/virtual-address-spaces)).

```text
   process A              process B                  kernel mode
 +-------------+        +-------------+        +-------------------------+
 | its own     |        | its own     |        | ONE shared space:       |
 | program,    |        | program,    |        | kernel + every          |
 | data and    |        | data and    |        | kernel-mode driver      |
 | libraries   |        | libraries   |        |                         |
 +-------------+        +-------------+        +-------------------------+
   A cannot reach B's memory directly            a bad driver CAN damage
                                                  the kernel and other drivers
```

That right-hand box is why **one faulty driver can crash the whole machine**: nothing walls it off from the rest of the kernel.

### A request, step by step

A program asks the kernel to do privileged work (open a file, create a thread, send network data) through **system calls**. Applications rarely make those calls themselves. They call the **Win32 API** (and other documented APIs), and the operating system's libraries make the system call. Opening a file looks roughly like this:

```text
 1. your program      "open C:\Logs\app.log"
 2. Win32 library      checks and prepares the request        (user mode)
 3. ntdll.dll          issues the system call                 (user mode)
 ----------------------- the processor switches to kernel mode -----------
 4. kernel             MAY THIS USER open this file?  no -> "Access is denied"
 5. file system and disk drivers fetch what is needed
 ----------------------- and switches back -------------------------------
 6. your program receives a HANDLE (a ticket for the open file), or an error
```

Step 4 is worth remembering: **"Access is denied" is the kernel refusing you.** It does not matter which program asked, so switching to another program does not get round a permission.

You can see the libraries in a running process. This asks PowerShell about itself:

```powershell
(Get-Process -Id $PID).Modules |
    Where-Object ModuleName -in 'ntdll.dll','KERNEL32.DLL','KERNELBASE.dll' |
    Format-Table ModuleName, FileName
```

```text
ModuleName     FileName
----------     --------
ntdll.dll      C:\WINDOWS\SYSTEM32\ntdll.dll
KERNEL32.DLL   C:\WINDOWS\System32\KERNEL32.DLL
KERNELBASE.dll C:\WINDOWS\System32\KERNELBASE.dll
```

That PowerShell had 84 modules loaded; these three are part of the road to the kernel. `$PID` is PowerShell's own process ID.

### Watching a program cross the line

Windows keeps two clocks for every process: **user processor time** (running its own code) and **privileged processor time** (the kernel working on its behalf) ([PrivilegedProcessorTime](https://learn.microsoft.com/dotnet/api/system.diagnostics.process.privilegedprocessortime)). So you can *measure* the split. I timed two jobs in one PowerShell: three million additions, then 20,000 tiny writes straight to disk. The full script is in `arch1.ps1`.

```text
arithmetic only (3 million adds)   user    391 ms   kernel     16 ms
file: 20000 small writes to disk   user    344 ms   kernel  1,000 ms
arithmetic only (3 million adds)   user    328 ms   kernel     31 ms
file: 20000 small writes to disk   user    219 ms   kernel    906 ms
```

**How to read it:** adding numbers needs no help, so almost all the time is user time. Writing to a disk can only be done by the kernel and its drivers, so kernel time dominates. The two runs differ a little, as timings always do: look at the **pattern**, not the exact figure.

You can see the same two clocks for any process you are allowed to inspect:

```powershell
Get-Process | Where-Object TotalProcessorTime |
    Sort-Object PrivilegedProcessorTime -Descending |
    Select-Object -First 5 ProcessName, UserProcessorTime, PrivilegedProcessorTime
```

**When this helps:** a program that is slow with high **user** time is busy with its own work (look at the program and its input). Unusually high **kernel** time suggests it is asking the system to do a great deal, such as many small file or network operations, or that a driver is spending the time. It is a **clue, not a verdict**. In Task Manager, the **Performance** tab's CPU graph has a right-click option **Show kernel times** that draws the kernel share separately (not exercised by my scripts).

### Linux has the same split

Linux calls them user space and kernel space, and programs cross with [system calls](https://man7.org/linux/man-pages/man2/syscalls.2.html) too. Bash's `time` prints the same two clocks as `user` and `sys` ([time(7)](https://man7.org/linux/man-pages/man7/time.7.html)). On Ubuntu under WSL2, second run:

```text
1 million additions in bash     real 2.311 s   user 1.954 s   sys 0.356 s
200,000 writes of 16 bytes (dd) real 0.218 s   user 0.033 s   sys 0.185 s
```

Do not compare these numbers with the Windows ones: the jobs and the languages are different. What matches is the pattern: **calculating is user time; asking for I/O is system time.** `real` is the time that passed on the clock.

### When something crashes: which side was it?

| | A **user-mode** program fails | A **kernel-mode** fault |
|---|---|---|
| What you see | One program closes or stops responding | Blue screen, then a restart |
| What else keeps running | Everything else | Nothing |
| Usual suspects | The program, its settings, its files, its libraries | Drivers, hardware, the kernel |
| Where to look first | Event Viewer, **Application** log (crashes are often **Application Error**, event 1000) | The stop code ([bug checks](https://learn.microsoft.com/windows-hardware/drivers/debugger/bug-checks--blue-screens-)), the **System** log and the [dump files](https://learn.microsoft.com/windows-hardware/drivers/debugger/kernel-mode-dump-files) |

To check for both on your own machine (reading only):

```powershell
Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Application Error'; Id=1000} -MaxEvents 5
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WER-SystemErrorReporting'; Id=1001} -MaxEvents 5
Test-Path $env:SystemRoot\Minidump
```

On the test PC the first found **one** application crash and the second found **no** recorded bug check. When nothing matches, `Get-WinEvent` prints an error saying no events were found; for this question that is good news. The `Minidump` folder existed, but **a folder is not a crash**: look inside it for files and their dates.

**Not every driver is in kernel mode.** Windows also supports drivers that run in user mode ([User-Mode Driver Framework](https://learn.microsoft.com/windows-hardware/drivers/wdf/overview-of-the-umdf)), so that a fault in one need not take the machine down.

### Seeing the drivers

Drivers are the code you add to Windows to make it work with hardware and some software, such as virtual machine programs and antivirus. Because most run in kernel mode, they are the first thing to suspect when a **blue screen starts after a change**. [`driverquery`](https://learn.microsoft.com/windows-server/administration/windows-commands/driverquery) lists them:

```text
driverquery /fo table

Module Name  Display Name           Driver Type   Link Date
============ ====================== ============= ======================
1394ohci     1394 OHCI Compliant Ho Kernel
3ware        3ware                  Kernel        5/18/2015 6:28:03 PM
ACPI         Microsoft ACPI Driver  Kernel
AcpiAudioCom ACPI Audio Compositor  Kernel
```

| Column | Meaning |
|---|---|
| **Module Name** | The short internal name; use it when you search for the driver |
| **Display Name** | The friendly name. The table format **cuts it off** (see the first row) |
| **Driver Type** | `Kernel`, or `File System` for file system drivers and filters |
| **Link Date** | When the driver file was **built**, **not** when it was installed. Often blank |

The table is too long to read: that PC had **434** drivers (395 Kernel, 39 File System). So **ask it a question.** CSV output turns into objects PowerShell can filter, and `/v` adds columns including **State**, **Start Mode** and **Path**:

```powershell
$drivers = driverquery.exe /v /fo csv | ConvertFrom-Csv
$drivers | Group-Object State
$drivers | Group-Object 'Start Mode'
$drivers | Where-Object 'Module Name' -eq 'disk' |
    Format-List 'Module Name','Display Name','Start Mode',State,Path
```

On the test PC: **200 Running, 234 Stopped**. A stopped driver is usually normal: Windows carries many drivers for hardware you do not have. Start modes were 321 Manual, 51 Boot, 35 System, 21 Auto and 6 Disabled. **Boot** and **System** are used for drivers that must load very early: by the boot loader, and while the kernel starts ([`sc.exe config`](https://learn.microsoft.com/windows-server/administration/windows-commands/sc-config)). The `disk` driver showed:

```text
Module Name  : disk
Display Name : Disk Driver
Start Mode   : Boot
State        : Running
Path         : C:\WINDOWS\system32\drivers\disk.sys
```

That makes sense: Windows cannot load much from a disk it has no driver for.

**Is it signed?** A digital signature lets Windows check who published a driver and that it was not altered ([driver signing](https://learn.microsoft.com/windows-hardware/drivers/install/driver-signing)). `/si` reports it for installed device drivers:

```powershell
driverquery.exe /si /fo csv | ConvertFrom-Csv | Where-Object IsSigned -eq 'FALSE'
```

Of 167 rows, three said `FALSE`: one third-party file system driver and two devices whose INF name and manufacturer were `N/A`. **`FALSE` here is a reason to find out what the item is, not proof that it is malicious** or even that its driver file is unsigned.

**What changed recently?** This is the useful question after a new problem. `driverquery` **cannot answer it**, because Link Date is a build date. Two places record installs:

- The **System** log's event **7045**, "a service was installed". Drivers installed as services appear there with a service type of *kernel mode driver*:

  ```powershell
  Get-WinEvent -FilterHashtable @{LogName='System'; Id=7045} |
      Where-Object { $_.Properties[2].Value -like '*kernel*' } |
      Select-Object -First 3 TimeCreated, @{n='Name';e={$_.Properties[0].Value}}
  ```

  ```text
  TimeCreated           Name
  -----------           ----
  11/5/2026 10:34:35 PM USB RNDIS6 Adapter
  11/2/2026 8:38:20 PM  Microsoft Bluetooth Hands-Free Audio driver
  10/30/2026 9:24:43 PM Realtek USB FE/1GbE/2.5GbE/5GbE NIC Family NetAdapterCx 2.2 64-bit Driver
  ```

- `C:\Windows\INF\setupapi.dev.log`, the device installation log ([SetupAPI logging](https://learn.microsoft.com/windows-hardware/drivers/install/setupapi-logging--windows-vista-and-later-)). It is a long text file with dates and details.

Neither is promised to hold everything forever: logs are limited in size, and not every change creates an event 7045. **After a blue screen that began with a change:** note the stop code, find what was installed just before it started, then use Device Manager to roll back, update or remove that driver. The exact steps depend on the device.

## Programs, processes and threads

- A **program** is a file on disk, usually an `.exe`.
- A **process** is a running instance of a program. It has its own memory, a security identity (the user it runs as) and at least one thread.
- A **thread** is a unit of execution inside a process. Windows schedules threads onto processor cores.

```text
  ON DISK                      IN MEMORY (running)

  cmd.exe   ---- start ---->   process, PID 4896              process, PID 12516
  (one file)                   +------------------------+     +------------------------+
        \                      | own memory             |     | own memory             |
         \--- start again -->  | runs as: a user        |     | runs as: a user        |
                               | threads: t t t t       |     | threads: t t t t       |
                               | handles: 82 (open      |     | handles: 82            |
                               |   files, keys, ...)    |     |                        |
                               +------------------------+     +------------------------+
```

Those numbers are real. I started `cmd.exe` twice and asked about both:

```text
   Id ProcessName Threads HandleCount PrivateMB Path
   -- ----------- ------- ----------- --------- ----
 4896 cmd               4          82       6.6 C:\WINDOWS\system32\cmd.exe
12516 cmd               4          82       6.6 C:\WINDOWS\system32\cmd.exe
```

**Same program, same path, two different processes.** Each has its own **process ID (PID)**, so ending one leaves the other running. A **handle** is the ticket from step 6 above: an open file, registry key or other thing the kernel is managing for the process. See [Processes and threads](https://learn.microsoft.com/windows/win32/procthread/processes-and-threads). A PID is only unique **while the process runs**; Windows can reuse the number later.

### Seeing processes from the command line

Command Prompt, with [`tasklist`](https://learn.microsoft.com/windows-server/administration/windows-commands/tasklist). `/fi` filters, `/v` adds detail and `/fo list` prints one fact per line:

```text
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

| Line | Ask yourself |
|---|---|
| **Image Name** | The file name only. Two different files can share a name |
| **PID** | The number you give to other tools |
| **Session#** | 0 is the services' session; your desktop is another number |
| **User Name** | Whose rights does it have? |
| **Mem Usage** | Memory in use now. One reading says little; steady growth over hours says more |
| **CPU Time** | Total processor time used since it started, not a percentage |

PowerShell, with [`Get-Process`](https://learn.microsoft.com/powershell/module/microsoft.powershell.management/get-process):

```text
Get-Process explorer | Format-List Id,SessionId,ProcessName,Path

Id          : 8852
SessionId   : 1
ProcessName : explorer
Path        : C:\WINDOWS\Explorer.EXE
```

`Get-Process` gives you the **path** of the file the process was started from, which helps you tell a genuine system process from an impostor with the same name. A real `explorer.exe` here runs from `C:\WINDOWS`; one running from a temporary or download folder deserves attention. **The path can be blank** when you are not allowed to inspect a process, and some have no file at all: PID 4, `System`, represents the kernel's own work and showed an empty path (PID 0, `Idle`, stands for the processor having nothing to do). Both are in session 0.

For the **parent** process and the full command line, ask [`Get-CimInstance`](https://learn.microsoft.com/powershell/module/cimcmdlets/get-ciminstance) for the process object:

```text
Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | Format-List ProcessId,ParentProcessId,CommandLine

ProcessId       : 8852
ParentProcessId : 8760
CommandLine     : C:\WINDOWS\Explorer.EXE
```

The **command line** often says more than the name. Two `powershell.exe` processes look identical in Task Manager's first view, while their command lines show which script each is running.

Processes form a **tree**: each one records the process that started it ([child processes](https://learn.microsoft.com/windows/win32/procthread/child-processes)). By following `ParentProcessId` upwards from a PowerShell window I got this (the top three links):

```text
 (pid 8920, already exited)
        |
        +-- explorer.exe           pid 8976    your desktop
                 |
                 +-- WindowsTerminal.exe   pid 11868   the terminal window
                          |
                          +-- powershell.exe      pid 6696    the shell inside it
```

Two lessons from the top line. **A parent can exit** while its children keep running, so a missing parent is not suspicious by itself. And because PIDs are reused, a `ParentProcessId` can later belong to an **unrelated** process: check that the "parent" started before the child.

A parent that makes no sense (a document viewer that started a command shell) is worth a second look; the security lessons return to this.

## Services

A **service** is a process that Windows starts and manages without a user needing to sign in, such as the print spooler or Windows Update ([Services](https://learn.microsoft.com/windows/win32/services/services)). Services have a start type (automatic, manual or disabled) and normally run under a service account instead of your own ([service user accounts](https://learn.microsoft.com/windows/win32/services/service-user-accounts)). The services lesson covers managing them; here you learn to recognise and read them.

The **start type** says **when a service is allowed to start** ([`sc.exe config`](https://learn.microsoft.com/windows-server/administration/windows-commands/sc-config) lists the values; `demand` is its word for manual):

| Start type | What it means |
|---|---|
| **Automatic** | Windows starts it while the computer boots, with nobody needing to sign in ([automatically starting services](https://learn.microsoft.com/windows/win32/services/automatically-starting-services)). *Automatic (Delayed Start)* starts it a little after boot instead. |
| **Manual** | It does not start just because the computer booted. It starts when something asks for it: you, a program, or another service that needs it. Some also start when a particular event happens, such as a device arriving ([trigger events](https://learn.microsoft.com/windows/win32/services/service-trigger-events)). |
| **Disabled** | It **cannot** be started, by you or by a program, until someone changes its start type ([`Set-Service`](https://learn.microsoft.com/powershell/module/microsoft.powershell.management/set-service)). |

**Start type and status are two different things.** The status says what the service is doing now, such as running or stopped. On the test PC:

```text
Get-Service Spooler, wuauserv, RemoteRegistry | Format-Table Name,Status,StartType

Name            Status StartType
----            ------ ---------
RemoteRegistry Stopped  Disabled
Spooler        Running Automatic
wuauserv       Stopped    Manual
```

- A **stopped Manual** service is usually normal: nothing has needed it yet. Windows Update (`wuauserv`) was waiting like this.
- A **stopped Automatic** service is worth a look, but is not proof of a fault: some start, finish their job or wait for a trigger, and stop. That same PC had five.
- **Disabled** is a deliberate choice by Windows, an administrator or some software. Find out why before you change it.

To get an overview, count them by status (`sc` is the Command Prompt tool; in PowerShell type `sc.exe`, because `sc` means something else there):

```text
Get-Service | Group-Object Status | Select-Object Name,Count
sc query type= service state= all        # Command Prompt equivalent (note the space after '=')
```

### Which process is a service?

A service is not always a process of its own. Some have their own program; many run inside a **service host**, `svchost.exe`:

```text
 services.exe (starts and watches services)
     |
     +-- spoolsv.exe                          -> Spooler
     +-- svchost.exe  -k NetworkService       -> Dnscache
     +-- svchost.exe  -k LocalServiceNet...   -> Dhcp
     +-- svchost.exe  -k LocalServiceNet...   -> EventLog
```

[`Get-CimInstance Win32_Service`](https://learn.microsoft.com/powershell/module/cimcmdlets/get-ciminstance) shows the link, with each service's PID, account and program:

```powershell
Get-CimInstance Win32_Service |
    Where-Object Name -in 'Spooler','Dhcp','Dnscache','EventLog' |
    Format-Table Name, ProcessId, StartName, PathName
```

```text
Name     ProcessId StartName                   PathName
----     --------- ---------                   --------
Dhcp          2208 NT Authority\LocalService   C:\WINDOWS\system32\svchost.exe -k LocalServiceNetworkRestricted -p
Dnscache      2392 NT AUTHORITY\NetworkService C:\WINDOWS\system32\svchost.exe -k NetworkService -p
EventLog      3608 NT AUTHORITY\LocalService   C:\WINDOWS\System32\svchost.exe -k LocalServiceNetworkRestricted -p
Spooler       4452 LocalSystem                 C:\WINDOWS\System32\spoolsv.exe
```

Going the other way, `tasklist /svc` names the services inside each process:

```text
tasklist /svc /fi "services eq Spooler"

Image Name                     PID Services
========================= ======== ============================================
spoolsv.exe                   4452 Spooler
```

**Why it matters:** if one `svchost.exe` is using the processor, ending that "process" ends every service inside it. Find out **which service** it is first. On that PC, 118 running services used 110 processes, so most had a process to themselves: since Windows 10 version 1703, PCs with enough memory separate many service hosts ([service host grouping](https://learn.microsoft.com/windows/application-management/svchost-service-refactoring)).

The **account** decides what a service may do:

| Account | In short |
|---|---|
| **LocalSystem** | Very powerful on the local machine ([LocalSystem](https://learn.microsoft.com/windows/win32/services/localsystem-account)). A flaw in such a service is serious |
| **LocalService** | Limited rights; anonymous on the network |
| **NetworkService** | Limited rights; uses the computer's identity on the network |

(See [service user accounts](https://learn.microsoft.com/windows/win32/services/service-user-accounts).) Of the running services on the test PC, 70 ran as LocalSystem, 32 as LocalService and 8 as NetworkService; for another 8 the account came back blank to this standard user.

## Sessions, users and profiles

- A **logon session** is created each time an account signs in. Services run in their own non-interactive session (session 0), separate from the desktop sessions of signed-in users ([interactive services](https://learn.microsoft.com/windows/win32/services/interactive-services) explains why a service cannot show a window on your desktop).
- Every user has a **profile**: a folder under `C:\Users` holding documents, desktop items, application settings and that user's registry hive (`NTUSER.DAT`).
- Windows identifies accounts by a **security identifier (SID)**, not by name. Names are for people; SIDs are what permissions are actually stored against ([security identifiers](https://learn.microsoft.com/windows/win32/secauthz/security-identifiers)).

```text
  SESSION 0  (services; no desktop)          SESSION 1  (the person at the screen)
 +------------------------------------+     +------------------------------------+
 | System, services.exe, spoolsv.exe, |     | explorer.exe, your terminal,       |
 | most svchost.exe ...               |     | your browser, your apps ...        |
 +------------------------------------+     +------------------------------------+
        a window opened here is NOT shown to the person in session 1
```

You can count the processes in each session:

```text
Get-Process | Group-Object SessionId | Format-Table Name, Count

Session Count
------- -----
0         130
1          85
```

(I renamed the first column to *Session*.) Another signed-in user would get another session number. The command `quser` lists signed-in users on some editions; on this **Windows 11 Home** PC it was **not present** (`The term 'quser.exe' is not recognized`), so do not rely on it.

Now your own identity:

```text
whoami /user

USER INFORMATION
----------------

User Name              SID
====================== ==============================================
desktop-abc123\student S-1-5-21-1111111111-2222222222-3333333333-1001
```

```text
 S-1-5-21-1111111111-2222222222-3333333333-1001
 |-------| |------------------------------| |--|
  prefix    which machine (or domain)        RID: which account there
```

A SID has the form `S-1-5-21-<machine or domain identifier>-<RID>`. The last number, the **RID**, is the account's own number on that machine; 500 is the built-in Administrator and ordinary accounts start at 1000. A few SIDs are the same on every machine and are called **well-known SIDs** ([list](https://learn.microsoft.com/windows/win32/secauthz/well-known-sids)): `S-1-5-18` is the **SYSTEM** account, `S-1-5-19` Local Service, `S-1-5-20` Network Service, and `S-1-5-32-544` the local **Administrators** group. See [`whoami`](https://learn.microsoft.com/windows-server/administration/windows-commands/whoami) and [`Get-LocalUser`](https://learn.microsoft.com/powershell/module/microsoft.powershell.localaccounts/get-localuser).

Two accounts with the same display name but different SIDs are different accounts with different permissions. A deleted and re-created account with the same name gets a new SID and does **not** inherit the old one's permissions.

**When you will meet raw SIDs:** a permissions window sometimes shows a long `S-1-5-21-...` number instead of a name. That usually means Windows cannot turn it into a name here: for example the account was deleted, or it belongs to another machine or a domain you cannot reach.

## What lives where

```text
 C:\                              (%SystemDrive%)
 |-- Windows\                     (%SystemRoot%)   the operating system
 |    |-- System32\                core programs, libraries and drivers\
 |    +-- INF\                     driver setup files and setupapi.dev.log
 |-- Program Files\               64-bit applications
 |-- Program Files (x86)\         32-bit applications
 |-- ProgramData\                 data shared by all users (hidden by default)
 +-- Users\
      +-- student\                 (%USERPROFILE%)  one person's profile
           |-- Documents\ Desktop\ Downloads\ ...
           |-- AppData\            per-user application data (hidden by default)
           +-- NTUSER.DAT          that user's registry hive
```

| Location | Purpose | When you look there |
| --- | --- | --- |
| `C:\Windows` | The operating system itself | Rarely change anything by hand |
| `C:\Windows\System32` | Core system programs and libraries (64-bit on a 64-bit system) | Checking that a "system" program really runs from here |
| `C:\Program Files` | 64-bit applications | Finding an installed program |
| `C:\Program Files (x86)` | 32-bit applications on a 64-bit system | The same, for 32-bit ones |
| `C:\ProgramData` | Application data shared by all users | Settings and logs that apply to everyone |
| `C:\Users\<name>` | One user's profile | "It works for me but not for them" problems |

`System32` holding **64-bit** files is not a typing mistake: the name stayed for compatibility. If a problem happens for **one user only**, suspect something in that profile or that user's settings; if it happens for **everyone**, look at the machine-wide places.

The system drive is not always `C:`. The environment variable `%SystemRoot%` always points at the Windows folder, and `%SystemDrive%` at the drive containing it. Use these in scripts instead of assuming `C:`. Environment variables are shown with `set` in Command Prompt ([`set`](https://learn.microsoft.com/windows-server/administration/windows-commands/set_1)) and as `$env:` in PowerShell:

```text
echo %SystemRoot%
echo %USERPROFILE%
```

```powershell
$env:SystemRoot
$env:USERPROFILE
Get-ChildItem Env:        # every variable
```

The first two lines are for **Command Prompt** and the rest for **PowerShell**. In the wrong shell, `%SystemRoot%` is just printed as text, a quick way to notice which shell you are in.

Special folders such as Documents and Downloads are called **known folders** and can be moved elsewhere (for example by OneDrive), so do not assume `%USERPROFILE%\Documents`; see [Known Folders](https://learn.microsoft.com/windows/win32/shell/knownfolderid).

## Which Windows is this?

Before you troubleshoot, know the edition, version and build, because documentation and behaviour differ between them.

```text
Get-ComputerInfo -Property OsName,OsVersion,OsBuildNumber,OsArchitecture

OsName         : Microsoft Windows 11 Home
OsVersion      : 10.0.26300
OsBuildNumber  : 26300
OsArchitecture : 64-bit
```

| Line | Why you care |
|---|---|
| **OsName** | The **edition** (Home, Pro, Server...) decides which tools and features exist, as `quser` just showed |
| **OsBuildNumber** | Search documentation and known problems by build |
| **OsArchitecture** | Which installers and drivers fit |

From Command Prompt, `ver` prints the version and `systeminfo` prints much more. `winver` opens a window with the same facts. On the test PC `ver` printed `Microsoft Windows [Version 10.0.26300.9974]`: the extra last number rises as updates are installed. See [`Get-ComputerInfo`](https://learn.microsoft.com/powershell/module/microsoft.powershell.management/get-computerinfo). Windows 11 reports itself as version `10.0` with a build number of 22000 or higher; Windows 10 has builds below that. This course treats **Windows 10 as the oldest supported client** and Windows 11 Pro as its default.

## Working from the terminal

You will spend much of this course in a terminal, often a remote one with no graphical tools. Get comfortable with one text editor that works there.

- **Windows Terminal** hosts Command Prompt, PowerShell and WSL side by side in tabs ([documentation](https://learn.microsoft.com/windows/terminal/)). It is the **window**; the shell inside it is a separate program, as the process tree above showed.
- **Microsoft Edit** (`edit`) is a small, open-source (MIT) terminal text editor with a modern interface and VS Code-like controls. It ships with Windows 11, so `edit C:\path\file.txt` works on a stock install, and it can be installed on Windows 10 and other systems (for example `winget install Microsoft.Edit`), and the project publishes Linux and Windows builds on its GitHub releases page. It is a good default for editing a config file or a script over a remote session when you would otherwise reach for Notepad. Its home is [github.com/microsoft/edit](https://github.com/microsoft/edit) (see the [wiki](https://github.com/microsoft/edit/wiki)).
- On Linux the same role is played by `nano`, `vim` or `vi`; the Linux lessons introduce them.

```text
edit $PROFILE            # PowerShell: open your PowerShell startup script (it may not exist yet)
notepad file.txt         # a graphical editor, for comparison
```

Install it only where you are allowed to install software; on a locked-down machine, use what is there.

## Guided exercise: observe, do not change

This exercise only looks at your system. For each step, **write down what you saw and one sentence about what it tells you.**

1. **Graphical:** press **Ctrl+Shift+Esc** to open **Task Manager**. Open the **Details** tab. Right-click a column header, choose **Select columns**, and enable **PID**, **User name** and **Session ID**.
2. **Command line:** run `tasklist /v /fo table`, and in PowerShell `Get-Process | Sort-Object Id | Select-Object -First 10 Id,SessionId,ProcessName`.
3. Find `explorer.exe`. Note its PID, the user it runs as and its session ID. Follow its parent with `Get-CimInstance`. Is the parent still running?
4. Find any entry whose user is `NT AUTHORITY\SYSTEM`. Note its session ID. Compare it with the one from step 3 and explain the difference.
5. Open Notepad twice. Find both processes. What is the same about them, and what is different? Close one and look again.
6. Pick one `svchost.exe` and use `tasklist /svc` to name the services inside it.
7. Run the user and kernel time command from this lesson. Which process has used the most kernel time? Give one possible reason, and say why it is only a possibility.
8. Group your drivers by State and by Start Mode. Then find the three most recent *kernel mode driver* installs in event 7045. Do you recognise them?
9. Run `whoami /user` and write down your SID, then compare the last number with what `Get-LocalUser | Select-Object Name,SID` shows.
10. Run `echo %SystemRoot%` and `echo %USERPROFILE%` and confirm the values match the table above for your machine.
11. Run `Get-ComputerInfo -Property OsName,OsVersion,OsBuildNumber` and note your edition and build.

## Common mistakes

- **Assuming the system drive is `C:`.** Use `%SystemRoot%` and `%SystemDrive%`.
- **Judging a process by its name.** Check its path, command line and parent.
- **Ending a busy `svchost.exe` without looking inside.** Find the service first.
- **Treating a name as identity.** Permissions follow the SID.
- **Reading every blue screen as a hardware fault.** Kernel mode includes drivers, so after a change, look at what changed first.
- **Reading a driver's Link Date as its install date.** It is when the file was built.
- **Treating every stopped service or driver as broken.** Many are waiting until they are needed.
- **Expecting a service to show a window on your desktop.** Services run in session 0.
- **Not knowing the edition and build.** A fix or tool that works on one may be missing on another.

## Check your understanding

1. A machine shows a blue screen after a new driver is installed. Which mode is most likely involved, and why?
2. You start Notepad twice. How many processes exist, and how do you tell them apart?
3. Why might two users with the same display name still have different permissions?
4. Which command shows the file path a running process was started from?
5. Which well-known SID is the SYSTEM account? What does `S-1-5-32-544` stand for?
6. A user's account was deleted and re-created with the same name, and they lost access to their old files. Why?
7. Why can one faulty kernel-mode driver crash the whole machine when one faulty application cannot?
8. Two different programs both get "Access is denied" on the same file. Why does trying another program not help?
9. A process shows far more kernel time than user time. What might that suggest?
10. A colleague wants to know which drivers were installed last week and sorts `driverquery` by Link Date. What is wrong, and where should they look?
11. A `svchost.exe` is using a lot of processor time. What do you find out before ending it?
12. `Get-Service` shows an Automatic service that is Stopped. Is it broken?

**Expected answers:** (1) kernel mode, because drivers run there and a fault there stops the whole system; (2) two, distinguished by PID; (3) permissions are stored against the SID, and two accounts have different SIDs even if the names look alike; (4) `Get-Process <name> | Format-List Path`, or `Get-CimInstance Win32_Process` for the command line too; (5) `S-1-5-18`; the local Administrators group; (6) the new account has a new SID, and the old permissions were stored against the old SID; (7) kernel-mode code shares one address space with no wall between its parts, while each application has its own private space; (8) the kernel makes the permission check, whichever program asks, for the user it runs as; (9) it is asking the system to do much work, such as many small file or network operations, or time is being spent in a driver: a clue to investigate, not proof; (10) Link Date is when the file was built; look at event 7045 in the System log and at `setupapi.dev.log`; (11) which services are inside it (`tasklist /svc` or `Win32_Service` by PID); (12) not necessarily: some finish their job or wait for a trigger and stop, so check whether something that needs it is failing, and read its events.
