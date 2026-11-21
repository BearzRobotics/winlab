*Draft for owner review.* A one-off command line becomes a **tool** when it has a name, takes arguments, says what went wrong, cleans up after itself and cannot run twice at once. This lesson covers the pieces: **functions** (and their traps), **argument parsing** (`getopts` and a manual loop), **here-documents**, **exit codes**, **`trap`** and signals, **`mktemp`** and why predictable temp file names are dangerous, **logging**, **lock files**, and knowing **where your script lives**.

**What was tested.** All of it was run in **bash 5.3.9** on Ubuntu 26.04 (WSL2), with `getopts`, `trap`, the dot command and `mktemp` also checked in **dash 0.5.12** where noted (`tests/verification/bash/fn1.sh`, `fn2.sh`, `fn3.sh`). Every output shown is from a real run. **Which tools:** on this Ubuntu most of the small utilities (`mktemp`, `stat`, `date`, `wc`, `seq`, `sleep`, `timeout`, `realpath`, `dirname`) are the **uutils (Rust) coreutils 0.8.0**, while `find`, `xargs`, `grep`, `sed`, `gawk`, `cp`, `mv`, `rm` and `df` are GNU (`tests/verification/bash/whichimpl.sh` lists each; I did not check `flock` or `logger`). The `mktemp` modes and error text, for example, come from uutils; GNU coreutils may word messages differently, so on another system compare before trusting an exact message. Not tested: other bash versions, macOS (different `mktemp`, no `flock` by default, as far as I know; I did not verify), FreeBSD, and cron or systemd environments. Scripts start `#!/usr/bin/env bash`; the shell facts are in `foundations.shells-and-posix` and the expansion facts in `foundations.bash-variables-and-expansion`.

## Functions

```bash
greet() { echo "hello $1"; }       # POSIX form
greet world
```

A function is run **in the current shell**, with its own positional parameters: inside it `$1`, `$2`, `$#` and `"$@"` are the function's arguments, while the script's own `$1` is untouched (after `set -- top1 top2` and a call `show x`, the script's `$1` was still `top1`). `$0` stays the **script's** name; `${FUNCNAME[0]}` is the function's name (bash). `shift` inside a function shifts the function's arguments only.

### A function has a status and an output; they are different things

```bash
square() { echo $(( $1 * $1 )); }
r=$(square 7)            # r=49: capture what it PRINTS

is_even() { (( $1 % 2 == 0 )); }
is_even 4 && echo even   # the STATUS is the last command's
```

- **The status** of a function is the status of its last command (a function whose last command was `echo` returned `0` even though an earlier `false` failed), or whatever `return N` says.
- **`return` takes 0 to 255:** `return 300` gave status `44` (300 mod 256) and `return -1` gave `255`. A function that needs to hand back a number bigger than 255 must print it.
- **`exit` inside a function ends the whole shell** (or the subshell it runs in): `(fexit)` with `exit 3` ended with status `3`. Use `return` to leave a function.
- `type greet` says `greet is a function`; `declare -f greet` prints its body.

### Scope: `local`, and bash's local is dynamic

Without `local` a variable is **global**: a function assigning `x=changed` changed the script's `x`. With `local` it is private to the call... **and to everything it calls.** Bash uses *dynamic* scope:

```bash
x=global
f1() { local x=inner; f2; }
f2() { echo "f2 sees x=$x"; }
f1          # f2 sees x=inner  (the caller's local, not the global)
```

So a function that reads a variable it never declared reads whatever the **nearest caller** set. Pass values as arguments, and `local` everything you assign.

More from the runs:

- `local` does not leak (`${y-unset}` after the call gave `unset`), but **loop variables do**: `for i in 1 2 3` inside a function left `i=3` in the caller unless you wrote `local i`.
- **`local a=1 b=$a` in one statement:** `$a` was still unset when `b` was assigned (`b=[]`). Declare, then assign: `local a=1; local b=$a`.
- `local -r k=1; k=2` fails with `k: readonly variable`.
- **A function in a pipeline, or in `$(...)`, runs in a subshell:** `echo | inc` left `cnt=0`, and `o=$(chg)` left `v=a` while `o` got the output. Variables set there are lost.

### Passing arguments through

Forward with `"$@"`: `wrap() { fwd "$@"; }` kept `[x y] [z]` as two words; `fwd $@` re-split them into three (`[x] [y] [z]`). `shift 2` with only one argument returned status `1` and **did not shift**. With `set -u`, read an optional argument as `${1:-}`, or as `${1:-default}`.

### Returning more than a status

Three ways, in order of preference:

1. **Print it and capture with `$(...)`.** Simple, but it costs a subshell, and anything else the function prints is captured too (send diagnostics to `>&2`).
2. **Set a global** by documented name (`REPLY="alice"`). Cheap and visible; do it deliberately.
3. **A nameref** (`local -n ref=$1; ref=value`, bash 4.3+): `setvar result` set the caller's `result` to `via nameref`, and `sumarr arr` summed an array passed *by name* (6 for `1 2 3`).

To get a status **and** a value: `val=$(both); echo "val=$val status=$?"` gave `value` and `4`, because the status of the assignment is the status of the command inside. Several lines of output: `mapfile -t out < <(pair)`.

### Functions versus commands

A function **shadows** a command of the same name: after `ls() { echo "my ls function"; }`, `ls /` printed the function's text, and **`command ls /`** bypassed it; `unset -f ls` removed it. The same works for builtins (`cd() { echo "my cd"; }` was used until `unset -f cd`; `builtin cd` bypasses it). `type -t` tells you what a name is: `function`, `file`, `builtin` or `keyword` (all four appeared in my run). In a script that must be safe, **call external tools as `command tool` or by full path** if a caller's environment might define functions of the same name.

Two more facts: recursion works (`fact 10` = `3628800`), and **`export -f hi`** makes a function visible to a child **bash** (`bash -c hi` ran it) but **not** to `sh` (`sh: 1: hi: not found`).

## Parsing arguments

### `getopts`: short options, built in, POSIX

```bash
parse() {
  local OPTIND=1 verbose=0 out="" opt
  while getopts ":vo:h" opt; do
    case $opt in
      v) verbose=1 ;;
      o) out=$OPTARG ;;
      h) echo "usage: ..."; return 0 ;;
      :) echo "option -$OPTARG needs an argument" >&2; return 2 ;;
      \?) echo "unknown option -$OPTARG" >&2; return 2 ;;
    esac
  done
  shift $((OPTIND - 1))
  echo "verbose=$verbose out=[$out] rest: $*"
}
```

The option string `":vo:h"`: `v` and `h` are flags, `o:` takes an argument (in `$OPTARG`), and the **leading colon** selects "silent" mode so *you* handle errors: a missing value arrives as `:` and an unknown option as `?`. My runs:

```text
parse -v -o file.txt a b   -> verbose=1 out=[file.txt] rest: a b
parse -vo file.txt a b     -> same: options can be combined
parse -ofile.txt a         -> out=[file.txt]: the value can be attached
parse -x a                 -> unknown option -x
parse -o                   -> option -o needs an argument
parse -- -v a              -> rest: -v a   (-- ends the options)
parse a -v b               -> rest: a -v b (parsing STOPS at the first non-option)
```

Facts that bite:

- **`OPTIND` is global state.** In my test, the first call parsed `-v -v` (2 options, `OPTIND=3`) and **the second call in the same shell parsed 0 options**, because `OPTIND` still said 3. `local OPTIND=1` inside the function fixed it (2 and 2).
- **`getopts` has no long options** (`--verbose` ended parsing: `o=[?]`, status 1). If you want `--output=FILE`, write the loop yourself (below).
- Options **after** the first operand are not options (`parse a -v b`). That is POSIX behaviour. (There is a separate external program, `getopt`, that can parse long options and reorder arguments; I did not test it and its behaviour differs between systems, so this lesson does not rely on it.)
- `getopts` behaved the same in **dash** for `-a -b x file` (it printed `a=`, `b=x`, `rest: file`), so it is the portable choice for short options.

### A manual loop (long options)

```bash
verbose=0; out=""
while [ $# -gt 0 ]; do
  case $1 in
    -v|--verbose) verbose=1 ;;
    -o|--output)  out=${2:?--output needs a value}; shift ;;
    --output=*)   out=${1#*=} ;;
    -h|--help)    echo "usage: args.sh [-v] [-o FILE] ARGS..."; exit 0 ;;
    --)           shift; break ;;
    -*)           echo "unknown option: $1" >&2; exit 2 ;;
    *)            break ;;
  esac
  shift
done
```

Results: `-v --output a.txt x y` gave `verbose=1 out=[a.txt] rest: x y`; `--output=b.txt -- -notopt` gave `out=[b.txt] rest: -notopt`; `--bogus` printed `unknown option: --bogus` and exited **2**; `-o` with no value stopped with `--output needs a value` (the `${2:?}` trick). Always handle `--` and always reject unknown options: silently ignoring them hides typos.

### Usage and error helpers

```bash
usage() { printf 'usage: %s [-v] FILE\n' "${0##*/}" >&2; exit 2; }
die()   { printf '%s: %s\n' "${0##*/}" "$*" >&2; exit 1; }
[ $# -ge 1 ] || usage
[ -r "$1" ] || die "cannot read '$1'"
```

Output went to **standard error** and the statuses were `2` (usage), `1` (runtime error) and `0`. `${0##*/}` is the script's name without its folder. Messages on stderr keep stdout clean for pipes.

## Here-documents

A here-document feeds lines of text to a command's standard input:

```bash
cat <<EOF
expanded: hello $name, 1+1=$((1+1)), $(date), literal \$ and \`
EOF
```

| Form | Behaviour (what I saw) |
|---|---|
| `<<EOF` | variables, `$(...)` and `$((...))` are **expanded**; escape `\$` and `` \` `` |
| `<<'EOF'` (quoted delimiter) | **nothing** is expanded: `$name` and `$(echo DATE)` printed literally, `\n` stayed |
| `<<-EOF` | leading **tab** characters are stripped (spaces are not), so you can indent inside an `if`; the closing delimiter may be tab-indented |
| `<<EOF \| tr a-z A-Z` | the here-document can feed a pipe (`PIPED HERE-DOC`) |
| `<<EOF > file` | writes a file (`host=world`) |
| `<<<"text"` | a *here-string* (bash): `read -r a b <<< "x y"` gave `a=x b=y` |

The **delimiter must be alone on its line**: with a space before `EOF` the shell did not see it, and the here-document swallowed ` EOF` as text up to the end of the file. Use a **quoted** delimiter (`<<'EOF'`) whenever the text is code, SQL or a config file that must not be expanded; otherwise a `$` in it will be silently replaced.

## Exit codes

Every process ends with a number from 0 to 255; `0` is success. In my runs: `exit 256` gave `0` and `exit -1` gave `255` (the value wraps modulo 256). Conventions worth following:

| Status | Meaning | Seen |
|---|---|---|
| `0` | success | |
| `1` | general failure | |
| `2` | wrong usage | my `usage()` |
| `126` | found but could not run (permission) | a file without the execute bit gave `126` |
| `127` | command not found | `nosuchcmd` gave `127` |
| `128 + n` | killed by signal `n` | `kill -TERM` gave `143`; `kill -INT` gave `130`; `kill -KILL` gave `137` |

More facts: `exit` with no argument uses the **last command's status** (`false; exit` gave `1`); `exit` inside `$( )` or a pipeline stage ends **only that subshell** (`x=$(exit 7)` let the script continue with status `7`; `echo a | { exit 5; }` left the parent running, `after: 5`); `[[ -f /nonexistent ]]` returned `1`. A script's status should mean something to its caller (cron, systemd, another script): use `0` only for success.

## `trap`: cleanup and signals

`trap 'commands' SIGNAL...` runs commands when a signal arrives or when the shell exits. The most useful signal is the pseudo-signal **`EXIT`**: it runs when the script ends for any reason handled by the shell.

```bash
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
```

What I verified:

- **`$?` inside the EXIT trap is the status the script was about to exit with** (`exit 3` gave `cleanup ran, $? was 3`), and the script then exits with that status. If the trap itself calls `exit 9`, the script's status becomes **9**.
- It also runs after a `set -e` failure (`false` aborted the script; the trap printed `EXIT trap, status 1`).
- **There is one trap per signal:** a second `trap ... EXIT` **replaced** the first.
- **Quoting decides when variables expand.** `trap 'echo "x=$x"' EXIT` expands `$x` when the trap *runs* (`after`); the double-quoted form expanded it when the trap was *set* (`before`). Use single quotes and refer to variables, as in `rm -rf "$tmp"`.
- A temporary directory removed by the trap was gone after the script (`temp dir exists after the script? no`).
- **Traps are not inherited by subshells:** `( echo in-subshell )` printed without running the parent's EXIT trap in the subshell (the parent's ran at its own exit).
- `trap -p` lists current traps. An **empty** trap (`trap '' TERM`) *ignores* the signal: `kill -TERM $$` then printed `still alive`.

### Signals

- A script that traps `TERM` and does `exit 143` cleaned up, ran its EXIT trap and reported **143** when I sent `kill -TERM`.
- **`kill -KILL` cannot be trapped:** the status was `137` and the EXIT trap **did not run**. A script can never promise cleanup after `kill -9`, power loss or a crash. Design for it (stale lock files, partial output files; see below).
- **A signal that was ignored when the script started cannot be trapped.** I started a script **in the background** from another script and sent `SIGINT`: its `trap ... INT` never ran (`ready`, `finished`, status 0), and `trap -p INT` inside showed `trap -- '' SIGINT`, because a non-interactive shell starts background jobs with `SIGINT` ignored. Started under `timeout -s INT`, the same script printed `got INT`. Test signal handling the way the script will really be started (cron, systemd, a terminal).
- **`ERR` traps** (bash) do not fire inside functions unless you also `set -E` (`errtrace`): without it `f() { false; ...; }` never triggered the trap; with `set -E` it printed `ERR trap at line 4`. `ERR` is a bash/ksh feature (dash: `bad trap`).

## `mktemp`: temporary files without races

```bash
f=$(mktemp)                         # /tmp/tmp.XXXXXXXXXX  mode 600, owner you
d=$(mktemp -d)                      # a directory, mode 700
t=$(mktemp "$d/report.XXXXXX")      # your own template (it needs `X` characters; with none I saw `too few X's in template`)
t2=$(mktemp --suffix=.log "$d/x.XXXX")
```

In my runs the file was created **mode 600**, owned by me, the directory **mode 700**, names differed on every call, and `TMPDIR=$d mktemp` created the file under `$d`. `mktemp` creates the file *atomically* with a name nobody can predict.

### Why not `/tmp/myscript.$$`?

`$$` (the process id) is **predictable**. If an attacker (or just another user) creates a **symlink** at the name your script will use, your script writes through it. I reproduced it in my own temp folder: with `report.$$` pointing to `victim.txt`, `echo "report text" > report.$$` **overwrote `victim.txt`** (`precious data` became `report text`). With `set -C` (noclobber) the same redirection failed (`cannot overwrite existing file`) and the victim was untouched, but `mktemp` avoids the whole class. **Never build temp names from `$$`, the date or a fixed name in a shared folder.** Keep temp files in a private directory (`mktemp -d`) and remove it in an EXIT trap.

## Logging

```bash
log() { printf '%s [%s] %s\n' "$(date '+%F %T')" "$1" "$2" >&2; }
log INFO started          # 2026-11-21 13:49:07 [INFO] started
```

- **Logs go to standard error** (or a file); standard output is for the script's real output.
- bash 4.2+ can format time **without starting a process**: `printf '%(%F %T)T\n' -1`. For 300 calls, `$(date +%T)` took **1,563 ms** and `printf -v x '%(%T)T' -1` took **12 ms** on this machine. For a script that logs thousands of lines the difference matters; for ordinary scripts clarity wins. It is bash-only.
- `logger` sends messages to the system log; it existed on my machine (`logger present? yes`; I did not read where it came from or test where the messages land). Under systemd, the documented behaviour is that a service's stdout and stderr go to the journal; the `linux.systemd` lesson is where that gets tested.

**Redirecting the whole script's output, carefully.** `exec > >(tee -a run.log) 2>&1` at the top of a script copies everything to a log, but it is **asynchronous**: `tee` runs in the background. In my run the script ended, the next command found **no `run.log`** (`0 line(s)`), and the output lines appeared on the terminal *after* the shell had moved on; half a second later the file had 2 lines. Alternatives that are synchronous: wrap the work in `{ ...; } 2>&1 | tee -a run.log` (the log had 2 lines immediately), restore the descriptors and `wait` at the end, or simply run the script as `script > run.log 2>&1` from outside.

## Lock files: one copy at a time

Two copies of a backup or cron job running at once can corrupt data. Three techniques I tried:

1. **`noclobber`:** `( set -C; echo $$ > job.lock )` succeeds only if the file does not exist (the second try: `cannot overwrite existing file`). Atomic creation, but **stale after a crash**.
2. **`mkdir job.lock.d`**: atomic too (`File exists` the second time). Same staleness problem.
3. **`flock`** (util-linux; present on my machine): the kernel holds the lock and **releases it automatically** when the process dies.

```bash
exec 9>/var/lock/myjob.lock       # open a descriptor on the lock file
flock -n 9 || { echo "another instance is running" >&2; exit 1; }
# ... work; the lock is held until the script exits
```

With two copies, the first printed `got the lock` and the second printed `another instance is running`. `flock -n` fails at once, `flock -w 3` waits up to 3 seconds, and `flock lockfile command` runs a command under the lock.

**The stale lock** (technique 1): I killed a script with `kill -9` while it held a noclobber lock. The next run printed `locked by PID 810`, and **PID 810 was no longer alive**. `kill -0 PID` (does the process exist?) is how a script can detect a stale lock; the lock file alone cannot.

**A `flock` surprise:** after `kill -9` of the script, I could **not** take the lock (`no`), because the script's child `sleep 30` had **inherited descriptor 9** and kept the lock alive; once the stray `sleep` was gone, the lock was free (`yes`). Starting the child as `sleep 30 9>&-` (closing the descriptor for it) released the lock immediately when the script died (`yes`). Close the lock descriptor for long-running children you start.

## Where is my script?

`$0` is how it was **started**, not an absolute path:

```text
./bin/where.sh          -> $0=./bin/where.sh   dirname=./bin
./link.sh (a symlink)   -> $0=./link.sh        dirname=.    (the link's folder, not the real one)
```

To find files next to the script, use `BASH_SOURCE[0]` and **quote everything**:

```bash
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)       # absolute folder of the script (symlinks not resolved)
real=$(realpath "${BASH_SOURCE[0]}")                      # the real file, links resolved
```

Facts: through a symlink the folder pattern above gave the **link's** folder; `realpath` gave the real file in `dir with spaces/bin/`. **`cd $(dirname $0)` without quotes failed** for a path containing a space (`cd: too many arguments`). When a script is **sourced**, `$0` is the *caller's* name but `BASH_SOURCE[0]` is the sourced file's own path.

### A script that is also a library

```bash
helper() { echo "helper called"; }
main()   { echo "main running with: $*"; helper; }
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
```

Executed (`bash lib.sh a b`) it ran `main`; sourced (`. ./lib.sh`) it only defined the functions, which a caller could then use. This also makes functions **testable**.

### `source` and the dot command

In bash `. plainlib.sh` (a bare name) **found the file in the current folder**; in **dash** it did not: `.: plainlib.sh: not found`, because POSIX shells search `PATH` for a bare name. `. ./plainlib.sh` worked in dash, and so did `PATH=.:$PATH` (not a safe habit). `bash --posix` also refused the bare name. **Always write `. ./lib.sh` or `. "$here/lib.sh"`.**

## File descriptors and `exec`

`exec` with only redirections changes the shell's own descriptors:

```bash
exec 3> fd3.txt; echo "to fd 3" >&3; echo "second" >&3; exec 3>&-     # open, write twice, close
exec 4< fd3.txt; read -r l1 <&4; read -r l2 <&4; exec 4<&-            # two reads from the same open file
{ echo out; echo err >&2; } > both.txt 2>&1                           # a whole group, both streams, one file (2 lines)
```

A descriptor opened with `exec` stays open across commands (the two `read` calls got the first and second lines), which is the basis of the lock-file technique above.

## Putting it together: a script skeleton

```bash
#!/usr/bin/env bash
set -u
umask 077

tmp=""     # global on purpose: the EXIT trap runs after main returns, when a local would be gone

usage() { printf 'usage: %s [-v] FILE\n' "${0##*/}" >&2; exit 2; }
die()   { printf '%s: %s\n' "${0##*/}" "$*" >&2; exit 1; }

main() {
    local OPTIND=1 verbose=0 opt
    while getopts ":vh" opt; do
        case $opt in
            v) verbose=1 ;;
            h) usage ;;
            *) usage ;;
        esac
    done
    shift $((OPTIND - 1))
    [ $# -eq 1 ] || usage

    tmp=$(mktemp -d) || die "cannot create a temp directory"
    trap 'rm -rf "$tmp"' EXIT

    exec 9>"${TMPDIR:-/tmp}/${0##*/}.lock"
    flock -n 9 || die "another instance is running"

    [ -r "$1" ] || die "cannot read '$1'"
    (( verbose )) && printf 'processing %s\n' "$1" >&2
    # ... the real work, in "$tmp" ...
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
```

I ran this skeleton (`tests/verification/bash/run-skeleton.sh`): no arguments, `-h` and an unknown option each printed the usage line and exited **2**; a missing file printed `cannot read '/nonexistent'` and exited **1**; a normal run printed `done: 3 lines`; a **second copy started while the first was running** printed `another instance is running` and exited 1; and no temp directories were left behind.

**It did not work the first time, and the reason is the lesson.** My first version declared `local tmp` inside `main`. The EXIT trap runs **after `main` has returned**, when that local no longer exists: with `set -u` the trap printed `tmp: unbound variable` and the temp directory **was left behind** (1 leftover). A variable used by an `EXIT` trap must be **global** (hence `tmp=""` at the top). Cleanup code that fails silently is worse than none, so *test the cleanup path*, as in practice item 7.

The next lessons (`bash-robust-scripts`) add `set -e` and `pipefail` with their limits, testing and debugging.

## Reading an unknown script (functions and flow)

- **A function that shadows a command** (`ls() {...}`, `cd() {...}`, `rm() {...}`, `sudo() {...}`) changes what later lines mean. Search for `name()` and `function name` first.
- **`trap` lines:** what runs at exit, and is it cleanup or something else (an `EXIT` trap that runs a downloaded file)?
- **Temp files named from `$$`, the date or a fixed path in `/tmp`** are a symlink-attack surface; `mktemp` is the safe form.
- **`export -f`, `source "$var"`, `. "$1"`** run code chosen at run time.
- **A lock or PID file with no liveness check** will block forever after a crash.
- **Here-documents with an unquoted delimiter** containing `$` or backticks will expand them; one that writes into `/etc`, a crontab or `sudoers` deserves a careful read.

## Common mistakes

- Assigning a function's "result" to a global without saying so; leaking loop variables (no `local i`).
- `local x=$(cmd)` hiding `cmd`'s failure, and `local a=1 b=$a` in one statement.
- Using `exit` in a function that should `return`, or `return` in the main script outside a function.
- Forgetting `local OPTIND=1` when calling `getopts` twice.
- Expecting `getopts` to handle `--long` options or options after operands.
- Ignoring `--` and unknown options.
- An unquoted here-document delimiter around text that contains `$`.
- A space or tab before the here-document delimiter (or tabs when you used `<<-` with spaces).
- Predictable temp names (`/tmp/x.$$`); not removing temp files on every exit path.
- Assuming an EXIT trap runs after `kill -9`.
- Testing a signal handler only in the foreground; backgrounded scripts start with `SIGINT` ignored.
- A noclobber or `mkdir` lock with no stale-lock check; a `flock` descriptor inherited by a long-running child.
- `cd $(dirname $0)` unquoted; `. lib.sh` (bare name) in a portable script.
- `exec > >(tee ...)` and then reading the log right away.

## Practice

1. Write `square`, `is_even` and `describe` (prints the number and whether it is even) and use all three ways of getting a result: stdout, a global and a nameref.
2. Demonstrate dynamic scoping with two functions, then fix the leak so the callee cannot read the caller's local.
3. Write a function that returns status `44` via `return 300`, and explain why. Then change it to print the 300 instead.
4. Write `backup.sh` with `getopts` for `-v`, `-n COUNT` and `-o DIR`, a usage message on stderr and exit status `2` for bad usage. Call the parsing function twice and show why `local OPTIND=1` is needed.
5. Add `--output=FILE` and `--` support with a manual loop and show how `--bogus` is rejected.
6. Write a here-document that creates a config file with **one** expanded variable and **one** literal `$HOME`, in a single document.
7. Write a script that creates a private temp directory, writes to it, and removes it in an EXIT trap. Prove the directory is gone after `exit 1`, after `set -e` aborts, and after `kill -TERM`. Then show it is **not** removed after `kill -KILL`.
8. Reproduce the symlink attack on `/tmp/x.$$` in a **temp folder you own**, then show `mktemp` and `set -C` each prevent it.
9. Write a cron-safe script with a `flock -n` lock. Start two copies. Then start a child with and without `9>&-`, `kill -9` the parent, and explain the difference.
10. Make a script that is also a library with a `BASH_SOURCE`/`$0` guard, and source it from another script in a **different folder with a space in its name**.
11. **Read this and list every problem:**

    ```bash
    #!/bin/bash
    tmp=/tmp/report.$$
    trap "rm -f $tmp" EXIT
    cd $(dirname $0)
    . helpers.sh
    while getopts "v" o; do verbose=1; done
    result=$(compute $1)
    local count=$(wc -l < $1)
    echo "done" > $tmp
    cat $tmp | tee /var/log/report.log
    exit $count
    ```

    **Answer.** `#!/bin/bash` is acceptable here: the script uses bash features (`local`, `$(...)`, `[[`-style habits), and a shebang that names bash is exactly right (`#!/usr/bin/env bash` is an equally good spelling, useful where bash is not in `/bin`). What would be **wrong** is `#!/bin/sh` on this script. `tmp=/tmp/report.$$` is a **predictable** name (symlink attack): use `mktemp`. `trap "rm -f $tmp"` expands `$tmp` *when set* (fine here) but is fragile with spaces: single quotes and `"$tmp"` are safer. `cd $(dirname $0)` is **unquoted** (breaks with spaces) and `$0` is wrong through symlinks: use `"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`. `. helpers.sh` is a bare name: bash finds it in the current folder (and, after the `cd`, the script's folder), dash would not, and the bash manual says `PATH` is searched first for a name without a slash, so it could load a **different** `helpers.sh` (I tested the cwd fallback, not the `PATH` order): write `. ./helpers.sh`. `getopts "v"` with no `:` handles errors noisily, ignores arguments and sets `verbose` but never shifts (`shift $((OPTIND-1))`); `OPTIND` is not local. `$(compute $1)` is unquoted. `local count=...` is **outside a function** (an error in bash) and `$(wc -l < $1)` is unquoted and hides failures (`local x=$(cmd)`). `cat $tmp | tee ...` is a useless `cat` and `$tmp` is unquoted. `exit $count` exits with a *line count*, which wraps modulo 256 and means nothing as a status. The script also never checks `$#` or that `$1` is readable, and never prints errors to stderr.

## Check your understanding

1. What is the difference between a function's status and its output, and how do you get both?
2. Why can a callee read a caller's `local` variable in bash?
3. What does `return 300` give, and why?
4. Why can a second call to a function that uses `getopts` parse nothing, and what is the fix?
5. How does `<<'EOF'` differ from `<<EOF`, and what does `<<-` strip?
6. What does an EXIT trap see as `$?`, and when does it not run?
7. Why is `/tmp/report.$$` unsafe, and what replaces it?
8. Why did my `INT` trap not run for a script started in the background?
9. Why is `flock` better than a noclobber lock file, and what descriptor trap can still defeat it?
10. Why is `. lib.sh` not portable, and what do you write instead?

**Expected answers:** (1) the status is the last command's (or `return N`), the output is what it prints; capture the output with `$(...)` and read `$?` in the same statement: `val=$(f); st=$?`; (2) bash uses dynamic scope: `local` is visible to everything the function calls; (3) `44`: statuses are 0 to 255, so 300 wraps modulo 256; print large numbers instead; (4) `OPTIND` is global and still points past the earlier arguments; declare `local OPTIND=1` in the function; (5) a quoted delimiter turns off all expansion in the text; an unquoted one expands variables, `$(...)` and `$((...))`; `<<-` strips leading tabs; (6) the status the script was exiting with; it does not run after `SIGKILL` (or a crash or power loss); (7) the name is predictable, so an attacker can plant a symlink and make your script write through it; use `mktemp` (and a private directory); (8) signals ignored when a script starts cannot be trapped, and a non-interactive shell starts background jobs with `SIGINT` ignored; (9) the kernel releases the lock when the process dies, so no stale lock; a child that inherits the lock descriptor keeps the lock alive after the parent is killed; close it for the child (`9>&-`); (10) POSIX shells such as dash search `PATH` for a bare name and report `not found`; write `. ./lib.sh` or `. "$here/lib.sh"`.
