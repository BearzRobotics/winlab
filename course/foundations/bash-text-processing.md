*Draft for owner review.* Unix is built around **text streams**: logs, configuration files, command output. A handful of small tools turn them into answers: **`grep`** finds lines, **`cut`**, **`tr`**, **`sort`**, **`uniq`** reshape them, **`sed`** edits them, **`awk`** computes over their fields, **`find`** and **`xargs`** feed them with file names. This lesson teaches each tool, the **regular expressions** they share, the **traps** that silently corrupt data (an `sed -i` typo, a `grep -q` under `pipefail`, a CSV with a quoted comma, a pattern with a stray `.`), and **which differences between GNU, uutils, BusyBox and `mawk` will bite you on another machine**.

**What was tested, and where.** Everything below was run on **Ubuntu 26.04 (WSL2)** with **bash 5.3.9** (`tests/verification/bash/ts1.sh` and `ts2.sh`). On this machine `grep` is **GNU grep 3.12**, `sed` is **GNU sed 4.9**, `awk` is **GNU Awk 5.3.2** (`mawk` is also installed and was tested separately), `find` and `xargs` are **GNU findutils 4.10**, while `sort`, `uniq`, `cut`, `tr`, `wc`, `head`, `tail` and `cat` are the **uutils (Rust) coreutils 0.8.0**. For portability I compared **BusyBox 1.35.0** (a downloaded static binary). **Not tested:** BSD and macOS versions (their `sed -i`, `grep` and `sort` differ in ways the lesson flags only from what I could check), other GNU or uutils versions, and non-ASCII locales beyond what is noted: this machine has only the `C`, `C.utf8` and `POSIX` locales installed.

Use **single quotes** around patterns and programs (the shell must not expand `$`, `*` or `\` before the tool sees them), and quote variables you insert (`foundations.bash-variables-and-expansion`).

## Choosing the tool

| You want to... | Use | Notes |
|---|---|---|
| keep lines that match / do not match | `grep`, `grep -v` | exit status says whether anything matched |
| take columns separated by **one** character | `cut -d: -f1,3` | cannot split on runs of spaces |
| take columns separated by **spaces or a pattern**, compute, count, format | `awk` | a small programming language |
| replace text, delete or insert lines, edit a file in place | `sed` | line-oriented stream editor |
| translate or delete single characters | `tr` | **characters**, not words |
| order lines, remove duplicates, count | `sort`, `uniq`, `sort -u` | `uniq` needs sorted input |
| compare two sorted lists | `comm`, `diff`, `join` | |
| run a command per input item | `xargs`, `find -exec` | quote-handling traps below |

When in doubt: **`grep`** to find, **`awk`** to compute, **`sed`** to substitute. Many pipelines mix them: `awk '{print $1}' access.log | sort | uniq -c | sort -rn`.

## Regular expressions

A **regular expression** (regex) is a pattern for text. Three dialects matter:

| Dialect | Used by | `+`, `?`, `\|`, `()` |
|---|---|---|
| **BRE** (basic) | `grep`, `sed` by default | literal; write `\+ \? \| \( \)` (the backslash forms are a **GNU extension**) |
| **ERE** (extended) | `grep -E`, `sed -E`, `awk` | work without a backslash |
| **PCRE** (Perl) | `grep -P` (GNU only), many languages | `\d`, lazy `.*?`, look-around |

What I ran on a file containing `a+b`, `aab`, `apple pie`, `cherry 2`, `cherry 10`, `file.txt` and `fileXtxt`:

```text
grep 'a+b'        -> 1 line   (BRE: + is a literal plus, matched "a+b" only)
grep 'a\+b'       -> 2 lines  (GNU BRE: \+ means "one or more a, then b": "aab" and "tab	here")
grep -E 'a+b'     -> 2 lines  (ERE)
grep 'apple\|cherry'  -> 3   grep -E 'apple|cherry' -> 3
grep -P '\d+'     -> cherry 2, cherry 10
grep 'file.txt'   -> 2 lines (the . matched X too)   grep 'file\.txt' -> 1
grep -F 'a+b'     -> 1        (fixed string: no regex at all)
```

Building blocks: **`.`** any character; **`*`** zero or more of the previous; **`^`** start of line, **`$`** end; **`[abc]`**, **`[^abc]`**, **`[0-9]`**; POSIX classes **`[[:digit:]]`**, `[[:alpha:]]`, `[[:space:]]`, `[[:upper:]]`; **`\b`** word boundary and `\w` (GNU extensions: `echo 'cat concat cat.' | grep -o '\bcat\b' | wc -l` gave **2**); **`(ab)+`** a group; in ERE, `{n,m}` counts.

- **Escape the dot.** An unescaped `.` matches *any* character: `grep 'file.txt'` matched `fileXtxt` too. This is the most common regex bug (in IP addresses, file names, versions).
- **Greedy matching:** `.*` takes as much as it can. `echo 'x<a>y<b>z' | sed 's/<.*>/[]/'` gave `x[]z` (from the first `<` to the *last* `>`); the fix `s/<[^>]*>/[]/` gave `x[]y<b>z`. BRE and ERE have no lazy `.*?`; use a negated class, or `grep -P`.
- **Fixed strings:** when the pattern is *data* (a user name, an IP, text from a variable), use **`grep -F`**. With `pat='a+b'`, `grep -F "$pat"` is exact; `grep "$pat"` treats the `+` as a quantifier in some dialects and `.`/`*`/`[` always as special.
- **A pattern that starts with a dash** is read as an option: `grep '-v' file` printed the usage message, while `grep -- '-v' file` worked. Use `--` (or `-e -v`).
- **Locales:** character ranges like `[a-z]` can behave differently by locale on some systems. On this machine only `C`, `C.utf8` and `POSIX` are installed, so I could **not** demonstrate a difference, and the `[a-z]` test gave the same count in all three. Use POSIX classes (`[[:lower:]]`) for portable intent.

## `grep`

```bash
grep PATTERN file...        # print matching lines
grep -E 'cat|bird' file     # extended regex        grep -F 'text' file   # fixed string
grep -i / -v / -w / -x      # ignore case / invert / whole word / whole line
grep -n / -H / -h / -c      # line numbers / file names / no names / count lines
grep -o PATTERN file        # print ONLY the matching part, one per line
grep -l / -L                # list files with / without a match
grep -A2 / -B2 / -C2        # lines after / before / around a match
grep -r PATTERN dir         # recurse
grep -q / -s                # quiet (status only) / silence "no such file" errors
```

My results: **`-c` counts lines, not occurrences** (`aa aa` gave `1`; `grep -o a | wc -l` gave `4`); `-A1`/`-B1`/`-C1` around `5` gave `5 6`, `4 5` and `4 5 6`; `-m 2` stopped after two matches; `-x` matched a whole line; `-w cat` matched `cat` but not `concat`; `-f patterns.txt` read patterns from a file (2 matches). Recursion with filters: `grep -r --include='*.c' --include='*.h' --exclude-dir=.git TODO src` found `src/a.c` and `src/lib/b.h` and skipped `src/.git/c.c`. With **no file**, `grep` reads standard input; with **`-r` and no file** it searches the current folder.

**Exit status:** `0` a match was found, `1` none, `2` an error (I got `0 1 2` for found, not found and a missing file). That makes `if grep -q pattern file; then` the idiom, and means `-s` hides the message but the status is still `2`.

Traps, each reproduced:

- **Binary files:** `grep apple bin.dat` printed `binary file matches` instead of the line; `-a` treats the file as text.
- **Windows line endings break `$`:** for `done\r\n`, `grep 'done$'` matched **0** lines; after `tr -d '\r'` it matched 1. Check with `cat -A` and strip CRs when a file comes from Windows.
- **Colour** is added only when output is a terminal (`--color=auto`), so pipes see clean text.

### `grep -q` and `set -o pipefail`: a surprise

`grep -q` **stops reading as soon as it finds a match**. The program feeding it may then be killed by SIGPIPE, and under `pipefail` that failure becomes the pipeline's status:

```bash
set -o pipefail
seq 1 200000 | grep -q '^1$'
echo $?                  # 141 (128 + 13, SIGPIPE), although the line WAS found
if seq 1 200000 | grep -q '^1$'; then echo then; else echo else; fi   # prints: else
```

I got **141** and the **`else`** branch for a successful match (`PIPESTATUS` showed `141 0`). Fixes that gave status 0: do not use `-q` (`grep '^1$' >/dev/null`), or capture the producer's output first (`out=$(seq ...); grep -q '^1$' <<< "$out"`). Any "early-exit" consumer (`head`, `grep -q`, `grep -m1`) can trigger this with a large producer. The `pipefail` option is covered in the robust-scripts lesson.

## `cut`, `tr`, `paste` and friends

```bash
cut -d: -f1,3,7 /etc/passwd      # fields 1, 3 and 7 split on ":"
cut -d: -f1-3 file               # a range of fields
cut -c1-4 file                   # characters 1 to 4
tr a-z A-Z                       # translate characters
tr -d '\r'                       # delete characters
tr -s ' '                        # squeeze runs of a character into one
tr -cd '0-9'                     # delete everything EXCEPT digits (-c complements)
paste -sd, file                  # join lines with commas
column -t                        # align columns
```

- **`cut` splits on exactly one character.** `printf 'a   b  c\n' | cut -d' ' -f2` printed an **empty field** (the second space-separated field is empty); `awk '{print $2}'` printed `b`. For runs of spaces use `awk`, or squeeze first (`tr -s ' ' | cut -d' ' -f2`).
- **A line without the delimiter is printed whole** (`echo nocolon | cut -d: -f2` printed `nocolon`); **`-s`** skips such lines.
- **`cut -c` counted bytes on this machine:** `printf 'é1\n' | cut -c1` printed a broken half of the UTF-8 character. For text that may be multibyte, use `awk` (`substr`) or `cut` options your implementation documents for characters.
- **`tr` works on sets of single characters, not strings.** `echo abba | tr 'ab' 'xy'` gave `xyyx` (a→x, b→y); `tr 'abc' 'x'` padded the short SET2 and gave `xxx`. To replace a word use `sed`.
- `tr -d '\r'` converts Windows files; `tr -s ' '` collapses spaces; `tr -cd '0-9'` extracted `5551234` from `tel: 555-1234`.
- `paste -sd,` gave `a,b,c`; `paste <(...) <(...)` put two files side by side; `column -t` aligned a small table (it is not in BusyBox's applets in my build); `nl` numbers **non-empty lines only** by default (use `-ba` for all); `tac` reverses line order, `rev` reverses each line; `wc -L` gave the longest line length; `fold -w 4` wrapped lines at 4 characters.

## `sort`, `uniq`, `comm`, `join`, `diff`

```bash
sort -n file          # numeric           sort -nr    # numeric, reverse
sort -V file          # version order     sort -h     # human sizes (1K 3M 2G)
sort -k2,2n file      # by field 2, numerically    sort -t: -k3,3n   # field separator ":"
sort -u file          # sort and remove duplicates
sort file | uniq -c   # count duplicates          uniq -d / -u   # only duplicated / only unique
```

| Input | Result |
|---|---|
| `10 9 2 100`, `sort` | `10 100 2 9` (**text** order) |
| same, `sort -n` | `2 9 10 100` |
| `1.10 1.9 1.2`, `sort` | `1.10 1.2 1.9`; **`sort -V`** gave `1.2 1.9 1.10` |
| `1K 2G 3M 500`, `sort -h` | `500 1K 3M 2G` |
| `b 2 / a 10 / c 1`, `sort -k2,2n` | `c 1; b 2; a 10` |
| `b a b a`, `uniq` | `b a b a` (**not** collapsed: duplicates must be adjacent) |
| same, `sort \| uniq -c` | `2 a; 2 b` |

- **`uniq` only collapses adjacent lines;** always `sort` first (or `sort -u`). The **top-N idiom** `sort | uniq -c | sort -rn | head` gave `3 x; 2 y` for `x y x z x y`.
- **`-k2` means "from field 2 to the end of the line",** while `-k2,2` is "field 2 only": `sort -k2` ordered `c 1; a 10; b 2` as *text*. Always write `-k2,2` (plus `n`, `r`...).
- **Leading blanks count** in default comparisons (`'  b'` sorted before `a`); `sort -b` ignores them.
- **Stable sorts:** `sort -s -k1,1` kept the original order of equal keys (`b 1` before `b 0`).
- **Locale and collation change the order.** In my test, `LC_ALL=C sort` put `A B a b` (uppercase first); the **uutils** `sort` under `LC_ALL=en_US.UTF-8` gave `a A b B` **even though that locale is not installed** (`locale -a` lists only C, C.utf8 and POSIX). GNU `sort` usually falls back to the C order when a locale is missing; I did not test GNU `sort` here. The lesson: **pin the order with `LC_ALL=C` in scripts that must be reproducible**, and when comparing two sorted lists make sure both were sorted the same way.
- `sort -c file` **checks** if sorted (`disorder: 2` was reported); **`sort -o file file`** is safe for sorting a file in place (the `-o` output is written after reading), whereas `sort file > file` **empties it** (`bash-basics`).
- **`comm`** compares two **sorted** files: `-12` shows lines in both (`b c`), `-23` only in the first. **`join`** joins two sorted files on a key (`1 alice admin`). **`diff -u`** shows changes (`-b`, `+c`).

## `sed`: the stream editor

`sed` reads lines, applies commands, writes the result. Without `-i` **it never changes the file**: output goes to standard output.

### Substitution

```bash
sed 's/old/new/'          # first match on each line
sed 's/old/new/g'         # every match               sed 's/old/new/2'   # the 2nd match
sed 's/old/new/I'         # ignore case               sed -n 's/^port=//p'   # only changed lines
sed -E 's/(.*) (.*)/\2, \1/'     # groups with ERE; BRE needs \( \)
```

Results: with `a a a`: first only `X a a`, `g` gave `X X X`, `2` gave `a X a`, `2g` gave `a X X`. `&` stands for the whole match (`s/b/[&]/` made `a[b]c`); groups reorder (`john smith` became `smith, john`). **Other delimiters** avoid escaping slashes: `s|/usr|/opt|`. GNU extras: `I` (case-insensitive), `\U` and `\L` (case conversion), `\b`.

- **`-n` plus `p`** prints only the lines where a substitution happened (`sed -n 's/^port=//p'` gave `5432`). **Without `-n`, `s///p` prints matching lines twice** (`aXc aXc`).
- An **empty pattern reuses the last regex**: `sed '/X/s//-/'` gave `a-b`.

### Addresses and commands

An address chooses lines: a number (`2`), the last line (`$`), a range (`2,4`), a regex (`/^user/`), a regex range (`/two/,/four/`), a step (`1~2` odd lines), `2,+1`, and **`!`** negates. Commands: **`p`** print, **`d`** delete, **`i\`** insert before, **`a\`** append after, **`c\`** change, **`q`** quit, **`=`** print the line number, **`y/abc/xyz/`** transliterate, **`w file`** write matches to a file.

```text
sed -n 2p            -> two            sed -n '$p'        -> five
sed -n 2,4p          -> two three four sed -n '1~2p'      -> one three five
sed '2d;4,5d'        -> one three      sed '/^#/d;/^$/d'  -> the config without comments and blank lines
sed 2q               -> one two        (stops reading: fast on big files)
sed -n '$='          -> 5              (counts lines)
sed -e 's/one/1/' -e 's/two/2/'        (several commands; or separate them with ;)
sed -n '/two/,/four/p' -> two three four
```

Multi-line tricks use the **hold space** and `N`: `sed -n '1!G;h;$p'` reversed the file (like `tac`); `sed ':a;N;$!ba;s/\n/,/g'` joined all lines into `one,two,three,four,five`; `sed 'N;s/\n/+/'` joined pairs. They are powerful and unreadable: for anything beyond a one-liner, prefer `awk` or a script. **`sed -n l`** prints hidden characters (`a\tb \r$`), a handy cousin of `cat -A`; `sed 's/\r$//;s/ *$//'` strips CRs and trailing spaces.

### `sed -i`: editing in place, and its dangers

| Command | Result I saw |
|---|---|
| `sed -i 's/db1/db2/' file` | the file was edited (no backup) |
| `sed -i.bak 's/db1/db3/' file` | edited, and `file.bak` kept the original |
| `sed -i 's/db1/Z/' x1 x2` | both files edited |
| `sed -i ... symlink` | **the link was replaced by a regular file** (`[ -L lnk ]` was false afterwards; I did not inspect the original target) |
| `sed -i 's/db1/' file` (a typo) | `unterminated 's' command` and **the file was left unchanged** |

- **Always keep a backup or test first:** run without `-i` and read the output, then `sed -i.bak`.
- **Portability:** GNU `sed -i 'EXPR' file` takes the suffix *attached* (`-i.bak`); **BSD/macOS `sed -i` requires a suffix argument** (`sed -i '' 'EXPR' file`), so a script written for one fails on the other. BusyBox `sed -i` worked like GNU in my test. For portable in-place edits write to a temporary file and `mv` it.

### Shell variables inside `sed`

The shell expands `$var` in double quotes **before** `sed` sees it, so the value becomes part of the program:

- `x='a.b'; sed "s/$x/[&]/g"` also matched `aXb` (the `.` is a regex wildcard). **Escape the value first** (`esc=$(printf '%s' "$x" | sed 's/[.[\*^$/]/\\&/g')`) or avoid regex for literal text (use `awk` with `index()` or shell parameter expansion).
- A value containing the delimiter breaks the command: `v='x/y'; sed "s/z/$v/"` failed with `unknown option to 's'`; using `|` as the delimiter worked (`x/y`).
- **`&` and `\` in a replacement are special:** `v='a&b'` produced `azb` (the `&` became the match); write `a\&b`.
- Single quotes stop the shell expanding `$` (`'s/\$5/five/'`); double quotes expand it first (`five=9; sed "s/$five/nine/"`).

## `awk`: fields and small programs

`awk` reads each line, splits it into **fields** (`$1`, `$2`, ..., `$NF` the last, `$0` the whole line) and runs `pattern { action }` rules. The default separator is **any run of blanks**.

```bash
awk '{print $1, $2}' file                  # columns
awk -F: '{print $1}' /etc/passwd           # separator ":" (a single char or a regex)
awk '$2 > 28 {print $1}' people            # pattern: numeric test on a field
awk '/NY/ {print $1}' people               # pattern: regex on the line
awk '$3 ~ /^N/ {print $1}' people          # regex on one field   (!~ negates)
awk 'NR > 1' file                          # skip a header (NR = line number)
awk 'END {print NR}' file                  # runs after the last line
awk '{s += $2} END {print s, s/NR}' file   # sum and average
awk -v min=26 '$2 >= min {printf "%-6s|%3d|\n", $1, $2}' file     # -v sets a variable; printf formats
```

On `alice 30 NY / bob 25 LA / carol 41 NY` I got: fields `alice 30; bob 25; carol 41`; `$NF` `NY LA NY`; the sum and average `96 32`; the maximum `carol 41`; a regex separator (`-F'[0-9]+'` on `a1b22c` gave `a b c`); a tab separator via `-F'\t'`.

- **Arrays are associative.** Count by key: `awk '{c[$3]++} END {for (k in c) print k, c[k]}'` gave `LA 1; NY 2`; sum by key gave `LA 25; NY 71`. The order of `for (k in c)` is **unspecified**: pipe to `sort`.
- **Remove duplicates, keeping order:** `awk '!seen[$0]++'` gave `b a c` for `b a b c a`.
- **Rebuild a line with a new separator:** `awk 'BEGIN{OFS=","} {$1=$1; print}'` gave `alice,30,NY` (assigning a field forces `$0` to be rebuilt with `OFS`). `{$2=$2+1; print}` edited a field.
- **Functions:** `length`, `substr(s,start,len)` (1-based), `index`, `toupper`, `split(s, arr, sep)`, `sub`/`gsub(/re/, repl)`, `match(s, /re/)` with `RSTART`/`RLENGTH` (`match()` found `123`), `printf`.
- **Ranges:** `/bob/,/carol/` printed `bob carol`. **Two files:** `FNR` (line in the current file) versus `NR` (total): `awk 'NR==FNR {r[$1]=$2; next} {print $2, r[$1]}' roles.txt -` is a lookup-join idiom (`alice admin; bob user`).
- **Config files:** `awk -F= '!/^#/ && NF==2 {print $1 " -> " $2}'` listed `host -> db1 ...`; `awk -F= '$1=="port" {print $2}'` printed `5432`.
- **Shell out:** `"echo hi" | getline x` read a command's output; `system("exit 3")` returned `3`; `ENVIRON["HOME"]` reads the environment.

### Awk traps

- **An unset variable is both `0` and `""`** (`print x+0, "[" x "]"` gave `0 []`): typos in variable names are silent.
- **Numbers from input compare numerically, constant strings compare as strings:** with fields `10 9`, `$1 > $2` was true (numeric); with the string constants `"10"` and `"9"` it was false (string compare). Add `+0` to force a number.
- **There is no integer type;** `7/2` is `3.5` (use `int(7/2)`).
- **Passing shell values:** use **`-v name="$value"`**. Building the program by **string interpolation** (`awk "\$3==\"$y\""`) works until the value contains a quote: with `y='x" || 1 || "'` it **printed every line** (code injection into the awk program). `-v` is safe from that, but **it processes backslash escapes** (`-v s='a\tb'` yielded a real tab), while `ENVIRON` keeps the text as is (`a\tb`).
- **CSV is not "split on commas":** `awk -F,` on `"Smith, John",3` saw **3 fields** (the quoted comma split it). `gawk` can handle it with `FPAT="([^,]+)|(\"[^\"]+\")"` (2 fields; `gawk` only). For real CSV use a CSV-aware tool.
- **Implementations differ.** On the same programs: **`mawk`** has **no `gensub` and no `asort`** (`function gensub never defined`), while `gawk` has both; **BusyBox `awk`** has `gensub` in my build but **no `asort`**, and its **`printf "%d", 2^40` printed `-2147483648`** (a 32-bit result) where `gawk` and `mawk` printed `1099511627776`. `length(array)`, `toupper`, `tolower`, `substr`, `split`, `sub` and `gsub` worked in all three. Stick to POSIX awk (the functions above, no `gensub`, `asort`, `strftime`, `FPAT`, `PROCINFO`) when a script must run everywhere, and say in the script when it needs `gawk`.

## `find` and `xargs`

`find ... -print0 | xargs -0 cmd` and `find ... -exec cmd {} +` were covered in `bash-basics`. More on `xargs`, which builds command lines from input:

- **Default input splitting** is on blanks and newlines **and it interprets quotes**: `echo "it's" | xargs echo` failed with `unmatched single quote`; **`xargs -d '\n'`** (GNU) used the line as is (`it's`). Prefer **`-0`** with `-print0`.
- **`-n2`** uses at most 2 arguments per run (`a b|c d|e`); **`-I{}`** runs once per item and puts the item where `{}` is.
- **Empty input still runs the command once (GNU):** `xargs echo ran < /dev/null` printed `ran`; **`-r`** (`--no-run-if-empty`, a GNU option) prevented it. Without `-r`, a pipeline that finds nothing still runs your command once with no arguments, which is harmless for `echo` and not harmless for commands whose no-argument behaviour matters.
- **Exit status 123** means at least one invocation failed (I got 123 from `sh -c 'exit 1'`).
- **`-P4`** ran 4 `sleep 1` commands in **1 second** in parallel.
- **`{}` inside `sh -c '...'` is an injection hole:** with an input line `x; echo INJECTED`, `xargs -I{} sh -c 'echo {}'` **ran the injected command** (`x` then `INJECTED`), while `xargs -I{} sh -c 'echo "$1"' _ {}` printed the line as data. Pass items as **arguments**, never splice them into a shell string.
- The command-line length limit is finite (`getconf ARG_MAX` gave `2097152` bytes); `xargs` splits into several runs to stay under it, and `-exec ... {} +` does the same.

## Putting it together: log analysis

A small web-server log (`10.0.0.1 - - [21/Nov/2026:10:01:02 +0000] "GET /index.html HTTP/1.1" 200 1024`):

```bash
awk '{print $1}' access.log | sort | uniq -c | sort -rn          # requests per IP:  3 10.0.0.1; 2 10.0.0.2; 1 10.0.0.3
awk '{print $9}' access.log | sort | uniq -c | sort -k2n         # status counts:    2 200; 1 304; 1 404; 2 500
awk '$9 ~ /^5/' access.log | wc -l                                # 5xx lines: 2   (grep -c ' 5[0-9][0-9] ' gave 2)
awk '{b[$1]+=$10} END {for (i in b) print i, b[i]}' access.log | sort    # bytes per IP: 10.0.0.1 1280 ...
awk -F'[ :]' '{print $5}' access.log | sort | uniq -c            # per hour: 3 for hour 10, 3 for hour 11
awk '$9 >= 400 {print $7, $9}' access.log                         # failing paths: /missing 404; /api/x 500; /api/y 500
sed -n '1s/.*"\(.*\)".*/\1/p' access.log                          # the request text: GET /index.html HTTP/1.1
```

Notes: `$9` is the status only because the format is fixed; **a log format that adds fields (or quoted fields containing spaces) shifts the numbers**, so check a sample line first. A pipeline of small tools is easy to read and test one stage at a time (`head -3` after each pipe).

### The right tool is also faster

On 100,000 lines on this machine: `wc -l` took **9 ms**, `awk 'END{print NR}'` **16 ms**, `grep -c ''` **7 ms**, but a bash `while read` loop doing the same count took **525 ms**; summing the numbers took **28 ms** in `awk` and **498 ms** in a bash loop. (One machine, one run each; the ratio is the point.) Use the text tools on whole files; use shell loops for orchestration, not for per-line data processing.

## Differences between implementations (what to check on another machine)

| Feature | GNU (here) | BusyBox 1.35 | Others |
|---|---|---|---|
| `grep -P` (PCRE) | yes | **no** (`unrecognized option: P`) | BSD/macOS: not tested |
| `grep -E`, `-o`, `-r --include` | yes | `-E`, `-o` yes | |
| `sed -E` and BRE `\+` | yes | yes | |
| `sed -z`, `\U` / `\L` / `I` flag | yes | **`-z` no; `\U` printed `Uhello`**; `I` yes | |
| `sed -i` | `-i[SUFFIX]` | like GNU (worked) | **BSD/macOS needs `-i ''`** |
| `sort -h`, `-V` | yes | `-V` yes, **`-h` no** | |
| `cut --complement` | yes | **no** | |
| `column -t` | yes | **not in my build** | |
| `xargs -r`, `-0`, `-d`, `-P` | yes (GNU findutils) | not tested | BSD/macOS: not tested |
| awk: `gensub`, `asort` | `gawk` yes | **`mawk`: no**; BusyBox: `gensub` yes, no `asort` | |
| awk: `printf "%d"` of 2^40 | correct | **-2147483648** | |

When a script must be portable, test it with `busybox` applets (`busybox sed ...`) and `mawk` as I did, and stick to the options POSIX defines.

## Reading an unknown script (text processing)

- **`sed -i` or `> same-file`** on important files: is there a backup? What happens on a typo?
- **Patterns built from variables** (`grep "$x"`, `sed "s/$x/.../"`, `awk "...$x..."`): can the value contain `.`, `/`, `&`, a quote? Is it `-F`, escaped or passed with `-v`?
- **`eval`, `sh -c "...$item..."`, `xargs -I{} sh -c`:** the data becomes code.
- **`cut -d' '` or `awk -F,` on data with repeated spaces or quoted fields.**
- **`grep -q` in a pipeline with `pipefail`.**
- **`uniq` without `sort`; `sort` without `LC_ALL=C` where the order matters.**
- **`for f in $(grep -l ...)`:** file names with spaces break; use `grep -lZ | xargs -0` or `while IFS= read -r -d ''`.
- **`curl ... | sh`** is a shell, not a text tool, but the same review applies: read it first.

## Common mistakes

- An unescaped `.` (or `*`, `+`, `[`) in a pattern that should be literal; use `grep -F`.
- `grep -c` for "how many times" (it counts lines).
- `cut -d' '` on aligned columns; `awk -F,` on CSV with quotes.
- `uniq` on unsorted data; `sort -k2` instead of `sort -k2,2`; text sort of numbers.
- `sort file > file`.
- `sed -i` without a backup, or written for GNU and run on macOS.
- Double-quoted `sed`/`awk` programs with an unvetted variable.
- Assuming `\+`, `\|`, `\b`, `\U` or `grep -P` exist everywhere.
- `grep -q` under `pipefail` with a long producer.
- Forgetting that `awk` fields from input compare as numbers but string constants as strings.
- Processing a Windows file without removing the `\r`.
- Using a shell `while read` loop for a million lines.

## Practice

1. From `/etc/passwd`, print the user names and shells of accounts with a UID of 1000 or more, three ways: `awk`, `cut` + `grep`, and `sed`.
2. Count how many lines of a file contain `error` (any case) and how many times the word appears in total; explain the two numbers.
3. Show that `grep 'file.txt'` matches `fileXtxt`, fix it two ways, and show that `-F` ignores regex characters in a pattern held in a variable.
4. Show `cut -d' ' -f2` failing on `a   b  c` and fix it with `awk` and with `tr -s`.
5. Sort `10 9 2 100`, `1.10 1.9 1.2` and `1K 2G 3M 500` correctly. Then show `sort -k2` versus `sort -k2,2n` on a small table.
6. Build the top-5 most frequent words of a text file with `tr`, `sort`, `uniq` and `head`. Make it case-insensitive.
7. Use `sed` to remove comments and blank lines from a config, to change one setting, and to extract one value. Do the change with `sed -i.bak` on a copy and compare with `diff -u`.
8. Reproduce the greedy-match problem on `x<a>y<b>z` and fix it.
9. Write the `awk` programs for: counting lines per category, summing a column per key, removing duplicate lines in order, and joining two files on a key.
10. Reproduce the `awk` injection with a value that contains a quote, then fix it with `-v`. Show that `-v` interprets `\t` but `ENVIRON` does not.
11. Run `seq 1 200000 | grep -q '^1$'` under `set -o pipefail`; explain 141 and give two fixes.
12. **Read this and list every problem:**

    ```bash
    #!/usr/bin/env bash
    set -o pipefail
    user=$1
    if cat /etc/passwd | grep -q $user; then
        shell=$(grep $user /etc/passwd | cut -d: -f7)
        sed -i "s/$user/$user-old/" /etc/passwd
        echo "$user uses $shell" >> /tmp/report.$$
    fi
    for f in $(grep -l $user /var/log/*); do
        wc -l $f
    done
    ```

    **Answer.** `$user` is unquoted everywhere (splitting, globbing, an empty argument turning `grep -q $user` into a read from standard input). It is also a **regex**: a user name like `a.b` or `root|x` matches more than intended; use `grep -F` or an anchored `awk -F: '$1==u'`. `cat file | grep` is a useless `cat`, and `grep -q` in a pipeline under `pipefail` can return **141** and take the `else` branch (the `cat` is killed by SIGPIPE on a large file). `grep $user /etc/passwd` matches *any* field of *any* line (a user named `bin` matches `sbin`), so `cut -d: -f7` may print several lines. **`sed -i` on `/etc/passwd`** with an unescaped user name, no backup and no check is how you lock everyone out; edit the system account files with `vipw`/`usermod`, not `sed`. `$user` inside the replacement can contain `/` or `&`. `/tmp/report.$$` is a **predictable temp name** (symlink attack): use `mktemp`. `for f in $(grep -l ...)` breaks on file names with spaces, and `wc -l $f` is unquoted. Nothing checks that `$1` was given.

## Check your understanding

1. What is the difference between BRE, ERE and PCRE, and which tools use which by default?
2. Why does `grep 'file.txt'` match `fileXtxt`, and what are two fixes?
3. What does `grep -c` count?
4. Why does `uniq` need `sort` first?
5. What is the difference between `sort -k2` and `sort -k2,2n`?
6. What does `sed 's/a/b/'` do to the file it reads? What does `sed -i` change, and what is the BSD/macOS difference?
7. Why can a shell variable inside a double-quoted `sed` or `awk` program be dangerous, and how does `awk -v` help?
8. Why does `awk -F,` fail on `"Smith, John",3`?
9. Why can `seq 1 200000 | grep -q '^1$'` take the `else` branch under `pipefail`?
10. Name three features that exist in GNU tools but not in BusyBox or `mawk`.

**Expected answers:** (1) BRE (`grep`, `sed` by default) treats `+ ? | ( )` as literals unless backslashed (a GNU extension); ERE (`grep -E`, `sed -E`, `awk`) does not need backslashes; PCRE (`grep -P`, GNU only) adds `\d`, lazy quantifiers, look-around; (2) the unescaped `.` matches any character; escape it (`file\.txt`) or use `grep -F`; (3) the number of matching **lines**, not occurrences (`grep -o ... | wc -l` counts occurrences); (4) it only collapses **adjacent** duplicates, so sort puts equal lines together; (5) `-k2` sorts from field 2 to the end of the line as text; `-k2,2n` sorts on field 2 only, numerically; (6) nothing: it writes the result to standard output; `-i` edits the file in place (`-i.bak` keeps a backup); GNU takes the suffix attached, BSD/macOS requires a separate suffix argument (`-i ''`); (7) the shell expands the value into the program, so a `.`, `/`, `&` or quote changes its meaning or injects code; `-v name="$value"` passes it as data (but it processes backslash escapes); (8) the comma inside the quotes is also a separator, so awk sees 3 fields; (9) `grep -q` exits at the first match, the producer is killed by SIGPIPE (status 141), and `pipefail` makes the pipeline fail; (10) any three of: `grep -P`, `sed -z`, `sed \U`, `sort -h`, `cut --complement`, `column`, `gawk`'s `gensub`/`asort`/`FPAT`, and correct 64-bit `printf %d` in awk.
