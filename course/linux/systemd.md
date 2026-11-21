*Draft for owner review.* **systemd** is the service manager (PID 1) on nearly every major Linux distribution: Debian, Ubuntu, the Red Hat family including AlmaLinux, SUSE, Arch. It starts the system, keeps services running, logs what they say, and gives you one tool (`systemctl`) to control them and another (`journalctl`) to read the logs. This lesson teaches units and services, how to write and break and fix one, dependencies and targets, overrides, and the journal. The next lesson (`linux.systemd-advanced`) covers timers, sockets, sandboxing, resource limits and analysis. (This course's lessons on other init systems, such as `dinit` on Chimera, come after this one.)

**What was tested, and where.** Everything below was run as **root** on **Ubuntu 26.04 LTS in WSL2** with **systemd 259 (259.5-0ubuntu3.4)** as PID 1, kernel 6.18 (`tests/verification/systemd/sd1.sh` to `sd5.sh`). Test units are named `wl-*` and were removed afterwards. Output is real; times, process IDs and host names are replaced with `<time>`, `<pid>` and `<host>` where they would only distract. **Not tested:** AlmaLinux or any Red Hat family system (where SELinux can change behaviour), other systemd versions, a real boot, the boot targets themselves (`isolate`, `rescue`, `emergency`: I read their properties but did not switch to them), `BindsTo=`, `systemctl edit` in an interactive editor, and anything that needs a physical machine. WSL has no real boot loader and no real hardware, so `systemd-analyze blame` numbers and the "degraded" state in WSL are not representative of a server. Documentation: the freedesktop.org man pages ([systemd.unit](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html), [systemd.service](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html), [systemd.exec](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html), [systemd.special](https://www.freedesktop.org/software/systemd/man/latest/systemd.special.html), [systemctl](https://www.freedesktop.org/software/systemd/man/latest/systemctl.html), [journalctl](https://www.freedesktop.org/software/systemd/man/latest/journalctl.html), [journald.conf](https://www.freedesktop.org/software/systemd/man/latest/journald.conf.html), [systemd.kill](https://www.freedesktop.org/software/systemd/man/latest/systemd.kill.html)). All of these pages load (checked 2026-11-21); the long pages were read only in part, so **every behaviour claim below rests on my test output**, with a doc quote only where I say so.

## Units

systemd manages **units**. Each unit is described by a file, and its type is the file's extension:

| Type | What it is | This lesson |
|---|---|---|
| `.service` | a process or group of processes | yes |
| `.target` | a named group of units (a "state" of the system) | yes |
| `.timer`, `.socket`, `.path` | start a service on a time, a connection, a file | next lesson |
| `.mount`, `.automount`, `.swap` | file systems and swap | not covered |
| `.slice`, `.scope` | resource-control groups (cgroups) | next lesson, briefly |
| `.device` | kernel devices known to systemd | not covered |

Unit files are looked for in this order (real output of `systemctl show -p UnitPath`, shortened to the directories that matter):

```text
/etc/systemd/system.control      (changes made with systemctl set-property)
/run/systemd/transient          (units made with systemd-run)
/etc/systemd/system             (YOURS: the administrator's units and overrides)
/run/systemd/system             (runtime units, lost at reboot)
/usr/local/lib/systemd/system
/usr/lib/systemd/system         (the PACKAGES': never edit these)
```

Rule: **packages put units in `/usr/lib/systemd/system`; you put your own, and your overrides, in `/etc/systemd/system`.** A unit with the same name in `/etc` wins over the one from the package.

## Looking at a unit

```text
$ systemctl status systemd-journald --no-pager -n0
● systemd-journald.service - Journal Service
     Loaded: loaded (/usr/lib/systemd/system/systemd-journald.service; static)
    Drop-In: /usr/lib/systemd/system/systemd-journald.service.d
             └─nice.conf
     Active: active (running) since Sat 2026-11-21 16:27:16 EST; 2s ago
 Invocation: a7f96f96203a4ca7a796c31000dd393f
TriggeredBy: ● systemd-journald-dev-log.socket
             ○ systemd-journald-audit.socket
             ● systemd-journald.socket
       Docs: man:systemd-journald.service(8)
             man:journald.conf(5)
   Main PID: 48 (systemd-journal)
     Status: "Processing requests..."
      Tasks: 1 (limit: 9167)
```

How to read it: **`Loaded:`** says which file, whether it is enabled (here `static`, explained below); **`Drop-In:`** lists override files; **`Active:`** is the state (`active (running)`, `inactive (dead)`, `failed`); **`Main PID`**, **`Tasks`**, and at the bottom the last log lines. `●` green means active, `○` inactive, `×` failed.

For scripts, use the exact commands and their **exit statuses** instead of parsing `status`:

```text
systemctl is-active systemd-journald     -> active          rc=0
systemctl is-active no-such-unit         -> inactive        rc=4  (a unit that does not exist is rc 4)
systemctl is-enabled systemd-journald    -> static
systemctl is-failed systemd-journald     -> active          rc=1  (is-failed succeeds only when the unit HAS failed)
systemctl show systemd-journald -p Id,ActiveState,SubState,UnitFileState,FragmentPath,Type,MainPID
   -> Id=systemd-journald.service  ActiveState=active  SubState=running  FragmentPath=/usr/lib/systemd/system/systemd-journald.service
      UnitFileState=static  Type=notify-reload  MainPID=<pid>
systemctl cat systemd-journald           -> prints the unit file(s) with their paths, drop-ins included
systemctl get-default                    -> graphical.target
systemctl list-units --type=service --state=running --no-legend    -> chrony.service cron.service dbus.service ... (15 on this machine)
systemctl list-units --failed --no-legend                           -> (nothing: no failed units)
systemctl list-dependencies multi-user.target                       -> the tree of what multi-user pulls in
```

`systemctl show` prints **properties** (`-p Name` for one, `--value` for the value only) and is the right tool for scripts. `systemctl cat` shows the file **as systemd would read it**.

## The install states: enabled, disabled, static, masked

A unit's **file state** (what `systemctl list-unit-files` shows) on this machine:

```text
227 static    51 enabled    37 disabled    12 alias    6 masked    4 generated    3 masked-runtime    1 transient    1 enabled-runtime
```

(the numbers belong to this machine; the **kinds** are the lesson.) Meaning:

- **`enabled`**: a symlink makes it start at boot (or when its target is reached).
- **`disabled`**: it has an `[Install]` section but no symlink: it does not start at boot, but you can start it by hand.
- **`static`**: no `[Install]` section. It cannot be enabled; it runs only when something else (a dependency, a socket, a timer) pulls it in, or you start it by hand.
- **`masked`**: linked to `/dev/null`: it **cannot be started at all**, not even by dependency.
- `alias`, `generated`, `transient`, `*-runtime`: names, units made by generators, units made by `systemd-run`, and runtime-only versions.

### Start is not enable

```text
$ systemctl start wl-hello       (starts it now; gone after a reboot)
$ systemctl enable wl-hello
  Created symlink '/etc/systemd/system/multi-user.target.wants/wl-hello.service' → '/etc/systemd/system/wl-hello.service'.
$ systemctl is-enabled wl-hello  -> enabled        $ systemctl is-active wl-hello  -> inactive   (enable did NOT start it)
$ systemctl enable --now wl-hello                  (both at once)       $ systemctl is-active wl-hello  -> active
$ systemctl disable --now wl-hello
  Removed '/etc/systemd/system/multi-user.target.wants/wl-hello.service'.
```

**`enable` = make a symlink in a `.wants` directory (taking effect at boot); `start` = run it now.** `enable --now` and `disable --now` do both. This is the same distinction as a service that "works now but is gone after a reboot", which is a common troubleshooting scenario.

### Masking

```text
$ systemctl mask wl-vendor            (a unit shipped in /usr/lib/systemd/system)
  Created symlink '/etc/systemd/system/wl-vendor.service' → '/dev/null'.
$ systemctl is-enabled wl-vendor      -> masked     rc=1
$ systemctl start wl-vendor           -> Failed to start wl-vendor.service: Unit wl-vendor.service is masked.
$ systemctl enable wl-vendor          -> Failed to enable unit: Unit /etc/systemd/system/wl-vendor.service is masked
$ systemctl status wl-vendor          ->  Loaded: masked (Reason: Unit wl-vendor.service is masked.)    Active: inactive (dead)
$ systemctl unmask wl-vendor          -> Removed '/etc/systemd/system/wl-vendor.service'.
$ systemctl mask --runtime wl-vendor  -> Created symlink '/run/systemd/system/wl-vendor.service' → '/dev/null'.     is-enabled: masked-runtime
```

`--runtime` puts the link in `/run`, so the mask is **lost at reboot**. And a limit worth knowing: **`mask` fails on a unit whose file is itself in `/etc/systemd/system`**:

```text
$ systemctl mask wl-hello            (the unit file I wrote in /etc/systemd/system)
  Failed to mask unit: File '/etc/systemd/system/wl-hello.service' already exists
```

(there is nothing to link over: the file is yours; delete or `disable` it instead.) Use **mask** when you must make sure a packaged service never starts, including as a dependency of something else (the common case: stop a unit that a package keeps enabling).

## Writing a service

Create `/etc/systemd/system/wl-hello.service`:

```ini
[Unit]
Description=WinLab hello ticker

[Service]
ExecStart=/bin/sh -c 'while :; do echo tick; sleep 1; done'

[Install]
WantedBy=multi-user.target
```

and start it. (After **creating or editing** a unit file, run `systemctl daemon-reload`: below, what happens when you forget.)

```text
$ systemctl start wl-hello
$ systemctl status wl-hello
● wl-hello.service - WinLab hello ticker
     Loaded: loaded (/etc/systemd/system/wl-hello.service; disabled; preset: enabled)
     Active: active (running) since <time>; 2s ago
   Main PID: <pid> (sh)
      Tasks: <n>
     CGroup: /system.slice/wl-hello.service
             ├─<pid> /bin/sh -c "while :; do echo tick; sleep 1; done"
             └─<pid> sleep 1
Nov 21 16:27:19 <host> sh[510]: tick
Nov 21 16:27:20 <host> sh[510]: tick
$ journalctl -u wl-hello --no-pager -o cat -n 3     -> tick / tick / tick
$ systemctl stop wl-hello ; systemctl is-active wl-hello    -> inactive   rc=3
```

The three sections: **`[Unit]`** (description, dependencies, conditions), **`[Service]`** (what to run and how), **`[Install]`** (what `enable` does: `WantedBy=multi-user.target` means "link me into that target's `.wants`"). The service's **standard output and error go to the journal** automatically. `CGroup:` shows **every process of the service**, which is how systemd can stop all of them.

### What `ExecStart` is, and is not

`ExecStart=` runs a program, **not a shell**. Tested, with `Environment=NAME=world` and an `EnvironmentFile` that sets `FROMFILE=file-value` and `QUOTED="two words"`:

```text
ExecStart=/bin/echo hello $NAME ${NAME} "$NAME" $FROMFILE [$QUOTED] | wc -l ; /bin/echo second [$HOME] 100%%
ExecStart=/bin/sh -c 'echo via-shell $NAME $FROMFILE "[$QUOTED]" $(echo sub)'
   -> hello world world world file-value [$QUOTED] | wc -l
      second [$HOME] 100%
      via-shell world file-value [two words] sub
```

- **No pipes, redirects or `&&`**: `| wc -l` was passed to `echo` as three more arguments. Use `/bin/sh -c '...'` (or a script) when you need a shell.
- The program must be an **absolute path** (`/bin/echo`).
- `;` as its own word **separates commands** (allowed here because the unit is `Type=oneshot`).
- **`$NAME` and `${NAME}` are substituted, but a bare `$NAME` only when it is a word by itself**: `[$QUOTED]` stayed literal (not expanded) while `${NAME}` inside a word does work. `$HOME` is **not set** for services unless you set it (and when it was a word by itself, systemd logged `Referenced but unset environment variable evaluates to an empty string: HOME`).
- **`%` and `$` are special**: `%%` gives a literal `%` (`100%%` printed `100%`; `%h` would be the user's home), and **`$$` gives a literal `$`**:

```text
ExecStart=/bin/sh -c 'echo "shell pid is $$"'   ->  shell pid is $            (systemd turned $$ into a single $ before the shell ever saw it)
```

So a shell trick that uses `$$` (the shell's own PID) at a terminal does **not** work the same way inside a unit file: I did not test how to pass a literal `$$` through, and it is usually simpler to put the logic in a script file. (This bit me in my own tests: a unit meant to run `kill -9 $$` ran `kill -9 $` and just exited with status 1, which made my first restart table wrong until I found it.)

- **`EnvironmentFile=`** reads `NAME=value` lines (quotes work); a leading **`-`** (`EnvironmentFile=-/path`) means "not an error if the file is missing". `Environment=` sets variables inline. Neither is a shell: no `export`, no `$(...)`.

## Why a service fails: reading the evidence

### Type=simple says "started" even when it cannot start

Take a unit whose program does not exist:

```ini
[Service]
ExecStart=/usr/bin/slepe 1000        # typo for sleep
```

```text
$ systemctl start wl-bad
(no output, rc=0)                                          <-- it reports SUCCESS
$ systemctl is-active wl-bad     (a moment later)  ->  failed
$ systemctl show wl-bad -p Result,ExecMainStatus,ExecMainCode,ActiveState,SubState
  ActiveState=failed  SubState=failed  Result=exit-code  ExecMainCode=1  ExecMainStatus=203
$ journalctl -u wl-bad --no-pager -o cat
  Started wl-bad.service - WinLab broken service.
  wl-bad.service: Unable to locate executable '/usr/bin/slepe': No such file or directory
  wl-bad.service: Failed at step EXEC spawning /usr/bin/slepe: No such file or directory
  wl-bad.service: Main process exited, code=exited, status=203/EXEC
  wl-bad.service: Failed with result 'exit-code'.
$ systemctl list-units --failed --no-legend  ->  ● wl-bad.service loaded failed failed WinLab broken service
```

**`Type=simple` (the default) returns success as soon as the process is forked**, before it has been executed; the manual says so ("will report success even if the service's binary cannot be invoked successfully"). **`Type=exec`** waits for the `exec` and fails right away:

```text
Type=simple:  systemctl start wl-simple-bad   -> start rc=0   then (0.3 s later) is-active: failed
Type=exec:    systemctl start wl-exec-bad     -> Job for wl-exec-bad.service failed because the control process exited with error code.
                                                 See "systemctl status wl-exec-bad.service" and "journalctl -xeu wl-exec-bad.service" for details.   rc=1
```

**Status `203/EXEC` means "systemd could not execute the program"** (wrong path, no execute permission, wrong interpreter line). Read **`Failed at step EXEC`** in the journal, never trust the exit status of `start` alone for a `Type=simple` service, and always check `is-active` afterwards.

### Edits are not applied until you reload

I fixed the typo in the file and started again **without** `daemon-reload`:

```text
$ systemctl start wl-bad
Warning: The unit file, source configuration file or drop-ins of wl-bad.service changed on disk. Run 'systemctl daemon-reload' to reload units.
$ systemctl daemon-reload ; systemctl start wl-bad ; systemctl is-active wl-bad     ->  active
```

(`systemctl cat` also warns when its output is outdated, and a restart before the reload kept the **old** environment value, as the drop-in section shows.) **Always `systemctl daemon-reload` after creating, editing or deleting a unit file or a drop-in.**

### Other failures worth recognising

```text
ExecStartPre=/bin/false  +  ExecStart=/bin/sleep 100:
   systemctl start wl-pre -> Job for wl-pre.service failed because the control process exited with error code.   rc=1   Result=exit-code  ActiveState=failed
exit 3 with the default (only 0 is success):
   systemctl start wl-exit3b -> Job ... failed because the control process exited with error code.   rc=1
exit 3 with SuccessExitStatus=3:    systemctl start wl-exit3 -> rc=0
```

`ExecStartPre=` runs before the main command and **a failure stops the start**; `SuccessExitStatus=` lists extra exit codes that count as success.

### `degraded` and `reset-failed`

`systemctl is-system-running` printed **`degraded`** (rc 1) while two of my test units were in the failed state, and **stayed `degraded`** after I cleared one of them: it means **at least one unit is failed**, and it reports `running` again only when none is.

```text
$ systemctl list-units --failed --no-legend  ->  wl-pre.service  loaded failed failed ...   wl-stubborn.service ...
$ systemctl reset-failed wl-pre              (clears the failed state and the restart counter of that unit)
```

## Keeping a service running: `Restart=`

```ini
[Unit]
StartLimitIntervalSec=10
StartLimitBurst=3
[Service]
ExecStart=/bin/sh -c 'echo started; exit 1'
Restart=on-failure
RestartSec=200ms
```

A service that exits at once, restarted each time:

```text
$ systemctl start wl-flaky ; sleep 2 ; systemctl show wl-flaky -p Result,NRestarts,ActiveState,SubState
  ActiveState=failed  SubState=failed  Result=exit-code  NRestarts=3
$ journalctl -u wl-flaky -o cat | sort | uniq -c | sort -rn
      4 wl-flaky.service: Failed with result 'exit-code'.
      3 wl-flaky.service: Main process exited, code=exited, status=1/FAILURE
      3 started
      3 Started wl-flaky.service - WinLab flaky service.
      1 wl-flaky.service: Start request repeated too quickly.
      1 wl-flaky.service: Scheduled restart job, restart counter is at 3.
$ systemctl start wl-flaky                         (again, at once)
  Job for wl-flaky.service failed because the control process exited with error code.   rc=1
$ systemctl reset-failed wl-flaky ; systemctl show wl-flaky -p Result,NRestarts,ActiveState  ->  inactive  success  NRestarts=0
```

**The start limit**: more than `StartLimitBurst` starts within `StartLimitIntervalSec` and systemd **gives up** (`Start request repeated too quickly`), leaving the unit `failed` until you `reset-failed`. (I did not see `Result=start-limit-hit` in this version; the result stayed `exit-code`.) That is the answer to "my service keeps dying and then stays dead".

### Which exits restart, for each `Restart=` value

I ran a service that ends each way (`exit 0`, `exit 1`, and killed by TERM, KILL, ABRT) with each policy and counted restarts after 4 seconds (`sd5.sh`):

| `Restart=` | exit 0 | exit 1 | SIGTERM | SIGKILL | SIGABRT |
|---|---|---|---|---|---|
| `no` (default) | stays down | stays down | stays down | stays down | stays down |
| `on-success` | **restarts** | stays down | **restarts** | stays down | stays down |
| `on-failure` | stays down | **restarts** | stays down | **restarts** | **restarts** |
| `on-abnormal` | stays down | stays down | stays down | **restarts** | **restarts** |
| `on-abort` | stays down | stays down | stays down | **restarts** | **restarts** |
| `always` | **restarts** | **restarts** | **restarts** | **restarts** | **restarts** |

The surprise is the **SIGTERM column**: a service that dies of SIGTERM is recorded as `Result=success` (SIGTERM is a "clean" signal, with SIGHUP, SIGINT and SIGPIPE: that list is from the man page summary, and my SIGTERM result agrees), so **`on-failure` does not restart it** but `on-success` does. The recorded result for each ending with `Restart=no`:

```text
exit0 Result=success   exit1 Result=exit-code ExecMainStatus=1   term Result=success   kill Result=signal ExecMainStatus=9   abrt Result=signal ExecMainStatus=6
```

(A cell says "restarts" when `NRestarts` reached 2 or more within the 4 seconds; `StartLimitIntervalSec=0` turned the start limit off for this test.) `Restart=on-failure` is the usual choice for a daemon, and `always` is for services that must never stay down. I did not test what each policy does when you run `systemctl stop` yourself, so check that before relying on it.

## Service types

| `Type=` | When `start` returns | Tested |
|---|---|---|
| `simple` (default) | at once, once the process is forked | `start` took 0.033 s |
| `exec` | after the program has been executed | fails with rc 1 when it cannot be |
| `forking` | when the started process exits (the daemon forked itself); use `PIDFile=` | main PID found from the PID file |
| `oneshot` | **when the command ends**; with `RemainAfterExit=yes` it stays "active (exited)" | `start` took 1.07 s for a 1-second command; `SubState=exited`; without `RemainAfterExit` the state returned to `inactive`/`dead` |
| `notify` | when the service sends `READY=1` (here `systemd-notify --ready` after 2 s) | `start` took 2.0 s; `SubState=running` |

For a modern daemon that says it is ready (`sd_notify`), `Type=notify` gives the correct "started" moment to dependent units. For a script that runs and finishes (a backup, a cleanup), **`Type=oneshot`**.

## Overrides: change a unit without editing the package's file

The package's file is in `/usr/lib/systemd/system`; changes in a **drop-in** survive package updates. A drop-in is a file `NAME.service.d/anything.conf` in `/etc/systemd/system`:

```text
$ mkdir -p /etc/systemd/system/wl-app.service.d
$ cat > /etc/systemd/system/wl-app.service.d/override.conf
[Service]
Environment=GREETING=hola
$ systemctl restart wl-app          (without daemon-reload)
  Warning: The unit file, source configuration file or drop-ins of wl-app.service changed on disk. Run 'systemctl daemon-reload' to reload units.
  (journal: greeting=hello )       <-- the OLD value
```

After `daemon-reload` it takes effect. **`systemctl edit`** does all this for you (creates the drop-in, runs the reload) but **opens an editor, and refuses without a terminal**:

```text
$ systemctl edit wl-app         (from a script)    ->  Cannot edit units interactively if not on a tty.
$ printf '[Service]\nEnvironment=GREETING=hola\n' | systemctl edit --stdin wl-app
  Successfully installed edited file '/etc/systemd/system/wl-app.service.d/override.conf'.
$ printf '[Service]\nEnvironment=GREETING=bonjour\n' | systemctl edit --stdin --drop-in=fr.conf wl-app
  Successfully installed edited file '/etc/systemd/system/wl-app.service.d/fr.conf'.
$ systemctl cat wl-app           (the original, then each drop-in; the last value wins)
$ systemctl revert wl-app        (deletes every drop-in and any /etc copy)
  Removed '/etc/systemd/system/wl-app.service.d/fr.conf'.   Removed '/etc/systemd/system/wl-app.service.d/override.conf'.   Removed '/etc/systemd/system/wl-app.service.d'.
```

(`edit --stdin` ran the reload for me and the next start printed `greeting=hola`.) `systemd-delta --type=extended,overridden` lists every unit that has overrides on the machine: `[EXTENDED]  /etc/systemd/system/wl-app.service → /etc/systemd/system/wl-app.service.d/override.conf`.

### Lists must be emptied first

`ExecStart=` is a **list**. A drop-in that just adds `ExecStart=` for a normal service adds a second command, which is **not allowed**:

```text
override.conf:   [Service]
                 ExecStart=/bin/sh -c 'echo "second"; sleep 30'
$ systemctl restart wl-app    ->  Failed to restart wl-app.service: Unit wl-app.service has a bad unit file setting.
```

Reset the list with an empty assignment first, then give the new command:

```text
[Service]
ExecStart=
ExecStart=/bin/sh -c 'echo "replaced"; sleep 30'          ->  journal: replaced
```

The same empty-assignment rule applies to every list-style key (`ExecStartPre=`, `Environment=`, `Wants=`, `After=`...): **an empty line clears what came before.**

## Dependencies and ordering

Two separate ideas, and the most common source of confusion:

- **Requirement** (`Requires=`, `Wants=`, `BindsTo=`, `PartOf=`, `Conflicts=`): *which units are pulled in or stopped together*.
- **Ordering** (`After=`, `Before=`): *which one is started first*.

They are **independent**: you normally need both. With `wl-db` and four units that depend on it (all tested):

| Unit has | Start the unit | Stop wl-db |
|---|---|---|
| `Requires=wl-db` + `After=wl-db` | wl-db is started too (db first) | the dependent **is stopped too** |
| `Wants=wl-db` + `After=wl-db` | wl-db is started too | the dependent **keeps running** |
| `Requires=wl-db` **without** `After=` | wl-db is started too, **at the same time** (no ordering) | (same as Requires) |

```text
Requires:  systemctl start wl-req  ->  wl-db=active wl-req=active
           systemctl stop wl-db    ->  wl-db=inactive wl-req=inactive
Wants:     systemctl start wl-wants; systemctl stop wl-db   ->  wl-db=inactive wl-wants=active
```

**A failing dependency:**

```text
Requires=wl-dbbad (its ExecStart does not exist, Type=exec):
   systemctl start wl-needbad  ->  A dependency job for wl-needbad.service failed. See 'journalctl -xe' for details.   rc=1    is-active: inactive
   journalctl: Dependency failed for wl-needbad.service. / wl-needbad.service: Job wl-needbad.service/start failed with result 'dependency'.
Wants=wl-dbbad:  systemctl start wl-wantbad  ->  rc=0   is-active: active       (a Wants dependency that fails does not stop it)
```

**`Requires=` = "I cannot run without it"; `Wants=` = "start it if you can".** Most units should use **`Wants=`** and **`After=`** and keep `Requires=` for true hard dependencies.

Other relationships:

```text
Conflicts:  wl-ca and wl-cb each Conflicts= the other.  systemctl start wl-ca; systemctl start wl-cb   ->  wl-ca=inactive wl-cb=active   (starting one stops the other)
PartOf:     wl-part has PartOf=wl-parent.  systemctl restart wl-parent   ->  the part was restarted too (it got a new PID)
```

(`BindsTo=` is `Requires=` plus "stop me if it disappears unexpectedly": I did not test it.) See the whole tree with `systemctl list-dependencies UNIT` (add `--reverse` for "what depends on this"; with nothing active depending on `wl-db` it listed just the unit).

### Ordering cycles

```text
$ systemd-analyze verify wl-cyc1.service
  wl-cyc1.service: Found ordering cycle: wl-cyc2.service/start after wl-cyc1.service/start - after wl-cyc2.service
  wl-cyc1.service: Job wl-cyc2.service/start deleted to break ordering cycle starting with wl-cyc1.service/start
```

Two units that are each `After=` the other cannot both be ordered: systemd **drops a job to break the loop**, so something silently does not start. `systemd-analyze verify UNIT` finds this (and typos, next lesson).

### Conditions and assertions

```text
ConditionPathExists=/tmp/wl-flagfile (file missing):
   systemctl start wl-cond  ->  rc=0, is-active: inactive,  Active: inactive (dead)
   journal: wl-cond.service skipped, unmet condition check ConditionPathExists=/tmp/wl-flagfile
AssertPathExists=/tmp/wl-flagfile (file missing):
   systemctl start wl-assert ->  Assertion failed on job for wl-assert.service.   rc=1
(after touch /tmp/wl-flagfile: systemctl start wl-cond -> rc=0, active)
```

A failed **Condition** quietly *skips* the unit (success, no run); a failed **Assert** is an error. "The service is installed and enabled but does not run, and nothing failed" often means an unmet `Condition…=`: read the journal for `skipped, unmet condition`.

### `OnFailure=` and `OnSuccess=`

```text
wl-watched: OnFailure=wl-handler.service, ExecStart=/bin/false
   -> /tmp/wl-handler.log: handler ran for wl-watched.service result=exit-code      (the handler saw $MONITOR_UNIT and $MONITOR_SERVICE_RESULT)
wl-succ: OnSuccess=wl-handler.service, ExecStart=/bin/true
   -> the handler ran (in my test its MONITOR_* variables were empty)
```

## Targets

A **target** is a unit with no process: a named *point* that groups other units. `multi-user.target` ("a normal text-mode system"), `graphical.target`, `network-online.target`, `sysinit.target`, `rescue.target`, `emergency.target`. The default target is a symlink:

```text
$ systemctl get-default                                  ->  graphical.target
$ ls -l /usr/lib/systemd/system/default.target           ->  default.target -> graphical.target
$ systemctl show -p Requires multi-user.target           ->  Requires=basic.target
$ systemctl show -p Wants multi-user.target              ->  Wants=systemd-user-sessions.service dmesg.service wsl-pro.service ... (everything WantedBy=multi-user.target)
$ systemctl show -p AllowIsolate,Requires,Conflicts rescue.target emergency.target
     rescue.target:    Requires=sysinit.target rescue.service   Conflicts=shutdown.target   AllowIsolate=yes
     emergency.target: Requires=emergency.service               Conflicts=shutdown.target   AllowIsolate=yes
```

`WantedBy=multi-user.target` in a service's `[Install]` is what makes `enable` link it into the target's `.wants` directory. You can write your own target to start a group at once:

```text
wl-grp.target:   [Unit] Wants=wl-db.service wl-wants.service
$ systemctl start wl-grp.target   ->  wl-db=active wl-wants=active wl-grp.target=active
$ systemctl stop wl-grp.target    ->  wl-db=active wl-wants=active wl-grp.target=inactive      (stopping the target does NOT stop what it Wants)
```

`systemctl isolate NAME.target` switches to a target and stops what does not belong to it; `systemctl set-default NAME.target` changes the default; booting into `rescue` or `emergency` is how you repair a broken machine. **I did not run any of these (they would change the running system)**; the properties above are what the tests showed.

## Stopping and killing

When you `stop` a service, systemd sends **SIGTERM** to its processes and, if they are still running after `TimeoutStopSec`, **SIGKILL**:

```text
wl-stubborn: a script with  trap '' TERM  and a loop;  TimeoutStopSec=3
$ systemctl stop wl-stubborn    ->  stop took 3.1 s
  Stopping wl-stubborn.service...
  wl-stubborn.service: State 'stop-sigterm' timed out. Killing.
  wl-stubborn.service: Killing process 539 (wl-stubborn.sh) with signal SIGKILL.
  wl-stubborn.service: Killing process 550 (sleep) with signal SIGKILL.
  wl-stubborn.service: Main process exited, code=killed, status=9/KILL
  wl-stubborn.service: Failed with result 'timeout'.
$ systemctl show wl-stubborn -p Result,ActiveState   ->  ActiveState=failed  Result=timeout
$ systemctl show wl-polite -p KillMode,KillSignal,TimeoutStopUSec,SendSIGKILL
   ->  TimeoutStopUSec=1min 30s  KillMode=control-group  KillSignal=15  SendSIGKILL=yes
```

The defaults: **`KillMode=control-group`** (every process in the service's cgroup, children included, as the log killing both the script and its `sleep` shows), **`KillSignal=15`**, **`TimeoutStopSec=1min 30s`** (the "a start or stop job is running for ... (1min 30s)" message at shutdown). A well-behaved service ends on SIGTERM at once (`wl-polite` stopped in 0.0 s).

### Reload

`ExecReload=` defines what `systemctl reload` does:

```text
ExecReload=/bin/kill -HUP $MAINPID       (here $MAINPID IS expanded: it is a word by itself)
$ systemctl reload wl-reload   ->  journal: Reloading wl-reload.service... / got-HUP / Reloaded wl-reload.service.
```

## The journal

`journald` collects the output of every service, the kernel messages, and syslog. Read it with `journalctl`.

```text
$ systemd-cat -t wl-test -p warning echo "something looks odd" ; systemd-cat -t wl-test -p info echo "just info"
$ journalctl -t wl-test --no-pager -o short-precise
Nov 21 <time> <host> wl-test[<pid>]: something looks odd
Nov 21 <time> <host> wl-test[<pid>]: just info
$ journalctl -t wl-test -p warning -o cat     ->  something looks odd          (-p warning means warning and MORE SERIOUS)
$ journalctl -t wl-test -p 0..4 -o cat        ->  something looks odd          (a priority RANGE; 0 emerg ... 7 debug)
$ logger -t wl-logger -p user.err "from logger"
$ journalctl -t wl-logger -o json | ...       ->  "MESSAGE":"from logger" "PRIORITY":"3" "SYSLOG_FACILITY":"1" "SYSLOG_IDENTIFIER":"wl-logger" "_TRANSPORT":"syslog"
```

The commands you will use daily:

| Command | What it shows |
|---|---|
| `journalctl -u UNIT` | one unit's log (`-u` can repeat; a pattern works: `-u "wl-inst@*"`) |
| `journalctl -f` | follow, like `tail -f` |
| `journalctl -n 50` | the last 50 entries |
| `journalctl -b` / `-b -1` | this boot / the previous boot |
| `journalctl -p err` | errors and worse |
| `journalctl -k` | kernel messages |
| `journalctl --since "-1h" --until now` | a time window (also `"2026-11-21 00:00:00"`; an empty window printed `-- No entries --`) |
| `journalctl -t NAME` | by syslog identifier (tag) |
| `journalctl _SYSTEMD_UNIT=cron.service` | by any journal **field** |
| `journalctl -o cat` / `-o json` / `-o verbose` | output formats (`cat` = message only) |
| `journalctl -F _TRANSPORT` | the values a field has had (here: `driver journal kernel stdout syslog`) |
| `journalctl --list-boots` | boots in the journal (`-2`, `-1`, `0` here) |
| `journalctl --disk-usage` | `Archived and active journals take up 32M in the file system.` |

**Fields**: every entry has structured fields (`_SYSTEMD_UNIT`, `PRIORITY`, `_PID`, `MESSAGE`, `_TRANSPORT`...). Anything you can see in `-o verbose`, you can filter by.

### Persistent or not

```text
$ ls -d /var/log/journal /run/log/journal   ->  /run/log/journal   /var/log/journal           (both exist here)
$ grep -E "^#?(Storage|SystemMaxUse|...)" /etc/systemd/journald.conf
  #Storage=persistent  #SystemMaxUse=  #RuntimeMaxUse=  #MaxRetentionSec=0  #ForwardToSyslog=no
```

If **`/var/log/journal` exists**, the journal is stored on disk and survives reboots; if not, it lives in `/run/log/journal` and is **lost at reboot** (the common reason for "the logs from before the crash are gone"). Settings go in `/etc/systemd/journald.conf` or a drop-in in `/etc/systemd/journald.conf.d/` (the same override idea as units; this machine had a vendor drop-in `/usr/lib/systemd/journald.conf.d/syslog.conf`). `journalctl --list-boots` showing only boot `0` tells you the journal is not persistent. (I did not change journald's configuration in the tests.)

## Common mistakes

- **Editing a unit and not running `systemctl daemon-reload`**: the old definition keeps running (and `systemctl` warns "changed on disk").
- **Editing `/usr/lib/systemd/system/*.service` directly**: the next package update overwrites it. Use a drop-in.
- **Trusting `systemctl start` for `Type=simple`**: it returns 0 before the program is executed; check `is-active` and the journal, or use `Type=exec`.
- **`enable` without `--now`** (nothing runs until the next boot), or **`start` without `enable`** (gone after reboot).
- **`ExecStart` with a pipe, `&&`, `$(...)` or a relative path**: it is not a shell.
- **`$$` in a unit** is a literal `$`; `%` also needs doubling.
- **Using `Requires=` where `Wants=` would do**, or `Requires=` without `After=`.
- **Adding a second `ExecStart=` in a drop-in** without an empty `ExecStart=` first.
- **`Restart=on-failure` expecting a restart after SIGTERM**; **`Restart=always` with no start limit** flooding the logs.
- **Masking by hand-made symlinks** or trying to `mask` a unit whose file is in `/etc`.
- **Forgetting `reset-failed`** after a start-limit failure.
- **Ordering cycles** (two `After=` pointing at each other).

## Practice

All work in a scratch VM or a lab (never your own workstation's real services); name units `wl-…` or similar and remove them afterwards.

1. **Read a unit.** Run `status`, `show -p …` and `cat` for `ssh` (or `sshd`) and `systemd-journald`; write down the file, whether it is enabled, the `Type=`, and which drop-ins apply.
2. **Write a service.** Make a ticker like the one above; start it, read its journal, `enable --now`, then `disable --now`. Show the symlink created and removed.
3. **Break it three ways:** a wrong program path with `Type=simple` and with `Type=exec`; a missing execute bit; an `ExecStartPre=/bin/false`. For each, record the exit status of `start`, `is-active`, and the first useful journal line.
4. **Forget `daemon-reload`.** Change a value in the unit file, restart, show the warning and the old behaviour, then reload.
5. **Drop-ins.** Override an environment variable and replace an `ExecStart` correctly (empty assignment first). Show the failure when you leave it out. Use `systemctl edit --stdin` and `systemctl revert`.
6. **The restart table.** Reproduce at least three rows of the `Restart=` table for exit 0, exit 1 and SIGTERM, and explain why `on-failure` does not restart a SIGTERM death.
7. **The start limit.** Trigger "Start request repeated too quickly", read it in the journal, clear it with `reset-failed`.
8. **Dependencies.** Reproduce the three-row `Requires`/`Wants` table and show the difference when `After=` is missing.
9. **Conditions.** Show a skipped unit and a failed assertion; find the "unmet condition" line.
10. **Journal.** Write a message with `systemd-cat` at two priorities and read back only the worse one; find your own boot's kernel messages; find out whether your journal is persistent.
11. **Mask.** Mask a packaged service you can safely spare (in a VM), show start failing, unmask it; then try to mask your own `/etc` unit and explain the error.
12. **Find the bug.** (a) a unit with `ExecStart=/usr/bin/backup.sh | logger` (b) `[Service] ExecStart=/bin/sh -c 'kill -9 $$'` (c) a drop-in with `ExecStart=/new/command` for an existing service (d) two units each with `After=` the other. Say what each does and fix it.

## Check your understanding

Take the quiz for this lesson (it draws ten from the bank). After a wrong answer, reread the section named in the review line.
