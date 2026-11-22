*Draft for owner review.* **Samba** lets a Linux machine serve files to Windows, macOS and other Linux machines over **SMB**, the protocol behind Windows file shares. It is the usual answer to "I want a network drive for the family photos". This lesson sets up one share on each lab VM, tests it from the same machine over loopback with `smbclient` and a real `mount -t cifs`, shows who gets in and who does not, and then reproduces and fixes the problem that stops most AlmaLinux (SELinux) shares from working the first time: the **file label**. Nothing here is exposed to a network.

**What was tested, and where.** As root on **Ubuntu 24.04.5** (Samba **4.19.5-Ubuntu**, service `smbd`, installed with `apt-get install samba smbclient cifs-utils`) and **AlmaLinux 9.8** (Samba **4.24.5**, service `smb`, installed with `dnf install samba samba-client cifs-utils policycoreutils-python-utils`), with throwaway users and passwords made for the test (`tests/verification/homelab/hl2.sh` and `hl2b.sh`; output is real). **Not tested:** a client on another machine (Windows `net use`, macOS Finder, a phone), the Windows side of anything, **firewall rules** (`firewalld` is not installed on the AlmaLinux image and `ufw` was inactive on Ubuntu, so I could not show a blocked port), Active Directory or domain membership, Samba as a domain controller, **encryption** of the share (the connection was signed but **not encrypted**, see below), `smb.conf` options for macOS compatibility (`vfs_fruit`), printing, quotas, and exposing SMB to the internet, which you should not do.

## What you are building

A **share** is a named folder (`labfiles`) published by the server. A client connects to `//server/labfiles`, proves who it is with an account the **server** knows, and then sees the folder. Two permission systems apply, and a file is reachable only when **both** allow it:

1. **Samba's own rules** in `/etc/samba/smb.conf` (who may connect, whether the share is writable).
2. **The Linux file system** (the mode and owner of the real files, and, on AlmaLinux, the SELinux label).

Most "it connects but I cannot save" problems are the second system disagreeing with the first.

## Install, users and a share

```text
Ubuntu:    sudo apt-get install samba smbclient cifs-utils      (service smbd; enabled and running after install)
AlmaLinux: sudo dnf install samba samba-client cifs-utils       (service smb; disabled and NOT running after install)
```

The two images differ here: Ubuntu started the server for me; on AlmaLinux `systemctl is-enabled smb` said `disabled` and `is-active` said `inactive`, so nothing was listening until I ran `systemctl enable --now smb`.

**Samba keeps its own password database.** A user needs a normal Linux account **and** a Samba password, set separately with `smbpasswd`. The Linux account can have no login shell (`/usr/sbin/nologin`), because it is only used for file access:

```text
$ groupadd wl-labfiles
$ useradd -m -s /usr/sbin/nologin -G wl-labfiles wl-alice
$ useradd -m -s /usr/sbin/nologin wl-bob                   (a second user, NOT in the group)
$ printf 'Lab-pass-1\nLab-pass-1\n' | smbpasswd -a -s wl-alice
Added user wl-alice.
$ pdbedit -L
wl-alice:1001:
wl-bob:1002:
$ mkdir /srv/wl-share; chown root:wl-labfiles /srv/wl-share; chmod 2770 /srv/wl-share
```

(The passwords are lab-only throwaways; a real one belongs in a prompt, not a script. `chmod 2770` is read, write, execute for the owner and the group, nothing for others, and the leading `2` is the **setgid** bit, which makes new files inherit the folder's group.) Appended to `/etc/samba/smb.conf`:

```text
[labfiles]
   comment = WinLab test share
   path = /srv/wl-share
   valid users = @wl-labfiles
   read only = no
   create mask = 0660
   directory mask = 2770
   force group = wl-labfiles
```

`valid users = @wl-labfiles` lets in only members of that group; `read only = no` makes the share writable; the masks and `force group` decide the mode and group of files people create. Each is documented in the [smb.conf(5) manual page](https://www.samba.org/samba/docs/current/man-html/smb.conf.5.html) (that site loaded for me once and timed out later in the session; I checked the option names there when it loaded). Check the file before restarting with `testparm`, which prints what Samba **understood** ([testparm(1)](https://manpages.debian.org/stable/samba-common-bin/testparm.1.en.html)):

```text
$ testparm -s | sed -n '1,4p;/\[labfiles\]/,$p'
Load smb config files from /etc/samba/smb.conf
Loaded services file OK.
Weak crypto is allowed by GnuTLS (e.g. NTLM as a compatibility fallback)
Server role: ROLE_STANDALONE
[labfiles]
	comment = WinLab test share
	create mask = 0660
	directory mask = 02770
	force group = wl-labfiles
	path = /srv/wl-share
	read only = No
	valid users = @wl-labfiles
```

`systemctl restart smbd` (Ubuntu) or `smb` (AlmaLinux), then `ss -tlnp` showed `smbd` listening on **445 and 139**, on `0.0.0.0` and `[::]`: **every interface**. In a real network that is a decision, covered in the exposure lesson.

## Use it, as each kind of visitor

`smbclient` ([smbclient(1)](https://manpages.debian.org/stable/smbclient/smbclient.1.en.html)) is a command-line SMB client. It lists the shares, then uses one:

```text
$ smbclient -L 127.0.0.1 -U wl-alice%Lab-pass-1
	Sharename       Type      Comment
	print$          Disk      Printer Drivers
	labfiles        Disk      WinLab test share
	IPC$            IPC       IPC Service (winlab-linux server (Samba, Ubuntu))
SMB1 disabled -- no workgroup available
```

AlmaLinux also listed **`wl-alice  Disk  Home Directories`**: its packaged configuration evidently has a `[homes]` section (I did not open the file), which shares each Samba user's home folder. That is a share I never asked for, a good example of why you read the default configuration and run `testparm` instead of assuming only your section exists.

```text
$ smbclient //127.0.0.1/labfiles -U wl-alice%Lab-pass-1 -c 'ls; put /tmp/wl-up.txt up.txt; ls'
  .                                   D        0  Sun Nov 22 13:22:46 2026
  ..                                  D        0  Sun Nov 22 13:22:46 2026
  readme.txt                          N       22  Sun Nov 22 13:22:46 2026
putting file /tmp/wl-up.txt as \up.txt (10.7 kb/s) (average 10.7 kb/s)
  up.txt                              A       11  Sun Nov 22 13:22:49 2026
$ ls -l /srv/wl-share
-rw-rw---- 1 root     wl-labfiles 22 Nov 22 13:22 readme.txt
-rw-rw---- 1 wl-alice wl-labfiles 11 Nov 22 13:22 up.txt
```

(I have put the lines in logical order; as printed, the `putting file` message came before the listing because the two use different output streams.) The uploaded file is owned by `wl-alice` (the user who sent it), group `wl-labfiles` and mode `660`: exactly what `force group` and `create mask` asked for. Now the people who should **not** get in:

```text
$ smbclient //127.0.0.1/labfiles -U wl-alice%wrong -c ls
session setup failed: NT_STATUS_LOGON_FAILURE                  (wrong password)
$ smbclient //127.0.0.1/labfiles -U wl-bob%Lab-pass-2 -c ls
tree connect failed: NT_STATUS_ACCESS_DENIED                   (right password, not in the group)
$ smbclient //127.0.0.1/labfiles -N -c ls
tree connect failed: NT_STATUS_ACCESS_DENIED                   (no password: guest)
```

Read the two different errors. **`LOGON_FAILURE` at session setup** means "I do not accept who you are". **`ACCESS_DENIED` at tree connect** means "I know who you are, and you may not use this share". Knowing which stage failed halves the search. (On AlmaLinux the guest attempt printed `Anonymous login successful` and **then** the same `ACCESS_DENIED`: an anonymous session was allowed, the share was not.)

### Protocol version, signing and encryption

```text
$ smbclient ... -m NT1 -c ls
lp_load_ex: Max protocol NT1 is less than min protocol SMB2_02.
Protocol negotiation to server 127.0.0.1 (for a protocol between SMB2_02 and NT1) failed: NT_STATUS_INVALID_PARAMETER_MIX
```

I asked the client to speak only the old **SMB1** (`NT1`) dialect, which has well-known security problems. It refused to even try: this Samba's minimum is SMB2. A real `mount -t cifs` and the server's `smbstatus` show what was negotiated:

```text
$ mount -t cifs //127.0.0.1/labfiles /mnt/wl-mnt -o username=wl-alice,password=Lab-pass-1
//127.0.0.1/labfiles on /mnt/wl-mnt type cifs (rw,relatime,vers=3.1.1,cache=strict,...,username=wl-alice,uid=0,...)
$ smbstatus -b
PID     Username     Group        Machine                          Protocol Version  Encryption   Signing
48230   wl-alice     wl-alice     127.0.0.1 (ipv4:127.0.0.1:46584) SMB3_11           -            partial(AES-128-CMAC)
```

**SMB 3.1.1**, the newest dialect, was used. **Signing** was on (it stops a middleman changing messages), but **Encryption** is `-`: the data is **not encrypted** on the wire. Over loopback that is irrelevant; across a real network, anyone who can capture the packets can read the files unless you turn encryption on (`smb encrypt` in `smb.conf`, which I did not test) or tunnel SMB through a VPN, as the WireGuard lesson shows. (Passing `password=` on a command line, as I did here, is visible to other users in the process list; it is for the test only. `mount.cifs` can read a credentials file instead; see [mount.cifs(8)](https://man7.org/linux/man-pages/man8/mount.cifs.8.html).)

## AlmaLinux: it connects and you cannot save

On AlmaLinux the same configuration, with the same users and the same Unix permissions, produced:

```text
$ smbclient //127.0.0.1/labfiles -U wl-alice%Lab-pass-1 -c 'ls; put /tmp/wl-up.txt up.txt'
  .                                   D        0  Sun Nov 22 13:28:44 2026
  ..                                  D        0  Sun Nov 22 13:28:44 2026
NT_STATUS_ACCESS_DENIED opening remote file \up.txt
```

Two clues: the listing **does not show `readme.txt`** (it exists, group-readable), and the save fails with `ACCESS_DENIED` for a user in the right group. The Unix permissions are fine; something else is saying no. On a Red Hat system the first suspect is **SELinux**, which labels every file and lets each program touch only certain labels (see the SELinux part of `security.security-fundamentals` and the `alma-selinux-context` lab). The labels:

```text
$ ls -dZ /srv/wl-share /srv/wl-share/readme.txt
unconfined_u:object_r:var_t:s0 /srv/wl-share
unconfined_u:object_r:var_t:s0 /srv/wl-share/readme.txt
```

and the denials, from the audit log (`ausearch -m avc -c smbd -ts recent -i`, see the logging lesson):

```text
denied  { create } for  pid=36328 comm=smbd[127.0.0.1] name=up.txt scontext=system_u:system_r:smbd_t:s0 tcontext=system_u:object_r:var_t:s0 tclass=file permissive=0
denied  { getattr } for pid=36328 comm=smbd[127.0.0.1] path=/srv/wl-share/readme.txt ... scontext=system_u:system_r:smbd_t:s0 tcontext=unconfined_u:object_r:var_t:s0 tclass=file permissive=0
```

Read the two contexts: the **source** `smbd_t` is the label of the Samba daemon; the **target** `var_t` is the generic label a folder under `/srv` gets. Policy lets `smbd_t` read and write files labelled `samba_share_t`, not `var_t`. `{ getattr }` on `readme.txt` is why it was missing from the listing: Samba could not even read its attributes. `permissive=0` means SELinux was enforcing, so the denial was real.

**The fix is to give the folder the right label, not to turn SELinux off.** `semanage fcontext` records a labelling rule, and `restorecon` applies it ([semanage-fcontext(8)](https://man7.org/linux/man-pages/man8/semanage-fcontext.8.html), [restorecon(8)](https://man7.org/linux/man-pages/man8/restorecon.8.html)):

```text
$ semanage fcontext -a -t samba_share_t '/srv/wl-share(/.*)?'
$ restorecon -Rv /srv/wl-share
Relabeled /srv/wl-share from unconfined_u:object_r:var_t:s0 to unconfined_u:object_r:samba_share_t:s0
Relabeled /srv/wl-share/readme.txt from unconfined_u:object_r:var_t:s0 to unconfined_u:object_r:samba_share_t:s0
$ semanage fcontext -l -C                                  (-C: only my local rules)
/srv/wl-share(/.*)?    all files    system_u:object_r:samba_share_t:s0
$ smbclient ... -c 'ls; put /tmp/wl-up.txt up.txt; ls'
putting file /tmp/wl-up.txt as \up.txt (10.7 kB/s) (average 10.7 kB/s)
  readme.txt                          N       22  Sun Nov 22 13:28:44 2026
  up.txt                              A       11  Sun Nov 22 13:28:49 2026
$ ls -lZ /srv/wl-share
-rw-rw----. 1 wl-alice wl-labfiles system_u:object_r:samba_share_t:s0 11 Nov 22 13:28 up.txt
```

The new file inherited the folder's label, so later files work without touching anything. The pattern `'/srv/wl-share(/.*)?'` is a regular expression meaning "the folder and everything under it". The rule lives in the policy store, so a later `restorecon` or full relabel gives the same result; a one-off `chcon` would not be recorded in the policy (I did not test `chcon`; that comes from the manual page's purpose, not from my run). I also did not use the **booleans** that exist for this (`getsebool -a | grep samba` listed `samba_export_all_rw --> off` and `samba_enable_home_dirs --> off`): `samba_export_all_rw` would let Samba write **everywhere**, which is the wrong direction for least privilege. I did not turn either on.

## Windows and other clients

A Windows client would reach the share at `\\server\labfiles` (File Explorer) or with `net use Z: \\server\labfiles /user:wl-alice`; macOS uses Connect to Server (`smb://server/labfiles`). **I did not test any of these**, so treat them as pointers, not results. SMB must reach port 445 through any firewall in the path, and I could not test that either (see the limits above).

## Common mistakes

- **Fixing a permission problem with `chmod 777`.** It opens the folder to everyone on the server. Find which of the two permission systems said no.
- **Setting the Linux password but not the Samba one.** `smbpasswd -a` is separate; `pdbedit -L` lists who is in Samba's database.
- **Turning SELinux off.** Label the folder (`semanage fcontext` then `restorecon`).
- **Forgetting AlmaLinux does not start the service.** `systemctl enable --now smb`.
- **Not reading the default `smb.conf`.** `[homes]` shared every user's home on AlmaLinux.
- **Treating `ACCESS_DENIED` and `LOGON_FAILURE` as one thing.** One is "who are you?", the other "you may not".
- **Assuming signing means privacy.** Signing detects tampering; only encryption (or a VPN) hides the content.
- **Putting `password=` on a command line.** Other users can see it; use a credentials file.

## Check yourself

1. Create a share for a group and two users, one inside and one outside it. Show the three outcomes (works, `LOGON_FAILURE`, `ACCESS_DENIED`) and say what each means.
2. On AlmaLinux, make a share under `/srv`, see it fail, find the denial with `ausearch` and fix it with the right label. What do the two contexts in the denial tell you?
3. What did `smbstatus` say about encryption, and what does that mean for the share across a real network?
4. Why did `readme.txt` not appear in the listing before the relabel?
5. Which `smb.conf` options decide the owner, group and mode of a file a client creates?

## Not tested, and honest limits

Any client other than `smbclient` and `mount.cifs` on the same machine; firewalls; Windows and macOS clients; encryption; AD; `vfs_fruit`; very old SMB versions (only refusing SMB1 was shown); and `chcon`. Ubuntu and AlmaLinux ran different Samba versions (4.19.5 and 4.24.5) and I did not compare their defaults beyond what is shown. Passwords in the scripts are throwaways for this test.
