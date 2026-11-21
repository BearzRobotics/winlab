*Draft for owner review.* Security work on a server is mostly a few habits applied consistently: give each account only what it needs, expose only the ports that must be reachable, keep software patched, and keep a record of who did what. This lesson names those habits and shows where each one lives on Windows and Linux. Everything here uses built-in tools.

## Least privilege

An account should be able to do its job and nothing more. Daily work is done as a standard account; an administrator account is used only when a task needs it.

| Idea | Windows | Linux |
|---|---|---|
| Who is this? | `whoami /all` | `id` |
| Elevated rights | UAC prompt, "Run as administrator" | `sudo` |
| Groups | `net localgroup`, `Get-LocalGroupMember` | `groups`, `getent group` |

Shared administrator passwords and everyday use of an admin account are the usual failures. A lab machine with a default account name and a known password is not a model to copy.

## Permissions

Access to a file is decided by the account's identity and the file's access list.

- **Windows (NTFS):** each item has an access control list. Permissions are inherited from the parent folder unless inheritance is turned off. Read them with `icacls C:\Data\Reports`. The effective result combines allow and deny entries, and **deny wins**.
- **Linux:** owner, group, other, each with read, write, execute: `ls -l`, `chmod`, `chown`. A directory needs `x` to be entered. Mode `700` means only the owner.

Common finding: a folder is unreadable to a team because inheritance was removed or the mode is too tight. Fix the group or entry that should have access, not "give Everyone full control".

## Accounts and passwords

- Disable or lock accounts that are not in use instead of leaving them active (`Disable-LocalUser`, `passwd -l`). A *disabled* account can be turned back on; deleting loses its history.
- Password length matters more than complexity rules. Do not reuse passwords across systems.
- Look at who has signed in: Windows Security event log (IDs 4624 success, 4625 failure); Linux `last`, `journalctl -u ssh`.

## Firewalls and exposed ports

A firewall decides which connections reach a service. The safe default is to deny and allow only what is needed.

```
Get-NetFirewallRule -Enabled True -Direction Inbound     # Windows
sudo firewall-cmd --list-all                              # AlmaLinux (firewalld)
sudo ufw status verbose                                   # Ubuntu
ss -tln                                                   # what is listening, either OS family
```

Two questions for any open port: **is something supposed to be listening**, and **should this source be allowed to reach it**? A service listening on a port the firewall blocks is a very different fault from a firewall that allows a port nothing uses.

## Patching and attack surface

Each installed program and enabled service is something that can be attacked. Remove or disable what is not needed, and keep what remains updated (`Get-HotFix`, Windows Update; `dnf check-update`, `apt list --upgradable`). Record what you changed.

## Mandatory access control on Linux

On AlmaLinux, SELinux labels every file and process and denies anything the policy does not allow, even for root. A web server that is running with correct permissions but returns "403 Forbidden" often has the wrong SELinux label: check `ls -Z`, `getenforce`, and `ausearch -m avc -ts recent`. Do not turn SELinux off to "fix" it; correct the label (`semanage fcontext`, `restorecon`).

## Check yourself

1. Why is deleting a former employee's account usually worse than disabling it?
2. A folder lets Alice read but she is also in a group with a deny entry. Can she read it?
3. A page returns 403 on AlmaLinux though the Unix permissions are fine. What do you check?
