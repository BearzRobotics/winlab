*Draft for owner review.* A fleet of Windows machines stays healthy when updates arrive on a schedule and settings are applied by policy rather than by hand. This lesson covers how Windows receives updates, where policy settings live, and how to tell which setting is winning. It uses only built-in tools.

## How updates reach a machine

Windows Update is a service (`wuauserv`) that scans for updates, downloads them, and works with the installer services. Updates arrive from Microsoft directly or from a managed source (WSUS, or a cloud service such as Windows Update for Business). What you can read on a machine:

```
Get-Service wuauserv, bits, cryptsvc
Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 5
Get-WinEvent -LogName Microsoft-Windows-WindowsUpdateClient/Operational -MaxEvents 10
```

Update types you will hear named: quality updates (monthly fixes and security), feature updates (a new Windows version), driver updates, and definition updates (Defender signatures). Rings and deferrals let an administrator roll updates to a pilot group first.

When updates stop: check the service and its startup type first, then policy (below), then free disk space, then the update log.

## Where policy lives

A **policy** is a setting an administrator wants enforced. On Windows it is a registry value, written by one of these:

| Source | Scope | Tool |
|---|---|---|
| Local Group Policy | This machine | `gpedit.msc` (Pro and up) |
| Domain Group Policy | Machines or users in the domain | Group Policy Management |
| MDM / Intune | Enrolled devices | the management service |
| Direct registry write | One machine | `reg`, `Set-ItemProperty` (a script or a person) |

Policy values sit in `HKLM:\SOFTWARE\Policies` and `HKCU:\SOFTWARE\Policies`, plus a few older locations such as `...\CurrentVersion\Policies\System`. A value there is a strong hint that *something* set it on purpose.

## Finding what applies

```
gpresult /r                  # which Group Policy objects applied (summary)
gpresult /h report.html      # full report
Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
```

On an enrolled device, Settings shows "some settings are managed by your organization". If a managed source re-applies a value after you remove it, remove it at the source, not on the machine.

## Editing registry policy safely

1. Export the key first: `reg export "HKLM\SOFTWARE\Policies" before.reg`.
2. Change one value.
3. Verify the behaviour and write down what you changed.

Removing a policy value returns a setting to its default; setting it to `0` is often *not* the same as "not configured".

## Check yourself

1. Updates have stopped. What are three things to check, in order?
2. You delete a policy value and it comes back after a restart. What does that tell you?
3. Why export a registry key before editing it?
