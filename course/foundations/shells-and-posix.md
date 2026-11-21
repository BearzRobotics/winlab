*Draft for owner review.* "Shell script" is not one language. **bash**, **dash**, **busybox ash**, **FreeBSD's sh** and the shell you get as `/bin/sh` on your distribution are different programs that agree on a core (**POSIX sh**) and disagree about the rest. A script that works when you type it can fail on another machine, or, worse, *run and do the wrong thing*. This lesson explains how a script actually starts, which shell runs it, what is and is not portable, and how to check a script before you trust it.

**What was tested.** On a WSL2 Ubuntu 26.04 machine: **bash 5.3.9**, **dash 0.5.12** (this machine's `/bin/sh`), **busybox 1.35.0 `ash`** and **ShellCheck 0.11.0**. I also ran **bash invoked under the name `sh`** (a symlink), because on some distributions that is what `/bin/sh` is. Every result below was produced by running the snippet (`tests/verification/bash/shells1.sh` and `shells2.sh`). **Not tested:** FreeBSD sh, yash, zsh, ksh, macOS, the owner's distribution (`util-core`) and what `/bin/sh` is on AlmaLinux, Arch or Alpine. Check yours with `readlink -f /bin/sh` and do not assume.

## How a script starts

When you run `./script.sh`, **the kernel**, not your shell, reads the first line. If it starts with `#!` (the *shebang*), the rest names the interpreter, and the kernel runs `interpreter script.sh`. See [execve(2)](https://man7.org/linux/man-pages/man2/execve.2.html).

```bash
#!/usr/bin/env bash
echo "hello from $0"
```

- `#!/usr/bin/env bash` finds `bash` on `PATH` (useful when it is not in `/bin`). `#!/bin/bash` names one fixed path. **Both are fine for a bash script; neither is `sh`.**
- `#!/bin/sh` means "the system's POSIX shell", whatever that is on this machine. **A script that starts `#!/bin/sh` must be written in POSIX sh** (see below).

What I saw when the start-up goes wrong:

| Situation | Result I saw |
|---|---|
| Interpreter path does not exist (`#!/no/such/bash`) | `bad interpreter: No such file or directory`, exit status **126** |
| `#!/usr/bin/env nosuchshell` | `env: 'nosuchshell': No such file or directory`, exit status **127** |
| Windows line endings (`#!/bin/bash` then CR LF) | `/bin/bash^M: bad interpreter: No such file or directory`, status **126**: the kernel looked for a program literally named `bash<CR>` |
| No execute permission, run as `./j.sh` | `Permission denied`, status **126**; `bash j.sh` ran it fine |
| No shebang at all | it ran, both as `./i.sh` from bash and as `sh i.sh`; `$0` shows only the script's path, so *which* shell ran it is not visible and depends on how it was started. Do not rely on this |

Two consequences: **the shebang is ignored when you type the shell yourself** (`bash script`, `dash script`, `sh script`: the shell you typed wins), and **a script edited on Windows may need its line endings fixed** before Linux will run it (`^M` in an error message is the sign).

### Interactive, login and non-interactive shells

A shell you type into is *interactive*; one that runs a script or `bash -c '...'` is not. In bash `$-` lists the active options: in my runs `bash -c 'echo $-'` gave `hBc` and an interactive `bash -ic` gave `himBHc` (the `i` is "interactive"). Which start-up files (`~/.bashrc`, `~/.profile` and so on) are read depends on login versus interactive; the rules are in the [bash manual](https://tiswww.case.edu/php/chet/bash/bashref.html) (section "Bash Startup Files"), which I did not test file by file. The practical rule for scripts: **a script must not depend on your `~/.bashrc`** (aliases, functions and `PATH` changes there are absent in cron, systemd and `ssh host command`), so set `PATH` and everything else you need inside the script.

## The shells, and what `/bin/sh` is

| Shell | What it is |
|---|---|
| **POSIX sh** | A *standard* ([POSIX Shell Command Language](https://pubs.opengroup.org/onlinepubs/9799919799/utilities/V3_chap02.html)), not a program. Scripts written to it run on any conforming shell |
| **bash** | The GNU shell and the usual interactive shell; a large superset of POSIX sh |
| **dash** | A small, fast, nearly POSIX-only shell. On Debian and Ubuntu it is `/bin/sh` ([dash manual](https://manpages.debian.org/unstable/dash/dash.1.en.html)). On this Ubuntu machine `ls -l /bin/sh` gave `/bin/sh -> dash` |
| **busybox ash** | The shell inside BusyBox ([busybox.net](https://busybox.net/)); used where space is tight. It accepts some bash extras and not others (below) |
| **FreeBSD sh** | The FreeBSD base system's shell ([manual](https://man.freebsd.org/cgi/man.cgi?query=sh&sektion=1)). Not tested here |
| **yash, zsh, ksh, util-core's sh** | Exist; not tested here |

**`/bin/sh` is a choice each distribution makes.** On this machine it is dash. On others it may be bash or busybox: I did not check them, so run `readlink -f /bin/sh` on the machine you care about. The reliable rule is the one at the top: if the shebang says `sh`, write POSIX; if you want bash features, say `bash`.

### The trap: bash running as `sh` is still mostly bash

When bash is started under the name `sh` it switches to **POSIX mode** ([bash manual, POSIX mode](https://tiswww.case.edu/php/chet/bash/bashref.html)), but that mode changes a few behaviours; it does **not** remove bash's extensions. I made a symlink `sh -> bash` and ran bashisms through it: arrays, `[[ ]]`, brace expansion, `&>`, `(( ))` and here-strings all **worked**, with output identical to bash. So a script tested only on a machine where `/bin/sh` is bash will "work" and then break on Debian, Ubuntu or Alpine. **Test portable scripts with a real dash or busybox ash**, not with bash pretending.

## A bashism table, from running it

I ran each snippet in bash, dash and busybox ash. "Fails" means a loud error. "**Silent**" means no error and a *different result*, the dangerous kind.

| Snippet | bash | dash | busybox ash |
|---|---|---|---|
| `[[ abc == a* ]] && echo match` | `match` | fails: `[[: not found` | **Silent:** printed nothing (it accepts `[[` but does no pattern match) |
| `[ a == a ]` | equal | fails: `unexpected operator` | equal |
| `[ a = a ]` | equal | equal | equal |
| `a=(x y z); echo ${a[1]}` | `y` | fails: `Syntax error: "("` | fails: `unexpected "("` |
| `echo {1..3}` | `1 2 3` | **Silent:** prints `{1..3}` | **Silent:** prints `{1..3}` |
| `echo -e "a\tb"` | tab | **Silent:** prints `-e a<TAB>b` | tab |
| `printf "a\tb\n"` | tab | tab | tab |
| `echo $'a\tb'` | tab | **Silent:** prints `$a<TAB>b` | tab |
| `cat <(echo hi)` | `hi` | fails: `Syntax error: "("` | `hi` |
| `v=banana; echo ${v//a/o}` | `bonono` | fails: `Bad substitution` | `bonono` |
| `v=ABC; echo ${v,,}` | `abc` | fails: `Bad substitution` | fails |
| `v=foo.txt; echo ${v%.txt}` | `foo` | `foo` | `foo` |
| `function f { echo hi; }; f` | `hi` | fails | `hi` |
| `f() { echo hi; }; f` | `hi` | `hi` | `hi` |
| `source file` | works | fails: `source: not found` | works |
| `. file` | works | works | works |
| `ls /nonexistent &> out; echo rc=$?` | `rc=2`, error captured | **Silent:** `rc=0`, error printed on screen | `rc=2` |
| `((x = 2 + 3)); echo $x` | `5` | **Silent:** `x: not found`, exit 0 | `x: not found` |
| `let x=2+3` | `5` | fails: `let: not found` | `5` |
| `cat <<< hi` | `hi` | fails | fails |
| `case a in a) echo one ;& b) ...` | falls through | fails | fails |
| `x=1; [ -v x ]` | `set` | fails | fails |
| `printf "%q\n" "a b"` | `a\ b` | fails: `%q: invalid directive` | fails |
| `echo ${RANDOM:+has RANDOM}` | `has RANDOM` | empty | `has RANDOM` |
| `trap "echo ERR" ERR` | works | `bad trap` | works |
| `declare -i n=3` / `typeset` / `shopt` / `mapfile` | work | `not found` | `not found` |
| `type -a ls` | `ls is /usr/bin/ls` | `-a: not found` | `/usr/bin/ls` |
| `time true` | a `real/user/sys` report | runs `/usr/bin/time`, different format | same as dash |
| `set -o pipefail; false \| true; echo $?` | `1` | `1` (dash 0.5.12) | `1` |
| `local x=1` in a function | works | works | works |

Why the **silent** ones happen, because each is a parsing fact, not luck:

- **`&>`**: dash reads `ls /nonexistent &> out` as `ls /nonexistent &` (run in the background) followed by `> out` (create an empty file). The error appears on your terminal, the status is 0, and the "log file" is empty.
- **`((x = 2 + 3))`**: dash reads two nested subshells `( ( x = 2 + 3 ) )`, so it tries to run a command called... `x`.
- **`echo -e`** and **`$'...'`**: neither is POSIX; dash's `echo` always interprets backslashes and prints the `-e` itself.
- **`{1..3}`**: brace expansion is a bash feature; other shells pass the text through.
- **`[[` in busybox ash** is accepted but is only `[` under another name in my test, so a pattern like `a*` is compared literally. A script can pass its tests and be wrong.

`local`, `echo -n` and (in recent shells) `pipefail` worked in all three on this machine, but not because POSIX promises them: the 2024 edition of POSIX adds `pipefail` while the 2018 text does not mention it (I checked both pages for the word), and `local` is not defined by either. **"Worked everywhere I tried" is not "portable".** Older or unusual shells may differ.

### Portable replacements

| Instead of | Write (POSIX sh) |
|---|---|
| `[[ $x == a* ]]` | `case $x in a*) ... ;; esac` |
| `[ "$a" == "$b" ]` | `[ "$a" = "$b" ]` |
| arrays | positional parameters (`set -- a b c; "$@"`), or one item per line read with `while IFS= read -r` |
| `echo -e`, `$'..'` | `printf '%s\n' ...` (`printf` handles backslashes the same everywhere) |
| `{1..3}` | `i=1; while [ "$i" -le 3 ]; do ...; i=$((i + 1)); done` |
| `cmd &> file` | `cmd > file 2>&1` |
| `((i++))`, `let` | `i=$((i + 1))` |
| `source file` | `. file` |
| `function f {` | `f() {` |
| `<(cmd)`, `<<<` | a pipe, a here-document, or a temporary file |
| `${v//a/b}`, `${v,,}` | `sed` or `tr` (tools you call, not shell syntax) |

## Choosing the shell

1. **Needs bash features** (arrays, `[[ ]]`, `mapfile`, process substitution)? Say `#!/usr/bin/env bash` and be proud of it. Tell the reader that bash is required.
2. **Must run on any Unix** (installers, boot scripts, containers with busybox, scripts in an unknown environment)? Write **POSIX sh**, start with `#!/bin/sh`, and test it in a real dash and busybox ash.
3. **Interactive use**: whatever you like; keep the habits out of scripts.
4. **Too complex** (data structures, parsing, many files)? Consider a language built for it: the shell's strength is gluing programs together.

## Checking a script before you trust it

### Syntax only: `bash -n` and `dash -n`

```bash
bash -n script.sh      # parse, do not run
dash -n script.sh
```

My test script with an array: `bash -n` returned 0, `dash -n` printed `Syntax error: "(" unexpected` and returned 2. That is a quick **portability check for POSIX scripts**: if `dash -n` is happy, the *syntax* is POSIX-ish. It does not run anything, so it cannot catch a mistyped command (`lss /tmp` passed `bash -n` with status 0) or a logic error.

### ShellCheck (optional, strongly recommended)

[ShellCheck](https://www.shellcheck.net/) ([source](https://github.com/koalaman/shellcheck)) is a static analyser for sh and bash scripts. **It is not installed by default** on most systems. Install routes (each package page exists, but I did **not** run these installs; I used the static binary below): Debian/Ubuntu `apt install shellcheck` ([Debian](https://packages.debian.org/sid/shellcheck), [Ubuntu](https://packages.ubuntu.com/shellcheck)), Fedora `dnf install ShellCheck` ([package](https://packages.fedoraproject.org/pkgs/ShellCheck/ShellCheck/)), Arch `pacman -S shellcheck` ([package](https://archlinux.org/packages/extra/x86_64/shellcheck/)), Alpine `apk add shellcheck` ([package](https://pkgs.alpinelinux.org/package/edge/community/x86_64/shellcheck)). Without root: the project publishes a static Linux binary on its [releases page](https://github.com/koalaman/shellcheck#installing); I downloaded v0.11.0 (the unpacked binary is about 16 MB) into my home folder and ran it from there, with nothing installed system-wide. Checking the published checksum before running a downloaded binary is the careful habit; I recorded the file hash but did not compare it with a publisher's list.

On this script (a `#!/bin/sh` file with bashisms and unquoted variables):

```bash
#!/bin/sh
name=$1
if [[ $name == b* ]]; then
    echo -e "starts with b: $name"
fi
files=(one two)
echo ${files[0]}
for f in $(ls); do
    rm $f
done
```

ShellCheck printed (shortened):

```
line 3: SC3010 (warning): In POSIX sh, [[ ]] is undefined.
line 3: SC3014 (warning): In POSIX sh, == in place of = is undefined.
line 4: SC3037 (warning): In POSIX sh, echo flags are undefined.
line 6: SC3030 (warning): In POSIX sh, arrays are undefined.
line 7: SC2086 (info): Double quote to prevent globbing and word splitting.
line 8: SC2045 (error): Iterating over ls output is fragile. Use globs.
line 9: SC2086 (info): Double quote to prevent globbing and word splitting.
```

and **exit status 1**. Reading the codes: **SC3xxx** are portability findings *for the shell named in the shebang* (the same file checked with `--shell=bash` dropped them), **SC2xxx** are correctness and safety findings, and each code has a wiki page (for example [SC3010](https://www.shellcheck.net/wiki/SC3010), [SC2086](https://www.shellcheck.net/wiki/SC2086)) that explains the failure and the fix.

Useful options and facts I ran:

- `-S warning` hides `info`-level notes; `-f gcc` prints one line per finding (`file:line:col: warning: ... [SC3010]`).
- `-x` follows files you `source`. Without it, `. ./lib.sh` gives **SC1091 (info)**: *Not following: ./lib.sh was not specified as input*.
- **Turn a check off on purpose and say why**, on the line before: `# shellcheck disable=SC2086   # intentional word splitting`. My example then passed with status 0.
- A **clean POSIX script** (a `for` over `./*.txt` with `[ -e "$f" ] || continue`) passed with no output and status 0.
- **ShellCheck did not flag the mistyped command** `lss /tmp` either. A static checker finds patterns, not every bug. Tests and a dry run are still your job.

### Test in the real shells

```bash
dash script.sh          # POSIX behaviour
busybox ash script.sh   # if busybox is installed (I used a downloaded static binary)
bash script.sh
```

A script meant to be portable should behave the same in all of them.

## Reading an unknown script (the shell part)

1. **Read the shebang first.** `#!/bin/sh` or `#!/usr/bin/env bash`? A `#!/bin/sh` script that contains `[[`, arrays or `&>` was written by someone who tested on bash; on dash it fails or, for `&>` and `((`, does something else *silently*.
2. **Is there a shebang at all?** Without one, whatever shell launched it runs it.
3. **Run `shellcheck` on it** (and `dash -n`), then read what it flags. A flagged line is a place to read carefully.
4. **Check line endings.** `^M` errors mean Windows endings (`file script.sh` shows "CRLF line terminators").
5. **Know what `curl ... | sh` means:** it runs whatever the server sent, in the system's `sh`, before you have read it. Download first, read, then run.

## Common mistakes

- `#!/bin/sh` on a script that uses bash features.
- Testing a portable script only where `/bin/sh` is bash.
- Believing a bash-only construct "works" because it ran: check what the other shells do with it (`&>`, `((`, `echo -e`).
- A Windows-edited script with CR LF line endings.
- A script that needs `~/.bashrc` to find a command or define a function.
- Treating `bash -n` or ShellCheck as proof of correctness.
- Using `echo` for anything with backslashes or a leading `-`; use `printf`.

## Practice

1. On a Linux machine, find out what `/bin/sh` is (`readlink -f /bin/sh`) and what `sh --version` or `ls -l /bin/sh` shows. Write the answer for two machines if you have two.
2. Write a three-line script in each form (`#!/usr/bin/env bash`, `#!/bin/sh`, none) and run it as `./x`, as `bash x`, and as `sh x`, with `echo "$0"` inside. Explain each result.
3. Create a script with a CR LF shebang (use `printf '#!/bin/bash\r\necho hi\r\n'`) and read the error. Fix it with `sed -i 's/\r$//'` and run it again.
4. Run every row of the table above that you can on your own machine and add a column for your `/bin/sh`.
5. Rewrite this POSIX-incompatible script so `dash -n` and `shellcheck` accept it:

   ```bash
   #!/bin/sh
   for i in {1..3}; do echo -e "n=$i"; done
   cmd &> log.txt
   [[ $1 == y* ]] && echo yes
   ```
6. Run ShellCheck on a script you wrote earlier. For each finding, decide: fix, or disable with a comment explaining why.
7. **Read this and say which shell it needs, what fails on dash, and what fails silently:**

   ```bash
   #!/bin/sh
   set -e
   logfile=/tmp/out.log
   ls /nonexistent &> "$logfile"
   ((count = count + 1))
   echo -e "done: $count"
   ```

   **Answer (I ran it, `tests/verification/bash/run-ex7.sh`).** It needs bash: `&>`, `((` and `echo -e` are all bash features. **On dash:** `ls /nonexistent &> "$logfile"` runs `ls` in the *background* and creates an **empty** log (0 bytes) while the error prints on the terminal; `set -e` does not notice because the background job's status is not tested; then `((count = count + 1))` is read as nested subshells running a command named `count`, which fails with `count: not found`, and `set -e` ends the script with **exit status 127**. **On bash:** the redirect works, the log holds the error text, and `set -e` stops the script at that very line with **exit status 2**, because `ls` failed; it never reaches the later lines. The same file fails at *different places with different statuses* depending on the shell. Examine it safely with `dash -n` and `shellcheck` before running anything.

## Check your understanding

1. Who reads the shebang line: the shell or the kernel? What happens when you type `bash script` for a script whose shebang says `#!/bin/sh`?
2. What does `bad interpreter: ... ^M` mean, and how do you fix it?
3. Why is "it works on my machine where `/bin/sh` is bash" not a test of a `#!/bin/sh` script?
4. In dash, what does `cmd &> file` actually do?
5. What does `echo -e "a\tb"` print in dash?
6. Why is `bash -n` not enough, and what does ShellCheck add (and still not catch)?
7. What do ShellCheck codes SC3xxx mean?
8. Give four replacements for bashisms in POSIX sh.

**Expected answers:** (1) the kernel reads it when you run `./script`; if you type the shell yourself, that shell runs the file and the shebang is ignored; (2) the file has Windows (CR LF) line endings, so the interpreter name ends in a carriage return; convert them (`sed -i 's/\r$//'` or `dos2unix`); (3) bash running as `sh` still accepts bash extensions, so errors only appear on a real dash or busybox ash; (4) it runs `cmd` in the background and creates an empty `file`; the output stays on the terminal and the status is 0; (5) `-e a<TAB>b`: it prints the `-e` and always interprets the backslash; (6) `-n` only parses; ShellCheck finds portability and safety patterns (unquoted variables, `ls` in a loop, bashisms for the declared shell) but not mistyped command names or logic errors; (7) portability warnings: a construct is undefined in POSIX sh for the shell named in the shebang; (8) any four of the table: `case` for `[[ ]]`, `=` for `==`, `printf` for `echo -e`, `> file 2>&1` for `&>`, `$(( ))` for `(( ))`, `.` for `source`, `f()` for `function f`.
