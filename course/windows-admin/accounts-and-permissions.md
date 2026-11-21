*Draft for owner review.* Who can sign in and who can open what: the two questions behind most "access denied" tickets. This lesson covers local accounts, groups, the access token and NTFS permissions on a Windows machine, each from PowerShell and from Command Prompt as well as the graphical tools. (Domain accounts follow the same ideas; the Active Directory lessons come later.)

Machine, user and group names below are samples; the layout is real output. Everything that *changes* an account or a permission needs an **elevated** (administrator) session, and you should try it only on a lab VM or a machine you own.

## Account types

| Type | Where it lives | Notes |
|---|---|---|
| **Local account** | this machine's own account database (SAM) | what this lesson manages |
| **Microsoft account** | Microsoft's cloud, linked to a local profile | common on home PCs; managed in Settings, not here |
| **Domain account** | Active Directory | managed centrally; see the AD lessons |
| **Work or school account** | Microsoft Entra ID (cloud directory) | managed by the organisation |

Windows also creates **built-in accounts**: `Administrator` (disabled on a standard install and best left that way), `Guest` (disabled), `DefaultAccount` and `WDAGUtilityAccount` (both system-managed). Details are in [Local accounts](https://learn.microsoft.com/windows/security/identity-protection/access-control/local-accounts) and the broader idea of an account, group or service as a *security principal* in [Security principals](https://learn.microsoft.com/windows/security/identity-protection/access-control/security-principals).

## Local accounts from the command line

PowerShell, using the [LocalAccounts module](https://learn.microsoft.com/powershell/module/microsoft.powershell.localaccounts/get-localgroupmember):

```
Get-LocalUser | Select-Object Name, Enabled, LastLogon, PasswordExpires | Format-Table

Name               Enabled LastLogon             PasswordExpires
----               ------- ---------             ---------------
Administrator        False
jsmith                True 11/21/2026 7:18:53 AM
Guest                False
WDAGUtilityAccount   False                       11/28/2026 8:09:17 PM
```

Create, change and remove accounts ([`New-LocalUser`](https://learn.microsoft.com/powershell/module/microsoft.powershell.localaccounts/new-localuser), [`Set-LocalUser`](https://learn.microsoft.com/powershell/module/microsoft.powershell.localaccounts/set-localuser)):

```
$pw = Read-Host -AsSecureString "Password"            # never put a password in a script or in history
New-LocalUser -Name 'jsmith' -Password $pw -FullName 'Jordan Smith' -Description 'Finance'
Set-LocalUser -Name 'jsmith' -PasswordNeverExpires $false
Disable-LocalUser -Name 'jsmith'
Enable-LocalUser  -Name 'jsmith'
Rename-LocalUser  -Name 'jsmith' -NewName 'jordan.smith'
Remove-LocalUser  -Name 'jordan.smith'
```

Command Prompt, with [`net user`](https://learn.microsoft.com/windows-server/administration/windows-commands/net-user):

```
net user                          # list the local accounts
net user jsmith                   # one account's full state
net user jsmith * /add            # create it, prompting for the password
net user jsmith /active:no        # disable
net user jsmith /active:yes       # enable
net user jsmith /delete
```

`net user jsmith` prints, in one screen, whether the account is active, when the password was last set and when it expires, the last logon, and the groups it belongs to:

```
User name                    jsmith
Full Name                    Jordan Smith
Account active               Yes
Account expires              Never
Password last set            11/20/2026 9:12:00 AM
Password expires             Never
Local Group Memberships      *Users
```

**Graphical:** on Windows 10/11 Pro and Enterprise, `lusrmgr.msc` opens **Local Users and Groups**; on Home editions that console is not available, which is a good reason to know the commands. **Settings, Accounts** manages the same accounts in a simplified way.

## Groups

Give access through **groups**, not individual accounts: add a person to a group once, and every permission the group holds follows.

```
Get-LocalGroup
Get-LocalGroupMember -Group Administrators
Add-LocalGroupMember    -Group 'Remote Desktop Users' -Member 'jsmith'
Remove-LocalGroupMember -Group 'Remote Desktop Users' -Member 'jsmith'
```

```
net localgroup                                   # list groups
net localgroup Administrators                    # members of one group
net localgroup "Remote Desktop Users" jsmith /add
net localgroup "Remote Desktop Users" jsmith /delete
```

Built-in groups you will meet constantly:

| Group | Purpose |
|---|---|
| **Administrators** | full control of the machine |
| **Users** | ordinary signed-in users; can run applications and change their own settings |
| **Remote Desktop Users** | may sign in with Remote Desktop |
| **Backup Operators** | may read and restore files regardless of their permissions, for backup software |
| **Guests** | restricted temporary access |

Keep **Administrators** short. Everyone in it can do anything on the machine, and any program they run elevated can too.

### Why can a user not sign in?

A short checklist, in the order to check it:

1. **Account disabled** (`Enabled: False`, or `Account active  No`).
2. **Locked out** after too many wrong passwords (a lockout policy applies; the account unlocks after the policy's period or by an administrator).
3. **Password expired** or must be changed at next logon.
4. **Not allowed to log on** here: remote sign-in needs membership in *Remote Desktop Users* (or *Administrators*); a policy may deny local or network logon.
5. **Logon hours or a workstation restriction** in a managed environment.
6. **Wrong account or domain**: signing in as `jsmith` when the account is `DESKTOP-ABC123\jsmith` or the domain account.

## The access token

At sign-in Windows builds an **access token**: the user's SID, the SIDs of every group they belong to, and their privileges. Every process they start carries a copy. You can read yours:

```
whoami /groups
whoami /priv
```

```
GROUP INFORMATION
-----------------
Group Name                                          Type             SID          Attributes
=================================================== ================ ============ ================================
Everyone                                            Well-known group S-1-1-0      Mandatory group, Enabled by default, Enabled group
BUILTIN\Users                                       Alias            S-1-5-32-545 Mandatory group, Enabled by default, Enabled group
```

A group change reaches the token only at the **next sign-in**, which explains "I added them to the group and nothing changed". Tell the user to sign out and in (or restart the service that holds the old token). See [`whoami`](https://learn.microsoft.com/windows-server/administration/windows-commands/whoami).

### Administrators and UAC

An administrator signs in with **two tokens** under **User Account Control** ([UAC](https://learn.microsoft.com/windows/security/application-security/application-control/user-account-control/)): a *filtered* token with the Administrators group set to "deny only", and a full one used only after the user **elevates** and approves the prompt. In the output of `whoami /groups` from a normal (non-elevated) prompt, the Administrators group shows the attribute `Group used for deny only`. From an elevated prompt it shows `Enabled group`. That is why a script that works in an admin console can fail when run from a normal one with "access denied", and the fix is to start the shell elevated, not to turn UAC off.

Start something elevated from PowerShell with `Start-Process powershell -Verb RunAs`, and run as another user with `runas /user:DESKTOP-ABC123\jsmith cmd`.

## NTFS permissions

Every file and folder on an NTFS volume has an **access control list** (ACL): a list of **entries** (ACEs), each naming a user or group, an allow or deny, and a right. A file also has an **owner**, who can always change the permissions. The background is in [Access control overview](https://learn.microsoft.com/windows/security/identity-protection/access-control/access-control).

### Reading permissions

```
icacls C:\Data\Reports

C:\Data\Reports NT AUTHORITY\SYSTEM:(OI)(CI)(F)
                BUILTIN\Administrators:(OI)(CI)(F)
                CONTOSO\Finance:(OI)(CI)(M)
                BUILTIN\Users:(OI)(CI)(RX)

Successfully processed 1 files; Failed processing 0 files
```

Each entry reads `who:(flags)(right)`:

| Right | Meaning |
|---|---|
| `F` | Full control (read, write, delete, and change permissions) |
| `M` | Modify (read, write, delete; not change permissions or ownership) |
| `RX` | Read and execute |
| `R` | Read |
| `W` | Write |
| `D` | Delete |

| Flag | Meaning |
|---|---|
| `(OI)` | **object inherit**: files inside get this entry |
| `(CI)` | **container inherit**: sub-folders get this entry |
| `(IO)` | **inherit only**: applies to children, not this folder itself |
| `(NP)` | **no propagate**: only to the immediate children |
| `(I)` | this entry was **inherited** from the parent (shown on children) |

In PowerShell, [`Get-Acl`](https://learn.microsoft.com/powershell/module/microsoft.powershell.security/get-acl) returns the same data as an object:

```
(Get-Acl C:\Data\Reports).Access | Format-Table IdentityReference,FileSystemRights,AccessControlType,IsInherited
```

### Changing permissions

[`icacls`](https://learn.microsoft.com/windows-server/administration/windows-commands/icacls) is the tool to learn:

```
icacls C:\Data\Reports /grant "Finance:(OI)(CI)M"          # add Modify for the Finance group, inherited downward
icacls C:\Data\Reports /grant:r "Finance:(OI)(CI)RX"        # :r REPLACES that group's existing entries
icacls C:\Data\Reports /remove Finance                      # remove all of Finance's entries
icacls C:\Data\Reports /deny  "Interns:(OI)(CI)W"           # deny Write (use sparingly)
icacls C:\Data\Reports /inheritance:d                       # stop inheriting; copy what was inherited
icacls C:\Data\Reports /inheritance:e                       # turn inheritance back on
icacls C:\Data\Reports /reset /t                            # reset to the parent's permissions, below here too
```

Before a broad change, **save the permissions** so you can put them back:

```
icacls C:\Data /save C:\Backup\data-acl.txt /t
icacls C:\ /restore C:\Backup\data-acl.txt
```

`Set-Acl` writes an ACL object back ([`Set-Acl`](https://learn.microsoft.com/powershell/module/microsoft.powershell.security/set-acl)), which suits scripts that read, modify and write an ACL. For one-off changes `icacls` is shorter and safer.

**Taking ownership** is for the case where no one, not even administrators, has permission (for example a folder from a deleted account). [`takeown`](https://learn.microsoft.com/windows-server/administration/windows-commands/takeown) changes the owner, after which you can grant yourself rights:

```
takeown /f C:\OldUserData /r /d y
icacls C:\OldUserData /grant Administrators:(OI)(CI)F /t
```

### The rules that decide access

- **Inheritance:** a folder passes its entries to what it contains unless inheritance is turned off. A broken inheritance chain is a frequent cause of "this one folder is different".
- **Deny overrides allow.** Use deny sparingly, because it is hard to read later.
- **Effective access** is the combination of all entries that match the user *and all of their groups*. Rights add up across groups unless a deny applies.
- **The owner** can always change the permissions, even with no entry.
- **Share permissions** apply to access over the network and **NTFS permissions** apply always; over the network, the **stricter result wins**. (Share permissions are covered when we share a folder, below.)

## Shares and NTFS together

A shared folder has its own share-level permissions on top of the NTFS ACL ([`New-SmbShare`](https://learn.microsoft.com/powershell/module/smbshare/new-smbshare), [`Get-SmbShareAccess`](https://learn.microsoft.com/powershell/module/smbshare/get-smbshareaccess)):

```
New-SmbShare -Name Reports -Path C:\Data\Reports -ChangeAccess Finance
Get-SmbShareAccess -Name Reports
```

A common, tidy design is to give the share broad access (for example Everyone: Change, or Authenticated Users) and manage who may do what **only in the NTFS permissions**, so there is one place to look. If a user can open the folder at the console but not over the network (or the reverse), the share permissions and the NTFS permissions disagree.

## Fixing an access problem

1. **Name** the user, the object and the action that failed, and copy the exact error.
2. **Read** the ACL (`icacls <path>`), the owner, and the user's groups (`whoami /groups` run as that user, or `net user <name>`).
3. **Decide** what *should* be true: which group should have what right on this path.
4. **Change the group's entry**, not "Everyone" and not the individual user.
5. **Remember the token:** the user must sign out and in for a new group membership to apply.
6. **Test** as the user, and record the change (what, why, and how to undo it).

Do not "fix" access by giving *Everyone* Full control, and do not set permissions on the whole `C:\` drive: you can break the operating system.

## Common mistakes

- **Adding users to ACLs directly** instead of through a group, so nobody can tell later who has access to what.
- **Forgetting the next sign-in** and concluding the change failed.
- **Using Deny** where removing an Allow would do; a deny on a broad group can lock out administrators.
- **Disabling inheritance** and then forgetting that new entries on the parent no longer reach the folder.
- **Checking only NTFS** when the problem is a share-level permission, or the reverse.
- **Turning off UAC** to make a script work instead of starting it elevated.
- **Putting a password on the command line** or in a script; use `Read-Host -AsSecureString` or a secret store.
- **Leaving the built-in `Administrator` enabled** with a known name and a weak password.

## Check yourself

1. You add a user to a group. When does it take effect for their open session?
2. A folder has no entry for a team that used to read it. What do you check first?
3. Why prefer groups to adding users to ACLs directly?
4. What does `(OI)(CI)M` mean in an `icacls` entry?
5. A user can open `\\server\Reports` from the server console but gets "access denied" from their PC. Where do you look?
6. You must change permissions on a whole tree. What do you do first?
7. From a non-elevated prompt, `whoami /groups` shows Administrators as "deny only". What does that tell you?

**Answers.** (1) At their next sign-in, because the access token is built at sign-in. (2) Whether inheritance is broken on that folder, and whether the team's group entry was removed or the team's group membership changed. (3) One change to the group updates everyone, and the permission list stays readable. (4) Modify, applied to files (OI) and to sub-folders (CI), so it is inherited downward. (5) The share permissions, not only the NTFS permissions: over the network the stricter of the two wins. (6) Save the current permissions with `icacls <path> /save` so you can restore them. (7) The prompt is not elevated: UAC has given the process its filtered token, and elevating gives the full one.

## Practice

Two labs cover this lesson: `labs.user-account-disabled` (an account that cannot sign in) and `labs.folder-permissions` (a group that lost its access). For each, write the first command you would run to read the evidence and the three possible causes in order, run the lab, and then write the record from the troubleshooting lesson. After a fix, run the check as the affected user, not as an administrator, because an administrator's token can hide the problem.
