*Draft for owner review.* A script that works on the day you write it is easy. A **robust** script still does the right thing when a file is missing, a variable is empty, a name has a space in it, the network drops, the user presses Ctrl+C, or it is run twice. This lesson teaches how bash scripts fail, what **`set -e`**, **`set -u`** and **`set -o pipefail`** really do (and where they silently do nothing), how to clean up after yourself, how to make a script **idempotent**, how to **debug** one, how to use **ShellCheck**, and the **security traps** that matter when a script runs with other people's data or with administrator rights. It is also the lesson to read before you run a script somebody else wrote.

**What was tested, and where.** Everything below was run on **Ubuntu 26.04 (WSL2)** with **bash 5.3.9** and **ShellCheck 0.11.0**, from `tests/verification/bash/rb1.sh`, `rb2.sh` and `rb3.sh` (the template and the test harness at the end). `sleep`, `timeout`, `mktemp`, `stat` are the ones on that machine (several coreutils there are the Rust **uutils** versions; see `foundations.bash-text-processing`). **Not tested:** bash older than 5 (the lesson says where behaviour differs only when I could confirm it; for example, I did not test that an empty array under `set -u` was an error before bash 4.4, so I do not claim it), other shells' `set -e` behaviour (dash, busybox ash, zsh; the rules differ in corners and the POSIX text is the reference), macOS, and Windows Git Bash. Commands use `bash`; where a snippet would also work in POSIX `sh` it says so, and anything with `[[ ]]`, arrays, `pipefail`, `local` or `${var,,}` is bash only (`foundations.shells-and-posix`).

Reference reading for the whole lesson: the [Bash Reference Manual, The Set Builtin](https://tiswww.case.edu/php/chet/bash/bashref.html#The-Set-Builtin) and [Bash Variables](https://tiswww.case.edu/php/chet/bash/bashref.html#Bash-Variables) (for `PS4`, `BASH_XTRACEFD`); the [POSIX Shell Command Language](https://pubs.opengroup.org/onlinepubs/9799919799/utilities/V3_chap02.html); Greg's wiki [BashFAQ/105: why `set -e` does not do what you expect](https://mywiki.wooledge.org/BashFAQ/105) and [BashPitfalls](https://mywiki.wooledge.org/BashPitfalls); [ShellCheck](https://www.shellcheck.net/). The pages load (checked 2026-11-21); I did not read the manual's `set` section in full, so every behaviour claim below rests on my own test output, not on my paraphrase of the manual.

## What "robust" means

A robust script:

1. **Stops, or handles the problem, when something fails**, instead of carrying on with wrong data.
2. **Refuses to guess**: an unset variable or a missing argument is an error, not an empty string.
3. **Cleans up** temporary files and half-written output, even when interrupted.
4. Can be run **twice** and ends in the same state (idempotent), or says clearly that it cannot.
5. **Says what it is doing** on request (verbose, dry-run) and **where it failed** when it does.
6. Treats every file name, argument and line of input as **data, never code**.

Bash does the opposite by default: a failing command is ignored and the script goes on, an unset variable expands to nothing, and a failure in the middle of a pipeline is hidden.

```text
$ bash -c 'false; echo after'
after
$ bash -c 'echo "[$undefined]"'
[]
$ bash -c 'false | true; echo "rc=$?"'
rc=0
```

The three switches below change this. They help, but they are **not a safety net**: they have exceptions that surprise people, and the most robust code **checks the commands that matter explicitly**.

## `set -e` (errexit): useful, with exceptions

`set -e` makes the shell **exit when a command fails**. "Fails" means a non-zero exit status, with these exceptions. Each row was run (`rb1.sh`); `rc` is the script's exit status and the text is its output.

| Script | rc | Output | What it shows |
|---|---|---|---|
| `false; echo after` | 0 | `after` | no `set -e`: carries on |
| `set -e; false; echo after` | 1 | *(none)* | stops at a bare failure |
| `set -e; false && echo x; echo after` | 0 | `after` | a failure on the **left of `&&`** does not stop it |
| `set -e; true && false; echo NOT-REACHED` | 1 | *(none)* | but a failure as the **last** command of an `&&` list does |
| `set -e; false \|\| echo handled; echo after` | 0 | `handled`, `after` | a failure before `\|\|` is "handled" |
| `set -e; if false; then :; fi; echo after` | 0 | `after` | the **condition** of `if` or `while` never exits |
| `set -e; ! false; echo after` | 0 | `after` | a **negated** command never exits |
| `set -e; ((i++))` with `i=0` | 1 | *(none)* | `((i++))` returns 1 when the old value was 0, so it exits |
| `set -e; i=0; i=$((i+1)); echo "after i=$i"` | 0 | `after i=1` | assignment form does not have the problem |
| `set -e; grep -q zzz /etc/passwd; echo NOT-REACHED` | 1 | *(none)* | "no match" is exit status 1, so it counts as failure |
| `set -e; read -r x < /dev/null; echo NOT-REACHED` | 1 | *(none)* | `read` at end of file returns 1 |

### The function trap

This is the exception that does the most damage. **`set -e` is ignored inside a function that is called as part of a condition** (in an `if`, before `||`, on the left of `&&`), including every command inside that function:

```text
set -e; f() { false; echo inside; }; f; echo after
   -> rc=1, no output                (called plainly: stops)
set -e; f() { false; echo inside; }; if f; then echo yes; fi; echo after
   -> rc=0   inside | yes | after    (called in an if: false is ignored, "inside" runs)
set -e; f() { false; echo inside; }; f || echo handled; echo after
   -> rc=0   inside | after          (the || is never needed: f "succeeded")
```

So a function that works when called plainly can quietly stop checking its own commands when somebody later writes `if f; then ...`. **Do not rely on `set -e` inside functions you also use as conditions.** Check inside the function (`cmd || return 1`).

### The "last command is a test" trap

A function or script whose **last command is `[ ... ] && something`** returns 1 when the test is false, and under `set -e` that *is* the failure:

```text
set -e; f() { [ -f /nonexistent ] && echo yes; }; f; echo NOT-REACHED   -> rc=1, no output
set -e; f() { if [ -f /nonexistent ]; then echo yes; fi; }; f; echo after  -> rc=0   after
set -euo pipefail; f() { [[ -n "" ]] && echo yes || true; }; f; echo after -> rc=0   after
```

The fix is an `if` (it says what you mean) or `|| true` (it says "this is allowed to fail"). A related surprise in a loop: `for i in 1 2; do [ "$i" = 1 ] && echo one; done; echo NOT-REACHED` prints `one` **and then `NOT-REACHED`** with rc 0: the test in the `&&` list failed on the second pass, and it did not stop the script, because a failure on the left of `&&` does not.

### Subshells, command substitution, `local`

```text
set -e; ( false; echo in-subshell ); echo NOT-REACHED         -> rc=1       (the subshell fails, then the script does)
set -e; if ( false; echo in-subshell ); then echo yes; fi      -> in-subshell | yes   (in a condition: ignored again)
set -e; x=$(false); echo NOT-REACHED                           -> rc=1       (plain assignment: stops)
set -e; echo "[$(false)]"; echo after                          -> [] | after   (the substitution's status is lost)
set -e; f() { local x=$(false); echo "local survived rc=$?"; }; f
   -> local survived rc=0          (local itself succeeded, hiding the failure)
set -e; f() { local x; x=$(false); echo NOT-REACHED; }; f      -> rc=1       (declare first, then assign)
set -e; export X=$(false); echo after                          -> after      (same trap with export, readonly, declare)
```

**Declare, then assign**: `local x; x=$(cmd)`, never `local x=$(cmd)`. (ShellCheck warns about this one, SC2155.)

Inside `$( )`, `set -e` is **not inherited** by default:

```text
set -e; x=$(false; echo ran); echo "x=[$x]"                   -> x=[ran]
set -e; shopt -s inherit_errexit; x=$(false; echo ran); echo "x=[$x]"   -> rc=1, no output
```

`shopt -s inherit_errexit` makes substitutions obey `-e` (tested on 5.3.9; I did not test older versions, so check `help shopt` on yours). Use it in scripts that depend on `-e`.

### Does the setting reach other scripts?

```text
child.sh = "false; echo child-continued"
set -e; bash child.sh; echo "parent after child rc=$?"         -> child-continued | parent after child rc=0
(the child is a new bash: it has its own settings; and its exit status was 0 because echo was its last command)
set -e; . ./lib.sh  (lib.sh = "false; echo lib-continued")     -> rc=1   (sourced code runs in YOUR shell: it obeys -e)
set -e; export SHELLOPTS; bash -c "false; echo child-continued"; echo parent
   -> rc=1, no output   (an exported SHELLOPTS makes child bash processes inherit -e)
```

Sourcing a file also shares **`set -u`**: a file containing `set -u` changes the shell that sourced it (tested: the caller then died on an unset variable). **A library file should not change the shell options of whoever includes it.**

### What to do about all this

`set -e` is a **last line of defence**: it stops the script when you forgot to check something. Treat it like a seat belt, not like steering. For commands whose failure you can predict, say what to do:

```bash
cd "$dir" || die "cannot enter $dir"           # explicit, and it works with or without set -e
if ! grep -q "$key" "$file"; then ...         # tests the status on purpose
grep -q "$key" "$file" || true                # "no match" is allowed here
```

The Greg's wiki page cited above lists more cases; the take-away is that **you cannot predict from reading a line whether `set -e` will stop it**, so do not write code whose correctness depends on that.

## `set -u` (nounset): catch typos and missing arguments

```text
echo "[$undefined]"                    -> []                                     (no -u)
set -u; echo "[$undefined]"            -> rc=1   undefined: unbound variable
set -u; echo "Hi $nmae"                -> rc=1   nmae: unbound variable          (a typo, caught)
set -u; echo "[$1]"                    -> rc=1   $1: unbound variable            (missing argument)
set -u; echo "[${1-none}]"             -> [none]                                 (a default stops the error)
set -u; echo "[${undefined-}]"         -> []                                     (default: empty)
set -u; [ -z "$v" ] && echo empty      -> rc=1   v: unbound variable
set -u; [[ -v v ]] || echo "unset (tested safely)"   -> unset (tested safely)    (-v tests without reading)
set -u; f() { local x; echo "[$x]"; }; f      -> rc=1   x: unbound variable      (declared is not set)
set -u; f() { local x=; echo "[$x]"; }; f     -> []                              (set to empty)
set -u; a=(x); echo "[${a[3]}]"        -> rc=1   a[3]: unbound variable
set -u; a=(); echo "[${a[@]}]"         -> []                                     (bash 5.3.9: no error)
set -u; for a in "$@"; do echo x; done; echo "[ok]"   -> [ok]                    (no arguments: fine)
```

The "empty array" row is **bash 5.3.9 behaviour**; I did not test older versions, and portable scripts avoid depending on it.

The rule that goes with it: **write the default you mean** (`${var-}` empty if unset; `${var:-default}` default if unset *or empty*; `${var:?message}` **abort with a message** if unset or empty). That last form is the safest guard for paths:

```text
dir=; echo "would run: rm -rf $dir/*"                  -> would run: rm -rf /*          (no -u: the empty variable becomes "/")
set -u; echo "would run: rm -rf $dir/*"                -> rc=1   dir: unbound variable
dir=; echo "rm -rf ${dir:?refusing: dir is empty}/*"   -> rc=1   dir: refusing: dir is empty
dir=/tmp/x; echo "rm -rf ${dir:?refusing}/*"           -> rm -rf /tmp/x/*
```

`set -u` catches an **unset** variable but not an **empty** one that is *set*; `${var:?}` catches both. Use it in front of every `rm -rf`.

## `set -o pipefail`: do not hide a failing stage

The exit status of a pipeline is normally that of the **last** command only.

```text
false | true; echo "rc=$?"                          -> rc=0
set -o pipefail; false | true; echo "rc=$?"         -> rc=1
false | true | false; echo "${PIPESTATUS[*]}"       -> 1 0 1       (every stage, bash only)
```

`PIPESTATUS` (bash) holds the status of **each** stage; copy it immediately (`rc=("${PIPESTATUS[@]}")`), because the next command overwrites it. `pipefail` and `PIPESTATUS` are bash features; I did not test whether another `sh` accepts `set -o pipefail`, so check yours (`foundations.shells-and-posix`).

### The SIGPIPE surprise

When the **reader exits early**, the writer gets SIGPIPE and dies with status **141** (128 + 13). Under `pipefail` this makes a healthy pipeline "fail":

```text
set -o pipefail; yes | head -1; echo "rc=$?  PIPESTATUS=${PIPESTATUS[*]}"
   -> y | rc=141  PIPESTATUS=141 0
set -eo pipefail; yes | head -1; echo NOT-REACHED          -> y      rc=141 (the script stopped)
set -o pipefail; yes | head -1 || true; echo after         -> y | after
```

The same thing happens with `grep -q` at the end of a pipeline (`foundations.bash-text-processing`). Fixes: let the reader consume everything, capture the output first, or accept it for that one line (`|| true`, or `{ producer | consumer; } || [ $? = 141 ]`).

## Reporting failures: `trap ... ERR`

An `ERR` trap runs when a command fails (with the same exceptions as `set -e`). It is the natural place to print **where** the script failed:

```text
trap "echo ERR at line \$LINENO" ERR; false; echo after                  -> ERR at line 1 | after
trap "echo ERR at line \$LINENO" ERR; f() { false; }; f; echo after     -> ERR at line 1 | after
set -E; trap "echo ERR at line \$LINENO" ERR; f() { false; }; f; echo after
   -> ERR at line 1 | ERR at line 1 | after        (-E: the trap also fires inside functions)
set -eE; trap 'echo "failed at line $LINENO: $BASH_COMMAND" >&2' ERR; ls /nonexistent 2>/dev/null; echo NOT-REACHED
   -> rc=2   failed at line 1: ls /nonexistent 2> /dev/null
trap "echo ERR" ERR; if false; then :; fi; false || true; echo after     -> after    (conditions never fire it)
f() { caller 0; }; f                                                     -> 1 main s.sh   (line, function, file)
```

Without `set -E` (`errtrace`), the trap does **not** fire for failures inside functions (the second row printed it once for the main script; the third, with `-E`, twice). Use `set -Eeuo pipefail` and a trap that prints `$LINENO` and `$BASH_COMMAND`, as in the template at the end.

### The cleanup trap that changes your exit status

An `EXIT` trap runs on every exit, normal or not, and it sees the status that is about to be returned:

```text
set -e; trap "echo trap-saw-rc=\$?" EXIT; false                -> rc=1   trap-saw-rc=1
trap "false; echo cleanup-ran" EXIT; exit 0                    -> rc=0   cleanup-ran    (a failing cleanup, no set -e: ignored)
trap "exit 9" EXIT; exit 0                                     -> rc=9                  (an explicit exit in the trap wins)
```

Now put the two together. This is the **first draft** of the cleanup function in the template at the end, run under `set -Eeuo pipefail` (`rb3.sh`):

```text
cleanup() { [ -n "$tmp" ] && rm -f -- "$tmp"; }       # tmp is empty, so the test "fails" and returns 1

./tool-buggy.sh            -> rc=1   Usage: tool-buggy.sh [-n] [-v] FILE KEY=VALUE | failed at line 1: exit 2
./tool-buggy.sh -n c.conf q=1   -> rc=1   DRY: would set q=1 in c.conf | failed at line 1: exit 0
```

**Every run exited 1.** The script meant to exit 2 (usage) and 0 (dry run). The cleanup function ran at exit, its last command was a false test, `set -e` and the ERR trap fired inside the `EXIT` trap, and the status was overwritten. Nothing was *wrong with the output*, which is why a test of the exit status caught it and a glance at the screen did not. The fix is the form that cannot return a failure:

```bash
cleanup() { if [ -n "$tmp" ]; then rm -f -- "$tmp"; fi; }
```

**Write cleanup functions with `if`, end them with a command that succeeds, and test the exit status.**

## Cleanup, signals and exit codes

The shell turns a signal into an exit status of **128 + the signal number** (TERM 15 → 143, INT 2 → 130, KILL 9 → 137, PIPE 13 → 141). The list of signals is in [signal(7)](https://man7.org/linux/man-pages/man7/signal.7.html). Tested, with the script run in the background and signalled from outside:

```text
script: tmp=$(mktemp -d); cleanup() { rm -rf "$tmp"; ... }; trap cleanup EXIT; trap 'echo "caught TERM"; exit 143' TERM; sleep 30 & wait $!
kill -TERM   -> caught TERM | cleanup ran, tmp gone: yes     rc=143
kill -KILL   -> (nothing printed; the EXIT trap did not run)  rc=137
no TERM trap -> EXIT trap ran                                 rc=143    (the default action ends the script, EXIT still runs)
TERM while a foreground child ("sleep 30") is running -> EXIT trap ran     rc=143
trap "echo got INT; exit 130" INT; kill -INT $$       -> got INT                rc=130
```

- **`kill -KILL` (and a power cut) cannot be trapped.** Cleanup that must survive them needs a different design (a stale-file check at the next start, a lock with the owner's PID).
- **`EXIT` is the one trap to rely on for cleanup**; it also runs on normal exit and on `exit` inside a `TERM` or `INT` handler. Setting `trap cleanup EXIT` right after you create the thing to clean up (not at the top of a 200-line script) keeps the trap honest. `trap - EXIT` clears it; `trap -p EXIT` shows it.
- **A background job of a non-interactive script ignores SIGINT.** I ran `bash -c "trap 'echo got INT' INT; sleep 2; echo finished" &` and sent it `kill -INT`: it printed `finished` and exited 0, `got INT` never appeared. If your tool starts workers with `&` and relies on Ctrl+C reaching them, test that it does.
- **`wait $!` form:** the tests above start the long command in the background and `wait` for it, because `wait` returns as soon as a trapped signal arrives. (The manual describes that a trap waits for a *foreground* command to finish; I did not test that case, so test it before relying on it.)
- **Time limits:** `timeout 1 sleep 5` returned **124** (timed out) ([timeout(1)](https://man7.org/linux/man-pages/man1/timeout.1.html)). Bound every network call and every wait that could hang.

A small **retry with a growing delay**, run on a command that fails twice:

```bash
retry() { local n=$1 delay=$2; shift 2; local i=1
  until "$@"; do
    [ "$i" -ge "$n" ] && { echo "giving up after $i tries" >&2; return 1; }
    echo "try $i failed, waiting ${delay}s" >&2; sleep "$delay"; i=$((i+1)); delay=$((delay*2))
  done; }
```
```text
try 1 failed, waiting 1s
try 2 failed, waiting 2s
succeeded on try 3
try 1 failed, waiting 0s
giving up after 2 tries          (rc=1)
```

## Idempotent scripts

A script is **idempotent** if running it again leaves the same end state and does no harm. Administrators run scripts more than once (a failed run, a second server, a config-management tool). Use commands that are idempotent by design, and **guard** the rest:

```text
mkdir d1; mkdir d1; echo after        -> mkdir: d1: File exists | after     (mkdir -p does not complain)
ln -s tgt l1; ln -s tgt l1            -> ln: Already exists; rc=1           (ln -sfn replaces it quietly: rc=0)
echo 'setting=on' >> naive.txt (twice) -> 2 copies of the line               (naive append)
grep -qxF "$line" conf.txt || echo "$line" >> conf.txt   (twice)  -> 1 line   (append only if missing)
```

The idempotence run in `rb2.sh`: `mkdir -p out/sub; ln -sfn out/sub link; grep -qxF ... || echo ... >>; [ -e flag ] || touch flag; rm -f gone.txt` executed twice printed the same `dirs=2 conf_lines=1 link=out/sub` both times.

| Do | Instead of |
|---|---|
| `mkdir -p`, `install -d` | `mkdir` that fails the second time |
| `ln -sfn target link` | `ln -s` |
| `rm -f file` | `rm file` (fails when it is already gone) |
| `grep -qxF "$line" file \|\| echo "$line" >> file` | blind `>>` |
| `id user >/dev/null 2>&1 \|\| useradd user` | `useradd user` |
| `cmp -s new old \|\| cp new old` | rewriting an unchanged file (and triggering a restart) |

### Write files atomically

If a script is killed while writing a config file, readers see half a file. Write a **temporary file in the same directory** and **rename** it over the target (a rename inside one file system is meant to be atomic; I did not test that by interrupting a rename):

```bash
tmp=$(mktemp "$target.XXXXXX")        # same directory, random name, mode 0600
trap 'rm -f -- "$tmp"' EXIT
printf 'new\n' > "$tmp"
mv -f -- "$tmp" "$target"
```
```text
new
leftover temp files: 0
```

[mktemp(1)](https://man7.org/linux/man-pages/man1/mktemp.1.html) creates the file with a random name and mode **600** (tested: `600`). `cp` or `>` straight onto the target is **not** atomic.

### A dry-run switch

Let a user (or you, at 2 a.m.) see what a script would do. Route every change through one function:

```bash
DRY=${DRY:-1}
run() { if [ "$DRY" = 1 ]; then printf 'DRY: %q\n' "$*" >&2; else "$@"; fi; }
run rm -- "a b.txt"
```
```text
DRY: rm\ --\ a\ b.txt
file still there (dry run)
file removed (real run)
```

`%q` prints the command in a form you could paste back into bash. A dry run only helps if **every** change goes through `run`; one stray `rm` outside it defeats it.

## Debugging

### `set -x` and `PS4`

`set -x` prints each command, after expansion, before it runs (to standard error). Default output for a small script (`rb2.sh`):

```text
+ f 3
+ local n=3
+ echo n=3
n=3
++ date +%Y
++ cut -c1-2
+ x=20
+ set +x
```

Each extra `+` is one level of nesting (a command substitution is `++`). The **prefix is the `PS4` variable**. Put the file, line and function in it and the trace becomes a map:

```text
$ PS4='+ ${BASH_SOURCE##*/}:${LINENO}:${FUNCNAME[0]:-main}: ' bash x1.sh
+ x1.sh:3:main: f 3
+ x1.sh:1:f: local n=3
+ x1.sh:1:f: echo n=3
n=3
++ x1.sh:4:main: date +%Y
++ x1.sh:4:main: cut -c1-2
+ x1.sh:4:main: x=20
+ x1.sh:5:main: set +x
```

- Turn tracing on for **one region** (`set -x ... set +x`), or for a whole run with `bash -x script.sh`.
- **The trace shows secrets.** `pw=hunter2; curl_stub --user "bob:$pw"` traced `+ pw=hunter2` and `+ curl_stub --user bob:hunter2`. Never leave `-x` on around credentials, and never send a trace to a shared log without reading it.
- `BASH_XTRACEFD` sends the trace to another file descriptor instead of stderr, so it stays out of the script's normal error output: `exec 9>trace.log; BASH_XTRACEFD=9; set -x` wrote `2` lines to `trace.log` and `hi` to the screen.
- `bash -v script.sh` prints each line **as read**, before expansion (`a=1` and `echo "$a"` appear, then `1`).

### `bash -n`: parse, do not run

```text
$ bash -n bad.sh            (an unfinished if)
bad.sh: line 3: syntax error: unexpected end of file from `if' command on line 1     rc=2
$ bash -n danger.sh         (contains: rm -rf /  -- valid syntax)
rc=0   (parsed only, nothing ran)
```

`bash -n` finds **syntax** errors only: it says nothing about whether the script is safe. It is a safe first look at a file you do not trust, because it does not run it.

## ShellCheck: a second pair of eyes

[ShellCheck](https://www.shellcheck.net/) is a static analyser for sh and bash scripts. It is **optional**: it is not installed by default on most distributions, install it from your package manager or download a release from the project's GitHub page. Version 0.11.0 on this test machine, run on a deliberately flawed script:

```bash
#!/bin/bash
dir=$1
cd $dir
for f in $(ls *.txt); do
  if [ $f == "a.txt" ]; then
    rm -rf $dir/tmp*
  fi
done
echo $undefined_var
cat file | grep foo | wc -l
```
```text
flawed.sh:3:1: warning: Use 'cd ... || exit' or 'cd ... || return' in case cd fails. [SC2164]
flawed.sh:3:4: note: Double quote to prevent globbing and word splitting. [SC2086]
flawed.sh:4:10: error: Iterating over ls output is fragile. Use globs. [SC2045]
flawed.sh:4:15: note: Use ./*glob* or -- *glob* so names with dashes won't become options. [SC2035]
flawed.sh:5:8: note: Double quote to prevent globbing and word splitting. [SC2086]
flawed.sh:6:12: note: Double quote to prevent globbing and word splitting. [SC2086]
flawed.sh:9:6: warning: undefined_var is referenced but not assigned. [SC2154]
flawed.sh:9:6: note: Double quote to prevent globbing and word splitting. [SC2086]
flawed.sh:10:12: note: Consider using 'grep -c' instead of 'grep|wc -l'. [SC2126]
```

Each code has a wiki page that explains the problem and the fix, for example [SC2086](https://github.com/koalaman/shellcheck/wiki/SC2086) (quote variables). The `-f gcc` option (used here) prints one line per finding. ShellCheck also **checks the dialect**: given a `#!/bin/sh` file that uses an array and `[[ ]]`:

```text
dial.sh:2:3: warning: In POSIX sh, arrays are undefined. [SC3030]
dial.sh:3:6: warning: In POSIX sh, array references are undefined. [SC3054]
dial.sh:4:1: warning: In POSIX sh, [[ ]] is undefined. [SC3010]
```

ShellCheck cannot know your intent, and it **does not catch everything** (it says nothing about the `cleanup` bug above: the template with the buggy cleanup is also clean). Treat a warning as "explain why this is fine or fix it"; if you disable one with `# shellcheck disable=SCnnnn`, write why on the line above.

## Security traps

When a script runs with **administrator rights** or processes **other people's data**, a bug is a vulnerability. All of these were run (`rb2.sh`).

**Names that start with a dash are options.** `touch ./-rf ./-n a b` then `echo *` gives `-n -rf a b`: a plain `rm *` would receive `-n -rf`. Put **`--`** before names (`rm -- "$f"`), or prefix globs with `./` (`rm ./*`). `rm -- -rf -n` removed them.

**Unquoted variables are split and globbed.** `for f in $(ls)` on a directory with `my file.txt` and `plain.txt` gives `[my][file.txt][plain.txt]`; `for f in *` gives `[my file.txt][plain.txt]`. Never parse `ls`; use a glob.

**Unquoted variables inside `[ ]` are code, not data.**

```text
x=;          [ $x = y ]   -> [: =: unary operator expected              (empty: the test is malformed)
x="-n";      [ $x ]       -> true                                       (data that looks like an option)
x="a = a";   [ $x = y ]   -> [: too many arguments                      (data that adds operands)
x="-f /etc/passwd"; [ $x ]  -> true                                     (the test of a FILE ran, chosen by the user)
x="-f /etc/passwd"; [ -n "$x" ]   -> non-empty (string test)            (quoted: it is just a string)
```

Quote every expansion, or use `[[ ]]` in bash (it does not split) (`foundations.bash-variables-and-expansion`).

**`eval` runs its argument as code.** `in="x; echo INJECTED"; eval "echo $in"` printed `x` and then `INJECTED`; `printf '%s\n' "$in"` printed the string. If you must build commands, build an **array** and run `"${cmd[@]}"`.

**`printf` and `echo` with data:** `printf "$in\n"` (data as the *format*) treats `%` sequences as instructions; `in="%s %s %s"` produced blanks instead of the text. Use `printf '%s\n' "$in"`. `in="-n"; echo "$in"` printed **nothing** (swallowed as an option); `printf '%s\n' "-n"` printed `-n`.

**`read` without `-r` eats backslashes**: reading `C:\temp\new` gave `[C:tempnew]`; with `-r` it gave `[C:\temp\new]`. Use `read -r` always.

**`"$@"` versus `$*`**: for `f "a b" c`, `"$@"` gave `[a b][c]` and unquoted `$*` gave `[a][b][c]`.

**`PATH` decides which program runs.** A directory you can write to, `.`, or an empty entry early in `PATH` lets someone replace `ls`:

```text
PATH=/tmp/x/hijack:$PATH; ls         -> HIJACKED ls
command -v ls                        -> /tmp/x/hijack/ls               (shows which one will run)
PATH=/usr/bin:/bin; export PATH      -> the real ls                    (first lines of a privileged script)
ls() { echo "function ls"; }; ls; command ls / >/dev/null    -> function ls | (command ls ran the program)
```

Set `PATH` at the top of any script that runs with extra privileges (`foundations.bash-basics` and the owner rule in the course plan: name external programs unambiguously; `command -v` to check).

**Temporary files.** `/tmp/myscript.$$` is guessable (the number was `849`; anyone can create that name first, or as a symlink). Use `mktemp` (random name, mode `600`). `umask 077` makes files you create private (tested: `600`).

**Secrets leak three ways.** In the **trace** (`set -x`, above). In the **environment**: `export TOKEN=abc; bash -c 'echo child sees: $TOKEN'` printed `child sees: abc`, so every child process gets it. And on the **command line**, which other users can read:

```text
$ bash -c "sleep 3; :" prog --token=SECRET123 &
$ tr "\0" " " < /proc/$!/cmdline
bash -c sleep 3; : prog --token=SECRET123
```

Pass secrets by **file** (mode 600), **standard input**, or a file descriptor, not as arguments.

## Reading an unknown script before you run it

Before running something you did not write (a downloaded installer, a colleague's "fix.sh", a script in a ticket), spend five minutes:

1. **Read the first lines**: the shebang (`bash` or `sh`?), `set` options, `PATH`.
2. **Do not run it to find out.** `bash -n script.sh` checks syntax only; `shellcheck script.sh` flags the risky patterns; then **read it**.
3. Look for: `rm -rf`, `curl`/`wget` (and what is *done with the download*, especially piped to a shell), `sudo`/`doas`, `eval`, `chmod 777`, writing to `/etc` or a profile or `crontab`, `base64 -d |`, and any variable used in a path that could be empty.
4. **Find what it touches**: which paths, which network hosts, which accounts, which services.
5. **Run it as a normal user in a throw-away VM** (the course's lab VMs and snapshots are for exactly this). With `bash -x` and a good `PS4` you can follow it. Do not run it as an administrator first.

Downloading a script and piping it straight to a shell skips every one of these steps. It is the habit this course tries to remove.

## A robust script template, tested

This is the shape used for administration scripts, written for **bash** (`#!/usr/bin/env bash`; `/bin/bash` is equally correct). It keeps a `KEY=VALUE` line in a config file, **idempotent**, **atomic**, with a **dry-run** (`-n`) and **verbose** (`-v`) switch. It was run, tested with a harness, and checked with ShellCheck 0.11.0 (no findings).

```bash
#!/usr/bin/env bash
# tool.sh: keep a setting line in a config file (idempotent), with a dry-run switch.
# Usage: tool.sh [-n] [-v] FILE KEY=VALUE
set -Eeuo pipefail
PATH=/usr/bin:/bin; export PATH
umask 077

prog=${0##*/}
dry=0 verbose=0
tmp=

die()     { printf '%s: %s\n' "$prog" "$*" >&2; exit 1; }
usage()   { printf 'Usage: %s [-n] [-v] FILE KEY=VALUE\n' "$prog" >&2; exit 2; }
log()     { [ "$verbose" = 1 ] && printf '%s\n' "$*" >&2 || true; }
cleanup() { if [ -n "$tmp" ]; then rm -f -- "$tmp"; fi; }
on_err()  { printf '%s: failed at line %s: %s\n' "$prog" "$1" "$2" >&2; }
trap cleanup EXIT
trap 'on_err "$LINENO" "$BASH_COMMAND"' ERR
trap 'exit 143' TERM
trap 'exit 130' INT

while getopts ':nv' opt; do
  case $opt in
    n) dry=1 ;;
    v) verbose=1 ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ $# -eq 2 ] || usage

file=$1 setting=$2
case $setting in
  [A-Za-z_]*=*) key=${setting%%=*} ;;
  *) die "bad setting '$setting' (expected KEY=VALUE)" ;;
esac
[ -e "$file" ] || die "no such file: $file"
[ -w "$file" ] || die "not writable: $file"

if grep -qxF -- "$setting" "$file"; then
  log "already set: $setting"
  exit 0
fi

if [ "$dry" = 1 ]; then
  printf 'DRY: would set %s in %s\n' "$setting" "$file"
  exit 0
fi

tmp=$(mktemp "$file.XXXXXX")
# keep every other line, replace or append the key
awk -v key="$key" -v new="$setting" '
  index($0, key "=") == 1 { if (!done) print new; done = 1; next }
  { print }
  END { if (!done) print new }' "$file" > "$tmp"
mv -f -- "$tmp" "$file"
tmp=
log "set: $setting"
```

Its behaviour, run on a file `c.conf` that contains `a=1` and `b=2`:

```text
$ ./tool.sh                           -> rc=2   Usage: tool.sh [-n] [-v] FILE KEY=VALUE
$ ./tool.sh -n c.conf b=9             -> rc=0   DRY: would set b=9 in c.conf
$ ./tool.sh -v c.conf b=9             -> rc=0   set: b=9          (file now: a=1 b=9)
$ ./tool.sh -v c.conf b=9             -> rc=0   already set: b=9  (second run: nothing changes)
$ ./tool.sh -v c.conf c=3             -> rc=0   set: c=3          (file now: a=1 b=9 c=3)
$ ./tool.sh c.conf 'bad setting'      -> rc=1   tool.sh: bad setting 'bad setting' (expected KEY=VALUE)
$ ./tool.sh nofile.conf x=1           -> rc=1   tool.sh: no such file: nofile.conf
$ ./tool.sh -z c.conf x=1             -> rc=2   Usage: ...
read-only file                        -> rc=1   tool.sh: not writable: c.conf
leftover temp files                   -> 0
```

Why each line is there: `set -Eeuo pipefail` (stop, no unset, no hidden pipeline failure, ERR trap inside functions); `PATH` and `umask` first; **`die`** and **`usage`** are the only exits, with different statuses (1 and 2); **validate arguments and inputs before doing anything**; `grep -qxF --` (whole line, fixed string, `--` guards a value starting with a dash); the **idempotent** early exit; the **dry run** before any change; the **temporary file in the same directory**, `mv` to replace, `tmp=` afterwards so the cleanup has nothing left to do; **`cleanup` uses `if`** (the bug above); the `awk` values are passed with **`-v`**, not spliced into the program (`foundations.bash-text-processing`). The key-line match `index($0, key "=") == 1` treats the key as text, not as a regular expression.

### A test harness in fifteen lines

Test the **exit status and the message** for success and for each failure. This run is the one that found the cleanup bug (the first time it printed `3 passed, 5 failed`):

```bash
check() {  # check NAME EXPECTED_RC EXPECTED_OUTPUT_SUBSTRING COMMAND...
  local name=$1 want_rc=$2 want_out=$3; shift 3
  local out rc; out=$("$@" 2>&1); rc=$?
  if [ "$rc" = "$want_rc" ] && [[ $out == *"$want_out"* ]]; then
    pass=$((pass+1)); printf 'ok   %s\n' "$name"
  else
    fail=$((fail+1)); printf 'FAIL %s (rc=%s, output: %s)\n' "$name" "$rc" "$out"
  fi
}
```
```text
ok   usage on no arguments
ok   rejects a bad setting
ok   dry run says what it would do
ok   dry run changes nothing
ok   sets a new key
ok   second run is a no-op
ok   file has the line once
FAIL deliberately wrong test (rc=0, output: )
7 passed, 1 failed
```

The last line is a test that is **supposed** to fail, to prove that the harness can tell. A test suite that has never failed has not been shown to work. For larger projects, look at the **bats** framework (not covered here and not tested).

## Common mistakes

- **Trusting `set -e` to catch everything.** It ignores failures in conditions, after `||`, on the left of `&&`, and inside functions called that way.
- **`local x=$(cmd)`** (loses the status of `cmd`): declare first.
- **`cleanup() { [ -n "$x" ] && rm ...; }`**: returns 1, and overwrites the exit status when `set -e` and an `ERR` trap are on. Use `if`.
- **Using `set -u` and then reading `$1` or an optional variable without a default.**
- **`rm -rf "$dir/"*` with a variable that may be empty**: use `${dir:?}`.
- **`for f in $(ls)`** and **unquoted `$f`** (names with spaces, dashes or `*`).
- **Putting `set -x` around a password.**
- **Predictable `/tmp` names**, and `cp`/`>` straight onto a live file.
- **Starting a script with `#!/bin/sh` and using bash features** (`foundations.shells-and-posix`).
- **Not testing the failure paths**: the happy path of the template worked from the first run; the exit status of the usage case did not.

## Practice

Use a **copy** of anything you test on. Start with `rb`-style one-liners in a scratch directory.

1. **Predict, then run.** For each snippet, say whether `NOT-REACHED` prints, then check: `set -e; f() { false; true; }; f || echo x; echo NOT-REACHED`; `set -e; x=$(false); echo NOT-REACHED`; `set -e; local_demo() { local x=$(false); echo NOT-REACHED; }; local_demo`; `set -e; i=0; ((i++)); echo NOT-REACHED`.
2. **Reproduce the pipefail 141.** Show `yes | head -1` under `set -eo pipefail`, then give two fixes and run them.
3. **Reproduce the `PIPESTATUS` table** for `false | true | false` and write one line that saves it and reports which stage failed.
4. **Make a script idempotent.** Take a script that appends a line to a file, creates a directory and creates a user. Run it twice; fix it until the second run changes nothing and prints nothing alarming.
5. **Atomic update.** Write a script that rewrites a file through `mktemp` and `mv`; kill it with `kill -TERM` while it sleeps in the middle, and show that no temp file is left and the original is intact.
6. **Trace with a useful `PS4`.** Run a script with `bash -x` and `PS4` showing file, line and function; then use `BASH_XTRACEFD` to send the trace to a file.
7. **The cleanup bug.** Reproduce it: write the template with `cleanup() { [ -n "$tmp" ] && rm ...; }`, run it with no arguments, and show the exit status. Fix it and show the status is now 2.
8. **ShellCheck.** Run it on `flawed.sh` above; fix every finding; then run `bash -x` on your fixed version with a directory that contains `my file.txt` and a file named `-rf`.
9. **Break the path.** Create a `hijack/ls` script, put it first in `PATH`, show which `ls` runs with `command -v`, then fix the script's `PATH` line.
10. **Read an unknown script.** A teammate gives you a 40-line installer. List, from reading it (not running it), every file it writes, every program it downloads, and every command that needs `sudo`. Say which lines you would not run.
11. **Write your own harness.** Extend the 15-line `check` to also verify that a given file did **not** change; add a test for the read-only-file case of the template.
12. **Find the bug.** (a) `set -euo pipefail; cd "$1"; rm -rf "$2"/*` run as `./s.sh /data` (b) `tmp=/tmp/work.$$; mkdir $tmp; trap 'rm -rf $tmp' EXIT` (c) `grep -q root /etc/passwd | cat` under `pipefail`. Explain each failure and fix it.

## Check your understanding

Take the quiz for this lesson (it draws ten from the bank). After a wrong answer, reread the section named in the review line.
