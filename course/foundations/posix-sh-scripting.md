*Draft for owner review.* `posix-sh-basics` taught the **language**. This lesson teaches how to **write a script** in it that really is portable: argument parsing, lists without arrays, reading lines without the pipeline trap, strings without `${v/a/b}`, returning values, safe temporary files, cleanup, locking, atomic updates, and the **differences between the GNU tools and the BSD tools** that break "POSIX" scripts even when the shell language is perfect. It ends with a **tested template** and a **test harness that runs the same tests under dash, busybox ash and Chimera's FreeBSD `sh`**.

**What was tested, and where.** `tests/verification/posix/psh2.sh` (62 snippets) and `psh3.sh` (template and harness) were run in **dash 0.5.12-12ubuntu3** (Ubuntu 26.04 in WSL2, the reference), **busybox ash 1.35.0** (shell only; the commands it ran were the system's) and the **FreeBSD `sh` of chimerautils 15.1.2-r0** on the Chimera Linux lab VM, whose other tools are the **BSD** ones (`sed`, `grep`, `awk`, `stat`, `expr`, `find`, `mktemp`: see `docs/decisions/0009-chimera-lab.md`). On the Ubuntu side the external tools were the GNU ones (`sed`, `grep`, `find`, `awk`) and the Rust **uutils** coreutils (`foundations.bash-text-processing`). **ShellCheck 0.11.0** was used with `-s sh`. **Not tested:** `yash`, `ksh`, `zsh`, macOS, other versions of these shells, and any system where `/bin/sh` is bash; the harness was **not** run under bash on purpose. The three-shell comparison cannot prove a script portable: it is evidence, and dash is the strict one. References: the [POSIX Shell Command Language](https://pubs.opengroup.org/onlinepubs/9799919799/utilities/V3_chap02.html) and the [POSIX utilities](https://pubs.opengroup.org/onlinepubs/9799919799/idx/utilities.html) (the pages load; I did not read them for this lesson), the [FreeBSD sh(1)](https://man.freebsd.org/cgi/man.cgi?query=sh) and [dash(1)](https://manpages.debian.org/unstable/dash/dash.1.en.html) pages, and [ShellCheck](https://www.shellcheck.net/wiki/).

## The top of a portable script

```sh
#!/bin/sh
set -eu
PATH=/usr/bin:/bin; export PATH
umask 077
```

- `#!/bin/sh`: **POSIX only** from here on (the rule of this course). Never `#!/bin/sh` with a bashism.
- `set -eu`: the same two switches as in bash, **without** `pipefail`. `set -o pipefail` ran in all three shells here but ShellCheck flags it (SC3040) and I cannot promise every `sh` has it. `set -e` has the **same exceptions** as in bash (conditions, left of `&&`, before `||`): `set -e; f() { [ -f /nonexistent ] && echo yes; }; f; echo not-reached` stopped with status 1 in all three, and the `if` form printed `after`. Everything in `foundations.bash-robust-scripts` about those traps applies; `foundations.shells-and-posix` has the dash-specific ones.
- `set -u` stopped the script with **status 2** in all three shells (bash 5.3.9 gave 1 in the robust-scripts tests), and so did assigning to a `readonly` variable: do not test exact statuses of those across shells.
- `PATH` and `umask`: as in the bash lessons (a hijackable `PATH` is a hijackable `PATH` in any shell).
- `echo "$-"` after `set -eu` printed `ue` in dash and ash and **`eu`** in the FreeBSD `sh`: the order of option letters differs, so **never compare `$-` as a string**; test with `case $- in *e*) ...;; esac`.

## Arguments and options

Two portable ways. A hand-written loop (`case` and `shift`) gives you long options and full control:

```sh
verbose=0; out=
while [ $# -gt 0 ]; do
  case $1 in
    -v) verbose=1 ;;
    -o) [ $# -ge 2 ] || { echo "-o needs a value" >&2; exit 2; }; out=$2; shift ;;
    --) shift; break ;;
    -*) echo "unknown option $1" >&2; exit 2 ;;
    *) break ;;
  esac
  shift
done
echo "v=$verbose out=$out rest=$*"
```
```text
set -- -v -o result.txt -- -file       ->  v=1 out=result.txt rest=-file        (all three shells)
```

`getopts` is shorter and the usual choice (same result in all three shells):

```sh
verbose=0
while getopts vo: opt; do
  case $opt in v) verbose=1 ;; o) out=$OPTARG ;; *) exit 2 ;; esac
done
shift $((OPTIND - 1))
echo "v=$verbose out=$out rest=$*"          # set -- -v -o out.txt file1 file2  ->  v=1 out=out.txt rest=file1 file2
```

`getopts` prints its own message for a bad option (`Illegal option -z` in the test, and the loop carried on with status 0); in the silent mode (leading colon) the test showed `opt` as `?` with the bad letter in `OPTARG`, so keep a `*)` branch that exits. Other idioms (all three shells): a default under `set -u` is `${1:-none}`; a missing argument is `[ $# -ge 1 ] || { echo "usage: s.sh FILE" >&2; exit 2; }` (status 2, message on standard error).

## Lists without arrays

The positional parameters are the array. Build one with `set --`, loop with `"$@"`:

```sh
set --
for f in "a b" c "d e"; do set -- "$@" "$f"; done
printf '[%s]' "$@"; echo; echo "count=$#"
```
```text
[a b][c][d e]
count=3
```

If you need **your own** positional parameters back afterwards, do the list work **inside a function**, whose `$@` is its own. For file names, glob with `./*` so that a name starting with a dash is safe:

```sh
touch 'a b' ./-n x; for f in ./*; do printf '[%s]' "$f"; done; echo       ->  [./-n][./a b][./s.sh][./x]
```

For a **list in a string**, set `IFS` for one split and **restore it**, and turn globbing off if the data may contain `*`:

```text
set -f; IFS=,; v="a,b*,c"; set -- $v; echo "$# [$2]"                    ->  3 [b*]        (without set -f the b* would expand)
p=/usr/bin:/bin:/opt/x; old=$IFS; IFS=:; set -- $p; IFS=$old; echo "$# $2"   ->  3 /bin
```

## Reading lines, and the pipeline trap

```text
while IFS= read -r line; do printf "[%s]" "$line"; done < l.txt             ->  [one two][three]
printf "  a b  \n" | { read -r x; printf "[%s]\n" "$x"; }                   ->  [a b]          (leading and trailing blanks trimmed)
printf "  a b  \n" | { IFS= read -r x; printf "[%s]\n" "$x"; }              ->  [  a b  ]      (IFS= keeps them)
printf "a\nb" | while read -r l || [ -n "$l" ]; do printf "[%s]" "$l"; done  ->  [a][b]          (keeps an unterminated last line)
```

Use **`IFS= read -r`** to read a line exactly. In **dash, ash and the FreeBSD sh alike**, every part of a pipeline runs in a subshell (as in bash without `lastpipe`), so a counter set in a `while` loop at the end of a pipeline is lost:

```text
n=0; printf "a\nb\nc\n" | while read -r l; do n=$((n+1)); done; echo "n=$n"    ->  n=0     (all three)
```

Fixes that worked in all three:

```text
here-document:   n=0; while read -r l; do n=$((n+1)); done <<EOF       (the three lines a, b, c written inline, then EOF)
                 ...
                 EOF                                                    ->  n=3
temp file:       printf "a\nb\nc\n" > in.txt; while read -r l; do ...; done < in.txt     ->  n=3
braces:          printf "a\nb\nc\n" | { n=0; while read -r l; do n=$((n+1)); done; echo "n=$n"; }   ->  n=3
```

There is **no process substitution** (`< <(cmd)`) and no `lastpipe` in POSIX sh. Put everything that needs the result **inside the same braces**, or use a temp file.

## Strings without bashisms

```text
s=hello.txt; echo "${#s} ${s%.txt} ${s#hello} ${s%%.*}"                    ->  9 hello .txt hello
printf "%s\n" hello | cut -c2-4                                            ->  ell        (substring)
printf "%s\n" Hello | tr "[:lower:]" "[:upper:]"                           ->  HELLO      (case change)
printf "%s\n" a-b-c | sed "s/-/_/g"                                        ->  a_b_c      (replace)
case "hello world" in *world*) echo yes;; esac                             ->  yes        (contains)
case file.tar.gz in *.gz) echo gz;; esac; case file.tar.gz in file*) echo starts;; esac   ->  gz | starts
```

`case` replaces `[[ $s == *world* ]]`, `${s#prefix}` and `${s%suffix}` replace `${s/…}` for the common cases, and `cut`, `tr`, `sed` replace the rest, at the price of a process each (`foundations.bash-advanced` measures it: about 4 ms per process on the test machine, so keep them out of tight loops).

Numbers and text:

```text
[ 10 -gt 9 ] && echo num-gt                    ->  num-gt        (numeric tests: -eq -ne -lt -le -gt -ge)
[ "10" = "10.0" ] || echo strings-differ       ->  strings-differ  (= compares text)
echo $((7/2)) $((10%3))                         ->  3 1            (integers only; $((1.5+1)) is an error in all three)
printf "%03d %5.2f %-4s|\n" 7 3.14159 ab       ->  007  3.14 ab  |
expr length hello      ->  5 in dash and ash, **expr: syntax error** on Chimera       (use ${#s})
```

`printf` is the formatting tool; `expr` is not portable beyond simple arithmetic and `expr STRING : REGEX`.

### `echo` versus `printf`, again

```text
echo "a\tb"; echo "-n x"; echo -n y; echo        dash:  a<TAB>b | -n x | y        ash and Chimera:  a\tb | -n x | y
printf "%b\n" "a\tb"; printf "%s\n" "a\tb"       all three:  a<TAB>b | a\tb
v=-n; printf "%s\n" "$v"; echo "$v"              ->  -n  (printf)    and  nothing  (echo ate it as an option)
```

`printf '%s\n' "$value"` is correct for **every** value in **every** shell. `printf '%b'` interprets backslash escapes (use it when you want them). Keep `echo` for fixed plain strings with no backslashes and no leading dash.

### Returning a value from a function

No namerefs, no `printf -v`. Print the value and capture it, or set a global, or (carefully) `eval`:

```text
f() { printf "%s\n" "$(($1 * 2))"; }; r=$(f 21); echo "r=$r"                ->  r=42       (capture: a subshell, no side effects)
setvar() { eval "$1=\$2"; }; setvar out "a b c"; echo "[$out]"              ->  [a b c]    (eval: the NAME must be trusted; \$2 is expanded safely)
```

The `eval` form is safe **only if the variable name comes from you**, never from input: `eval "$1=..."` with `$1="x; rm -rf ~"` is code execution (`foundations.bash-robust-scripts`).

## Files, temporary files, cleanup, locks

```text
t=$(mktemp) && [ -f "$t" ] && echo file-ok; d=$(mktemp -d) && [ -d "$d" ] && echo dir-ok     ->  file-ok | dir-ok     (all three; mktemp is not in the shell, it is a program)
```

`mktemp` is **not POSIX** (it is on every system I used here, including Chimera's); **never build temp names from `$$`** (guessable). Cleanup with a trap on `EXIT`, `INT` and `TERM`:

```sh
tmp=$(mktemp)
cleanup() { rm -f "$tmp"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
```
```text
kill -TERM $$  ->  exit status 143 in all three shells; temp file removed in the slow-script test of psh3
                   (run directly under each of the three shells: rc=143 leftover=0)
f() { trap "echo cleanup-in-f" EXIT; return 5; }; f; echo "rc=$?"        ->  rc=5 | cleanup-in-f    (an EXIT trap set in a function runs when the SCRIPT exits, not when the function returns)
```

A **lock** that is atomic without `flock` (which is not POSIX): `mkdir` fails if the directory exists, and only one process can create it:

```text
mkdir lock 2>/dev/null && echo got || echo busy; mkdir lock 2>/dev/null && echo got || echo busy; rmdir lock    ->  got | busy
```

Remove the lock in the `EXIT` trap, and decide what to do about a lock left by a killed script (`SIGKILL` runs no trap).

**Atomic update**: write a temporary file in the **same directory**, then `mv` over the target:

```text
printf old > cfg; tmp=$(mktemp ./cfg.XXXXXX); printf new > "$tmp"; mv -f "$tmp" cfg; cat cfg      ->  new       (no temp file left: 0)
```

### `sed -i`, `stat -c` and other tool differences

POSIX standardises the shell **and** a list of utilities with **limited options**. GNU tools add many options; BSD tools add different ones. A script that uses a GNU option runs on Ubuntu and fails on Chimera (and on macOS and the BSDs):

| Command | GNU / uutils (Ubuntu, WSL) | BSD (Chimera) | Portable replacement |
|---|---|---|---|
| `sed -i "s/a/b/" f` | edits in place, rc 0 | **`sed: 1: "f | ": invalid command code f`**, rc 1, **file unchanged** | `sed "s/a/b/" f > f.new && mv f.new f` (worked everywhere) |
| `stat -c %a f` | `644` | `stat: unrecognized option: c` | `ls -l` and `cut`, or avoid |
| `expr length hello` | `5` | `expr: syntax error` | `${#s}` |
| `readlink -f lnk` | resolves | resolved (`/tmp`) | not POSIX; works on all three here, but check on others |
| `realpath /tmp/../tmp` | `/tmp` | `/tmp` | not POSIX; same remark |
| `find . -type f -exec echo {} +` | works | works | POSIX: use `-exec ... {} +` |
| `find -print0 \| xargs -0` | works | **worked** (`./a b`) | not POSIX, works on all three here |
| `grep -E`, `-F`, `-q`, `-x`, `-c` | works | works | all fine |
| `date +%Y-%m-%d`, `date -u +%H:%M` | works | works | fine |
| `mktemp`, `mktemp -d`, `mktemp ./cfg.XXXXXX` | works | works | not POSIX; ubiquitous |

The `sed -i` failure is the important one: BSD `sed` takes the **next word as the backup suffix** (so `"s/a/b/"` became the suffix and `f` became the command), it printed an error and left the file as it was. On a GNU system the same line silently edited it. Write the temp-file version and nobody has to know which `sed` they have. The full set of Chimera's differences, and the others I found, is in `docs/decisions/0009-chimera-lab.md` and `foundations.bash-text-processing`.

`which` exists on all three systems here but is not part of the shell language: use **`command -v`**:

```text
command -v no_such_tool >/dev/null 2>&1 || echo "missing: install it first"       ->  missing: install it first
V=one sh -c 'echo "in: $V"'; echo "out: ${V-unset}"                                ->  in: one | out: unset      (an environment variable for ONE command)
```

## Which shell am I in?

None of the three set `BASH_VERSION`, `KSH_VERSION` or `ZSH_VERSION` (`bash=no ksh=no zsh=no`), so **do not branch on which shell it is**: write the portable thing. `ls -l /bin/sh` tells you what `sh` is on a machine (`/bin/sh -> dash` on Ubuntu, a regular program on Chimera).

## The template, tested

The same job as the bash lesson's `tool.sh` (keep a `KEY=VALUE` line in a file: idempotent, atomic, dry-run and verbose switches), in **POSIX sh only**:

```sh
#!/bin/sh
# tool.sh: keep a KEY=VALUE line in a config file (idempotent, atomic), POSIX sh only.
# Usage: tool.sh [-n] [-v] FILE KEY=VALUE
set -eu
PATH=/usr/bin:/bin; export PATH
umask 077

prog=${0##*/}
dry=0 verbose=0
tmp=

die()     { printf '%s: %s\n' "$prog" "$*" >&2; exit 1; }
usage()   { printf 'Usage: %s [-n] [-v] FILE KEY=VALUE\n' "$prog" >&2; exit 2; }
log()     { if [ "$verbose" = 1 ]; then printf '%s\n' "$*" >&2; fi; }
cleanup() { if [ -n "$tmp" ]; then rm -f -- "$tmp"; fi; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

while getopts nv opt; do
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
awk -v key="$key" -v new="$setting" '
  index($0, key "=") == 1 { if (!done) print new; done = 1; next }
  { print }
  END { if (!done) print new }' "$file" > "$tmp"
mv -f -- "$tmp" "$file"
tmp=
log "set: $setting"
```

What changed from the bash version: no `-E` and no `pipefail`; no `ERR` trap (`trap ... ERR` is **not** accepted by dash or the FreeBSD sh: `bad trap` / `bad signal ERR`), so failures are reported by the explicit `die` calls; the `log` function uses `if` (not `[ ] && printf`, which would return 1 under `set -e`); no `local`; `getopts nv` without the leading colon; `awk -v` for data; `grep -qxF --`; `cleanup` written with `if` (the lesson of `bash-robust-scripts`: a cleanup ending in a failing test overwrites the exit status).

Run on a file with `a=1` and `b=2`, **in dash, ash and the FreeBSD sh, the output was identical**:

```text
tool.sh -v c.conf b=9    ->  set: b=9           rc=0     (file now: a=1 b=9)
tool.sh -v c.conf b=9    ->  already set: b=9   rc=0     (the second run changes nothing)
```

and the template is **clean under `shellcheck -s sh`** (no findings; rc 0). A **TERM sent mid-run** gave status 143 and left **no temp file**, in all three shells.

### One test harness, three shells

The harness is itself POSIX sh. It takes the **script** (`TOOL`) and the **shell command that runs it** (`SUT`), so the same 13 tests run under each shell. I ran it as `TOOL=/path/tool.sh SUT=dash dash harness.sh`, then with `SUT="busybox ash"` and with `SUT=sh` on Chimera.

```sh
#!/bin/sh
pass=0 fail=0
check() { # check NAME WANT_RC WANT_SUBSTRING COMMAND...
  name=$1 want_rc=$2 want_out=$3; shift 3
  out=$("$@" 2>&1); rc=$?
  case $out in *"$want_out"*) found=1 ;; *) found=0 ;; esac
  if [ "$rc" = "$want_rc" ] && [ "$found" = 1 ]; then
    pass=$((pass + 1)); printf 'ok   %s\n' "$name"
  else
    fail=$((fail + 1)); printf 'FAIL %s (rc=%s, output: %s)\n' "$name" "$rc" "$out"
  fi
}
work=$(mktemp -d) && cd "$work" || exit 1
cp "$TOOL" tool.sh; printf 'a=1\n' > f.conf
check 'usage on no arguments'        2 'Usage:'          $SUT tool.sh
check 'rejects a bad setting'        1 'bad setting'     $SUT tool.sh f.conf oops
check 'dry run reports'              0 'DRY: would set'  $SUT tool.sh -n f.conf b=2
check 'dry run changes nothing'      0 ''                grep -qx 'a=1' f.conf
check 'sets a new key'               0 ''                $SUT tool.sh f.conf b=2
check 'second run is a no-op'        0 'already set'     $SUT tool.sh -v f.conf b=2
check 'replaces an existing key'     0 ''                $SUT tool.sh f.conf a=9
check 'old value is gone'            1 ''                grep -qx 'a=1' f.conf
check 'file has the new value once'  0 '1'               grep -cx 'a=9' f.conf
check 'missing file'                 1 'no such file'    $SUT tool.sh nofile.conf x=1
chmod 400 f.conf
check 'read-only file'               1 'not writable'    $SUT tool.sh f.conf z=1
chmod 600 f.conf
check 'no temp file left behind'     0 '0'               sh -c 'ls | grep -c "^f.conf\."; true'
check 'unknown option'               2 'Usage:'          $SUT tool.sh -z f.conf x=1
printf '%s passed, %s failed\n' "$pass" "$fail"
cd / && rm -rf "$work"
[ "$fail" -eq 0 ]
```
```text
--- dash        13 passed, 0 failed
--- ash         13 passed, 0 failed
--- Chimera sh  13 passed, 0 failed
```

Three honest limits: (1) all three passing is **evidence, not proof** (I did not run yash, ksh or zsh); (2) the harness uses `mktemp` and `grep -c`, which are not POSIX but exist on all the systems I used; (3) it ran as a **normal user**; the "read-only file" test relies on that, and I did not test it as root (I expect root to be able to write a mode-400 file, so the test would then fail).

### What a bashism does to the template

I made a copy with `set -euo pipefail` and an array (`arr=(1 2)`) on one line. ShellCheck `-s sh` reported:

```text
tool-bashism.sh:4:10: warning: In POSIX sh, set option pipefail is undefined. [SC3040]
tool-bashism.sh:10:11: warning: In POSIX sh, arrays are undefined. [SC3030]
```

and **dash** stopped with `tool-bashism.sh: 10: Syntax error: "(" unexpected`, **busybox ash** with `tool-bashism.sh: line 10: syntax error: unexpected "("`. Only a strict shell and ShellCheck find this; **bash would have run it**.

## Reading someone else's `#!/bin/sh` script

All of `bash-robust-scripts` ("Reading an unknown script before you run it") applies. Add:

1. **Run `shellcheck -s sh` and `dash -n`-style checks first** (the lesson tested `dash script.sh` and ShellCheck, not `dash -n`).
2. A `#!/bin/sh` script that only works when you run it with bash is **broken for its stated shell**; either fix it or change the shebang to bash.
3. Check every external command against the **BSD/GNU table** above if it must run on both.
4. Find **`eval`**, backticks, unquoted variables in `[ ]` and in `rm`, and `$(...)` fed to `rm` or `sh`.

## Common mistakes

- **Testing with bash.** Use `dash script.sh`, `busybox ash script.sh`, and the system `sh`.
- **`echo` for data**, `echo -e`, `echo -n`: use `printf '%s\n'`.
- **`local` without a value**, and `local -n`.
- **`sed -i`, `stat -c`, `expr length`, `readlink -f`, `date -d`, `sort -V`, `grep -P`** without checking the target system's tools.
- **Using `$$` for temporary file names** (`mktemp`).
- **Losing a counter in a pipeline** (`... | while read`): use a here-document, a temp file, or braces.
- **Forgetting to restore `IFS`**, or splitting data that contains `*` without `set -f`.
- **`[ -a ]`/`[ -o ]`**, `==` in `[ ]`.
- **`. lib.sh` without `./`** (works on Chimera, not on dash or ash).
- **Comparing `$-` or exit statuses of `set -u`/readonly errors** across shells.
- **Trusting a single passing shell.**

## Practice

1. **Matrix a script.** Take any bash script you wrote and strip it down to POSIX sh. Run it under `dash`, `busybox ash` (if you have it) and the system `sh`; keep a table of results like the ones above.
2. **Arrays by `set --`.** Write a function that takes a list of file names and prints them with `[ ]` around each, using only `"$@"`. Test with names containing spaces and a name that starts with `-`.
3. **The pipeline trap.** Write a count of lines matching a pattern three ways (here-document, temp file, braces) and show that the plain pipeline gives 0.
4. **`sed -i` portability.** Edit a config value in place in a way that works on GNU and BSD. If you have no BSD system, say what you would test and what you could not.
5. **Idempotent and atomic.** Take the template and add a `--delete KEY` option; keep the tests passing and add two new ones for it.
6. **Break the harness.** Make one test fail on purpose and show that all three shells report it.
7. **Signal handling.** Add a test to the harness that starts the template's slow variant, sends `TERM`, and checks that no temp file is left.
8. **Lock.** Write a script that takes a `mkdir` lock, removes it on `EXIT`, and refuses to run twice at once; test with two copies started together.
9. **ShellCheck.** Run `shellcheck -s sh` on a script you wrote; fix every SC3 finding, then re-run under dash.
10. **Find the bug.** (a) `#!/bin/sh` / `cmd | while read -r l; do n=$((n+1)); done; echo "$n"` (b) `#!/bin/sh` / `tmp=/tmp/work.$$; echo data > $tmp` (c) `#!/bin/sh` / `sed -i 's/a/b/' "$f"` (d) `#!/bin/sh` / `trap 'rm -f "$tmp"' ERR` For each, say how it fails and on which system.

## Check your understanding

Take the quiz for this lesson (it draws ten from the bank). After a wrong answer, reread the section named in the review line.
