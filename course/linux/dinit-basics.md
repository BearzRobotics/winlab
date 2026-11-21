*Draft for owner review.* **dinit** is a service manager and init system written by Davin McCall. **Chimera Linux** uses it as PID 1, and so does the owner's own distribution, FenrirOS, which is Chimera-influenced (I have not seen FenrirOS; this course has no verified facts about it). Where `systemd` is large, dinit is small: a handful of service types, a plain key-value file per service, dependencies, supervision with restarts, and one control tool, `dinitctl`. This lesson teaches how to look at a dinit system, start, stop and enable services, write a first service, change one, and find out why one failed. The next lessons cover the service file format in depth (`linux.dinit-service-files`), the system as a whole including user services (`linux.dinit-in-practice`), and a side-by-side with systemd (`linux.init-systems-compared`).

**Version warning.** dinit is **pre-1.0**. Everything below was tested on **dinit 0.22.0**, the version in Chimera's repository at the time (build 20261103). The upstream project page shows **0.23.0 (beta, released 2026-11-07)**, which I did **not** test, and the online manual pages are for 0.23.0 while I quote the 0.22.0 pages that are installed on the test machine (`man dinit-service`). Behaviour, messages and option names may change before 1.0.

**What was tested, and where.** A **Chimera Linux 20261103** base installation built by WinLab in a QEMU VM (kernel 7.3.1, musl, BSD userland **chimerautils 15.1.2**, **dinit 0.22.0**, **dinit-chimera 0.99.25** (Chimera's service set), **turnstile 0.1.11**), as root unless noted, with test services named `wl-*` (`tests/verification/dinit/dn1.sh` to `dn5-*.sh`). Output is real; process IDs are shown as `<pid>` where they would distract. **Not tested:** any distribution other than Chimera, dinit 0.23.0, shutdown and reboot, the recovery service and `single` boot, a real disk or UEFI machine, cgroup settings (`run-in-cgroup`), `socket-listen`, `inittab-*` and `kill-all-on-stop`. Documentation: the manual pages [dinit(8)](https://davmac.org/projects/dinit/man-pages-html/dinit.8.html), [dinit-service(5)](https://davmac.org/projects/dinit/man-pages-html/dinit-service.5.html) and [dinitctl(8)](https://davmac.org/projects/dinit/man-pages-html/dinitctl.8.html) on the [project page](https://davmac.org/projects/dinit/), the [dinit-chimera](https://github.com/chimera-linux/dinit-chimera) service suite, and Chimera's [Service management](https://chimera-linux.org/docs/configuration/services) page, which says enabling a service "simply creates a symlink in /etc/dinit.d/boot.d" (all pages load; checked 2026-11-21). The behaviour in this lesson rests on my test output; the installed 0.22.0 manual pages were read in full for the settings I describe.

## What dinit does

dinit starts the **services** you ask for, **and the services they depend on first**, in parallel where it can. It **supervises** process services (watching them, restarting them), keeps their state, and answers commands on a **control socket** (`dinitctl` talks to it; for the system instance the socket is `/run/dinitctl` on this machine, as the permission error for a normal user shows). As PID 1 it also handles shutdown and reboot (not tested here).

```text
$ tr "\0" " " < /proc/1/cmdline         ->  /usr/bin/dinit
$ dinit --version                       ->  Dinit version 0.22.0.
```

dinit has **five service types**: `process`, `bgprocess`, `scripted`, `internal` and `triggered`. They are explained in the next lesson; for now:

- a **process** service is one program that dinit starts and watches;
- a **scripted** service is started and stopped by running commands, and counts as started when the command succeeds;
- an **internal** service has no program: it only groups other services (like a systemd target).

On this machine's `/usr/lib/dinit.d` (80 files):

```text
$ grep -h "^type" /usr/lib/dinit.d/* | tr -s " " | sort | uniq -c | sort -rn
     42 type = scripted
     23 type = process
     12 type = internal
```

## Where service files are

One **plain text file per service**, named for the service. For the system instance the manual lists `/etc/dinit.d`, `/run/dinit.d`, `/usr/local/lib/dinit.d` and `/lib/dinit.d`, searched in that order; on Chimera `/lib` is a link to `usr/lib` (`/lib -> usr/lib`), so the packages' files are in **`/usr/lib/dinit.d`** and **yours go in `/etc/dinit.d`**. A file in `/etc/dinit.d` wins over one of the same name in `/usr/lib/dinit.d`. (This is the same idea as `/etc/systemd/system` and `/usr/lib/systemd/system`.)

Two facts about **loading** that surprise people coming from systemd:

- dinit reads a service file **only when it is first needed**, not at start. A new file works at once: `dinitctl start wl-hello` found `wl-hello` the moment I wrote it, and `dinitctl list` did not show it before that.
- Once loaded, a service description is **never unloaded or re-read automatically**, not even when the service stops or fails (the manual says so). There is no `daemon-reload`; there are `reload` and `unload` instead (below).

## How the system starts: `boot`

dinit starts one service by default: **`boot`**. On Chimera:

```text
$ cat /usr/lib/dinit.d/boot
# This is the primary entry point. It triggers startup
# of every other service. In addition to that it also
# provides the user-enabled service directory.

type = internal
depends-on: system
waits-for.d: /etc/dinit.d/boot.d

$ cat /usr/lib/dinit.d/system
# the actual primary chimera service

type = internal
depends-on: login.target
depends-on: network.target
waits-for.d: /usr/lib/dinit.d/boot.d
```

Two directories of **symbolic links**, each named for a service, decide what starts at boot:

```text
/usr/lib/dinit.d/boot.d:   agetty chrony dbus-daemon elogind tmpfiles-clean turnstiled udevd      (the distribution's defaults, links such as  agetty -> ../agetty )
/etc/dinit.d/boot.d:       dhcpcd sshd                                                           (what the administrator, or the install script, enabled)
```

`waits-for.d: DIRECTORY` means: for every file name in the directory (contents do not matter, usually a link), add a **waits-for** dependency to the service of that name. So **enabling a service is making a link in `/etc/dinit.d/boot.d`**, which is exactly what `dinitctl enable` does (below).

## Looking at the system

```text
$ dinitctl status boot
Service: boot
    State: STARTED
    Activation: explicitly started
$ dinitctl status sshd
Service: sshd
    State: STARTED
    Activation: start due to dependent(s)
    Process ID: <pid>
$ dinitctl is-started sshd ; echo rc=$?           ->  STARTED   rc=0
$ dinitctl is-started no-such-service ; echo rc=$?  ->  rc=1      (and no state is printed)
$ dinitctl list | grep -v "early-" | head
[[+]     ] boot
[{+}     ] system
[{+}     ] login.target (has console)
[{+}     ] network.target
[{+}     ] chrony
[{+}     ] chronyd (pid: <pid>)
[{+}     ] sshd (pid: <pid>)
[{+}     ] dhcpcd (pid: <pid>)
[{+}     ] agetty-service@tty1 (pid: <pid>)
[[+]     ] rtkit (pid: <pid>)
```

(`dinitctl list` showed 72 loaded services on the test machine, most of them the `early-*` start-up steps.) Reading the `list` indicators, from the manual:

| Indicator | Meaning |
|---|---|
| `[{+}     ]` | started |
| `[[+]     ]` | started and **marked active** ("explicitly activated", square brackets) |
| `[{ }<<   ]` | starting |
| `[   >>{ }]` | stopping |
| `[     {-}]` | stopped |
| `[     {X}]` | **failed to start**, or the process ended with an error or signal |

The two **Activation** values you will see: **`explicitly started`** (someone ran `dinitctl start`, or it is the boot service) and **`start due to dependent(s)`** (it is running only because something that needs it is). This matters for stopping, below.

`dinitctl status` takes a service **name**; there is no "show everything about a unit" command like `systemctl cat`, so you read the file yourself (`cat /usr/lib/dinit.d/sshd`):

```text
type = process
command = /usr/bin/sshd -D
smooth-recovery = true
depends-on: ssh-keygen
depends-on: local.target
depends-on: network.target
```

## Starting and stopping

```text
$ dinitctl start wl-hello                 ->  Service 'wl-hello' started.     rc=0       (start waits until the service has started)
$ dinitctl status wl-hello                ->  Service: wl-hello / State: STARTED / Activation: explicitly started / Process ID: <pid>
$ dinitctl stop wl-hello                  ->  Service 'wl-hello' stopped.     rc=0
$ dinitctl status wl-hello ; dinitctl is-started wl-hello     ->  State: STOPPED / STOPPED      rc=1
$ dinitctl restart wl-hello               ->  Service 'wl-hello' stopped. / Service 'wl-hello' started.
$ dinitctl start wl-nonexistent           ->  dinitctl: failed to find service description.
                                              dinitctl: check service description file exists / service name spelling.     rc=1
```

All of these **wait** until the change is complete. `--no-wait` returns at once. Exit status 0 means success, 1 means failure.

### Explicit activation: why a dependency stops or stays

dinit keeps, for each started service, whether it was **explicitly activated** (by `start`) or is **only a dependency**. The rule (from `dinit(8)`, and every line below tested): a service stays up while it is explicitly activated **or** some started service needs it.

```text
starting wl-need (depends-on: wl-db) starts wl-db:        wl-db "Activation: start due to dependent(s)"
stopping wl-need then stops wl-db (nobody else needs it):  db=STOPPED need=STOPPED
dinitctl start wl-db ; dinitctl start wl-need ; dinitctl stop wl-need     ->  db=STARTED need=STOPPED     (wl-db was explicit, so it stays)
dinitctl stop wl-db     (while wl-need is running):
    dinitctl: cannot stop service 'wl-db' due to the following dependents:
    (only direct dependents are listed. Exercise caution before using '--force' !!)
      wl-need                                                                       rc=1
dinitctl stop --force wl-db    ->  Service 'wl-db' stopped.     db=STOPPED need=STOPPED      (the dependent is stopped too)
```

Three more commands finish the picture:

```text
dinitctl release wl-act    (a service explicitly started, with no dependents)   ->  Service 'wl-act' stopped.      (removes the "explicit" mark; with no dependents it stops)
dinitctl wake wl-act       (a stopped service nothing depends on)               ->  dinitctl: service has no active dependents, cannot wake.     (wake only starts what something else needs)
dinitctl start --pin wl-db ; dinitctl stop wl-db    ->  dinitctl: cannot stop service 'wl-db' as it is pinned started          rc=1
dinitctl unpin wl-db       ->  Service 'wl-db' unpinned.
```

`release` and `stop` differ: `stop` stops now (and **refuses** while a dependent runs, unless `--force`), `release` only removes the mark. `start --pin` locks a state so that nothing, including a dependency change, can alter it until `unpin`: useful for a manual repair. (I once saw `release` leave a service running while other, stopped, services that depended on it were still loaded; I did not find out why, and the clean cases above behaved as described.)

## `enable` and `disable`

```text
$ dinitctl enable wl-enab
Service 'wl-enab' has been enabled.
Service 'wl-enab' started.
$ ls -l /etc/dinit.d/boot.d | grep wl-        ->  wl-enab -> ../wl-enab
$ dinitctl disable wl-enab    ->  Service 'wl-enab' has been disabled.      (link removed; the service is STOPPED)
$ dinitctl enable wl-enab ; dinitctl stop wl-enab ; ls /etc/dinit.d/boot.d | grep wl-     ->  wl-enab    (stopped, but still enabled: the link remains)
$ dinitctl --offline enable wl-enab    ->  Service 'wl-enab' has been enabled.        (no daemon needed: only the link is made)
```

- **`dinitctl enable` both makes the link and starts the service** (unlike `systemctl enable`, which only makes the link unless you add `--now`).
- A **stop does not disable**: the link stays, so by the design above it starts again at the next boot (I did not reboot to confirm).
- **`--offline`** (with `-d DIR` for the service directory) makes or removes the link without talking to the daemon, which is how you enable a service on a system that is not running (for example from a chroot during installation; the lab VM's installer made its two links by hand with `ln -s`, and I did not test `--offline` in a chroot).
- `dinitctl disable` on a service that something else needs gives a note: `dinitctl: note: disabled service may have other dependents`. A disabled service can still start as a dependency.

### Enabling into another group

`enable` links the service into **the `waits-for.d` directory of one other service**: by default the one named in the service's own `@meta enable-via NAME` line, otherwise **`boot`**. `--from NAME` chooses another.

```text
$ cat /etc/dinit.d/wl-member        type = process / command = /bin/sleep 1000 / @meta enable-via wl-grpA
$ cat /etc/dinit.d/wl-grpA          type = internal / waits-for.d: /etc/dinit.d/wl-grpA.d
$ dinitctl start wl-grpA ; dinitctl enable wl-member     ->  Service 'wl-member' has been enabled. / Service 'wl-member' started.      the link: /etc/dinit.d/wl-grpA.d/wl-member -> ../wl-member
$ dinitctl enable --from wl-nodir wl-member              ->  dinitctl: service 'wl-nodir' has no waits-for.d directory specified      rc=1
```

**A caution from my own tests:** with the group service **not started**, `dinitctl enable wl-member` printed `Service 'wl-member' has been enabled.` and then **did not return** (my `timeout 8` ended it, rc=124), with a warning `dinitctl: warning: enabling dependency for non-started service`. I saw it once and did not reproduce it again after the group had been started, so I do not know the whole cause: **start the group first, and wrap `enable` in `timeout` in scripts**.

## Your first service

```text
# /etc/dinit.d/wl-hello
type = process
command = /bin/sh -c "while :; do echo tick; sleep 1; done"
log-type = buffer
```

```text
$ dinitctl start wl-hello
Service 'wl-hello' started.
$ dinitctl status wl-hello
Service: wl-hello
    State: STARTED
    Activation: explicitly started
    Process ID: <pid>
$ dinitctl catlog wl-hello           ->  tick / tick / tick ...        (the service's output, kept in memory because of log-type = buffer)
$ dinitctl stop wl-hello
```

### Quotes: only double quotes quote

**Single quotes are not quote characters in a dinit file.** My first version of this file, with `sh -c 'while ...'`, ran as `sh -c` followed by the words `'while`, `:;`, ..., and the shell reported the problem in the buffered log:

```text
$ dinitctl catlog wl-hello      (with command = /bin/sh -c 'while :; do echo tick; sleep 1; done')
  :;: Syntax error: Unterminated quoted string
  (dinit: note: service restarted)
  :;: Syntax error: Unterminated quoted string
```

and the service flapped between STARTING and STARTED because the default is to restart (explained next lesson). **Use double quotes** around any argument with spaces. Like systemd's `ExecStart=`, the command is **not run by a shell**; for pipes and redirects use `/bin/sh -c "..."` or a script file.

## Changing a service: `reload` and `unload`

Because a loaded description is kept, editing the file is not enough. Tested with a file whose command echoes its version (`v1`, `v2`, ...), rewritten each time (**with `cat`/`printf`, not `sed -i`: see the next lesson for why**):

| What I did after changing the file | Which command ran |
|---|---|
| `dinitctl restart` only | the **old** one (`v1`) |
| `dinitctl reload` then `restart` | the **new** one |
| `stop`, `unload`, then `start` | the **new** one |
| `stop`, `reload`, then `start` | the **new** one |
| `start` or `restart` on a loaded service whose file changed | the old one, **plus a warning** |

```text
dinitctl: warning: service description may have changed; use 'dinitctl reload wl-chg' to apply changes.
```

The same worked for a service that **failed** because of a wrong path: after fixing the file, `start` printed the warning and failed the same way; **`reload` then `start` worked**, and so did `unload` then `start`. Limits (from the manual, and one tested): `reload` cannot change a **running** service's type: it printed `dinitctl: could not reload service; service in wrong state, incompatible change, or bad service description.` (rc 1). `unload` works **only on a stopped service that no loaded service depends on**: unloading a dependency first gave `dinitctl: could not unload service; service not stopped, or is a dependency of another service.`; unload dependents first.

## When a service will not start

### A program that cannot be executed

```text
# /etc/dinit.d/wl-bad            command = /usr/bin/slepe 1000      (a typo for sleep)
$ dinitctl start wl-bad ; echo rc=$?
Service 'wl-bad' failed to start.
Reason: execution of service process failed:
        Stage: executing command
        Error: No such file or directory
rc=1
$ dinitctl status wl-bad
Service: wl-bad
    State: STOPPED (could not be launched)
        Stage: executing command
        Error: No such file or directory
$ dinitctl is-failed wl-bad ; echo rc=$?       ->  STOPPED    rc=0          (the service counts as failed)
$ dinitctl list | grep wl-bad                  ->  [     {X}] wl-bad
```

Unlike a systemd `Type=simple` service (whose `start` reports success for a missing program), **dinit's `start` fails at once with the stage and the system error**. The stage names where it broke: `executing command`, `opening log file`, `changing directory`:

```text
logfile = /var/log/wl-nodir/log.txt (directory missing)   ->  Stage: opening log file       Error: No such file or directory
working-dir = /nonexistent                                ->  Stage: changing directory     Error: No such file or directory
start-timeout = 1 with a slow service                     ->  Service 'wl-slow' failed to start. Reason: start timed out.      State: STOPPED (start timed out)
a scripted service that exits 3                           ->  Reason: service process terminated before ready: exited - status 3      State: STOPPED (failed to start; exited - status 3)
a dependency that failed (depends-on:)                    ->  Reason: a dependency of the service failed to start. Check dinit log.
```

`is-failed` means "stopped because of a startup failure, timeout or dependency failure"; a process that **started and then died** is not a startup failure (a crash-looping service that ran out of restarts printed `STOPPED`, rc 1, from `is-failed`).

### Files dinit cannot read: `dinit-check`

```text
$ dinitctl start wl-nocmd        (type = process but no command)
dinitctl: error loading service (or dependency of service).
dinitctl: try 'dinit-check <service-name>' or check log for more information.         rc=1
$ dinit-check wl-nocmd           ->  Service 'wl-nocmd': 'command' setting not specified.          ... One or more errors/warnings issued.
$ dinit-check wl-bogus           ->  Service 'wl-bogus' (/etc/dinit.d/wl-bogus:3): unknown setting: 'bogus-setting'.
$ dinit-check wl-baddep          ->  Unable to load service 'wl-missing-dep': service description not found.
$ dinit-check wl-cyc1            ->  (reports the cycle:  wl-cyc1 -> wl-cyc2 ...)
$ dinit-check wl-hello           ->  Checking service: wl-hello... / Performing secondary checks... / No problems found.        rc=0
$ dinit-check                    ->  checks every service in the directories ("No problems found." for the stock set)
```

The `dinitctl` error messages are short on purpose. The three you will meet: **`failed to find service description`** (file missing or name misspelled), **`error in service description`** (a setting is unknown or wrong), **`error loading service (or dependency of service)`** (a dependency is missing, a cycle, or a required setting is absent). **Run `dinit-check NAME` for the detail**: it prints the file, the line and the reason. `dinit-check` is the equivalent of `systemd-analyze verify`.

### dinit's own log

`dinit-check` tells you what is wrong with a file; the **log** tells you what happened. dinit logs to the **console** and to **syslog** (`/dev/log`). On the freshly installed machine there was no `/dev/log` and no `/var/log/messages` (the log daemon, `syslog-ng`, is installed but not enabled; the `no-system-log` lab is exactly this). After `dinitctl enable syslog-ng`:

```text
$ dinitctl enable syslog-ng ; ls /var/log        ->  ... messages syslog-ng.log ...
$ grep wl-logbad /var/log/messages
2026-11-21 22:01:00 err dinit[1]: wl-logbad: execution failed - executing command: No such file or directory
2026-11-21 22:01:00 err dinit[1]: service wl-logbad failed to start.
$ grep wl-logok /var/log/messages
2026-11-21 22:01:01 notice dinit[1]: service wl-logok started.
2026-11-21 22:01:01 notice dinit[1]: service wl-logok stopped.
$ ... start wl-nonexistent-xyz      ->  err dinit[1]: Could not load service wl-nonexistent-xyz: service description not found.
$ ... start wl-logbogus             ->  err dinit[1]: Error in service description for 'wl-logbogus' (file /etc/dinit.d/wl-logbogus, line 3): unknown setting: 'bogus-setting'.
```

So `Check dinit log` in the `dinitctl` messages means **`/var/log/messages`** (once a syslog daemon is running). I did not capture the console output of dinit without a syslog daemon, so I cannot say how much of this would have been visible. (`syslog-ng`'s own service file has `options: starts-log`, the option that tells dinit "the system log daemon is up now, start logging through `/dev/log`".)

## Common mistakes

- **Expecting `daemon-reload`**: there is none. Use `reload` (service stopped or compatible change) or `unload` then `start`.
- **Editing the file and restarting**: the old definition keeps running; heed the `may have changed` warning.
- **Single quotes** in `command =` (not quoting characters).
- **Thinking `enable` only makes a link**: it also **starts** the service; and a manual `stop` does not disable.
- **`dinitctl stop` on a dependency** and being surprised by the refusal (use `--force` only knowingly).
- **Believing a started dependency stops with its dependent** when it was started explicitly.
- **No log daemon**: `Check dinit log` has nowhere to look until `syslog-ng` runs.
- **Putting service files only in `/usr/lib/dinit.d`**: your own go in `/etc/dinit.d`.
- **`enable` of a group member while the group is stopped**: it may not return (use `timeout`).

## Practice

Use a scratch VM (the Chimera lab VM has a `winlab-clean` snapshot); name services `wl-…` and remove the files afterwards.

1. **Tour.** Run `dinitctl list`, `dinitctl status` and `cat` for `sshd`, `chrony` and `boot`; draw the dependency tree of `boot` two levels deep.
2. **First service.** Write the ticker with a buffered log; start it, read `catlog`, stop it. Then rewrite the command with single quotes and read what happens.
3. **Activation.** Reproduce the table: dependent stops dependency; explicit dependency stays; `stop` refused with a dependent; `--force`.
4. **Enable.** Enable and disable a service; show the link, then show that `stop` leaves it enabled. Then enable offline.
5. **Reload.** Reproduce at least three rows of the reload table and the warning. Then fix a failed service two ways (`reload`, `unload`).
6. **Failures.** Produce a missing program, a missing log directory and a missing working directory; record the `Stage:` line of each. Find the same text in the system log after enabling `syslog-ng`.
7. **dinit-check.** Break a service in four ways (unknown setting, missing dependency, no command, cycle) and read each report.
8. **Group.** Make a group with `waits-for.d` and `@meta enable-via`; enable a member; try `--from` with a service that has no directory.
9. **Pin.** Pin a service started, show the refusal, unpin.
10. **Find the bug.** (a) `command = /bin/sh -c 'echo hi; sleep 100'` (b) a service file edited and then `dinitctl restart` with no reload, still running the old command (c) `dinitctl stop wl-db` refused while `wl-app` is running (d) `dinitctl enable wl-member` that never returns. Say what is going on and what you would do.

## Check your understanding

Take the quiz for this lesson (it draws twelve from the bank). After a wrong answer, reread the section named in the review line.
