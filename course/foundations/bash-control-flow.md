The first bash lesson covered commands, pipes and writing a short script. Real scripts decide, loop over data, share code through functions, and fail safely. This lesson is about those habits, and about the mistakes that cause most shell-script bugs. Everything uses only the shell and standard tools, so it works on any Linux server.

## Conditions

`if` runs a command and looks at its exit status (0 is success). The usual command to test things is `[ ... ]`, which is just a program with a funny name; the spaces inside the brackets are required.

```bash
if [ -f /etc/passwd ]; then echo "is a regular file"; fi
if [ -d /var/log ];    then echo "is a directory";    fi
if [ -z "$name" ];     then echo "name is empty";     fi
if [ "$a" = "$b" ];    then echo "strings equal";     fi
if [ "$n" -gt 10 ];    then echo "number greater";    fi
```

| Test | True when |
| --- | --- |
| `-e` `-f` `-d` | path exists, is a regular file, is a directory |
| `-r` `-w` `-x` | readable, writable, executable by you |
| `-z` `-n` | string is empty, is not empty |
| `=` `!=` | strings are equal, not equal |
| `-eq` `-ne` `-gt` `-ge` `-lt` `-le` | numbers |

Numbers use letters (`-gt`) and strings use symbols (`=`). Mixing them up is a classic mistake.

Bash also has `[[ ... ]]`, which is safer and more capable: it does not word-split variables, supports `&&` and `||` inside, and does pattern and regular-expression matching (`[[ $file == *.log ]]`, `[[ $x =~ ^[0-9]+$ ]]`). Prefer it in scripts that start with `#!/bin/bash`.

Combine tests with `&&` ("and") and `||` ("or"), which run the right side only if the left succeeded or failed:

```bash
[ -d backup ] || mkdir backup        # create it only if missing
cd /srv/app && ./deploy.sh           # deploy only if cd worked
```

Chains with `if`:

```bash
if [ "$n" -lt 10 ]; then
    echo small
elif [ "$n" -lt 100 ]; then
    echo medium
else
    echo large
fi
```

## case

`case` matches one value against patterns, which is tidier than a long `elif` chain:

```bash
case "$answer" in
    y|Y|yes) echo "continuing" ;;
    n|N|no)  echo "stopping"; exit 1 ;;
    *)       echo "please answer yes or no" ;;
esac
```

Each branch ends with `;;`. Patterns use shell wildcards (`*`, `?`, `[abc]`), `|` means "or", and `*)` is the catch-all.

## Loops

```bash
# over a list of words
for color in red green blue; do echo "$color"; done

# over files: let the shell expand the glob, and quote the variable
for f in /var/log/*.log; do echo "$f"; done

# counting
for i in 1 2 3; do echo "$i"; done
for ((i = 0; i < 3; i++)); do echo "$i"; done

# while a condition holds, or until it becomes true
n=0
while [ "$n" -lt 3 ]; do echo "$n"; n=$((n + 1)); done
until ping -c1 -W1 example.com >/dev/null; do sleep 5; done
```

`break` leaves a loop; `continue` skips to the next pass.

**The safe way to read a file line by line:**

```bash
while IFS= read -r line; do
    echo "got: $line"
done < /home/labadmin/labdata/names.txt
```

`IFS=` stops leading and trailing spaces being trimmed, and `-r` stops backslashes being interpreted. To split a line into fields, give `read` several names: `while IFS=: read -r user uid shell; do ... done < users.txt`.

**What to avoid:** `for f in $(ls)`. Command substitution is split on spaces, so a file called `my notes.txt` becomes two items, and file names starting with `-` are read as options. Use a glob (`for f in *`) or `find ... -print0` with `read -d ''` for unusual names.

## Functions and variables

```bash
log() {
    local level=$1
    shift
    echo "[$level] $*"
}

log INFO "starting"
log ERROR "something failed"
```

- Arguments are `$1`, `$2`, ... inside the function, just as in a script. `shift` drops the first one.
- Declare variables with `local`, or they are global and may clash with the rest of the script.
- A function's **status** is set with `return N` (0 to 255) and read from `$?`. A function's **value** is what it prints; capture it with `$(...)`:

```bash
square() { echo $(( $1 * $1 )); }
result=$(square 7)
```

## Arrays

```bash
files=(report.txt notes.txt data.csv)
echo "${files[0]}"          # report.txt
echo "${#files[@]}"         # 3 (the length)
for f in "${files[@]}"; do echo "$f"; done

declare -A count            # an associative array (a dictionary)
count[error]=3
count[info]=12
for key in "${!count[@]}"; do echo "$key: ${count[$key]}"; done
```

Always write `"${array[@]}"` with the quotes so each element stays one word.

## Failing safely

By default a script carries on after a failing command. These options change that; learn what each does before you use it:

```bash
set -u              # using an unset variable is an error (catches typos)
set -e              # exit when a simple command fails (has surprising exceptions)
set -o pipefail     # a pipeline fails if ANY stage fails, not just the last one
```

A common, sensible start for scripts is `set -u` and `set -o pipefail`, plus explicit checks where you expect failure. `set -e` is convenient but its rules (it does not trigger inside `if` conditions or on the left of `&&`) trip people up.

Clean up after yourself with `trap`:

```bash
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT     # runs when the script ends, even on error
```

Use exit statuses honestly: `0` for success, `1` or other for failure, and print messages to standard error with `>&2`. Cron, systemd and other scripts depend on them.

## Good habits

- Quote every variable expansion unless you specifically want word splitting.
- Prefer `$(...)` to backticks, and `[[ ]]` to `[ ]` in bash scripts.
- Check your script with `bash -n script.sh` (syntax only) and run it on a copy of real data.
- Keep scripts small. When a script grows parsing and data structures, consider whether another tool fits better.

## Practice

The labs for this lesson ask for scripts that count by category with `case`, read a file line by line with functions, report with exit statuses, make a backup and rotate old ones, and handle arguments. Each is checked against fresh data and, where it matters, the exit status and the files left on disk.

## Check your understanding

1. Why can `if [ $name = "bob" ]` fail with a syntax error, and what two changes make it robust?
2. What does `for f in $(ls)` get wrong, and what replaces it?
3. How do you get a function's printed result into a variable, and how do you signal that it failed?
4. What does `set -o pipefail` change about `grep ERROR app.log | sort`?

**Expected answers:** (1) if `$name` is empty the test becomes `[ = "bob" ]`; quote the variable (`"$name"`) or use `[[ ]]`; (2) it splits on spaces and treats leading dashes as options; use a glob, `for f in /path/*`, and quote `"$f"`; (3) `result=$(myfunc args)`, and `return 1` (read with `$?`) to signal failure; (4) the pipeline's status becomes failure if `grep` fails (for example the file is missing), instead of always reporting `sort`'s success.
