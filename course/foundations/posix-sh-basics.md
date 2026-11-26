*Draft for owner review.* A script that starts `#!/bin/sh` promises to use **only the POSIX shell language**, so that it runs on any system's `sh`: **dash** on Debian and Ubuntu, **busybox ash** on Alpine and in small images, the **FreeBSD `sh`** on Chimera, and others. This lesson teaches that language (the part every `sh` shares), shows **where the shells still differ even inside it**, and shows with real output which **bashisms** each shell accepts, rejects, or silently misreads. The reference shell is **dash**, the standard POSIX shell on Linux when you install a separate one; busybox ash and Chimera's `sh` are the second and third checks. **Bash is never used to test a `#!/bin/sh` script**: bash accepts nearly everything, so a pass tells you nothing (`foundations.shells-and-posix`).

**What was tested, and where.** All results below come from `tests/verification/posix/psh1.sh` (120 snippets) run in three shells:

| Shell | Version and where | How it was run |
|---|---|---|
| **dash** (reference) | `0.5.12-12ubuntu3`, Ubuntu 26.04 in WSL2; `/bin/sh -> dash` there | `dash s.sh` |
| **busybox ash** | BusyBox v1.35.0 (a static binary I downloaded) | `busybox ash s.sh` (the **shell only**: external commands such as `mktemp` were the system's) |
| **FreeBSD `sh`** | the `/usr/bin/sh` of **chimerautils 15.1.2-r0** (`apk info --who-owns`), on the Chimera Linux lab VM (build 20261103), run over SSH | `sh s.sh` |

and **ShellCheck 0.11.0** with `shellcheck -s sh`, whose `SC3xxx` codes are the "this is not POSIX" oracle I quote. **Not tested:** `yash`, `ksh`, `zsh` in sh mode, macOS `/bin/sh` (which I believe is bash in POSIX mode, not checked), the owner's util-core `sh`, any other version of these shells, and what `/bin/sh` is on AlmaLinux or Alpine (the lesson says "from memory" where it mentions them). I did **not** read the full POSIX specification for this lesson; where I say "not POSIX" it is ShellCheck's classification, and the specification is the authority: [POSIX Shell Command Language](https://pubs.opengroup.org/onlinepubs/9799919799/utilities/V3_chap02.html) (the page loads; I did not read its sections), with the commands in [POSIX Utilities](https://pubs.opengroup.org/onlinepubs/9799919799/idx/utilities.html). Other references: the [dash manual page](https://manpages.debian.org/unstable/dash/dash.1.en.html) (not re-read), [ShellCheck's wiki](https://www.shellcheck.net/wiki/), [BusyBox](https://busybox.net/), and the [FreeBSD `sh(1)`](https://man.freebsd.org/cgi/man.cgi?query=sh) manual page (Chimera's `man sh` also exists in the VM).

## Which shell is `/bin/sh`?

It depends on the system. Tested:

```text
Ubuntu 26.04 (WSL2):  ls -l /bin/sh   ->  /bin/sh -> dash
Chimera Linux:        ls -l /bin/sh   ->  -rwxr-xr-x 1 root root 204216 Oct 15 14:59 /bin/sh      (a program, not a link)
                      apk info --who-owns /usr/bin/sh   ->  /usr/bin/sh is owned by chimerautils-15.1.2-r0
```

From memory and **not tested here**: Debian also uses dash; Alpine uses busybox ash; Red Hat family systems (including AlmaLinux) link `sh` to bash, which then runs in a POSIX-compatible mode but still accepts many extensions. So a `#!/bin/sh` script that "works on my RHEL box" may fail on Ubuntu. The only way to know a script is portable is to **run it under strict shells**, and the strictest of the three here is dash.

How to run a script under a specific shell without changing its shebang:

```sh
dash script.sh                # reference
busybox ash script.sh         # busybox's ash (if busybox is installed)
sh script.sh                  # whatever /bin/sh is on THIS machine (on Chimera: FreeBSD sh)
```

Never `bash script.sh` to test a `#!/bin/sh` script, and never `sh script.sh` on a system where `sh` is bash (it would be a bash test). Check with `ls -l /bin/sh` first.

## The core language

Everything in this section behaved **the same in all three shells** unless a note says otherwise (the snippet number is the row in `psh1.sh`).

### Quoting, word splitting and globbing

```text
v="a b"; set -- $v; echo $#; set -- "$v"; echo $#        -> 2 | 1          (unquoted splits, quoted does not)
set -- "a b" c; for x in "$@"; do printf "[%s]" "$x"; done        -> [a b][c]
set -- "a b" c; for x in "$*"; do printf "[%s]" "$x"; done        -> [a b c]
echo *.zzz [a]*.zzz                                                -> *.zzz [a]*.zzz     (no match: the pattern stays literal)
echo {1..3} {a,b}x                                                 -> {1..3} {a,b}x      (brace expansion does not exist in any of the three)
HOME=/h; echo ~ ~/x "~"                                            -> /h /h/x ~
```

Always quote expansions (`"$var"`, `"$@"`) exactly as in bash (`foundations.bash-variables-and-expansion`); the rules are the same, there are just **no arrays**, **no `[[ ]]`**, **no brace expansion** and **no `**`** to help you.

### Parameter expansion (the POSIX subset)

```text
v=/a/b.tar.gz; echo "${v#*/} ${v##*/} ${v%.*} ${v%%.*} ${#v}"
   -> a/b.tar.gz b.tar.gz /a/b.tar /a/b 11
unset u; echo "${u:-d} ${u-d}"                       -> d d
e=; echo "[${e:-d}] [${e-d}]"                        -> [d] []        (:- also replaces EMPTY; - only unset)
echo "${u:=set} $u"                                   -> set set       (assign a default)
echo "[${e:+alt}]"                                    -> []            (:+ is "use this if set and non-empty")
unset u; echo "${u:?missing}"; echo after              -> exits: dash "s.sh: 1: u: missing", ash "s.sh: line 1: u: missing", Chimera "s.sh: u: missing"; rc=2 in all
```

The five operators `# ## % %% :-` plus `${#v}`, `:=`, `:?` and `:+` are the whole portable set. **Everything else** (`${v:1:2}`, `${v/a/b}`, `${v^^}`, `${!name}`) is a bashism (table below). Substitute with `cut`, `sed`, `tr` and `case` (`foundations.posix-sh-scripting`).

### Arithmetic

```text
echo $((2+3*4)) $((7/2)) $((7%3)) $((-7/2)) $((1<<3)) $((5>3))      -> 14 3 1 -3 8 1
i=5; i=$((i+2)); echo $i; echo $((i*=2)) $i                          -> 7 | 14 14
```

Integers only (`$((1.5+1))` was an arithmetic error in every shell). `$((i++))` and `**` are **not** portable (below).

### Tests: `[ ]`, `case`, exit status

```text
[ -n "x" ] && [ 3 -gt 2 ] && [ a = a ] && [ a != b ] && echo ok       -> ok
[ "a b" = "a b" ] && echo same; [ "" ] || echo empty-is-false           -> same | empty-is-false
touch f; mkdir d; [ -e f ] && [ -f f ] && [ -d d ] && [ -r f ] && [ -w f ] && [ ! -x f ] && echo ok   -> ok
case foo.txt in *.txt|*.md) echo text;; *) echo other;; esac; case x in [a-c]) echo abc;; *) echo no;; esac   -> text | no
case x in y) echo y;; esac; echo "rc=$?"                                -> rc=0       (no match: status 0)
case x in x) false;; esac; echo "rc=$?"                                 -> rc=1       (the status of the last command)
```

`=` (single) is the string comparison in `[ ]`; `==` is not portable. `case` is the portable pattern matcher (`*.txt`, `?`, `[a-c]`, `|`), and the way to do "starts with", "ends with" and "contains" without bash.

`[ -n x -a -n y ]` and `[ ! -n x -o -n y ]` ran in all three, but the ambiguous form `x="!"; [ "$x" -a "$x" ]` **failed in all three** (dash `[: -a: unexpected operator`, ash `!: unknown operand`, Chimera `[: -a: unexpected operator`), because a data value that looks like an operator confuses the parser. Use `[ ... ] && [ ... ]` and `[ ... ] || [ ... ]` instead.

### Positional parameters, `set --`, loops

```text
set -- a b c; shift; echo "$# $*"; for x; do echo "arg=$x"; done      -> 2 b c | arg=b | arg=c     (for x; do ... is "for each argument")
set -- a b c d e f g h i j; echo "$10 ${10}"                           -> a0 j      ($10 is "$1" followed by a literal 0; braces are needed beyond 9)
```

```text
set -- 1 2 3; set -- "$@" 4; echo "$# $*"                              -> 4 1 2 3 4     (append: the portable array)
touch a1 a2; for f in a*; do printf "[%s]" "$f"; done                   -> [a1][a2]
printf "a b\nc d\n" | while read -r x y; do echo "$y-$x"; done          -> b-a | d-c
```

`set --` replaces all positional parameters: it is **the portable array** (next lesson). `read -r` is the only portable `read`; always give `-r`.

### Functions

```text
f() { echo "in f: $1"; return 3; }; f x; echo "rc=$?"                  -> in f: x | rc=3
```

Write `name() { ...; }`. `function name { }` is a bashism and a **syntax error** in dash (below). **There is no portable `local`**: ShellCheck says `In POSIX sh, 'local' is undefined [SC3043]`, yet all three shells here accept it, with **different meaning when no value is given**:

```text
x=g; f() { local x=1; echo $x; }; f; echo $x           -> 1 | g          (all three: a local with a value)
y=g; f() { local y; echo "[${y-unset}]"; }; f           -> dash: [g]    ash: [unset]    Chimera sh: [g]
```

`local y` with no value **keeps the outer value in dash and in the FreeBSD sh, but unsets it in ash (and in bash)**. If you use `local` at all, **always give it a value** (`local y=`). The portable alternative is a subshell, unique variable names, or `( ... )`.

### Here-documents and redirection

```text
x=5; cat <<EOF  (x=$x sum=$((1+1)) $(echo cmd))                          -> x=5 sum=2 cmd        (unquoted delimiter: expansions happen)
cat <<'EOF'  ($HOME $(date) \\n)                                          -> $HOME $(date) \\n    (quoted: literal)
cat <<-EOF  with a leading TAB on each line                               -> the tabs are stripped
{ echo out; echo err >&2; } 2>&1 | sort | tr "\n" ,                       -> err,out,
exec 3>&1; echo to-fd3 >&3                                                 -> to-fd3
```

### Options: `getopts`

```text
set -- -a -b val rest; while getopts ab: o; do echo "$o=${OPTARG:-}"; done; shift $((OPTIND-1)); echo "left: $*"
   -> a= | b=val | left: rest
set -- -x; while getopts :a o; do echo "o=$o OPTARG=${OPTARG-}"; done          -> o=? OPTARG=x       (leading colon: silent mode)
```

`getopts` is the portable option parser; `getopt` (the external one) is not.

### `trap`

```text
trap "echo bye" EXIT; echo hi                                  -> hi | bye
trap "echo got-TERM; exit 7" TERM; kill -TERM $$; echo not-reached   -> got-TERM       rc=7
```

Use signal names **without** the `SIG` prefix (`TERM`, `INT`, `EXIT`). `ERR`, `DEBUG`, `RETURN` are bash.

### `printf` and `echo`

```text
printf "%s|%5d|%-5s|%x|%o|%c|%%\n" a 42 ab 255 8 xyz         -> a|   42|ab   |ff|10|x|%
printf "[%s]" a b c; echo                                     -> [a][b][c]
echo 'a\tb'                                                    -> dash: a<TAB>b     ash: a\tb     Chimera sh: a\tb
```

**`echo` is not portable**: dash's `echo` **interprets** backslash sequences by default and busybox ash's and Chimera's do not. `printf` behaves the same everywhere, so **use `printf '%s\n' "$value"`** for anything that is not a fixed, plain string. See also `echo -n` and `echo -e` below.

### Other everyday builtins

```text
command -v ls >/dev/null && echo found; command -v no_such_cmd_x || echo missing     -> found | missing
x=$(false); echo $?                                            -> 1        (the status of the substitution)
false | true; echo $?; true | false; echo $?                   -> 0 | 1    (a pipeline's status is its last command)
eval "echo hi"; . ./l.sh                                       -> works in all three
IFS=:; set -- a:b:c; echo $#                                   -> 3        (IFS splitting; save and restore IFS)
sleep 0.1 & wait $!; echo "rc=$?"                              -> rc=0
set -e; false; echo not-reached                                 -> rc=1
set -e; if false; then :; fi; false || echo handled; echo after -> handled | after   (set -e exceptions are the same ones as in bash)
set -u; echo "$undefined"                                       -> exits rc=2 with "undefined: parameter not set"
readonly r=1; r=2                                               -> exits rc=2 with "r: is read only"
```

`command -v` is the portable "does this command exist" (`which` is a program, not part of the shell; on all three test systems a `which` was found, but it is not specified by the shell language). Note that **`set -u` on an unset variable and assigning a read-only variable end the script with status 2** in all three shells (confirmed again in `psh4.sh`); in my bash 5.3.9 test of `set -u` the status was 1, so exit statuses are not portable either. An alias defined on one line is usable on the **next** line in all three (`alias hi="echo aliased"` then `hi` printed `aliased`), not on the same line.

## Where the POSIX core still differs

These came out **different** in the three shells above. A script that depends on any of them is not portable even though every line looks POSIX.

| Snippet | dash | busybox ash | Chimera (FreeBSD sh) |
|---|---|---|---|
| `echo 'a\tb'` | `a<TAB>b` | `a\tb` | `a\tb` |
| `f() { local y; echo "[${y-unset}]"; }` with outer `y=g` | `[g]` | `[unset]` | `[g]` |
| `set -- a; shift 2; echo "rc=$?"` | **exits with rc 2**: `can't shift that many` | `rc=1` and continues | `rc=1` and continues |
| `echo "line $LINENO"` | `line ` (**empty** in this build, also in a file) | `line 1` | `line 1` |
| `. l.sh` (file in the current directory, no `./`) | not found (rc 2) | not found (rc 2) | **works** (`v=1`) |
| `$RANDOM` | unset | **set** | unset |
| `kill -l` | `0 HUP INT QUIT ILL ...` | ` 1) HUP  2) INT ...` | `HUP INT QUIT ILL ...` |
| error text format | `s.sh: 1: u: missing` | `s.sh: line 1: u: missing` | `s.sh: u: missing` |

(`$LINENO` printed nothing in dash 0.5.12-12ubuntu3, both with `-c` and from a file; I did not check why.) **Always source with a path** (`. ./l.sh` or `. "$dir/l.sh"`), **never rely on `$LINENO`** in portable code, **never use `echo` for data**, and **avoid `local`** or give it a value.

## Bashisms: who accepts what?

Each row was run in all three shells. "**silent**" means the shell accepted the line but did **something other than what a bash user expects**, which is the dangerous case. The last column is ShellCheck's verdict for `#!/bin/sh`.

| Bash feature | dash | busybox ash | Chimera sh | ShellCheck |
|---|---|---|---|---|
| `[[ a == a ]]` | `[[: not found` (rc 127) | works | `[[: not found` (127) | SC3010 |
| `[ a == a ]` | **error**: `unexpected operator` (rc 2) | works | works | SC3014 |
| arrays `a=(1 2 3)` | syntax error | syntax error | syntax error | SC3030 |
| `${v:1:2}` substring | `Bad substitution` | **works** (`bc`) | `Bad substitution` | SC3057 |
| `${v/a/b}`, `${v//a/b}` | `Bad substitution` | **works** | `Bad substitution` | SC3060 |
| `${v^^}`, `${v,,}` | `Bad substitution` | syntax error | `Bad substitution` | SC3059 |
| `${!name}` | `Bad substitution` | syntax error | `Bad substitution` | SC3053 |
| `$'a\tb'` | **silent**: prints `$a<TAB>b` (a literal `$`) | works | works | SC3003 |
| `<<<` here-string | syntax error | syntax error | syntax error | SC3011 |
| `<( )` process substitution | syntax error | **works** | syntax error | SC3001 |
| `&>` redirect both | **silent**: means `echo hi &` (background) then an empty redirect; `echo hi &> out.txt` left `out.txt` **empty** and printed `hi` on the screen | **works like bash** (no output; `out.txt` contains `hi`) | **silent**, same as dash | SC3020 |
| `\|&` | syntax error | syntax error | syntax error | SC3029 |
| `(( i++ ))` | **silent**: tries to run a command named `i++` (`not found`), `i` stays 1 | same | same | SC3006 |
| `$((i++))` | arithmetic error | **works** (`1 2`) | arithmetic error | SC3018 |
| `$((2**3))` | arithmetic error | works (`8`) | arithmetic error | SC3019 |
| `{1..3}` | **silent**: stays literal | literal | literal | SC3009 |
| `function f { }` | syntax error | works | syntax error | none shown |
| `source file` | `source: not found` | works | `source: not found` | SC3046 |
| `let i=2+3` | `let: not found` | works (5) | **works** (5) | SC3039 |
| `declare`, `typeset` | not found | not found | not found | SC3044 |
| `echo -n x` | works | works | works | SC3037 |
| `echo -e 'a\tb'` | **silent**: prints `-e a<TAB>b` | works | works | SC3037 |
| `read -n 1`, `read -a` | `Illegal option` | `-n` works; `-a` error | `Illegal option` | SC3045 |
| `read -p "prompt: " x` | works (`[val]`) | works | works | SC3045 |
| `printf -v s %03d 7` | `Illegal option -v` | **silent**: prints `-v` (treats it as the format) | `Illegal option -v` | SC3045 |
| `printf %q` | `invalid directive` | `invalid format` | **works** | SC3050 |
| `mapfile`, `coproc`, `shopt`, `pushd` | `not found` | `not found` | `not found` | SC3044, SC3032 |
| `$RANDOM`, `$SECONDS`, `$OSTYPE`, `$UID`, `$EUID`, `$HOSTNAME` | unset | `$RANDOM` and `$HOSTNAME` set | unset | SC3028 |
| `set -o pipefail` | **works** (this dash build) | works | works | SC3040 |
| `trap ... ERR`, `DEBUG` | `bad trap`, continues | ERR accepted; DEBUG error | `bad signal`, continues | SC3047 |
| `trap ... SIGTERM` | `bad trap` (killed, rc 15) | works | works | SC3048 |
| `[ -v x ]` | `unexpected operator` | `unknown operand` | `unexpected operator` | SC3016 |
| `select` | syntax error | syntax error | syntax error | SC3008 |
| `case ... ;&` | syntax error | syntax error | **works** (fall-through) | none shown |
| extglob `@(a\|b)` | syntax error | syntax error | syntax error | SC3044 |
| `**/*.txt` | literal | literal | literal | none shown |
| `$(<file)` | empty | empty | empty | SC3034 |
| `local -n` | `bad variable name` | `bad variable name` | `Illegal option -n` | SC3043 |
| `wait -n` | `Illegal option -n` | works | `Illegal option -n` | SC3045 |

One correction to how you read the `$'a\tb'` row: the **2024 edition of POSIX added `$'...'`** ([section 2.2.4](https://pubs.opengroup.org/onlinepubs/9799919799/utilities/V3_chap02.html)), so it is no longer only a bash feature. The tested dash still does not have it, and ShellCheck 0.11.0 still reports it, so for a `#!/bin/sh` script keep treating it as **not portable yet** and use `printf`.

What the table says:

1. **dash is the strictest of the three.** Almost everything that fails in dash is a bashism. When it fails in dash and passes in bash, **it is not POSIX**, whatever ash or the FreeBSD `sh` say.
2. **busybox ash accepts many bash extensions** (`${v:1:2}`, `${v/a/b}`, `[[ ]]`, `<( )`, `$((i++))`, `function`, `source`, `let`, `**`). A pass in ash proves little. Its `printf -v` silently printed `-v`, which would write the wrong thing into a file.
3. **The FreeBSD `sh` accepts a different set** (`==`, `let`, `;&`, `printf %q`, `$'...'`, `echo -e`, `pipefail`), and **rejects** `[[`, `${v/a/b}` and arrays. Passing on Chimera proves little too; **failing** there means the script is likely GNU-specific (see the userland differences in the next lesson).
4. **The silent ones are the dangerous ones**: `&>` (in dash and the FreeBSD `sh`), `(( ))`, `{1..3}`, `echo -e`, `$'...'` and `$(<file)` do not fail, they do something else. ShellCheck reports each of them; dash does not.
5. `set -o pipefail` **worked in all three** here (`false | true` gave status 1, tested also in dash 0.5.12-12ubuntu3 by `set -o` listing `pipefail`), but ShellCheck still calls it undefined in POSIX sh (SC3040). I do not know whether every dash and every other `sh` you will meet has it, so portable scripts must **not rely on it** and must handle pipeline failures explicitly.
6. There is **no safe way to "feature test" a bashism** in the middle of a `#!/bin/sh` script, because dash and the others parse the whole line first: a syntax error aborts before your check runs.

### How each shell reports syntax errors

```text
if true; then echo hi              dash:  s.sh: 2: Syntax error: end of file unexpected (expecting "fi")
                                   ash:   s.sh: line 2: syntax error: unexpected end of file (expecting "fi")
                                   Chimera: s.sh: 2: Syntax error: end of file unexpected (expecting "fi")
echo "oops                          dash:  s.sh: 2: Syntax error: Unterminated quoted string
                                   ash:   s.sh: line 2: syntax error: unterminated quoted string
                                   Chimera: s.sh: 1: Syntax error: Unterminated quoted string
v=abc; echo ${v:1}                  dash:  s.sh: 1: Bad substitution   (rc 2)         ash: prints bc          Chimera: s.sh: ${v:1}: Bad substitution
[[ -n x ]] && echo yes              dash:  s.sh: 1: [[: not found (rc 127)           ash: yes                Chimera: s.sh: [[: not found (rc 127)
```

Learn to recognise `Bad substitution`, `Syntax error: "(" unexpected`, `[[: not found` and `unexpected operator`: **all four mean "a bashism reached a POSIX shell"**.

## Checking a script

Four checks, in this order, on every `#!/bin/sh` script (the next lesson turns them into a harness):

1. `shellcheck -s sh script.sh` (optional tool; I always passed `-s sh`, which makes the `SC3xxx` dialect warnings appear; I did not test what it does with a `#!/bin/sh` shebang and no `-s`).
2. `dash -n script.sh` parses **without running** (I used `dash script.sh` in the tests; I did not test `dash -n` separately).
3. **Run it** with `dash script.sh`.
4. **Run it** with `busybox ash script.sh` and with the target system's own `sh` if it is not dash.

## Common mistakes

- **`#!/bin/sh` on a script that uses bash features** (works where `sh` is bash, fails on Ubuntu).
- **Testing a `#!/bin/sh` script with `bash script.sh`** (or on a system where `/bin/sh` is bash).
- **`echo` with variables or backslashes** (dash interprets them, the others do not); use `printf '%s\n'`.
- **`[ a == b ]`**, `[[ ]]`, `function f {`, `source`, `${v/a/b}`, arrays, `<<<`, `<( )`.
- **`local y` without a value** (dash keeps the outer value).
- **Sourcing without `./`** (`. lib.sh` is found on Chimera, not in dash or ash).
- **Relying on `$LINENO`**, `$RANDOM`, `$SECONDS`, `$OSTYPE`, `$UID`.
- **Believing a pass in busybox ash or in the FreeBSD `sh` proves POSIX.**

## Practice

All snippets go in files; run each under `dash`, `busybox ash` (if you have it) and the system `sh`.

1. **Which shell is `sh`?** Run `ls -l /bin/sh` on every machine and VM you have, and write down what it is. If it is bash, how will you test a `#!/bin/sh` script there?
2. **Reproduce the strictness.** Write a three-line script with `[[ -n "$1" ]] && echo yes`. Run it under `bash`, `dash` and `busybox ash`; record the three results and the dash error.
3. **Find the silent ones.** Run `echo hi &> /dev/null; echo done`, `i=1; ((i++)); echo $i` and `echo {1..3}` under dash and say what each really did.
4. **Fix a script.** Convert this bash fragment to POSIX sh and prove it with dash: `a=(1 2 3); for x in "${a[@]}"; do [[ $x == 2 ]] && echo two; done`.
5. **The `echo` trap.** Show `echo 'a\tb'` in two shells and rewrite it with `printf`. Then show `printf '%s\n' "-n"` against `echo "-n"`.
6. **The `local` trap.** Reproduce the `[g]` against `[unset]` difference and fix the function so it gives the same answer everywhere.
7. **Read the error.** For each of `Bad substitution`, `[[: not found`, `unexpected operator`, `Syntax error: "(" unexpected`, write the bashism that caused it and the POSIX replacement.
8. **ShellCheck.** Run `shellcheck -s sh` on the script from exercise 4 before and after, and list the SC3 codes it printed.
9. **Predict, then run.** `set -- a; shift 2; echo after` in dash, ash and the system `sh`: predict each, then check. What does this mean for a script that shifts blindly?
10. **Find the bug.** (a) `#!/bin/sh` then `if [ "$1" == "-h" ]; then ...` (b) `#!/bin/sh` then `echo -e "Usage:\n  $0 file"` (c) `#!/bin/sh` then `. lib.sh` (d) `#!/bin/sh` then `printf -v out "%s" "$x"`. Say in which shell each fails or misbehaves, and fix it.

## Check your understanding

Take the quiz for this lesson (it draws ten from the bank). After a wrong answer, reread the section named in the review line.
