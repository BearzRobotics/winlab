*Draft for owner review.* Command Prompt (`cmd.exe`) is the oldest of Windows' command shells and is still everywhere: in recovery tools, installers, scheduled tasks and batch files that have run for twenty years. Competence here means knowing not only the commands but **how cmd reads a line**, because most batch-file bugs are parsing surprises. This lesson builds that foundation; the lessons after it cover variables, control flow, batch files, text tools and advanced technique.

Every command in this lesson was run on Windows 11 to check its output. All exercises are safe: they read information or write inside a scratch folder you create. The graphical way is shown beside each command-line way, because most people use the GUI most of the time and you should be able to do both.

## Opening it and getting oriented

**GUI routes:** press **Win+R**, type `cmd` and press Enter; or search the Start menu for *Command Prompt*; or open **Windows Terminal** and choose the *Command Prompt* profile. In **File Explorer**, click the address bar, type `cmd` and press Enter to open a prompt **in that folder**. Run it as administrator only when a task needs it (right-click, *Run as administrator*); an elevated prompt can change anything.

The prompt shows your **current directory**. Try:

```
cd
dir
ver
```

`cd` with no arguments prints the current directory (`%CD%` holds the same value). `dir` lists its contents, which is what File Explorer's folder view shows. `ver` prints the Windows version:

```
Microsoft Windows [Version 10.0.26300.9974]
```

`cd ..` goes up one level and `cd <folder>` goes into one. **To change drive**, type the drive letter alone (`D:`); to change both at once use `cd /d D:\data` (without `/d`, `cd` changes the remembered folder on that drive but stays on the current drive, a classic surprise).

`help` lists the built-in commands; `help dir` or `dir /?` explains one. The official reference is the [Windows commands](https://learn.microsoft.com/windows-server/administration/windows-commands/windows-commands) index, and [`cmd`](https://learn.microsoft.com/windows-server/administration/windows-commands/cmd) documents the interpreter itself.

## How cmd runs what you type

Knowing the order saves hours later.

1. **Read the line.** cmd reads one line (or one parenthesised block in a batch file) as text.
2. **Parse special characters.** `& | < > ( ) ^` and quotes have meaning *before* any command runs (see the table below).
3. **Expand `%variables%`.** In a batch file this happens when the line is read (the next lesson shows why that matters in blocks).
4. **Find what to run.** If the first word is a **built-in** command (`cd`, `dir`, `echo`, `set`, `copy`, `if`, `for`...), cmd runs it itself. Otherwise it looks for a program: first the **current directory**, then each folder in `%PATH%`, trying each extension in `%PATHEXT%`.
5. **Run it and record the exit code.**

```
echo %PATHEXT%
.COM;.EXE;.BAT;.CMD;.VBS;.VBE;.JS;.JSE;.WSF;.WSH;.MSC;.CPL
```

So typing `notepad` finds `notepad.exe` because `.EXE` is in `PATHEXT`, and typing `deploy` runs `deploy.bat` or `deploy.cmd` if one is found first. **Searching the current directory first is a security risk**: a planted `ping.exe` in the folder you are in would run when you type `ping` (built-in commands such as `dir` cannot be overridden this way, programs can). Do not run commands from an untrusted folder, and prefer full paths in scripts. Windows can switch the behaviour off: when the environment variable `NoDefaultCurrentDirectoryInExePath` is defined, cmd stops searching the current directory for programs and a script in the current folder must be started as `.
ame.cmd` (see [NeedCurrentDirectoryForExePath](https://learn.microsoft.com/windows/win32/api/processenv/nf-processenv-needcurrentdirectoryforexepathw)). Test your scripts with and without it.

To see **which** program a name resolves to, use [`where`](https://learn.microsoft.com/windows-server/administration/windows-commands/where):

```
where notepad
C:\Windows\System32\notepad.exe
C:\Windows\notepad.exe
C:\Users\student\AppData\Local\Microsoft\WindowsApps\notepad.exe
```

The first line is the one that runs. (`where` lists matches by the search order; built-ins such as `dir` are not programs, so `where dir` finds nothing.)

### Special characters

| Character | Meaning | Escape it with |
|---|---|---|
| `&` | run the next command, always | `^&` |
| `&&` | run the next only if this one succeeded | `^&^&` |
| `\|\|` | run the next only if this one failed | `^\|^\|` |
| `\|` | pipe output into the next command | `^\|` |
| `<` `>` | redirect input, output | `^<` `^>` |
| `( )` | group commands into a block | `^(` `^)` |
| `^` | escape the next character | `^^` |
| `%` | variable expansion | `%%` in a batch file |
| `"` | quote: protects spaces and most specials inside | `""` is not an escape; nest carefully |

```
echo 1 ^& 2
1 & 2
echo a & echo b
a 
b
```

Notice that `echo a & echo b` printed `a ` with a **trailing space**: cmd passes the space before `&` to `echo`. Trailing spaces in output, and in values set with `set X=value & ...`, are a common source of bugs; the next lesson returns to it.

Two more traps in one place:

```
echo done 2>&1
echo 1> file.txt
(echo 1)> file.txt
```

The first line prints `done` and nothing else: `2>&1` is taken as a redirection **of the echo itself**, so it is not printed. The second does not write the character `1`: `1>` is parsed as "redirect stdout", so `echo` runs with no text and writes its status message (`ECHO is off.`) to the file. The third, with the command in parentheses, writes `1`. (A `rem` comment cannot follow a command on the same line, because cmd would treat it as part of the command, so comments here are in the text.)

## Quoting paths with spaces

A space separates arguments, so a path that contains one must be quoted:

```
dir "C:\Program Files\Common Files"
dir C:\Program Files
```

The second command fails (exit code 1): `dir` sees two arguments, `C:\Program` and `Files`. **`cd` is the exception**: `cd C:\Program Files` happens to work, because `cd` treats the rest of the line as one path. That leniency is exactly why the habit of quoting matters: it works with `cd` and then fails with the next command. Quote every path you expand from a variable too: `dir "%USERPROFILE%\Documents"`.

## Working with files and folders

| GUI action in File Explorer | Command |
|---|---|
| open a folder and look | `cd`, `dir` |
| New folder | `mkdir name` (or `md`) |
| copy | `copy src dst`, `xcopy`, `robocopy` |
| cut and paste | `move src dst` |
| rename (F2) | `ren old new` (`rename`) |
| delete | `del file`, `rmdir folder` (`rd`) |
| Properties, hidden or read-only attribute | `attrib` |
| the folder tree | `tree` |
| open a text file | `type file`, `more file` |

The reference pages: [`dir`](https://learn.microsoft.com/windows-server/administration/windows-commands/dir), [`copy`](https://learn.microsoft.com/windows-server/administration/windows-commands/copy), [`move`](https://learn.microsoft.com/windows-server/administration/windows-commands/move), [`rename`](https://learn.microsoft.com/windows-server/administration/windows-commands/rename), [`del`](https://learn.microsoft.com/windows-server/administration/windows-commands/del), [`rmdir`](https://learn.microsoft.com/windows-server/administration/windows-commands/rmdir), [`mkdir`](https://learn.microsoft.com/windows-server/administration/windows-commands/mkdir), [`attrib`](https://learn.microsoft.com/windows-server/administration/windows-commands/attrib), [`tree`](https://learn.microsoft.com/windows-server/administration/windows-commands/tree), [`type`](https://learn.microsoft.com/windows-server/administration/windows-commands/type), [`more`](https://learn.microsoft.com/windows-server/administration/windows-commands/more).

Make a scratch area and practise inside it:

```
mkdir "%TEMP%\wl-cmd-demo"
cd /d "%TEMP%\wl-cmd-demo"
mkdir sub
echo one> a.txt
copy a.txt sub\b.txt
ren a.txt c.txt
move c.txt sub\ >nul
dir /b sub
b.txt
c.txt
```

`dir` has options worth knowing: `/b` bare names only (best for scripts), `/s` include subfolders, `/a:h` show hidden files, `/ad` folders only, `/o:n` sort by name. **Wildcards:** `*` matches any run of characters and `?` one character: `dir /b sub\*.txt`.

`tree /f /a` prints a folder tree with its files in plain ASCII (`/a` avoids box-drawing characters that some code pages garble).

**Deleting is permanent.** `del` and `rd` do **not** use the Recycle Bin. `del /q` suppresses the confirmation, `del /f` removes read-only files, and `rd /s /q folder` deletes a folder and everything in it without asking. Test a delete by running the same pattern with `dir` first, and never run a recursive delete from a variable that might be empty.

For serious copying use `robocopy`: it retries, preserves attributes and security, and mirrors folders. [`robocopy`](https://learn.microsoft.com/windows-server/administration/windows-commands/robocopy) is covered in the text-and-files lesson; [`xcopy`](https://learn.microsoft.com/windows-server/administration/windows-commands/xcopy) is its older cousin.

## Environment variables

Variables hold values such as paths. Read one by wrapping its name in percent signs:

```
echo %USERNAME%
echo %USERPROFILE%
echo %PATH%
```

`set` with no arguments lists all variables for this window; `set U` lists those that start with `U`. `set NAME=value` changes a variable **only for the current window and the programs it starts**; closing the window discards it. (Permanent changes use `setx` or the **System Properties, Environment Variables** dialog, and affect programs started *afterwards*.) `%PATH%` is the list of folders searched when you type a program name without its location. See [`set`](https://learn.microsoft.com/windows-server/administration/windows-commands/set_1).

## Redirection

Programs have three standard streams: **0** input (stdin), **1** output (stdout) and **2** errors (stderr). Redirection connects them to files or to each other.

| Syntax | Effect |
|---|---|
| `cmd > file` | send stdout to `file`, **replacing** it |
| `cmd >> file` | append stdout to `file` |
| `cmd < file` | read stdin from `file` |
| `cmd 2> file` | send stderr to `file` |
| `cmd > file 2>&1` | send stdout and stderr to the same file |
| `cmd >nul` | discard stdout |
| `cmd >nul 2>nul` | discard everything |
| `cmd 1>&2` | send stdout to where stderr goes (used to print an error message) |

```
echo hello > "%TEMP%\hello.txt"
echo again >> "%TEMP%\hello.txt"
type "%TEMP%\hello.txt"
dir nothere > out.txt 2>&1
type out.txt
```

`>` **overwrites an existing file without asking**. **Order matters:** `cmd > file 2>&1` sends both to the file, but `cmd 2>&1 > file` sends errors to the screen, because `2>&1` was evaluated first, when stdout still pointed at the screen. `nul` is the device that discards anything written to it.

## Pipes

A pipe `|` feeds one command's output into another's input:

```
dir C:\Windows | more
set | findstr /i "user"
```

`findstr` filters lines, and `more` shows output one page at a time. In CMD, pipes pass **text**; remember that when you meet PowerShell, which passes objects. Both sides of a pipe run in **separate cmd processes**, so a variable set on one side of a pipe is not visible afterwards.

## Exit codes

When a program finishes it returns a number: `0` normally means success and anything else means failure. Read the last one with `%ERRORLEVEL%`:

```
dir C:\Windows >nul
echo %ERRORLEVEL%
0
dir C:\does-not-exist >nul 2>nul
echo %ERRORLEVEL%
1
cmd /c exit 3
echo %ERRORLEVEL%
3
```

`cmd /c <command>` runs one command in a new cmd and exits (`cmd /k` keeps the new prompt open). `exit /b 3` ends a batch file or subroutine with code 3. Scripts and scheduled tasks depend on these codes to decide whether a step worked. The related test `if errorlevel 1` means **1 or greater** (not "equal to 1"), a historical quirk the control-flow lesson covers.

## Combining commands

- `a & b` runs both, always.
- `a && b` runs `b` only if `a` succeeded (exit code 0).
- `a || b` runs `b` only if `a` failed.
- `( a & b )` groups commands, so you can redirect or conditionally run them as one.

```
dir C:\Windows >nul && echo found || echo missing
```

## Housekeeping commands

`cls` clears the screen; `title Name` sets the window title; `color 0A` sets colours (green on black); `doskey /history` lists what you typed (press **F7** for a pop-up list, **Up** to recall); `echo %DATE% %TIME%` shows the date and time in the **regional format**, which differs between machines: never parse it without checking the locale. The commands are [`cls`/`title`/`color`](https://learn.microsoft.com/windows-server/administration/windows-commands/title) and [`doskey`](https://learn.microsoft.com/windows-server/administration/windows-commands/doskey).

To start a graphical program from a prompt and **not** wait for it, use `start`: `start "" notepad`. (The empty quotes are the window title; without them a quoted path is misread as the title.)

## Limits

A single command line in cmd can be at most **8191 characters**; a longer one fails or is truncated, which matters when you build a long command from variables. cmd works in the **OEM or ANSI code page**, not Unicode, so non-English file names and text can appear garbled (the `chcp` command shows and changes the code page). It has no real data types, no arrays and weak error handling, which is why the advanced lesson ends by deciding when to move to PowerShell.

## From commands to batch files

A **batch file** (`.bat` or `.cmd`) is a text file of commands run top to bottom. A minimal one:

```
@echo off
echo Running as %USERNAME%
dir "%USERPROFILE%" > "%TEMP%\listing.txt"
echo Done, exit code %ERRORLEVEL%
```

`@echo off` stops each command from being printed before it runs (the `@` hides the `echo off` line itself). Save it as `hello.cmd` and run it by typing its name from its folder. Use `.cmd` rather than `.bat` for new files: the two behave almost identically, with one old difference in how some commands set the exit code. In a batch file, write `%%` where you would type `%` in the prompt for a `for` variable (the control-flow lesson explains this).

## Common mistakes

- **Not quoting a path** that contains a space.
- **Forgetting `/d`** with `cd` when changing drive.
- **Using `>` when you meant `>>`,** and overwriting a file.
- **Putting `2>&1` after `echo`** and having it swallowed.
- **Trusting `echo a & echo b`** to print `a` with no trailing space.
- **Running programs from an untrusted current directory.**
- **Using `del` or `rd /s` from a variable that might be empty.**
- **Parsing `%DATE%`** as if every machine printed the same format.

## Practice

1. In a scratch folder, create `a.txt` containing `one`, copy it to a sub-folder, rename the copy, and show the result with `tree /f /a`.
2. Run `dir C:\does-not-exist > both.txt 2>&1`, then `type both.txt`. Now repeat with `2>&1 > both2.txt` and compare what appears on screen.
3. Using `&&` and `||`, print `found` if `C:\Windows` exists and `missing` otherwise (hint: `dir` sets the exit code).
4. Use `where` to find out which `ping` program runs, then check `echo %PATH%` to explain why.
5. Write a three-line batch file that saves your profile listing to `%TEMP%\listing.txt` and prints the exit code. Run it, then break it on purpose (quote a missing folder) and read the code.

## Check your understanding

1. What is the difference between `>` and `>>`?
2. Why does `cd D:\data` appear to do nothing when you are on `C:`, and how do you fix it? Which command does work with an unquoted path containing a space, and why is that no reason to skip quoting?
3. What does an exit code of `0` mean, and why do scripts care?
4. In what order does cmd decide what `ping` means?
5. Why does `echo done 2>&1` not print `2>&1`?
6. What is the difference between `cmd > f 2>&1` and `cmd 2>&1 > f`?
7. A cmd pipe runs `a | b`. Why is a variable set inside `b` gone afterwards?

**Expected answers:** (1) `>` replaces the file and `>>` appends; (2) `cd` without `/d` changes the remembered folder on `D:` but not the current drive, so use `cd /d D:\data` or switch drive first; `cd` accepts an unquoted path with spaces but `dir` and most commands do not, so quote anyway; (3) it normally signals success, and scripts use it to decide what to do next; (4) built-in commands first, then the current directory, then each `%PATH%` folder, trying each `%PATHEXT%` extension; (5) the shell takes `2>&1` as a redirection of `echo` itself; (6) the first sends both streams to the file; the second sends errors to the screen because `2>&1` is evaluated while stdout still points there; (7) each side of a pipe runs in its own cmd process, which ends when the pipe does.
