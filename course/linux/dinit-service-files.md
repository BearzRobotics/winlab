*Draft for owner review.* `linux.dinit-basics` taught how to run a dinit system. This lesson is the **service description file** in depth: the five service types, dependencies and ordering, restarting (the **default is to restart**), stopping and signals, readiness, variables and templates, logging, limits and privileges, and the small features (`chain-to`, `@include`). Read the manual page `dinit-service(5)` next to it (`man dinit-service` on Chimera): every setting here is from it, and every behaviour I describe was run.

**Version and testing.** **dinit 0.22.0** on **Chimera Linux 20261103** in a QEMU VM (`tests/verification/dinit/dn1.sh` to `dn4.sh`; the online manual is for 0.23.0, which was **not** tested; dinit is pre-1.0). Quotes from the manual are from the **installed 0.22.0 pages**. **Not tested:** `socket-listen` and its permission settings, `inittab-id`/`inittab-line`, `run-in-cgroup`, `ioprio`, `nice` (my test script used BSD `nice` wrongly and printed a usage error), `securebits`, `rlimit-core`, `rlimit-data`, `rlimit-addrspace`, `signal-process-only`, `kill-all-on-stop`, `skippable`, `starts-on-console` and the other console options, `prepared-by`, `depends-ms.d`/`depends-on.d`, and `load-options`. References: [dinit-service(5)](https://davmac.org/projects/dinit/man-pages-html/dinit-service.5.html), [dinit(8)](https://davmac.org/projects/dinit/man-pages-html/dinit.8.html), [dinitctl(8)](https://davmac.org/projects/dinit/man-pages-html/dinitctl.8.html), and Chimera's [dinit-chimera](https://github.com/chimera-linux/dinit-chimera) service suite (its files in `/usr/lib/dinit.d` are good examples to read).

## The file format

One setting per line, `name = value` or `name: value`. The manual says there is no functional difference between `=` and `:`, but **some settings replace earlier ones and some add a new one**, and it recommends **`=` for the first kind and `:` for the second** (dependencies and `options` add). `+=` appends to a few settings (`command`, `stop-command`, `capabilities`, `securebits`). Rules, from the manual:

- `#` starts a comment, but only if preceded by whitespace; blank space is collapsed to one space; leading and trailing space is stripped.
- A command line is split into **tokens at white space**; **double quotes** group a token; a **backslash** escapes the next character. (**Single quotes are ordinary characters**: tested in the previous lesson.)
- Relative paths in most settings resolve against the directory of the service file; **use absolute paths**.

```text
type = process
command = /usr/bin/sshd -D
smooth-recovery = true
depends-on: ssh-keygen
depends-on: local.target
depends-on: network.target
```

(that is Chimera's `sshd`). The mapping from systemd (my own, from the manual pages; the tests below show where it holds and where it does not): `ExecStart=` is `command =`, `Type=` is `type =` (`simple` ≈ `process`, `oneshot` ≈ `scripted`, `forking` ≈ `bgprocess`, a target ≈ `internal`), `Requires=` ≈ `depends-on`, `Wants=` ≈ `waits-for`, `Restart=` is `restart =`, `ExecStop=` is `stop-command`. The differences matter more than the similarities, as the rest of this lesson shows.

## Service types

| `type =` | What dinit runs | Counts as started when | Tested |
|---|---|---|---|
| `process` | `command`, supervised | the process has begun execution (or signalled readiness, see below) | yes |
| `bgprocess` | `command`, which **forks and exits**; `pid-file` names the daemon | the original process has exited and the PID has been read | yes |
| `scripted` | `command` to start, optional `stop-command` to stop | the command has finished successfully | yes |
| `internal` | nothing | at once, once its dependencies have started | yes |
| `triggered` | nothing | when `dinitctl trigger` is run | yes |

### process and scripted

A `process` service is started by running the command; **if the process ends, the service stops** (and may restart). A `scripted` service has no process after the command ends, **and stays "started"**:

```text
type = scripted
command = /bin/sh -c "echo start-ran >> /tmp/wl-scr.log"
stop-command = /bin/sh -c "echo stop-ran >> /tmp/wl-scr.log"

$ dinitctl start wl-scr ; dinitctl status wl-scr      ->  State: STARTED         (no Process ID: nothing is running)
$ dinitctl stop wl-scr ; cat /tmp/wl-scr.log          ->  start-ran stop-ran     (the stop command ran at stop)
```

A scripted service whose command **fails** does not start:

```text
command = /bin/sh -c "exit 3"
$ dinitctl start wl-scr-fail   ->  Service 'wl-scr-fail' failed to start.
                                   Reason: service process terminated before ready: exited - status 3        rc=1
$ dinitctl status wl-scr-fail  ->  State: STOPPED (failed to start; exited - status 3)
```

Chimera uses `scripted` for one-off set-up (42 of its 80 files) and `process` for daemons (23). The `chrony` file is a scripted service that waits for time synchronisation: `command = /usr/bin/sh -c "/usr/bin/chronyc ... waitsync 180 ... || :"`, `start-timeout = 240`, `options: start-interruptible`.

### bgprocess

For a daemon that **forks into the background** and writes its PID to a file:

```text
type = bgprocess
command = /tmp/wl-daemon.sh          (starts sleep 1000 in the background, writes its PID to /tmp/wl-daemon.pid, exits 0)
pid-file = /tmp/wl-daemon.pid

$ dinitctl start wl-bg ; dinitctl status wl-bg   ->  State: STARTED   Process ID: <pid>      (the same PID as in the file: dinit supervises the daemon)
$ dinitctl stop wl-bg                            ->  the daemon was gone afterwards (kill -0 said: No such process)
```

Prefer `process` with the daemon's "stay in the foreground" option (`sshd -D`, `syslog-ng -F`) when it has one: dinit then sees the real process.

### internal and triggered

```text
# wl-int (internal)  depends-on: wl-int-dep (a process)
$ dinitctl start wl-int      ->  wl-int [[+]]   and   wl-int-dep (pid: <pid>)     (an internal service only groups; stopping it stops the dependency too)

# wl-trig (type = triggered)
$ dinitctl start wl-trig         ->  (waits: State: STARTING; my 'timeout 4' ended it, rc=124)
$ dinitctl trigger wl-trig       ->  State: STARTED
```

A triggered service **starts only after an outside event** says so, for example a script that runs `dinitctl trigger` when a device appears. After I stopped it and started it again (with `--no-wait`), it was **already `STARTED`**: **the trigger stays set** until `dinitctl untrigger` (I read that from this one result and the manual's description of `untrigger`).

## Dependencies

| Setting | Meaning (manual) | Tested result |
|---|---|---|
| `depends-on: X` | **hard**: X must start first; if X stops, this service stops | starting the dependent starts X; `dinitctl stop X` is **refused** while it runs (`--force` stops both) |
| `depends-ms: X` | **milestone**: X must start successfully first; afterwards X may stop without affecting this service | `stop --force X` left the dependent `STARTED` |
| `waits-for: X` | X must **finish starting or fail to start** first; failure does not prevent this service from starting | `stop --force X` left the dependent `STARTED`; a failing X did not stop it |
| `prepared-by: X` | like `depends-on`, but X is also restarted when this service restarts | not tested |
| `depends-on.d`, `depends-ms.d`, `waits-for.d: DIR` | one dependency per name in DIR | `waits-for.d` is how `boot`, `enable` and groups work (basics lesson) |

When the dependency **fails to start**:

```text
depends-on: wl-dbbad    ->  dinitctl start wl-xneed   ->  failed to start.   Reason: a dependency of the service failed to start. Check dinit log.      rc=1
depends-ms: wl-dbbad    ->  dinitctl start wl-xms     ->  the same                                                                                     rc=1
waits-for:  wl-dbbad    ->  dinitctl start wl-xwaits  ->  Service 'wl-xwaits' started.                                                                 rc=0
dinitctl list           ->  [     {X}] wl-xneed   [     {X}] wl-dbbad   [     {X}] wl-xms   [     {-}] wl-xwaits
```

Choose like this: **`waits-for`** for "I would like it, but I can run without it" (the equivalent of systemd `Wants=` + `After=`); **`depends-on`** for "I cannot run without it, and if it goes I must go" (`Requires=` + `After=`); **`depends-ms`** for "it must have come up successfully once, for example a one-off setup step". **In dinit a dependency also orders the start** (the dependent waits for the dependency): there is no separate "requirement without ordering" as in systemd.

You can also change dependencies of **loaded** services at run time, without editing files (it is not persistent):

```text
$ dinitctl add-dep need wl-solo wl-db     ->  Service 'wl-solo': dependency 'wl-db' added
$ dinitctl stop wl-db                     ->  cannot stop service 'wl-db' due to the following dependents: wl-solo
$ dinitctl rm-dep need wl-solo wl-db      ->  Service 'wl-solo': dependency 'wl-db' removed
```

(`need`, `milestone` and `waits-for` are the type names; `regular` is a deprecated alias of `need`).

### Ordering without a dependency: `after` and `before`

`after: X` means "if X is also **starting**, wait for it"; it does **not** start X. Three scripted services that each log their start and end, all `waits-for` of one internal service:

```text
no ordering:                         o2-start o3-start o1-start o3-end o1-end o2-end      (all in parallel)
o2 after o1, o3 after o2:            o1-start o1-end o2-start o2-end o3-start o3-end
o2 before o3, o3 before o1 (before:): o2-start o2-end o3-start o3-end o1-start o1-end
```

```text
wl-aft has "after: wl-o1" and is started alone   ->  wl-o1 stays STOPPED          (after: implies no dependency)
```

`before: X` on service Y is the same as `after: Y` on X. Neither loads the other service by itself.

## Restarting: the default is yes

```text
restart = {yes | true | on-failure | no | false}
```

**The default is to restart automatically** (the manual says so; I confirmed it): a process service killed with `kill -9` was started again within the 2-second wait (2 runs logged), and the same service **stayed stopped after a manual `dinitctl stop`**: *a manual stop inhibits automatic restart*, with its dependents. This is the **opposite default from systemd** (`Restart=no`).

What ends a service, and what each setting does (a script that logged each start, ended by exit code or signal; `restart-delay = 0.1`, `restart-limit-count = 0` to remove the limit; counted over 3 seconds):

| `restart =` | exit 0 | exit 1 | SIGTERM | SIGKILL | SIGUSR1 | SIGABRT |
|---|---|---|---|---|---|---|
| `yes` | **restarts** | **restarts** | **restarts** | **restarts** | **restarts** | **restarts** |
| `on-failure` | stays down | **restarts** | stays down | **restarts** | stays down | **restarts** |
| `no` | stays down | stays down | stays down | stays down | stays down | stays down |

`on-failure` restarts on a **non-zero exit** or on a **signal other than SIGHUP, SIGINT, SIGUSR1, SIGUSR2 and SIGTERM**, which the manual calls "deliberate termination" (this is the same idea as systemd's clean signals; the table shows TERM and USR1 staying down). It applies only to `process` and `bgprocess` services; for other types it means `no`. What `dinitctl status` says after each ending with `restart = no`:

```text
exit 0   State: STOPPED (terminated)
exit 1   State: STOPPED (terminated; exited - status 1)
SIGTERM  State: STOPPED (terminated; signalled - signal 15)
SIGKILL  State: STOPPED (terminated; signalled - signal 9)      SIGUSR1: signal 10      SIGABRT: signal 6
```

### Rate limit

```text
restart-delay = 0.2          (seconds between restarts; the default is 1.0)
restart-limit-count = 3      (restarts allowed per interval; the default is 5; 0 removes the limit)
restart-limit-interval = 10  (seconds; the default is 10)
```

A service that exits at once, with `restart-limit-count = 3`:

```text
$ dinitctl start wl-flaky ; sleep 3 ; wc -l < /tmp/wl-flaky.log           ->  4        (the first run and three restarts)
$ dinitctl status wl-flaky                                                ->  State: STOPPED (terminated; exited - status 1)
$ dinitctl list | grep wl-flaky                                           ->  [     {X}] wl-flaky (exit status: 1)
$ dinitctl is-failed wl-flaky                                             ->  STOPPED   rc=1        (a process that ran and died is not a "startup failure")
```

and when I started it again at once it crashed again and ended in the same state. There is no `reset-failed` command in `dinitctl`'s list; I did not test how long the limit lasts, so measure it before relying on a recovery.

### `smooth-recovery`

With `smooth-recovery = true` a dying process is **replaced without stopping the services that depend on it**, and without the service changing state. A service and a dependent, the service killed with `kill -9`:

```text
smooth-recovery = false:  service pid changed: yes;  dependent pid changed (it was restarted): yes
smooth-recovery = true:   service pid changed: yes;  dependent pid changed (it was restarted): no
```

(Chimera's `sshd` and `syslog-ng` use it.) The normal restart limits still apply; a dependency declared with `prepared-by` should not be smooth.

## Starting and stopping, timeouts, signals

```text
start-timeout = 60      (default: seconds to start; then the process group gets SIGINT; 0 = no limit)
stop-timeout  = 10      (default: seconds to stop; then SIGKILL to the process group; 0 = no limit)
term-signal   = TERM    (the signal that asks it to stop; NONE or HUP, ...)
stop-command  = ...     (run instead of signalling the process)
```

```text
a script with  trap '' TERM  and stop-timeout = 3:
$ dinitctl stop wl-stub   ->  Service 'wl-stub' stopped.        stop took 3 s       (TERM ignored, then SIGKILL after the timeout)
start-timeout = 1 and a slow service:  failed to start. Reason: start timed out.    State: STOPPED (start timed out)
```

`dinitctl signal SIGNAL SERVICE` sends a signal to the service's process:

```text
$ dinitctl signal USR1 wl-sig ; dinitctl signal HUP wl-sig       ->  the script's traps printed:  got-HUP  got-USR1
$ dinitctl signal --list    ->  HUP 1, INT 2, QUIT 3, KILL 9, USR1 10, USR2 12, TERM 15 ...   (a limited list)
$ dinitctl signal NOSUCH wl-sig    ->  dinitctl: 'NOSUCH' is not a valid signal name/number
```

With **`term-signal = HUP`** the stop sent HUP: the script's HUP trap printed `got-HUP`, and the log also showed a line `Hangup`, which is the shell reporting that a child (`sleep`) died of the same signal: by default dinit signals the **whole process group** (the manual's `signal-process-only` option restricts it to the main process; I did not test that option). This matters for a service that starts children.

## Readiness: when is a process "started"?

By default a `process` service is started **as soon as it begins to execute**. A service that needs time to become ready can say so by writing to a file descriptor:

```text
ready-notification = pipefd:3          (the service writes a line to descriptor 3 when it is ready)
ready-notification = pipevar:NAME      (dinit puts the descriptor number in environment variable NAME)

wl-rdy (a script that sleeps 2 s, then does: echo ready >&3):   dinitctl start wl-rdy    ->  start took 2.0 s
the same script without ready-notification:                    dinitctl start wl-nordy   ->  start took 0 s
```

(`syslog-ng`'s Chimera file uses `ready-notification = pipevar:SYSLOG_NG_READY_FD`.) The equivalent in systemd is `Type=notify`. Combine it with `start-timeout` so a service that never says ready fails cleanly (`start timed out`).

## Variables, templates and the environment

### Substitution rules

Command lines, paths and some other settings may contain **`$NAME`**. dinit replaces it **when the service is loaded**, from the service's environment (the manual's priority order: the service `env-file`, then `load-options`-exported variables, then dinit's own environment including `dinitctl setenv` values). Tested with `env-file` setting `GREETING=hello` and `NAME=from-file`:

```text
command = /bin/echo plain $GREETING braced ${GREETING} default ${UNSETVAR:-fallback} other ${NAME:+set} literal $$HOME word[$GREETING] "quoted $GREETING"
   ->  plain hello braced hello default fallback other set literal $HOME word[hello] quoted hello
```

- **`$NAME` is replaced even inside a word** (`word[$GREETING]` became `word[hello]`): the name ends at the first space, control or punctuation character other than `_`. This differs from systemd, where a bare `$VAR` must be a word of its own.
- `${NAME}`, `${NAME:-word}` (default if unset **or empty**), `${NAME-word}` (if unset), `${NAME:+word}` and `${NAME+word}`. The "word" cannot contain spaces or `}` and is not expanded further.
- **`$$`** gives a literal `$` (`$$HOME` printed `$HOME`): the same escape as in systemd.
- An **unset variable becomes an empty string**, which may give an **empty argument**.
- **One variable stays one argument; `$/NAME` splits it into several** (with `LIST=a b  c` in the env-file):

```text
command = /usr/bin/printf [%s] $LIST     ->  [a b  c]
command = /usr/bin/printf [%s] $/LIST    ->  [a][b][c]
```

### Substitution happens once

```text
command = /bin/echo substituted:$SETVAR_W
dinitctl setenv SETVAR_W=one ; dinitctl start wl-sub     ->  substituted:one
dinitctl setenv SETVAR_W=two ; dinitctl stop wl-sub ; dinitctl start wl-sub     ->  substituted:one      (still: the file was substituted at load)
dinitctl stop wl-sub ; dinitctl unload wl-sub ; dinitctl start wl-sub           ->  substituted:two      (reloaded: the new value)
```

But the **environment given to the process at each start** does change: a script that prints `$SETVAR_Z` printed `first`, then `second` after `setenv SETVAR_Z=second` and a restart, and an empty value after `unsetenv`. So **`dinitctl setenv` affects the environment of services started afterwards, not command-line substitutions already done**. That is also the way a user session passes variables to its services.

**A trap:** the substitution applies to **every `$` in a `command =` line**, including ones meant for the shell: `command = /bin/sh -c "while read l; do echo consumed:$l; done"` printed `consumed:` with an empty value, and a `$((i+1))` made the **whole description invalid** (`error in service description`). Put real shell code in a **script file**, or double the dollar signs (`$$l`).

### Templates

A service file can serve many instances: the **instance name is the part after `@`**, available as **`$1`**. **The file is named without the `@argument`**:

```text
# /etc/dinit.d/wl-tpl
type = process
command = /bin/sh -c "echo instance=$1 >> /tmp/wl-tpl.log; sleep 1000"

$ dinitctl start wl-tpl@alpha ; dinitctl start wl-tpl@beta     ->  logs  instance=alpha  instance=beta      (two loaded services, each with its own process)
$ dinitctl start wl-tpl         (no argument, but the file uses $1)    ->  dinitctl: error in service description.
# with  command = /bin/sleep ${1:-100}
$ dinitctl start wl-tplb ; dinitctl start wl-tplb@7     ->  sleep 100  and  sleep 7           (an unset $1 can use a default)
$ dinitctl enable wl-tpl@gamma    ->  the link /etc/dinit.d/boot.d/wl-tpl@gamma -> ../wl-tpl
```

Chimera uses it for terminals: `agetty-service@tty1` ... `agetty-service@ttyS0` are six local terminals and the serial console from one file, `agetty-service`. (A file named `wl-tpl@` was **not found**: I tried first and got `failed to find service description`.)

## Logging

| `log-type =` | Output of the service goes to | Tested |
|---|---|---|
| `none` (default) | nowhere | `dinitctl catlog` says `cannot cat log for service not configured to buffer output.` |
| `file` | the file in `logfile = PATH` (setting `logfile` implies `file`) | stdout **and** stderr, appended; mode `-rw-------` by default |
| `buffer` | memory (`log-buffer-size`); read with `dinitctl catlog [--clear]` | yes |
| `pipe` | a pipe that another service reads (`consumer-of = NAME`) | yes |

```text
logfile = /var/log/wl-log.txt   ->  to-logfile, to-stderr are both in the file; two starts gave 4 lines (it appends)
logfile-permissions = 640, logfile-uid = nobody   ->  -rw-r----- 1 nobody nogroup
logfile = /var/log/wl-nodir/log.txt (directory missing)   ->  failed to start, Stage: opening log file, Error: No such file or directory
log-buffer-size = 100 and a service printing 200 lines    ->  catlog gave 140 bytes beginning with line-0, line-1 ... (the first output; I did not print the end, the extra bytes are
                                                           probably a warning line); without the setting all 200 lines were kept; catlog --clear emptied it (0 bytes)
```

**The buffer keeps the first output and drops the rest** when it is full (the manual says "further output ... will be discarded"), the opposite of what you want for a log of recent events: use a `logfile` for long-running services.

### One service logging for another

```text
# wl-prod:  log-type = pipe              (a script that prints producer-line-1, then producer-line-2)
# wl-cons:  consumer-of = wl-prod        (a script that reads lines from stdin and appends them to a file)
$ dinitctl start wl-cons ; dinitctl start wl-prod ; sleep 1 ; cat /tmp/wl-consumed
   consumed:producer-line-1
   consumed:producer-line-2
```

This is how a dedicated log agent (a service whose standard input is another service's output) is built. The consumer **must be a process service**, and the producer must be a process-based service with `log-type = pipe`.

## Limits and privileges

A script printed its own user, directory, limits and capabilities, run as a default service and as a restricted one:

```text
default service:            user=root uid=0 cwd=/etc/dinit.d   nofile=1024   CapEff 000001ffffffffff   NoNewPrivs 0   oom_score_adj=0
run-as = nobody
working-dir = /var/tmp
rlimit-nofile = 256:512
oom-score-adj = 300
options: no-new-privs       ->  user=nobody uid=65534 cwd=/var/tmp   nofile=256   CapEff 0000000000000000   NoNewPrivs 1   oom_score_adj=300
run-as = nobody + capabilities = ^CAP_NET_BIND_SERVICE   ->  CapEff 0000000000000400            (the one capability: bit 10, binding low ports)
run-as = no-such-user       ->  dinitctl: error in service description.
working-dir = /nonexistent  ->  Stage: changing directory   Error: No such file or directory
```

| Setting | Effect |
|---|---|
| `run-as = USER` | run as that user (a name also sets the group and supplementary groups) |
| `working-dir = DIR` | the working directory; **the default is the directory of the service file** (`cwd=/etc/dinit.d`) |
| `rlimit-nofile = soft:hard` | the open-file limit (`256:512` gave `ulimit -n` 256) |
| `oom-score-adj = N` | OOM-killer bias (-1000..1000), needs `/proc` |
| `capabilities = IAB` | the capability vectors; `^CAP_NAME` grants an ambient capability |
| `options: no-new-privs` | the service cannot gain privileges (setuid and file capabilities) |

**dinit's sandboxing is much smaller than systemd's**: the 0.22.0 manual page lists process settings (user, directory, resource limits, nice, ionice, OOM score, cgroup, capabilities, no-new-privs) and **no file-system or network namespace settings** (no equivalent of `ProtectSystem=`, `PrivateTmp=`, `PrivateNetwork=`). To confine a service on Chimera you combine dinit's settings with other tools; I did not test any.

## Small features

- **`chain-to = NAME`**: when this service **terminates by itself with success**, start NAME. Tested: a `process` service that logged `first` and exited 0 (with `restart = false`) started `wl-chained` (`first second` in the log). **A `scripted` service does not terminate** (it stays started), so its `chain-to` did not fire. `always-chain` (in `options:`) forces it.
- **`@include PATH`** pulls another file's settings in (an error if the file is missing); **`@include-opt PATH`** does not mind. With an included file containing `restart = false`, a crashing service ran **1** time against **20** without it.
- **`@meta enable-via NAME`**: the default group for `dinitctl enable` (basics lesson).
- **`dinit-check NAME`** reads every file involved and reports problems (basics lesson).

## A trap from my own tests: BSD `sed -i`

Chimera's userland is FreeBSD's. `sed -i "s/a/b/" file`, which edits in place on GNU systems, **fails on BSD `sed`** because the next word is taken as the backup suffix; it prints an error (`sed: 1: "...": extra characters at the end of d command`) and **leaves the file unchanged**. I hit it twice while writing these tests: my first "fixes" to service files (a mistyped program name, a version marker) **never happened**, and I had drawn conclusions about `reload` from files that had not changed. The tests above were redone with the file rewritten by `cat` or `printf`. When a service file "did not change anything", **look at the file and at the error output before suspecting dinit**; and in scripts for Chimera write a temporary file and `mv` it (`foundations.posix-sh-scripting`).

## Common mistakes

- **Expecting systemd's defaults**: dinit **restarts by default** and a manual `stop` is what keeps it down.
- **A `$` meant for the shell** inside `command =`: it is substituted at load time (use `$$` or a script file).
- **Expecting `dinitctl setenv` to change a command line** that has already been loaded.
- **Naming a template file `name@`**: the file is `name`.
- **Relying on `log-type = buffer` for long-running output**: it keeps the first lines only.
- **A `scripted` service with `chain-to`**: it never terminates; use `process`.
- **A daemon that forks with `type = process`**: dinit sees the parent exit; use `bgprocess` with `pid-file`, or the daemon's foreground option.
- **`waits-for` when the service truly needs the other** (use `depends-on`), and the reverse.
- **Forgetting the process group**: a stop signal reaches the children too.
- **Editing service files with `sed -i` on Chimera.**

## Practice

Use the Chimera lab VM; name services `wl-…`.

1. **Types.** Write one service of each type; for `scripted` use a stop command; for `bgprocess` a small forking script with a PID file; for `triggered` trigger it by hand. Record `dinitctl status` for each.
2. **Dependencies.** Reproduce the three-row dependency table and the failing-dependency table; then use `add-dep` and `rm-dep` at run time.
3. **Ordering.** Reproduce the parallel, `after` and `before` runs with logging scripts.
4. **Restart.** Reproduce at least four cells of the restart table with script files; then set `restart-limit-count` and show the limit; then show smooth-recovery on and off with a dependent.
5. **Stopping.** Make a service that ignores TERM; show `stop-timeout`; then change `term-signal` and use `dinitctl signal`.
6. **Readiness.** Make a service that is ready after 2 seconds, with and without `ready-notification`, and time `start`.
7. **Variables.** Reproduce the substitution table, the `$LIST` versus `$/LIST` test, and the "substituted once" test.
8. **Templates.** Write a template with `$1` and a default; start three instances; enable one.
9. **Logging.** Compare `file`, `buffer` (with a small `log-buffer-size`), `pipe` with `consumer-of`.
10. **Privileges.** Run a script that prints its identity as root and as `nobody` with a limit, a directory, `no-new-privs` and one capability.
11. **Find the bug.** (a) `command = /bin/sh -c "echo $HOME; ..."` printing an empty value (b) a service that "keeps coming back" after `kill` that you wanted down (c) `chain-to` on a `scripted` service that never fires (d) a template file named `wl@` (e) a service file you "fixed" with `sed -i` on Chimera. Explain each.

## Check your understanding

Take the quiz for this lesson (it draws twelve from the bank). After a wrong answer, reread the section named in the review line.
