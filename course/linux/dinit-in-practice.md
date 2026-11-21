*Draft for owner review.* The first two dinit lessons taught the commands and the file format. This one puts them together on a real **Chimera Linux** system: how the machine boots (read from Chimera's own service files), how to **add your own service** end to end, a **troubleshooting playbook** built from the failures I produced, the **system log**, and **user services** with **turnstile**, including what happens at logout.

**Version and testing.** **dinit 0.22.0**, **dinit-chimera 0.99.25** (Chimera's service set), **turnstile 0.1.11** on **Chimera Linux 20261103** in a QEMU VM, kernel 7.3.1, BSD userland (`tests/verification/dinit/dn1.sh` to `dn6.sh`, `dn5-*.sh` for the user-session tests). dinit is pre-1.0 and 0.23.0 exists upstream (untested). **Not tested:** a real **reboot or shutdown**, the **recovery** and **single-user** boot paths (I read their service files only), **`/etc/rc.local`** (read the script that runs it; no such file exists on the machine), the **NetworkManager** service (read its file only), **graphical sessions**, **`pam_turnstile` on a console login** (only SSH logins), `root_session`, any other distribution that uses dinit, and **FenrirOS**, which I have never seen. Documentation: [dinit(8)](https://davmac.org/projects/dinit/man-pages-html/dinit.8.html), [dinit-service(5)](https://davmac.org/projects/dinit/man-pages-html/dinit-service.5.html), [dinitctl(8)](https://davmac.org/projects/dinit/man-pages-html/dinitctl.8.html), Chimera's [Service management](https://chimera-linux.org/docs/configuration/services), [dinit-chimera](https://github.com/chimera-linux/dinit-chimera) and [turnstile](https://github.com/chimera-linux/turnstile) (all load; the installed manual pages `turnstiled(8)` and `turnstiled.conf(5)` were read in full).

## How a Chimera system boots

dinit as PID 1 starts the **`boot`** service, and everything else follows from dependencies. These are Chimera's own files (read with `cat`, not changed):

```text
boot            type = internal   depends-on: system                waits-for.d: /etc/dinit.d/boot.d       (what the administrator enabled)
system          type = internal   depends-on: login.target  depends-on: network.target    waits-for.d: /usr/lib/dinit.d/boot.d   (the distribution's defaults)
login.target    "virtual service run before login is enabled"     internal  depends-on: local.target   options: runs-on-console
network.target  "virtual service for others to depend on; bring up networking daemons"   internal  depends-on: pre-network.target
pre-network.target  "reached before net daemons are started"      internal  depends-on: local.target
local.target    "rc.local has been run"   scripted  command = /usr/lib/dinit.d/early/scripts/local.sh   depends-on: pre-local.target, early-tmpfiles   waits-for: early-bless-boot
pre-local.target "core system init is done"   scripted  depends-on: early-fs-local.target, early-console.target, early-net-lo, early-hostname   waits-for: early-swap, early-rng, early-machine-id, early-sysctl, early-binfmt, early-kdump
```

Read it from the bottom: the 42 **`early-*`** services (pseudo file systems, device manager, root file system check and remount read-write, kernel modules, hostname, loopback network, machine id, sysctl, swap and so on) must finish before **`pre-local.target`** ("core system init is done"); then **`local.target`** runs `local.sh`; then the network **targets**; then **`login.target`**; then `system` and `boot` are up. The pattern to learn is that **targets are internal services used as named stages**, and that your own services hook in with **`depends-on`/`waits-for`** on a stage and **`before:`** another stage:

| Stage | Use it when |
|---|---|
| `local.target` | you need file systems, devices and the basics up (**the usual `depends-on` for a daemon**: `sshd`, `chronyd`, `turnstiled` all use it) |
| `pre-network.target` | you configure networking and need to run **before** network daemons |
| `network.target` | you need the network configured: `depends-on: network.target` (my example below, and `sshd` does); the network service itself uses `before: network.target` |
| `time-sync.target` | you need the clock correct (`tmpfiles-clean` waits for it; the `chrony` scripted service is `before: time-sync.target`) |
| `login.target` | services that must be up **before** users can log in use `before: login.target` (`elogind`, `turnstiled`, `dbus` do) |

`local.target`'s script is small and readable:

```text
$ cat /usr/lib/dinit.d/early/scripts/local.sh
#!/bin/sh
DINIT_SERVICE=local
. /usr/lib/dinit.d/early/scripts/common.sh
[ -x /etc/rc.local ] && /etc/rc.local
exit 0
```

so **an executable `/etc/rc.local` runs once at boot** (the machine had none, and I did not test one). Chimera's `/usr/lib/dinit.d` holds 80 files: the `early-*` set, a few targets, and about two dozen daemons: `agetty` and `agetty-service` (terminals), `chrony`/`chronyd`, `dbus`, `dbus-daemon`, `dhcpcd`, `elogind`, `networkmanager`, `polkitd`, `sshd`, `syslog-ng`, `turnstiled`, `udevd` and others. **Only some are enabled**: the defaults are in `/usr/lib/dinit.d/boot.d` and the administrator's in `/etc/dinit.d/boot.d`.

### Recovery and single-user

Two services exist for repair, and both run `sulogin`:

```text
recovery:  type = process   command = /usr/bin/sulogin   restart = false   options: runs-on-console
single:    type = process   command = /usr/bin/sulogin   restart = false   chain-to: boot   options: shares-console
```

The manual describes how they are used (`dinit(8)`): the **recovery** service is what dinit offers to start if `boot` fails and all services stop; and a kernel command line word **`single`** is taken as the name of the service to start (`single` here: a root shell, then `chain-to: boot` carries on to a normal start when you exit it). I did **not** boot either path, so treat this as the documented design, and test it on a VM with a snapshot before you need it.

## Networking

The base installation has **no network until a network service is enabled**: dinit starts only what is linked into the two `boot.d` directories, and the installed system had `dhcpcd` and `sshd` linked into `/etc/dinit.d/boot.d` by the WinLab installer. The services:

```text
dhcpcd:          type = process   command = /usr/bin/dhcpcd -B -M -j /var/log/dhcpcd-service.log   logfile = /var/log/dhcpcd.log   before: network.target   depends-on: pre-network.target
networkmanager:  type = process   command = /usr/bin/NetworkManager -n   smooth-recovery = true   before: network.target   depends-on: dbus   depends-on: pre-network.target
sshd:            type = process   command = /usr/bin/sshd -D   smooth-recovery = true   depends-on: ssh-keygen, local.target, network.target
$ ip -br addr     ->  lo UNKNOWN 127.0.0.1/8 ::1/128 ;  enp0s3 UP 10.0.2.15/24 ...        (after dhcpcd was enabled)
```

**One network service**: `dhcpcd` for a simple machine, `networkmanager` for a laptop or desktop, not both. To enable: `dinitctl enable dhcpcd` (and it starts at once). `sshd` depends on `ssh-keygen`, a scripted service that creates host keys at first boot (`ssh-keygen -A`).

Stopping `network.target` shows who relies on it:

```text
$ dinitctl stop network.target
dinitctl: cannot stop service 'network.target' due to the following dependents:
(only direct dependents are listed. Exercise caution before using '--force' !!)
  chronyd system sshd wl-app
```

(`wl-app` is my example below). Stopping the network target with `--force` would stop SSH too: **do not do it on a machine you reach over SSH.**

## Adding your own service, end to end

A small application that must run as an unprivileged user, keep state, log to a file, wait for the network, and be restarted if it crashes. The script `/usr/local/bin/wl-app.sh` prints a heartbeat each second and writes the count to a state file:

```sh
#!/bin/sh
echo "wl-app starting as $(id -un), state dir: $(ls -d /var/lib/wl-app)"
n=0
while :; do
  n=$((n+1))
  echo "heartbeat $n" > /var/lib/wl-app/last
  echo "heartbeat $n"
  sleep 1
done
```

(`#!/bin/sh` and POSIX only, as everywhere in this course: on Chimera `sh` is FreeBSD's.) The state directory and the service:

```text
$ mkdir -p /var/lib/wl-app && chown nobody /var/lib/wl-app
# /etc/dinit.d/wl-app
# WinLab example application
type = process
command = /usr/local/bin/wl-app.sh
run-as = nobody
working-dir = /var/lib/wl-app
logfile = /var/log/wl-app.log
logfile-uid = nobody
logfile-permissions = 640
restart = on-failure
smooth-recovery = true
restart-delay = 0.5
depends-on: network.target
options: no-new-privs
```

The steps, each one run:

```text
1. dinit-check wl-app                 ->  ... Performing secondary checks... Secondary checks complete. No problems found.
      (dinit-check goes through every service wl-app depends on, which is why its output starts with "Checking service: early-cgroups..." and so on)
2. dinitctl start wl-app              ->  Service 'wl-app' started.   (State: STARTED, Activation: explicitly started, Process ID)
3. cat /var/log/wl-app.log            ->  wl-app starting as nobody, state dir: /var/lib/wl-app / heartbeat 1 / heartbeat 2 / heartbeat 3
   ls -l /var/log/wl-app.log          ->  -rw-r-----  1 nobody nogroup ...          cat /var/lib/wl-app/last  ->  heartbeat 3
4. ps -o user,pid,args -p PID         ->  nobody  <pid>  /bin/sh /usr/local/bin/wl-app.sh          (the process runs as nobody)
5. kill -9 PID ; sleep 1.5 ; dinitctl status wl-app   ->  State: STARTED, with a new Process ID    (restart = on-failure: SIGKILL is a failure; smooth-recovery: no dependents disturbed)
6. dinitctl enable wl-app ; ls -l /etc/dinit.d/boot.d   ->  wl-app -> ../wl-app        (starts at every boot from now on)
7. dinitctl disable wl-app            ->  Service 'wl-app' has been disabled.   dinitctl: note: disabled service may have other dependents
```

(The step 7 note only means that `disable` removes the boot link: anything else that depends on the service could still start it. It is not an error.) A checklist for any new service, from this run and the earlier tests:

1. **Put the file in `/etc/dinit.d`**, the program on a path you control, and the state under `/var/lib/NAME` (owned by the user it runs as).
2. **`dinit-check NAME` first.** It catches unknown settings, missing dependencies, cycles and missing commands.
3. **Start it by hand and read the log**: `logfile` for anything long-running (`log-type = buffer` keeps only the first output).
4. **Decide the restart policy**: dinit's default is to restart always; `on-failure` + `smooth-recovery` is the usual choice for a daemon.
5. **Depend on the right stage**: `local.target` or `network.target`; use `waits-for` unless it truly cannot run without the dependency.
6. **Run it as a user**: `run-as`, plus `options: no-new-privs`, and `capabilities = ^CAP_NET_BIND_SERVICE` if it must bind a low port.
7. **Enable it** with `dinitctl enable`, and test that it comes back after a reboot (I did not reboot in these tests).

## The system log

`dinit` logs through **syslog**. On the fresh installation no log daemon runs, so `/var/log/messages` does not exist. **`syslog-ng`** ships with the system; its service file says `before: local.target` and `options: starts-log` (the option that tells dinit the log daemon is up). Enable it once:

```text
$ dinitctl enable syslog-ng
$ grep dinit /var/log/messages
2026-11-21 22:01:00 err dinit[1]: wl-logbad: execution failed - executing command: No such file or directory
2026-11-21 22:01:00 err dinit[1]: service wl-logbad failed to start.
2026-11-21 22:01:01 notice dinit[1]: service wl-logok started.
2026-11-21 22:01:01 notice dinit[1]: service wl-logok stopped.
2026-11-21 22:01:02 err dinit[1]: Could not load service wl-nonexistent-xyz: service description not found.
2026-11-21 22:01:02 err dinit[1]: Error in service description for 'wl-logbogus' (file /etc/dinit.d/wl-logbogus, line 3): unknown setting: 'bogus-setting'.
```

Levels, from the manual: `debug`, `notice`, `warn`, `error`; start and stop messages are `notice`, failures `error`. Other logs on the machine: **per-service files** from `logfile =` (`/var/log/dhcpcd.log`, `/var/log/turnstiled.log`, `/var/log/syslog-ng.log`), and `apk.log` for the package manager. There is **no journal**: if you want searchable structured logs you read the text files (`grep`, `tail -f`) and rotate them yourself (log rotation was not covered or tested).

## A troubleshooting playbook

Every row below was produced and diagnosed in the tests.

| Symptom | Look at | Cause and fix |
|---|---|---|
| `dinitctl start X`: `failed to find service description` | file name, directory | typo, or file not in `/etc/dinit.d`; templates need the **base** file name |
| `error in service description` | `dinit-check X`, then `/var/log/messages` | unknown setting, wrong value, bad `run-as` user, a `$((` in a command: the log gives file and line |
| `error loading service (or dependency of service)` | `dinit-check X` | missing dependency, cycle, missing `command` |
| `failed to start` + `Stage: executing command` | the `command` path, permissions, interpreter line | wrong or non-executable program |
| `Stage: opening log file` / `changing directory` | `logfile` directory, `working-dir` | create the directory (the service does not start without it) |
| `Reason: start timed out.` | `start-timeout`, `ready-notification` | the service never signalled ready, or is slow: raise the timeout or fix the readiness |
| `a dependency of the service failed to start` | `dinitctl list` for `{X}` services; log | fix the dependency; or make it `waits-for` if optional |
| My edit has no effect | `dinitctl start` printed `service description may have changed` | `dinitctl reload X` (or `unload`); then restart |
| The service keeps coming back | `restart` (default is yes) | `restart = no`; or `dinitctl stop` (a manual stop is not restarted) |
| It restarted a few times then stayed down | `restart-limit-count` (default 5 per 10 s) | fix the crash; `State: STOPPED (terminated; exited - status N)` |
| `cannot stop service ... due to the following dependents` | the listed names | stop the dependents, or `--force` knowingly |
| No `/var/log/messages` | `dinitctl is-started syslog-ng` | enable `syslog-ng` |
| No network after install | `ip -br addr`; `dinitctl is-started dhcpcd` | enable a network service (`dhcpcd`) |
| A "fixed" service file is unchanged | the error from your edit command | **BSD `sed -i` on Chimera does not edit in place** (see the service-file lesson); rewrite the file instead |
| `dinitctl enable` of a group member does not return | whether the group service is started | start the group first; use `timeout` in scripts |

(The lab scenarios `chimera-service-wont-start` and `chimera-no-system-log` are two of these rows; a good exercise is to solve them using only this table.)

## User services and turnstile

A **user** can have their own services, managed by a **separate dinit instance per login session**, started by **turnstile**.

```text
$ ps -eo pid,args | grep "[t]urnstiled"   ->  two processes (pid 394, and pid 840 which appeared with the login; I did not find out what the second one does)
   the service `turnstiled`:  depends-on: local.target   before: login.target   logfile = /var/log/turnstiled.log
# PAM: pam_turnstile.so appears in /usr/lib/pam.d/system-login:
-session optional pam_turnstile.so       (a leading "-" is PAM's way of saying "no error if the module is missing")
# /usr/lib/pam.d/sshd includes system-remote-login; I did not follow that file to system-login, but the SSH logins did start the user manager.
```

When `labadmin` logs in over SSH, turnstile starts a user manager:

```text
$ ps -eo user,pid,args | grep "[d]init"
labadmin 679 dinit --user --ready-fd 3 --services-dir /run/turnstiled/1000/srv.679 --services-dir /home/labadmin/.config/dinit.d ...
labadmin 687 dbus-daemon --session --dinit --address=unix:path=/run/user/1000/bus --print-address=4
labadmin 691 /usr/bin/dinit-dbus
labadmin 699 /usr/bin/dinit-monitor -E -c /usr/lib/turnstile/dinit graphical-notify WAYLAND_DISPLAY DISPLAY
$ echo $XDG_RUNTIME_DIR $DBUS_SESSION_BUS_ADDRESS    ->  /run/user/1000   unix:path=/run/user/1000/bus
```

Use `dinitctl --user` (the **default for a non-root user**; `dinitctl --system` as a user gives `connecting to socket: /run/dinitctl: Permission denied`):

```text
$ dinitctl --user list         ->  boot [[ ]<<  (still starting), system, wireplumber, pipewire, dbus, dbus-daemon, login.target, dinit-dbus, pipewire-pulse, graphical.monitor, graphical.target [{ }<<] ...
$ ls /usr/lib/dinit.d/user     ->  boot.d  dbus  dbus-daemon  dinit-dbus  pipewire  pipewire-pulse  wireplumber      (the distribution's user services)
$ cat ~/.config/dinit.d/wl-user      type = process / command = /bin/sleep 7777
$ dinitctl --user start wl-user      ->  Service 'wl-user' started.            (listed in the USER instance; the SYSTEM dinit cannot see it)
$ dinitctl --user enable wl-user     ->  dinitctl: warning: enabling dependency for non-started service / Service 'wl-user' has been enabled.
$ ls -l ~/.config/dinit.d/boot.d     ->  wl-user -> ../wl-user
$ dinitctl --user start wl-ubad      (command = /usr/bin/slepe)   ->  Service 'wl-ubad' failed to start. Reason: execution of service process failed: Stage: executing command   Error: No such file or directory
```

The turnstile dinit backend's configuration (`/etc/turnstile/backend/dinit.conf`) names the places it looks: the user's **`~/.config/dinit.d`** (with `boot.d` there for `enable`), `/etc/dinit.d/user`, `/usr/local/lib/dinit.d/user` and **`/usr/lib/dinit.d/user`**, plus a generated directory in `/run/turnstiled/UID/` holding the user's `boot` and the graphical targets. (My user `boot` stayed `[[ ]<<` starting, and `graphical.target` was `[{ }<<]`; I believe it waits for a graphical session that an SSH login never has, but I did not confirm that. `enable` warned about "a non-started service", and the link was still made.)

### What happens at logout: linger

The question for any user service is **"does it survive my logout?"** A root-run watcher, started inside the session, logged the state at +3, +8 and +18 seconds after the SSH session ended (`dn5-linger.sh`):

```text
no linger file:                                        with /var/lib/turnstiled/linger/labadmin:
+3 s   sleep 7777 procs=0  user dinit=0  run dir=         +3 s   sleep 7778 procs=1  user dinit=1  run dir=1000
+8 s   sleep 7777 procs=0  user dinit=0  run dir=         +8 s   sleep 7778 procs=1  user dinit=1  run dir=1000
+18 s  sleep 7777 procs=0  user dinit=0  run dir=         +18 s  sleep 7778 procs=1  user dinit=1  run dir=1000
```

**Without a linger file the user's services, the user's dinit and `/run/user/UID` were all gone within 3 seconds of the last logout; with a file named for the user in `/var/lib/turnstiled/linger/` everything stayed.** That is the whole mechanism: `turnstiled.conf` has `linger = maybe` by default, whose manual says "the default behavior is to stop them unless a file with the same name as the user exists in `/var/lib/turnstiled/linger`", and "it is not necessary to log in and out when the linger directory is changed". The manual says lingering is disabled when `manage_rundir` is `no`; it is `yes` here.

Two traps found on the way:

- **My first logout test was wrong**: to check the machine after logout I logged in again as the same user, and that login **kept the user manager alive**. Any check that logs in as the user changes the result; use a root-owned watcher started before you log out.
- **`loginctl list-sessions` showed several old sessions in state `closing`** for the same user (from earlier SSH commands) while the user manager was still running. I did not find out why they stayed `closing`; they did not stop the logout test from working once nobody was logged in.

`turnstiled.conf(5)` also says that **root logins are tracked but get no user service manager** unless `root_session = yes` (default `no`): not tested here. Other options worth knowing: `login_timeout` (60 seconds for the initial user services, then the manager is terminated), `rundir_path` (do not change it with elogind), and `export_dbus_address`.

## Where this leaves FenrirOS

FenrirOS is the owner's distribution, "heavily influenced by Chimera". If it uses **dinit and a service set like Chimera's**, the commands in these lessons should carry over; the **file locations, the boot targets, the package that provides the services and the logging setup** may differ, and I know nothing verified about any of them. Compare it against this lesson's boot section (`/usr/lib/dinit.d/boot`, `system`, `login.target`, `network.target`) rather than assuming.

## Common mistakes

- **Starting a daemon with no dependency on a stage**: it races the network or the devices; use `network.target` or `local.target`.
- **Enabling two network managers** (`dhcpcd` and `networkmanager`).
- **Forgetting the log daemon**: no `/var/log/messages` means the failure text has nowhere to go.
- **Testing a user-service logout by logging in as that user again.**
- **Assuming user services survive logout**: they do not without a linger file.
- **`--force` on a stage target** (`network.target`, `local.target`) over SSH.
- **Not testing a boot-time change on a snapshot first**; I did not reboot in these tests.
- **Using `sed -i`, `stat -c` and other GNU habits in your scripts on Chimera.**

## Practice

Use the Chimera lab VM (or any dinit system) with a snapshot.

1. **Boot map.** Draw the chain from `boot` to `local.target` from the files (use `cat`), and mark which services are enabled by `/usr/lib/dinit.d/boot.d` and which by `/etc/dinit.d/boot.d`.
2. **Your service.** Reproduce `wl-app`: write the script and file, `dinit-check`, start, read the log, `kill -9` it, enable it, disable it. Then change `restart` to `no` and `yes` and repeat the kill.
3. **Run as a user.** Add `run-as`, a state directory and `no-new-privs`; show the process owner with `ps`.
4. **Wait for the network.** Add `depends-on: network.target` and `dinitctl stop network.target` to see the refusal. (Do not use `--force` over SSH.)
5. **Logs.** Enable `syslog-ng`; produce an exec failure, an unknown setting and a missing service; find each in `/var/log/messages`.
6. **Playbook.** Break a service in five different ways (see the table); for each, write the first command you run and the line that shows the cause.
7. **Labs.** Solve `chimera-service-wont-start` and `chimera-no-system-log` using only this lesson.
8. **User services.** Log in over SSH, start a user service, enable it, then log out and check it from a root watcher with and without the linger file.
9. **Compare.** Read `networkmanager` and `dhcpcd`; list what each depends on and which stage it runs `before`.
10. **Find the bug.** (a) A service that starts before the network is up. (b) A user service that dies at logout. (c) `dinitctl enable` printing a warning and not returning. (d) A "fix" to a service file with `sed -i` that changed nothing. Explain each.

## Check your understanding

Take the quiz for this lesson (it draws twelve from the bank). After a wrong answer, reread the section named in the review line.
