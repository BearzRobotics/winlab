*Draft for owner review.* Two places hold most of a Windows machine's state: the registry for settings and the file system for everything else. This lesson covers how each is organised and how to change them without making the machine worse.

## The registry

The registry is a hierarchical database of settings, organised into **hives**:

| Hive | Holds |
|---|---|
| `HKLM` (HKEY_LOCAL_MACHINE) | Settings for the whole machine: services, drivers, installed software, policy |
| `HKCU` (HKEY_CURRENT_USER) | The signed-in user's settings (loaded from their `NTUSER.DAT`) |
| `HKCR` | File associations and COM; a merged view |
| `HKU`, `HKCC` | All loaded user hives; current hardware profile |

Each **key** holds **values** with a name, a type (`REG_SZ` text, `REG_DWORD` number, `REG_MULTI_SZ` list, `REG_BINARY`) and data.

```
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' | Select-Object ProductName, CurrentBuild
New-ItemProperty -Path 'HKCU:\Software\Contoso' -Name Greeting -Value 'hello' -PropertyType String -Force
Remove-ItemProperty -Path 'HKCU:\Software\Contoso' -Name Greeting
reg export "HKLM\SOFTWARE\Contoso" backup.reg
reg import backup.reg
```

Safe practice: **export the key before you change it**, change one value, test, and record it. Do not "clean" the registry with third-party tools. Policy values under `...\Policies` are a signal that something set them deliberately.

## Startup locations

Programs start with Windows from several places: services, scheduled tasks, the `Run` keys (`HKLM\...\CurrentVersion\Run`, `HKCU\...\Run`), and the Startup folders. When a program keeps coming back, find which of these starts it. The built-in `Get-CimInstance Win32_StartupCommand` lists many of them.

## File systems

Windows uses **NTFS** for system and data volumes: permissions, compression, encryption (EFS), journaling and large volumes. **ReFS** adds resilience for storage workloads. **FAT32** and **exFAT** are simple formats for removable media; FAT32 has a 4 GB file-size limit and no permissions.

```
Get-Volume | Select-Object DriveLetter, FileSystem, Size, SizeRemaining, HealthStatus
Get-Disk; Get-Partition
chkdsk C:                 # read-only check
fsutil volume diskfree C:
```

Disk free space affects updates, paging and logs; a full system drive causes odd, unrelated-looking failures. Find what is large before deleting anything:

```
Get-ChildItem C:\ -Recurse -File -ErrorAction SilentlyContinue |
  Sort-Object Length -Descending | Select-Object -First 10 FullName, @{n='MB';e={[int]($_.Length/1MB)}}
```

## Paths, links and attributes

`C:\Windows`, `C:\Program Files`, `C:\Users` and `C:\ProgramData` hold the system, installed programs, user profiles and shared application data. A **junction** or **symbolic link** makes one folder appear at another path: `mklink /D C:\Link C:\Target`. Hidden and system attributes (`attrib`) hide files without protecting them.

## Check yourself

1. Why export a registry key before editing it?
2. What does a `HKCU` value apply to, and what does an `HKLM` value apply to?
3. A machine behaves strangely and the C: drive has 200 MB free. What do you suspect?
