*Draft for owner review.* `linux.systemd` taught units, services, dependencies and the journal. This lesson covers the rest of the everyday systemd toolbox: **timers** (the replacement for most cron jobs), **transient units** with `systemd-run`, **socket and path activation**, **templates and instances**, **sandboxing** a service, **resource limits**, **`systemd-analyze`** to find mistakes and slow boots, and **user units**. Read `linux.systemd` first: this lesson uses its vocabulary.

**What was tested, and where.** Everything below was run as **root** on **Ubuntu 26.04 LTS in WSL2** with **systemd 259 (259.5-0ubuntu3.4)** (`tests/verification/systemd/sd2.sh` to `sd4.sh`), test units named `wl-*` and removed afterwards. **Also run on two real VMs (added 2026-11-22):** sd2 to sd4 ran again as root on **Ubuntu 24.04.5 (systemd 255)** and **AlmaLinux 9.8 (systemd 252, SELinux enforcing)**, and two new batteries ran there: `sd6a.sh`/`sd6b.sh` (user units and linger across a real logout) and `sd7a.sh`/`sd7b.sh` (a real power-off and boot with `Persistent=` timers, enabled/disabled/masked units and a lingering user service). Results are in the sections they belong to. Differences between the versions that the batteries showed: the OOM-kill message wording (259 "The kernel OOM killer killed some processes in this unit.", 252/255 "A process of this unit has been killed by the OOM killer."), the `systemd-analyze security` rule list (a `CapabilityBoundingSet=~CAP_BPF` row exists on 255 and 259 but not on 252, and 252 lists a `MemoryDenyWriteExecute=` row that the 255 and 259 runs did not show), and on the VMs `MemoryMax=` killed the process at once because **those VMs have no swap** (the WSL result of 286 MB swapped is a swap effect, as taught below). **Not tested:** other Red Hat family or SUSE systems, `RandomizedDelaySec=`, `Accept=no` sockets, the `DynamicUser` state directories, `systemd-analyze security` on real production units, and cgroup behaviour under a real container runtime. WSL2 is a virtual environment (`Virtualization=wsl`, `Chassis: container`), so boot-time numbers from `systemd-analyze` and sandbox-capability results may differ on a real server. Documentation (all pages load; the long ones were read only in part, so behaviour below is from my test output): [systemd.timer](https://www.freedesktop.org/software/systemd/man/latest/systemd.timer.html), [systemd.time](https://www.freedesktop.org/software/systemd/man/latest/systemd.time.html), [systemd.socket](https://www.freedesktop.org/software/systemd/man/latest/systemd.socket.html), [systemd.path](https://www.freedesktop.org/software/systemd/man/latest/systemd.path.html), [systemd.exec](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html), [systemd.resource-control](https://www.freedesktop.org/software/systemd/man/latest/systemd.resource-control.html), [systemd-run](https://www.freedesktop.org/software/systemd/man/latest/systemd-run.html), [systemd-analyze](https://www.freedesktop.org/software/systemd/man/latest/systemd-analyze.html).

## Timers

A **timer unit** starts a **service unit** (same name by default) at a time or after an interval. `wl-tick.timer` activates `wl-tick.service`. A one-shot service and its timer:

```ini
# wl-tick.service
[Unit]
Description=WinLab tick
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'date +%%s.%%N >> /tmp/wl-ticks; echo ran'
```
```ini
# wl-tick.timer
[Unit]
Description=WinLab tick timer
[Timer]
OnActiveSec=1
OnUnitActiveSec=2
AccuracySec=100ms
[Install]
WantedBy=timers.target
```

(`%%s` is a literal `%s` after systemd's `%` handling: the lesson on units explains why.) Start the **timer**, not the service:

```text
$ systemctl start wl-tick.timer ; sleep 7.5 ; (gaps between the recorded times)
  gap 2.1 s    gap 2.1 s    gap 2.0 s        4 runs in 7.5 s
$ systemctl list-timers wl-tick.timer
NEXT                        LEFT LAST                           PASSED UNIT          ACTIVATES
<time>   1s <time> 239ms ago wl-tick.timer wl-tick.service
$ systemctl show wl-tick.timer -p TimersMonotonic,AccuracyUSec,Persistent,Unit
  Unit=wl-tick.service
  TimersMonotonic={ OnUnitActiveUSec=2s ; next_elapse=... }
  TimersMonotonic={ OnActiveUSec=1s ; next_elapse=... }
  AccuracyUSec=100ms
  Persistent=no
```

### Monotonic timers and calendar timers

| Setting | Meaning |
|---|---|
| `OnActiveSec=` | this long after the **timer** was activated |
| `OnBootSec=` | this long after boot |
| `OnStartupSec=` | this long after systemd started |
| `OnUnitActiveSec=` | this long after the **service** last became active (a repeat) |
| `OnUnitInactiveSec=` | this long after the service last became inactive (repeat, with a gap) |
| `OnCalendar=` | at wall-clock times, like cron but more readable |

`OnActiveSec=1` with `OnUnitActiveSec=2` gave runs about 2 seconds apart (2.1, 2.1, 2.0 s). I tested `OnActiveSec`, `OnUnitActiveSec` and `OnCalendar`; the other three rows are from the manual and were not run. For something that runs at set times, use `OnCalendar=`.

### Calendar expressions: test them before you use them

`systemd-analyze calendar` shows how systemd reads an expression and when it fires next (the test ran on **Saturday 2026-11-21 16:3x EST**, so the "next" times below belong to that moment):

```text
$ systemd-analyze calendar "daily" "weekly" "Mon..Fri 09:00" "*-*-* 02:30" "*:0/15" "2026-12-25" "hourly" "*-*-01 00:00:00"
  daily            -> Normalized: *-*-* 00:00:00         Next: Sun 2026-11-22 00:00:00 EST
  weekly           -> Normalized: Mon *-*-* 00:00:00     Next: Mon 2026-11-23 00:00:00 EST
  Mon..Fri 09:00   -> Normalized: Mon..Fri *-*-* 09:00:00   Next: Mon 2026-11-23 09:00:00 EST
  *-*-* 02:30      -> Normalized: *-*-* 02:30:00         Next: Sun 2026-11-22 02:30:00 EST
  *:0/15           -> Normalized: *-*-* *:00/15:00       Next: Sat 2026-11-21 16:30:00 EST
  2026-12-25       -> Normalized: 2026-12-25 00:00:00    Next: Fri 2026-12-25 00:00:00 EST
  hourly           -> Normalized: *-*-* *:00:00          Next: Sat 2026-11-21 17:00:00 EST
  *-*-01 00:00:00  -> Normalized: *-*-01 00:00:00        Next: Tue 2026-12-01 00:00:00 EST
$ systemd-analyze calendar "Mon..Fri 09:00" --iterations=3
  Next: Mon 2026-11-23 09:00:00 EST   Iteration #2: Tue 2026-11-24 09:00:00 EST   Iteration #3: Wed 2026-11-25 09:00:00 EST
$ systemd-analyze calendar "funday"          ->  Failed to parse calendar specification 'funday': Invalid argument
$ systemd-analyze timespan "1h 30min" "2d"   ->  1h 30min = 5400000000 μs ;  2d = 172800000000 μs
```

The format is `DayOfWeek Year-Month-Day Hour:Minute:Second`, with `*` for any, `a..b` for a range, `a,b` for a list and **`/n` for every n** (`*:0/15` = every 15 minutes from minute 0). `daily` and `weekly` are shortcuts for midnight (weekly = **Monday** midnight). **Always run `systemd-analyze calendar` on an expression before shipping a timer**: a typo gives an error here instead of a job that never runs.

### `AccuracySec`, `Persistent` and a test that did not show what I expected

The default **`AccuracySec` is 1 minute** (the manual says so verbatim: "Defaults to 1min"; `systemctl show` printed `AccuracyUSec=1min`): systemd may delay a timer by up to that long to wake the machine less often. In my test I started two timers with `OnActiveSec=2`, one with the default accuracy and one with `AccuracySec=1s`, and **both ran 3.1 seconds after they were started**: I did **not** reproduce a delay on this lightly loaded machine, so do not expect it every time. For exact timing, set `AccuracySec=1s` (or smaller). A calendar timer `OnCalendar=*:*:0/10` fired about **0.94 s after** the scheduled second with both settings.

`Persistent=yes` makes a calendar timer run **once after boot if it missed a run while the machine was off**; it is the usual choice for daily and weekly jobs on laptops. **Tested across a real power-off** (`sd7a.sh`, `sd7b.sh`; Ubuntu 24.04 with systemd 255 and AlmaLinux 9.8 with systemd 252, same result on both): two timers with `OnCalendar` three minutes ahead, one `Persistent=true` and one `Persistent=false`; the VM was powered off with `systemctl poweroff` before that time and started again after it.

```text
(before)   NextElapseUSecRealtime=Sun 2026-11-22 05:14:00 UTC
(after boot at 05:15:10)
  fired-persist 05:15:16                                 <- the file the Persistent=true service appends to
  wl-persist.timer     LastTriggerUSec=Sun 2026-11-22 05:15:16 UTC    Persistent=yes
  wl-nopersist.timer   LastTriggerUSec=                                Persistent=no      <- never ran
  journal: Starting WinLab timer persist... / Finished WinLab timer persist.
```

The missed run happened about **6 seconds into the boot** (05:15:10 up, 05:15:16 run); the `Persistent=false` timer did not run at all and simply waited for its next calendar time. (A caution from my own test: when I repeated it with the same timer names after a clean-up, `LastTriggerUSec` already showed the time from the first run before the timer had fired. systemd keeps the last run time of a `Persistent=` timer in a stamp file under `/var/lib/systemd/timers/` (the directory exists and holds `stamp-*.timer` files on the Ubuntu VM); I did not work out why this one survived my clean-up, so use fresh timer names when you repeat the test.)

### Cron versus timers

A timer gives you what cron does not: the job is a **service** (logging in the journal, dependencies, resource limits, sandboxing, `systemctl status`), `list-timers` shows the next and last run, and `systemctl start wl-tick.service` runs the job by hand exactly as the timer would. The cost is two files instead of one line. Both work; do not mix them for the same job.

## Transient units with `systemd-run`

`systemd-run` creates a **temporary unit** from a command line, with no files to write:

```text
$ systemd-run --unit=wl-trans --collect /bin/sleep 100
  Running as unit: wl-trans.service; invocation ID: 946dcac99aaa4435a46811bdba1e3267
$ systemctl is-active wl-trans   ->  active
$ ls /run/systemd/transient      ->  wl-trans.service            (it lives only in /run/systemd/transient)
$ systemctl stop wl-trans        (with --collect the unit is gone afterwards: ls shows 0 wl- files)
$ systemd-run --on-active=2 --unit=wl-once --property=Type=oneshot /bin/sh -c "echo transient-ran > /tmp/wl-once"
  Running timer as unit: wl-once.timer
  Will run service as unit: wl-once.service
```

(The one-off timer had **not** run when I looked after 3 seconds; with the 2-second delay plus the startup time the real run was at about 3.1 s, as in the timer test above.) Useful options: `--unit=NAME`, `--property=Key=Value` (any unit setting), `--wait` (block until it ends and print the result), `--collect` (remove the unit even if it failed), `--scope` (run the command in a scope: your command stays in the foreground but inside a resource-controlled cgroup), `--on-active=`, `--on-calendar=` (one-off timers). **Transient units are lost at reboot**, which makes `systemd-run` the right tool for a one-time job, a test, or a resource-limited command.

## Socket activation

A **socket unit** listens on an address and starts a service when a client connects. The service need not run until it is needed, and a restart of the service does not drop the connection queue.

```ini
# wl-echo.socket
[Socket]
ListenStream=127.0.0.1:47651
Accept=yes
[Install]
WantedBy=sockets.target
```
```ini
# wl-echo@.service           (note the @: one instance per connection with Accept=yes)
[Service]
ExecStart=-/bin/cat
StandardInput=socket
```

```text
$ systemctl start wl-echo.socket ; systemctl is-active wl-echo.socket ; systemctl list-units "wl-echo@*" --no-legend | wc -l
  active          0                                   (listening, no service instance yet)
$ ss -ltn | grep 47651   ->  LISTEN 127.0.0.1:47651
$ exec 3<>/dev/tcp/127.0.0.1/47651 ; echo hello-socket >&3 ; read -r -t 3 line <&3 ; echo "got: $line"
  got: hello-socket
$ systemctl list-units "wl-echo@*"   ->  wl-echo@<conn>-127.0.0.1:37554.service active running        (one instance for the connection)
$ (after the client closed)          ->  0 instances;    systemctl show wl-echo.socket -p NAccepted,NConnections,Accept   ->  Accept=yes NConnections=0 NAccepted=1
$ systemctl stop wl-echo.socket ; ss -ltn | grep -c 47651    ->  0
```

With **`Accept=yes`** systemd accepts each connection and starts one **instance** of a **template service** (`name@.service`) with the connection as standard input and output: any program that reads stdin and writes stdout becomes a network service (`cat` here is an echo server). With `Accept=no` (not tested) the single service receives the listening socket itself and accepts connections. A real one I saw in the tests is `systemd-journald.socket`, which triggers `systemd-journald.service` (the `TriggeredBy:` lines in `systemctl status`). **Open a port only on the address you mean** (`127.0.0.1:` above); a bare port number listens on all addresses.

## Path units

A **path unit** starts a service when a file or directory changes or appears:

```ini
# wl-watch.path
[Path]
PathExists=/tmp/wl-trigger
[Install]
WantedBy=multi-user.target
```
```ini
# wl-watch.service
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo "triggered at $(date +%%S)" >> /tmp/wl-watch.log; rm -f /tmp/wl-trigger'
```
```text
$ systemctl start wl-watch.path ; systemctl is-active wl-watch.path wl-watch.service       ->  active / inactive
$ touch /tmp/wl-trigger ; sleep 1 ; cat /tmp/wl-watch.log      ->  triggered at <s>        (the trigger file was consumed)
```

The service **removes the trigger file**: with `PathExists=` a service that leaves the file in place would be started again at once. Other conditions are `PathChanged=`, `PathModified=`, `DirectoryNotEmpty=` (not tested). Typical uses: process a spool directory, restart a service when its config file changes.

## Templates and instances

A unit named `NAME@.service` is a **template**; `NAME@alpha.service` is an **instance** with `alpha` as its argument. Inside the file, **specifiers** expand to parts of the name:

```ini
# wl-inst@.service
[Unit]
Description=WinLab instance %i
[Service]
ExecStart=/bin/sh -c 'echo "i=%i n=%n N=%N p=%p H=%H"; sleep 30'
[Install]
WantedBy=multi-user.target
DefaultInstance=main
```
```text
$ systemctl start wl-inst@alpha wl-inst@beta
  i=alpha n=wl-inst@alpha.service N=wl-inst@alpha p=wl-inst H=<host>
  i=beta  n=wl-inst@beta.service  N=wl-inst@beta  p=wl-inst H=<host>
$ systemctl list-units "wl-inst@*"   ->  wl-inst@alpha.service active running   wl-inst@beta.service active running
$ systemctl enable wl-inst@          ->  Created symlink '/etc/systemd/system/multi-user.target.wants/wl-inst@main.service'      (DefaultInstance=main)
```

| Specifier | Meaning (as printed above) |
|---|---|
| `%i` | the instance name (`alpha`) |
| `%n` | the full unit name (`wl-inst@alpha.service`) |
| `%N` | the full name without the suffix |
| `%p` | the prefix (`wl-inst`) |
| `%H` | the host name |
| `%%` | a literal `%` |

Instance names carry **escaped** text; `systemd-escape` converts:

```text
systemd-escape "my dir/with space"          ->  my\x20dir-with\x20space
systemd-escape --path /var/lib/my-app       ->  var-lib-my\x2dapp
systemd-escape -u "var-lib-my\x2dapp"       ->  var/lib/my-app             (-u reverses it)
systemd-escape --template=wl-inst@.service "a/b"   ->  wl-inst@a-b.service
```

Templates are how systemd runs one service per **tty** (`getty@tty1.service` was in the list of running services) and per **connection** (above).

## Sandboxing a service

A service that does not need the whole machine should not get it. systemd can take away file system access, privileges, network and more with unit settings, and score the result. Two oneshot units run the **same** script; the second adds restrictions:

```ini
# wl-closed.service
[Service]
Type=oneshot
DynamicUser=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateNetwork=yes
NoNewPrivileges=yes
CapabilityBoundingSet=
ReadWritePaths=/var/tmp
ExecStart=/bin/sh -c '...prints the user, tries to write /etc, read /root, write /tmp and /var/tmp, lists the network links, prints CapEff...'
```

```text
                          wl-open (no restrictions)        wl-closed (as above)
user                      uid=0 root                        uid=62922 wl-closed       (DynamicUser: a temporary user)
write /etc                yes                               NO   (touch: cannot touch '/etc/wl-test-closed': Read-only file system)
read /root                yes                               NO
write /tmp                yes                               yes  (but into a PRIVATE /tmp)
write /var/tmp            -                                 yes  (ReadWritePaths; also private: the host did not see the file)
network links             eth0 lo                           lo   (only loopback)
CapEff                    000001ffffffffff (all)            0000000000000000 (none)
```

What each setting did:

| Setting | Effect (observed) |
|---|---|
| `DynamicUser=yes` | runs as a **temporary user** with a unique UID (62922 here); the manual says it implies other protections, which I did not test |
| `ProtectSystem=strict` | the **whole file system is read-only** except `/dev`, `/proc`, `/sys` and the paths in `ReadWritePaths=` (`/etc` write failed) |
| `ProtectHome=yes` | `/home`, `/root` and `/run/user` are **inaccessible** (`ls /root` failed) |
| `PrivateTmp=yes` | the service has its **own `/tmp` and `/var/tmp`**: the file it wrote was not visible on the host (`ls /tmp/wl-test-tmp` showed only the file from the open service) |
| `PrivateNetwork=yes` | its own network namespace: only `lo` |
| `NoNewPrivileges=yes` | the service and its children cannot gain privileges (setuid, file capabilities) |
| `CapabilityBoundingSet=` | an **empty** set removes every Linux capability (`CapEff` all zeros) |
| `ReadWritePaths=` | re-opens named paths under `ProtectSystem=` |

`systemd-analyze security` scores a unit's exposure:

```text
$ systemd-analyze security wl-open.service    ->  Overall exposure level for wl-open.service: 9.6 UNSAFE
$ systemd-analyze security wl-closed.service  ->  Overall exposure level for wl-closed.service: 5.2 MEDIUM
  (per-setting lines: ✓ RemoveIPC=  ✓ User=/DynamicUser=  ✓ CapabilityBoundingSet=~CAP_SYS_TIME  ✓ NoNewPrivileges=  ✓ AmbientCapabilities=
   ✗ RootDirectory=/RootImage=  ✗ PrivateDevices=  ✗ ProtectClock=  ✗ ProtectKernelLogs=  ✗ ProtectControlGroups=  ✗ ProtectKernelModules=  ✗ SystemCallArchitectures= ...)
```

The ✗ lines are the **next settings to consider** (`PrivateDevices=yes`, `ProtectKernelModules=yes`, `ProtectControlGroups=yes`, `ProtectClock=yes`, `SystemCallArchitectures=native`...). **Add restrictions one at a time and test the service after each**: any of them can break a service that needs the thing you took away (a log directory, a device, a capability such as binding a port below 1024). The score is a guide, not a goal: 0 is not always reachable, and a web server that needs to write to `/var/www` will always have exposure. This is also the defensive view of the "unknown script" skills: the same settings that confine your service confine an unknown program you run as a unit.

## Resource control

systemd puts every service in a **cgroup** and can limit CPU, memory, tasks and I/O with unit settings. On the test machine: `cat /sys/fs/cgroup/cgroup.controllers` printed `cpuset cpu io memory hugetlb pids rdma` and the file system type was `cgroup2fs` (cgroup v2).

```text
$ systemd-run --wait --collect -p CPUQuota=20% -p RuntimeMaxSec=4 sh -c "while :; do :; done"
  Finished with result: timeout          Service runtime: 4.241s        CPU time consumed: 862ms          (862 ms of 4.241 s = 20 %)
$ systemd-run --scope -p TasksMax=5 bash -c "for i in 1 2 3 4 5 6 7 8; do sleep 3 & done"
  /usr/bin/bash: fork: retry: Resource temporarily unavailable        (the 6th process could not be created)
```

`CPUQuota=20%` held the busy loop to 20 % of one CPU; `RuntimeMaxSec=4` ended it with `Result=timeout`; `TasksMax=5` made `fork` fail.

### The memory limit is not a kill switch by itself

```text
$ free -m   ->  Swap: 2048 0 2048       (swap exists)
$ systemd-run --wait --collect -p MemoryMax=40M  bash -c 'allocate 150 MB'
  Finished with result: success    Service runtime: 18.689s    CPU time consumed: 9.002s    Memory peak: 40M (swap: 286.4M)
$ systemd-run --wait --collect -p MemoryMax=40M -p MemorySwapMax=0  bash -c 'allocate 150 MB'
  Finished with result: oom-kill     Main processes terminated with: code=killed, status=9/KILL     Memory peak: 40M (swap: 0B)
  journal: wl-mem2.service: The kernel OOM killer killed some processes in this unit.  / Failed with result 'oom-kill'.
```

**With swap available, `MemoryMax=40M` did not stop a 150 MB allocation**: the excess went to swap (286 MB swapped, 18.7 s of runtime, 9 s of CPU) and the command finished. With **`MemorySwapMax=0`** the same command was **OOM-killed** (`Result=oom-kill`). The manual describes `MemoryMax=` as "the absolute limit on memory usage" and recommends `MemoryHigh=` as the main control with `MemoryMax=` as "the last line of defense"; the swap interaction above is **my test result, not a documented quotation**, and it depends on this machine's swap. To get a hard memory limit, limit swap too.

### Changing limits on a running unit

```text
$ systemctl set-property wl-prop CPUWeight=50
$ find /etc/systemd/system.control -name "*wl-prop*"   ->  /etc/systemd/system.control/wl-prop.service.d     (persistent: survives reboot)
  [Service]
  CPUWeight=50
$ systemctl set-property --runtime wl-prop CPUWeight=70      ->  CPUWeight=70      the file is in /run/systemd/system.control (lost at reboot)
$ systemctl revert wl-prop                                   ->  Removed ... 50-CPUWeight.conf (both places)         CPUWeight=[not set]
```

For a **transient** unit, `set-property` changed the running value (`MemoryMax=67108864` for `64M`, `33554432` for `32M`) and I saw no file in `/etc/systemd/system.control` for it. `systemctl show UNIT -p MemoryMax,CPUWeight` reads the current values.

## `systemd-analyze`: find mistakes and slow starts

```text
$ systemd-analyze verify wl-typo.service
  /etc/systemd/system/wl-typo.service:2: Unknown key 'Descrption' in section [Unit], ignoring.
  /etc/systemd/system/wl-typo.service:5: Unknown key 'Execstart' in section [Service], ignoring.
  wl-typo.service: Command /usr/bin/slepe is not executable: No such file or directory
```

`verify` catches **misspelled keys** (they are ignored silently otherwise, and key names are case-sensitive), **missing programs** and ordering cycles (previous lesson). Run it on every unit you write. Timing:

```text
$ systemd-analyze blame                  ->  1.098s landscape-client.service   764ms dev-sdb.device   751ms dev-sdd.device   686ms snapd.seeded.service
$ systemd-analyze critical-chain         ->  graphical.target @1.724s / └─multi-user.target @1.724s / └─snapd.seeded.service @635ms +686ms
$ systemd-analyze time                   ->  Startup finished in 1.725s (userspace)
$ systemd-analyze unit-paths             ->  the directories searched for units
```

`blame` lists units by **time taken**; `critical-chain` shows the **chain of units that decided the total**: reading both tells you whether a slow service delays everything (it does only if it is on the critical chain). WSL has no firmware or kernel phase, hence the single "userspace" figure.

## User units

Every user can have their own services, managed by `systemctl --user`, in `~/.config/systemd/user/`:

```text
$ systemctl --user is-system-running         ->  running
$ ls -d /run/user/0                           ->  /run/user/0        (the user manager's runtime directory; XDG_RUNTIME_DIR)
$ cat ~/.config/systemd/user/wl-user.service  ->  [Service] ExecStart=/bin/sleep 1000
$ systemctl --user daemon-reload ; systemctl --user start wl-user ; systemctl --user is-active wl-user   ->  active
$ loginctl show-user root -p Linger          ->  Linger=no
```

A user manager is the service `user@UID.service` (`user@0.service` was in the running list in WSL). **It exists because a login session started it.** On the two VMs, where root had no login session, the same commands failed: `systemctl --user is-system-running` printed `Failed to connect to bus: No medium found` (Ubuntu 24.04), `XDG_RUNTIME_DIR` was unset and `/run/user/0` did not exist. As the normal admin user over SSH (a real login) it works, so run user units as the user who logs in, not as root.

**Logout and linger, tested on a real logind** (Ubuntu 24.04 with systemd 255 and AlmaLinux 9.8 with systemd 252, `sd6a.sh` and `sd6b.sh`, same result on both). The test logs in over SSH as the normal user, enables a user service (`ExecStart=/bin/sleep 3000`), then ends the session while a root-owned watcher (`systemd-run`, so it outlives the login) logs once a second whether the user manager, `/run/user/1000` and the process are still there:

```text
$ systemctl --user enable --now wl-user ; systemctl --user is-active wl-user      ->  active
$ loginctl show-user labadmin -p Linger State RuntimePath   ->  Linger=no  State=active  RuntimePath=/run/user/1000

Linger=no, then the session ends:
  t=10 user-manager=active   rundir=/run/user/1000  sleep=1
  t=11 user-manager=inactive rundir=/run/user/1000  sleep=0        <- the user manager stopped and took the service with it
  t=12 user-manager=inactive rundir=gone            sleep=0
  ...t=25 user-manager=inactive rundir=gone sleep=0

$ sudo loginctl enable-linger labadmin ; loginctl show-user labadmin -p Linger   ->  Linger=yes
  (the file /var/lib/systemd/linger/labadmin exists)
Linger=yes, then the session ends:
  t=1 ... t=25  user-manager=active  rundir=/run/user/1000  sleep=1        <- still running 25 seconds after the logout
```

(The watcher starts a few seconds before the session closes, so "t=11" is not "11 seconds after logout"; the point is that it ended within the watch window without linger and never ended with linger.) **With linger the user manager also starts at boot, before anyone logs in:** after a real power-off and boot (`sd7a.sh`, `sd7b.sh`, same on both VMs) `user@1000.service` had `ActiveEnterTimestamp=05:15:19`, the SSH login session started at `05:15:23`, and the enabled `wl-user` service was already `active`. For an ordinary user's services that must survive logout or run at boot, `loginctl enable-linger USER` is the tested answer on systemd. The `systemctl --user` commands are the same on a desktop or SSH login; when you use `su` or `sudo` instead of a real login, set `XDG_RUNTIME_DIR` yourself (I did not test that on the VMs).

## Misc status

```text
systemctl is-system-running      ->  running | degraded (a unit failed) | starting | stopping | ... 
systemctl list-jobs              ->  No jobs running.
systemctl show --property=Version,Architecture,Virtualization,SystemState  ->  Version=259.5-0ubuntu3.4  Architecture=x86-64  Virtualization=wsl  SystemState=degraded
hostnamectl / timedatectl        ->  host name, chassis, machine id / local, UTC and RTC time
```

## Common mistakes

- **Starting the `.service` of a timer** and expecting a schedule: start the `.timer`.
- **A `OnCalendar=` never checked**: run `systemd-analyze calendar` first.
- **Assuming a timer fires exactly on time**: check `AccuracySec=`.
- **A path unit whose service does not clear the trigger**: it re-runs forever.
- **Socket listening on all addresses** when only loopback was meant.
- **Writing a unit key in the wrong case** (`Execstart`): ignored silently; use `systemd-analyze verify`.
- **Adding sandbox options all at once** and not knowing which one broke the service.
- **`MemoryMax=` on a machine with swap and no `MemorySwapMax=`** (not a hard limit).
- **Forgetting a transient unit is gone after reboot**, and forgetting `--collect` leaves failed transient units around.
- **User services that die at logout** (no linger).

## Practice

Run these in a scratch VM or lab. Name units `wl-…` and remove them afterwards.

1. **A timer.** Make a oneshot service that appends a time stamp to a file and a timer that fires every 5 seconds; show 5 runs and the gaps. Then change `AccuracySec` and compare.
2. **Calendar expressions.** Use `systemd-analyze calendar` to write timers for: every weekday at 08:30, the first Monday of each month, every 15 minutes, 1 January each year. Show the next three times for each.
3. **Replace a cron job.** Take a cron line you know and rewrite it as service plus timer; list it with `list-timers`; run the service by hand.
4. **Transient.** Run a command with `systemd-run --wait --collect` and read its result and CPU time; run another with `--on-active=5`; show that both disappear.
5. **Socket echo.** Reproduce the echo socket; connect two clients at the same time and count instances.
6. **Path trigger.** Make a service that processes files dropped in a directory (`DirectoryNotEmpty=`) and deletes them when done.
7. **Templates.** Write a template that prints its instance name; start three instances; enable a default instance.
8. **Sandbox.** Take a service you can start, run `systemd-analyze security` on it, add three restrictions one at a time, testing each, and record the score after each.
9. **Resource limits.** Reproduce the CPU quota (check the CPU time against the runtime), the task limit, and the memory limit with and without `MemorySwapMax=0`. What happens on your machine?
10. **Verify.** Make a unit with three mistakes (a wrong key case, a missing program, an ordering cycle) and find all three with `systemd-analyze verify`.
11. **Boot analysis.** On a VM, run `blame` and `critical-chain` and say which unit, if removed, would shorten the boot, and which would not.
12. **Find the bug.** (a) a timer with `OnCalendar=Mon-Fri 9:00` (check the expression with `systemd-analyze calendar` and compare it with `Mon..Fri 09:00`) (b) a socket `ListenStream=8080` meant for localhost only (c) a path unit that starts a service that does not remove its trigger file (d) a service with `MemoryMax=100M` that was expected to be killed on a swap-enabled machine. Say what goes wrong and fix each.

## Check your understanding

Take the quiz for this lesson (it draws ten from the bank). After a wrong answer, reread the section named in the review line.
