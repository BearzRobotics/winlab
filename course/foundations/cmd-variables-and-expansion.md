*Draft for owner review.* Variables are where most batch-file bugs live. cmd has no data types: a variable is a piece of text in the environment, and *when* that text is substituted into your command depends on a parsing rule that surprises everyone once. This lesson covers every way to set and read a variable, arithmetic, string slicing, the two kinds of expansion, scope, and the special variables Windows provides. Every example was run on Windows 11, and the outputs are real.

Run the examples from a `.cmd` file (save one in a scratch folder such as `%TEMP%\wl-cmd-demo`), not only from the prompt: some behaviour differs between the two, and the lesson says where.

## What a variable is

Every process has an **environment**: a list of `NAME=value` text pairs. cmd copies its environment from its parent, and every program cmd starts receives a copy of cmd's. Three facts follow:

- Values are **always text**. `5` is the characters "5"; arithmetic is something `set /a` does to text.
- **Names are not case-sensitive** in cmd (`%PATH%` and `%Path%` are the same variable).
- A change made in one process affects only that process and the programs it starts **afterwards**. It never reaches the parent. That is why a batch file you *run* cannot change your prompt's variables, while one you `call` from another batch file can (it runs in the same cmd).

Official reference: [`set`](https://learn.microsoft.com/windows-server/administration/windows-commands/set_1) and [`setlocal`](https://learn.microsoft.com/windows-server/administration/windows-commands/setlocal).

## Setting and reading

```
set name=Alice
echo %name%
Alice
set name
name=Alice
set name=
```

`set name=Alice` sets the variable (no spaces around `=`), `echo %name%` reads it, `set name` lists the variables whose names start with `name`, and `set name=` with nothing after the `=` deletes it. (Never put a comment on the same line as a `set`: everything after the `=` is the value, comment included. Use a separate `rem` line.)

**The spaces trap.** Spaces are part of the name and the value:

```
set x = 1
set x
x = 1
```

This created a variable called `x ` (with a trailing space) whose value is ` 1` (with a leading space). `%x%` is empty, and `%x %` is ` 1`:

```
echo [%x %] [%x%]
[ 1] []
```

**The quoted form fixes both problems.** Put the whole assignment in quotes, and nothing outside the quotes becomes part of the value:

```
set "name=Alice "
echo [%name%]
[Alice ]
set name=Bob 
echo [%name%]
[Bob ]
set "name=Bob"
echo [%name%]
[Bob]
```

In the first, the space before the closing quote is kept deliberately. In the second, a trailing space after `Bob` (invisible in the file) was kept silently: that is the bug. In the third, nothing outside the quotes can become part of the value, and special characters such as `&` are safe. Make `set "name=value"` your habit. Without the quotes, `set name=a & b` sets `name` to `a ` and then tries to run a command named `b`. To clear a variable, `set name=` works; to test it use `if defined name`.

### Reading input: `set /p`

```
set /p answer=Continue? (y/n): 
```

shows the prompt and stores what the user types. Pressing Enter without typing leaves the variable **unchanged**, so clear it first if you need to know whether it was set. With a redirect, `set /p` reads a line from a file: `set /p first=<file.txt` stores the first line.

### What `set` shows

`set` alone lists every variable, sorted. `set P` lists those whose names start with `P`. In PowerShell the same variables are the `Env:` drive (`Get-ChildItem Env:`); the PowerShell lessons compare the two.

## Arithmetic with `set /a`

`set /a` evaluates integer expressions. Inside `/a`, a variable name is read **without** percent signs:

```
set /a a=7*6
echo %a%
42
set /a b=17/5, c=17%%5
echo %b% %c%
3 2
set /a h=5, h+=3
echo %h%
8
```

| Operators | Meaning |
|---|---|
| `+ - * /` | add, subtract, multiply, **integer** divide (17/5 is 3) |
| `%` (`%%` in a batch file) | remainder |
| `( )` | grouping |
| `<< >>` | shift left, right |
| `& \| ^ ~` | bitwise and, or, xor, not |
| `= += -= *= /= %= &= ^= \|= <<= >>=` | assignment forms; a comma separates several assignments |

Rules that catch people:

- **32-bit signed.** Results wrap silently: `set /a f=2147483647+1` gives `-2147483648`. There are no floating-point numbers, and no 64-bit integers.
- **A leading `0` means octal.** `set /a d=010+1` gives `9`, not `11`. `0x` means hexadecimal: `set /a e=0x1F` gives `31`. A value like `08` is an error. Strip leading zeros from user input before using it.
- **Bitwise and shift operators are special characters to cmd.** Quote the whole expression: `set /a "g=1<<4"` gives `16`, and `set /a "m=0xFF & 0x0F"` gives `15`.
- `set /a` with no assignment prints the result, which is handy at the prompt: `set /a 6*7`.
- `%RANDOM%` is a pseudo-random number from 0 to 32767. A random number from 1 to 6: `set /a r=%random% %% 6 + 1`.

## String substitution and slicing

You can modify a variable while expanding it:

```
set s=C:\Dir\file.txt
echo %s:\=/%
C:/Dir/file.txt
echo %s:~3,3%
Dir
echo %s:~-3%
txt
echo %s:~0,-4%
C:\Dir\file
echo %s:*\=%
Dir\file.txt
```

In order: every `\` replaced by `/`; three characters from offset 3; the last three characters; everything but the last four; and everything up to and including the first `\` deleted.

| Form | Meaning |
|---|---|
| `%v:old=new%` | replace every `old` with `new` (case-insensitive); `%v:old=%` deletes it |
| `%v:~n%` | from offset `n` (0-based) to the end |
| `%v:~n,len%` | `len` characters from offset `n` |
| `%v:~-n%` | the last `n` characters |
| `%v:~n,-m%` | from `n`, leaving off the last `m` |
| `%v:*text=%` | delete everything up to and including the first `text` |

These forms work on **variables only**, not on `%1` parameters (copy the parameter into a variable first).

## When is a variable expanded?

This is the single most important idea in the lesson.

cmd reads a **line** (or a whole parenthesised block, which counts as one line), replaces every `%variable%` in it with the value the variable has **at that moment**, and only then runs the line. A variable that changes *during* the line, or inside a block, is not re-read.

**Same line:**

```
set y=1 & echo y=%y%
y=
echo after: %y%
after: 1 
```

The first `echo` printed nothing for `y`, because `%y%` was replaced before `set` ran. (It also shows the trailing-space trap: the value is `1 `, with a space, because of the space before `&`.)

**Inside a block**, this breaks every loop that counts:

```
setlocal enabledelayedexpansion
set z=0
for %%i in (a b c) do (set /a z+=1 & echo !z!)
1
2
3
for %%i in (a b c) do (set /a z+=1 & echo %z%)
3
3
3
```

With `%z%`, the value was fixed to what `z` was (3, left by the first loop) before the block ran, so it printed `3` three times. With `!z!` it was read each time the `echo` ran.

### Delayed expansion

Turn it on, usually at the top of the script, with `setlocal enabledelayedexpansion`, and then:

- `%var%` is still replaced when the line is read;
- `!var!` is replaced **when the command executes**.

Use `!var!` for any variable that is **changed inside a block or loop and read in the same block**. Costs:

- With delayed expansion on, **a `!` in a value or in text is consumed**: `set "t=Hello!"` then `echo !t!` prints `Hello`. To keep a `!` in a value, set the value **while delayed expansion is off** (`setlocal disabledelayedexpansion`) and read it with `!var!` afterwards, or write `^!` (one caret) in the `set` line while it is on. The advanced lesson shows the tests.
- It is a property of the current `setlocal`; it is off by default in a batch file, and off at the prompt (use `cmd /v:on` to start a prompt with it).

### Another expansion trap: `)` inside a block

```
if 1==1 (
  echo before
  echo %ProgramFiles(x86)%
)
before
C:\Program Files (x86
```

`%ProgramFiles(x86)%` expands to a text containing `)`, which ends the block early. The expected output lost its last character and the rest of the block ran at the wrong place. Inside blocks, copy such values into a variable with the quoted form first, outside the block (`set "pf86=%ProgramFiles(x86)%"`), and use `!pf86!` inside.

## Scope: `setlocal` and `endlocal`

By default a batch file changes the environment of the cmd that runs it. To keep your variables private, bracket the script:

```
setlocal
set "tmp1=work value"
...
endlocal
```

Everything set after `setlocal` is discarded at `endlocal` (or at the end of the script). `setlocal` calls nest. Add `enabledelayedexpansion` as above when you need it, and `enableextensions` is the default on modern systems.

**Returning a value from inside a `setlocal`.** The classic trick uses the line-expansion rule from above: `endlocal` and the `set` are on one line, so `%local1%` is replaced *before* `endlocal` discards it:

```
:f
setlocal
set "local1=value from inside"
endlocal & set "result=%local1%"
goto :eof
```

After `call :f`, `%result%` holds `value from inside`. This is the standard way to write a subroutine that returns something without leaking its working variables.

## Parameters

A batch file's arguments are `%1` to `%9`; `%0` is the script's own name and `%*` is **all** the arguments. `shift` moves them down by one (`%2` becomes `%1`), which is how you process more than nine:

```
call :sh a b c
...
:sh
echo %1 %2 %3
a b c
shift
echo %1 %2 %3
b c 
```

### Parameter modifiers

A `~` between the `%` and the digit asks for a transformation. Given `C:\Windows\System32\drivers\etc\hosts` as `%1`:

| Form | Result |
|---|---|
| `%~1` | the argument with surrounding quotes **removed** |
| `%~f1` | the full path: `C:\Windows\System32\drivers\etc\hosts` |
| `%~d1` | the drive: `C:` |
| `%~p1` | the path, no drive: `\Windows\System32\drivers\etc\` |
| `%~n1` | the file name only: `hosts` |
| `%~x1` | the extension, with the dot (empty here: `hosts` has none) |
| `%~dp1` | drive and path: `C:\Windows\System32\drivers\etc\` |
| `%~nx1` | name and extension: `hosts` |
| `%~z1` | the size in bytes |
| `%~t1` | the date and time |
| `%~a1` | the file attributes |

These work for the loop variable of `for` too (`%%~nxf`). The most useful one of all is **`%~dp0`**: the folder the script lives in, always ending with a backslash. Use it to find files beside the script, wherever it was started from:

```
call "%~dp0lib\helpers.cmd"
copy "%~dp0settings.ini" "%TEMP%"
```

**Always quote parameters when you use them**: `"%~1"`. The `~` form strips the user's quotes and your own quotes put protection back, so a path with spaces survives.

## Variables Windows provides

| Variable | Holds |
|---|---|
| `%CD%` | the current directory |
| `%DATE%`, `%TIME%` | date and time **in the regional format** (do not parse without checking the locale) |
| `%RANDOM%` | a random number, 0 to 32767 |
| `%ERRORLEVEL%` | the exit code of the last command |
| `%CMDCMDLINE%`, `%CMDEXTVERSION%` | the command line that started this cmd, and the command-extension version (`2`) |
| `%COMSPEC%` | the path of cmd.exe |
| `%COMPUTERNAME%`, `%USERNAME%`, `%USERDOMAIN%` | who and where |
| `%USERPROFILE%`, `%APPDATA%`, `%LOCALAPPDATA%`, `%TEMP%` | per-user folders |
| `%SystemRoot%`, `%SystemDrive%`, `%ProgramFiles%`, `%ProgramData%` | system folders; use them instead of assuming `C:\Windows` |
| `%ProgramFiles(x86)%` | the 32-bit program folder (mind the parentheses trap above) |
| `%PROCESSOR_ARCHITECTURE%` | `AMD64`, `ARM64` and so on |

`%CD%`, `%DATE%`, `%TIME%`, `%RANDOM%` and `%ERRORLEVEL%` are **dynamic**: they are computed when read and do not appear in the `set` listing. If you `set ERRORLEVEL=5` yourself you hide the real one; never do.

## Making a change permanent

`set` changes only the current process. To make a variable permanent:

- **GUI:** search the Start menu for *environment variables* and choose **Edit the system environment variables**, then **Environment Variables**. The upper list is for the current user and the lower for all users.
- **Command line:** [`setx`](https://learn.microsoft.com/windows-server/administration/windows-commands/setx) writes a value to the registry for *future* processes: `setx PROJECT "C:\work"` (add `/m` for machine-wide, which needs an administrator). The **current window does not see it**; open a new one.

Do not use `setx` to *append* to `PATH` by expanding `%PATH%` first: the value you get is the merged user-plus-system path, and writing it back copies the system entries into the user variable. Edit `PATH` in the dialog, or with a deliberate script.

## Common mistakes

- **`set x = 1`**: the hidden spaces. Use `set "x=1"`.
- **Reading a variable changed in the same block** with `%x%` instead of `!x!`.
- **Leaving delayed expansion on** and losing the `!` in file names and messages.
- **Octal surprises** with leading zeros in `set /a` (`08` and `09` are errors).
- **Forgetting that `/a` is 32-bit** and overflows silently.
- **Putting `)` in a variable used inside a block** (`%ProgramFiles(x86)%`).
- **Unquoted `%1`** with spaces in the argument.
- **Assuming a variable set in a pipe or by running another script is visible** afterwards.
- **Parsing `%DATE%`** as if the format never varied.

## Practice

1. Write `vars.cmd` that sets `name` with the quoted form and prints it inside brackets, then deletes it and prints whether it is defined.
2. Make a loop over `a b c d` that counts with `set /a`, and print the count in the same loop using `!count!`. Then change `!count!` to `%count%` and explain the difference.
3. Given `set s=report_2026-11-21.csv`, use only substitution and slicing to print the date part, and the extension.
4. Print the result of `07+1` and `010+1` with `set /a`, and explain both.
5. Write a subroutine `:upper_count` that uses its own `setlocal`, computes something, and returns it to the caller with the `endlocal & set` trick.
6. Print the folder your script is in, the script's file name and its size, using only `%~dp0`, `%~nx0` and `%~z0`.

## Check your understanding

1. What does `set x = 1` create, and how do you avoid the problem?
2. A loop prints the same number three times. What is wrong and how do you fix it?
3. What does `set /a "g=1<<4"` print for `%g%`, and why the quotes?
4. What is the value of `%s:~-3%` when `s` is `C:\Dir\file.txt`?
5. Why can `echo !t!` lose a `!`?
6. What is `%~dp0` for?
7. A subroutine needs to return a value without leaking its variables. How?
8. Why is `set /a x=08` an error?

**Expected answers:** (1) a variable named `x ` (trailing space) with value ` 1` (leading space); use `set "x=1"`; (2) `%var%` is expanded once when the block is read; turn on delayed expansion and use `!var!`; (3) `16`; `<<` is a special character that cmd would otherwise treat as a redirection; (4) `txt`; (5) with delayed expansion on, `!` is the delimiter, so a lone `!` is consumed; (6) the folder the script lives in, with a trailing backslash, so you can refer to files beside the script; (7) put `endlocal & set "result=%local%"` on one line, so the value is expanded before `endlocal` discards it; (8) a leading zero means octal and `8` is not an octal digit.
