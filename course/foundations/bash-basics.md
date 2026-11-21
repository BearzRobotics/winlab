Most servers in the world run Linux, and the way you work on them is a shell: a program that reads what you type and runs it. The usual one is **bash**. This lesson uses only what ships with the system. Nothing here needs extra software, so it works on any Linux server you meet, whatever else is installed.

You will practise on a Linux lab VM. Open the lab for this lesson to get one. The exercises only read or write inside your home folder.

## Running commands and getting help

A command is a program name followed by arguments:

```
ls -l /etc
echo hello
```

Three habits save a lot of time:

- `man ls` shows the manual page for a command. Press `q` to leave it, `/` to search inside it.
- `command --help` prints a short summary for most programs.
- `type ls` or `which ls` tells you what a name refers to (a program, a built-in, an alias).

## Where you are

```
pwd             # print the current folder
cd /var/log     # change folder
ls -la          # list files, including hidden ones, with details
cd              # back to your home folder
```

Paths that start with `/` are absolute; others are relative to where you are. `~` stands for your home folder and `..` for the folder above.

## Pipes and redirection

Every program has three streams: standard input (0), standard output (1) and standard error (2). The shell connects them:

```
ls /etc > files.txt          # send output to a file, replacing it
ls /etc >> files.txt         # append instead
sort < files.txt             # read input from a file
ls /nonexistent 2> err.txt   # send ONLY errors to a file
ls /etc | wc -l              # a pipe: the output of one command is the input of the next
```

Pipes are the heart of the shell. Small programs that each do one thing, joined together:

```
grep ERROR app.log | sort | uniq -c | sort -rn | head -5
```

Read that left to right: find the ERROR lines, sort them, count duplicates, order by count, keep the top five.

## Variables, quoting and command substitution

```
name=Alice                 # no spaces around =
echo "Hello, $name"
today=$(date +%F)          # run a command and keep its output
echo "Report for $today"
```

Quoting decides what the shell is allowed to interpret:

| Form | Meaning |
| --- | --- |
| `'single'` | Everything is literal. `'$name'` prints `$name`. |
| `"double"` | Variables and `$( )` are expanded, but spaces are kept together. |
| no quotes | The shell expands variables and then splits the result into words on spaces, and expands `*` against file names. |

The last row causes most beginner bugs. If a file is called `my notes.txt`, then `rm $file` becomes `rm my notes.txt` (two files), while `rm "$file"` is correct. **Quote your variables.**

## Exit status

Every command ends with a number. `0` means success; anything else means failure. The shell stores the last one in `$?`:

```
grep -q ERROR app.log
echo $?        # 0 if found, 1 if not found
```

`if` runs a command and tests its status:

```
if grep -q ERROR app.log; then
    echo "errors found"
else
    echo "clean"
fi
```

`[ ... ]` is itself a command that tests things: `[ -f file ]` (is a regular file), `[ -d dir ]` (is a directory), `[ "$a" = "$b" ]` (strings equal), `[ "$n" -gt 3 ]` (number greater than 3). Leave spaces inside the brackets.

## Loops

```
for f in /var/log/*.log; do
    echo "$f has $(wc -l < "$f") lines"
done

n=0
while [ "$n" -lt 3 ]; do
    echo "n is $n"
    n=$((n + 1))
done
```

`$(( ... ))` does arithmetic on whole numbers.

## Your first script

A script is a text file of commands. Save this as `hello.sh`:

```
#!/bin/bash
# greet each argument
if [ "$#" -eq 0 ]; then
    echo "usage: hello.sh NAME..." >&2
    exit 2
fi
for who in "$@"; do
    echo "Hello, $who!"
done
```

- The first line (`#!/bin/bash`, the *shebang*) says which program should run the file.
- `$1`, `$2`, ... are the arguments, `$#` is how many there are, and `"$@"` is all of them, each kept as one word.
- `>&2` sends a message to the error stream, which is where error messages belong.
- `exit 2` ends the script with a failure status other callers can test.

Make it executable and run it:

```
chmod +x hello.sh
./hello.sh Alice Bob
```

The `./` matters: the shell only searches the folders listed in `$PATH` for commands, and the current folder is not one of them.

## Good habits

- Start scripts with `set -u` (an unset variable is an error) while learning; add `set -e` only when you understand what it changes.
- Test with a copy of real data, never the only copy.
- Print errors to standard error and use exit statuses honestly. Cron and other scripts depend on them.
- Prefer the simple tool: `grep -c` over a loop that counts by hand.

## Practice

Open the labs for this lesson. They give you a task, a starter file in `/home/labadmin/labs`, and a check that runs your script against fresh data each time. Start with counting errors in log files, then work through the others.

## Check your understanding

1. What is the difference between `echo '$HOME'` and `echo "$HOME"`?
2. A script is run as `./backup.sh v7`. What do `$1` and `$#` contain?
3. Why does `rm $file` fail on a file called `my notes.txt`, and how do you fix it?
4. What does `echo $?` show right after `grep -q needle haystack.txt` finds nothing?

**Expected answers:** (1) the first prints the text `$HOME`, the second prints your home folder's path; (2) `$1` is `v7` and `$#` is `1`; (3) unquoted, the shell splits it into two words; quote it as `rm "$file"`; (4) `1`, because `grep` exits with status 1 when it finds no match.
