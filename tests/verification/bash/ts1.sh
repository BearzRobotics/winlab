#!/usr/bin/env bash
# Battery 1 for foundations.bash-text-processing: regex flavours, grep, and the small text tools. Temp folder only.
D=$(mktemp -d); cd "$D" || exit 1
echo "bash $BASH_VERSION; $(grep --version | head -1); sort: $(sort --version | head -1); locales: $(locale -a | tr '\n' ' ')"
BUSYBOX="$HOME/tools/busybox"
args() { printf '%d args:' "$#"; printf ' [%s]' "$@"; echo; }

printf 'apple pie\nbanana split\nAPPLE tart\ncherry 2\ncherry 10\nfile.txt\nfileXtxt\na+b\naab\n  indented\n\ntab\there\n' > t.txt
nl -ba t.txt | sed 's/^/  /' | head -14

echo '### 1. regex flavours: BRE, ERE, PCRE'
echo -n "grep 'a+b'   (BRE: + is literal): "; grep -c 'a+b' t.txt
echo -n "grep 'a\\+b'  (GNU BRE: \\+ is 'one or more'): "; grep -c 'a\+b' t.txt
echo -n "grep -E 'a+b' (ERE): "; grep -cE 'a+b' t.txt
echo -n "grep 'apple\\|cherry' (GNU BRE alternation): "; grep -c 'apple\|cherry' t.txt
echo -n "grep -E 'apple|cherry': "; grep -cE 'apple|cherry' t.txt
echo -n "grep -P '\\d+' (PCRE, GNU grep only): "; grep -P '\d+' t.txt | tr '\n' '|'; echo
echo -n "unescaped dot: grep 'file.txt' matches both: "; grep -c 'file.txt' t.txt; echo -n "escaped: grep 'file\\.txt': "; grep -c 'file\.txt' t.txt
echo -n "-F fixed string, no regex at all: "; grep -cF 'a+b' t.txt
echo -n "[[:digit:]] classes: "; grep -o '[[:digit:]]\+' t.txt | tr '\n' ' '; echo
echo -n "\\b word boundary and \\w (GNU): "; echo 'cat concat cat.' | grep -o '\bcat\b' | wc -l
echo -n "^ and \$ anchors: "; grep -c '^cherry' t.txt; echo -n "empty lines: "; grep -c '^$' t.txt
echo -n "greedy .*: "; echo 'x<a>y<b>z' | sed 's/<.*>/[]/'; echo -n "non-greedy via a negated class: "; echo 'x<a>y<b>z' | sed 's/<[^>]*>/[]/'
echo -n "grep -E '(ab)+' groups; backreference -E '(a)\\1': "; echo 'ababab aa' | grep -oE '(ab)+|(a)\2' | tr '\n' ' '; echo
echo -n "ranges depend on the locale: [a-z] in C vs en_US: "
for loc in C en_US.UTF-8 C.UTF-8; do printf '%s: ' "$loc"; printf 'a\nB\nz\nZ\n' | LC_ALL=$loc grep -c '[a-z]' | tr '\n' ' '; done; echo
echo -n "case-insensitive -i: "; grep -ci 'apple' t.txt
echo -n "a pattern starting with a dash: "; printf -- '-v\nx\n' | grep -- '-v'; echo -n "without --: "; printf -- '-v\nx\n' | grep '-v' 2>&1 | head -1 | cut -c1-60
echo -n "pattern from a variable with metacharacters (. + *): "; pat='a+b'; grep -c "$pat" t.txt; echo -n "   as a fixed string -F: "; grep -cF "$pat" t.txt

echo '### 2. grep options'
echo -n "-c counts LINES, -o | wc -l counts occurrences: "; echo 'aa aa' > dup.txt; echo "$(grep -c a dup.txt) vs $(grep -o a dup.txt | wc -l)"
echo -n "-n numbers, -H file name, -h no name: "; grep -n 'banana' t.txt; grep -H banana t.txt; grep -h banana t.txt t.txt | head -1
echo "-A/-B/-C context:"; seq 1 10 > ten.txt; echo "  -A1: $(grep -A1 5 ten.txt | tr '\n' ' ')  -B1: $(grep -B1 5 ten.txt | tr '\n' ' ')  -C1: $(grep -C1 5 ten.txt | tr '\n' ' ')"
echo -n "-m 2 stops after 2 matches: "; grep -m2 1 ten.txt | tr '\n' ' '; echo
echo -n "-x whole line, -w whole word: "; grep -cx 'cherry 2' t.txt; echo -n "   -w: "; printf 'cat\nconcat\n' | grep -cw cat
echo -n "-v invert, -e multiple patterns, -f patterns from a file: "; grep -v 'cherry' t.txt | wc -l | tr '\n' ' '; grep -e apple -e banana t.txt | wc -l | tr '\n' ' '; printf 'apple\nbanana\n' > pats.txt; grep -f pats.txt t.txt | wc -l
echo -n "-l / -L list files with / without a match: "; grep -l banana t.txt dup.txt; echo -n "   -L: "; grep -L banana t.txt dup.txt
echo -n "-r with --include and --exclude-dir: "; mkdir -p src/lib src/.git; echo 'TODO one' > src/a.c; echo 'TODO two' > src/lib/b.h; echo 'TODO hidden' > src/.git/c.c; grep -r --include='*.c' --include='*.h' --exclude-dir=.git TODO src | sort | tr '\n' ' '; echo
echo -n "-q status: "; grep -q apple t.txt; echo -n "found=$? "; grep -q zzz t.txt; echo -n "notfound=$? "; grep -q apple nosuch.txt 2>/dev/null; echo "error=$?"
echo -n "-s hides 'no such file' errors: "; grep -s apple nosuch.txt; echo "status $?"
printf 'bin\0data\napple\n' > bin.dat; echo -n "a binary file: "; grep apple bin.dat; echo -n "   -a treats it as text: "; grep -a apple bin.dat | tr -d '\0'
echo -n "CRLF line endings and the \$ anchor: "; printf 'done\r\n' > crlf.txt; grep -c 'done$' crlf.txt | tr '\n' ' '; echo -n "after removing the CR: "; tr -d '\r' < crlf.txt | grep -c 'done$'
echo -n "color is only added on a terminal, so output is clean in pipes: "; grep --color=auto apple t.txt | head -1 | od -c | head -1 | grep -c '033' | sed 's/^0$/no escape codes/'
echo -n "grep with no file reads stdin; with -r and no file reads the current folder: "; (cd src && grep -r TODO | wc -l)

echo '### 3. grep -q and pipefail (a classic surprise)'
cat > pf.sh <<'EOF'
#!/usr/bin/env bash
set -o pipefail
seq 1 200000 | grep -q '^1$'
echo "status of seq | grep -q (match found early): $?"
if seq 1 200000 | grep -q '^1$'; then echo "if branch: then"; else echo "if branch: else (a successful match took the else branch!)"; fi
echo "PIPESTATUS shows why: $(seq 1 200000 | grep -q '^1$'; echo "${PIPESTATUS[*]}")"
EOF
bash pf.sh
echo -n "workaround: read all input (no -q): "; bash -c 'set -o pipefail; seq 1 200000 | grep "^1$" >/dev/null; echo $?'
echo -n "or capture first: "; bash -c 'set -o pipefail; out=$(seq 1 200000); grep -q "^1$" <<< "$out"; echo $?'

echo '### 4. cut, tr, paste, column'
printf 'root:x:0:0:root:/root:/bin/bash\nalice:x:1001:1001::/home/alice:/bin/sh\n' > pw.txt
echo "cut -d: -f1,3,7: $(cut -d: -f1,3,7 pw.txt | tr '\n' ' ')   -f1-3: $(cut -d: -f1-3 pw.txt | head -1)   --complement -f2: $(cut -d: --complement -f2 pw.txt | head -1)"
echo "cut -c1-4: $(cut -c1-4 pw.txt | tr '\n' ' ')   -b/-c on multibyte: $(printf 'é1\n' | cut -c1) vs $(printf 'é1\n' | cut -b1 | od -c | head -1 | cut -c9-)"
echo -n "cut cannot split on runs of spaces: "; printf 'a   b  c\n' | cut -d' ' -f2 | od -c | head -1 | cut -c9-; echo -n "   awk can: "; printf 'a   b  c\n' | awk '{print $2}'
echo -n "cut with a missing delimiter prints the whole line: "; echo 'nocolon' | cut -d: -f2; echo -n "   -s skips such lines: "; echo 'nocolon' | cut -s -d: -f2 | wc -l
echo -n "tr upper/lower: "; echo 'Hello' | tr a-z A-Z; echo -n "tr -d chars: "; echo 'h-e-l-l-o' | tr -d '-'; echo -n "tr -s squeeze: "; echo 'a    b' | tr -s ' '
echo -n "tr -cd keeps only digits: "; echo 'tel: 555-1234' | tr -cd '0-9'; echo
echo -n "tr works on CHARACTER sets, not strings: tr 'ab' 'xy' on 'abba' -> "; echo 'abba' | tr 'ab' 'xy'; echo -n "   tr 'abc' 'x' (short SET2 is padded): "; echo 'abc' | tr 'abc' 'x'
echo -n "tr -d '\\r' removes Windows CRs: "; printf 'x\r\n' | tr -d '\r' | od -c | head -1 | cut -c9-
echo -n "paste -sd, joins lines: "; printf 'a\nb\nc\n' | paste -sd,; echo -n "paste two files side by side: "; paste <(printf '1\n2\n') <(printf 'a\nb\n') | tr '\t' '+' | tr '\n' ' '; echo
echo "column -t aligns: "; printf 'name qty\napple 3\nwatermelon 10\n' | column -t | sed 's/^/  /'
echo -n "wc -L longest line: "; wc -L < t.txt; echo -n "nl numbers non-empty lines only by default: "; printf 'a\n\nb\n' | nl | tr '\n' '|'; echo
echo -n "tac / rev: "; printf '1\n2\n3\n' | tac | tr '\n' ' '; echo 'abc' | rev
echo -n "fold wraps / expand tabs: "; echo 'abcdefghij' | fold -w 4 | tr '\n' '|'; printf 'a\tb\n' | expand -t4 | od -c | head -1 | cut -c9-

echo '### 5. sort and uniq'
printf '10\n9\n2\n100\n' > nums.txt
echo "default (text) sort: $(sort nums.txt | tr '\n' ' ')   -n: $(sort -n nums.txt | tr '\n' ' ')   -nr: $(sort -nr nums.txt | tr '\n' ' ')"
printf '1.10\n1.9\n1.2\n' > ver.txt; echo "version sort -V: $(sort -V ver.txt | tr '\n' ' ')   plain: $(sort ver.txt | tr '\n' ' ')"
printf '1K\n2G\n3M\n500\n' > hum.txt; echo "human sort -h: $(sort -h hum.txt | tr '\n' ' ')"
printf 'b 2\na 10\nc 1\n' > kv.txt; echo "by field 2 numerically -k2,2n: $(sort -k2,2n kv.txt | tr '\n' ';')   -k2 (to end of line, text): $(sort -k2 kv.txt | tr '\n' ';')"
printf 'x:3\ny:1\nz:2\n' | sort -t: -k2,2n | tr '\n' ' '; echo "(-t: sets the separator)"
printf 'b\na\nb\na\n' > dups.txt; echo "sort -u: $(sort -u dups.txt | tr '\n' ' ')   uniq without sort: $(uniq dups.txt | tr '\n' ' ')   sort | uniq -c: $(sort dups.txt | uniq -c | tr '\n' ';' | sed 's/  */ /g')"
echo "uniq -d (only duplicated): $(sort dups.txt | uniq -d | tr '\n' ' ')   uniq -u (only unique): $(printf 'a\nb\nb\n' | sort | uniq -u | tr '\n' ' ')"
echo "top-N pattern: $(printf 'x\ny\nx\nz\nx\ny\n' | sort | uniq -c | sort -rn | head -2 | sed 's/^ *//' | tr '\n' ';')"
echo -n "locale changes the order: "; printf 'b\nA\na\nB\n' > case.txt; for loc in C en_US.UTF-8 C.UTF-8; do printf '%s=[%s] ' "$loc" "$(LC_ALL=$loc sort case.txt | tr '\n' ' ')"; done; echo
echo -n "sort -f ignores case: "; sort -f case.txt | tr '\n' ' '; echo -n "  stable -s with -k1,1: "; printf 'b 1\na 2\nb 0\n' | sort -s -k1,1 | tr '\n' ';'; echo
echo -n "leading blanks matter in -k: "; printf '  b\na\n' | sort | tr '\n' '|'; printf '  b\na\n' | sort -b | tr '\n' '|'; echo
echo -n "sort -c checks if sorted: "; sort -c nums.txt 2>&1 | head -1; echo -n "sort output to the input file (-o is safe): "; cp nums.txt n2.txt; sort -n -o n2.txt n2.txt; tr '\n' ' ' < n2.txt; echo
echo -n "comm needs sorted input: "; comm -12 <(printf 'a\nb\nc\n') <(printf 'b\nc\nd\n') | tr '\n' ' '; echo -n "  -23 (only in first): "; comm -23 <(printf 'a\nb\n') <(printf 'b\nc\n'); echo -n "join on a key: "; join <(printf '1 alice\n2 bob\n') <(printf '1 admin\n2 user\n') | tr '\n' ';'; echo
echo -n "diff -u: "; diff -u <(printf 'a\nb\n') <(printf 'a\nc\n') | tail -n +3 | tr '\n' '|'; echo

echo '### 6. the tools on BusyBox (a different implementation)'
for t in "grep -E 'a+b' t.txt" "grep -P '\\d' t.txt" "grep -o 'a' dup.txt" "sort -h hum.txt" "sort -V ver.txt" "cut --complement -d: -f2 pw.txt" "tr -cd '0-9'" "column -t t.txt" "paste -sd, nums.txt" "uniq -c dups.txt" "comm -12 nums.txt nums.txt"; do
  gnu=$(bash -c "$t" </dev/null 2>&1 | head -1 | cut -c1-28); bb=$(bash -c "$BUSYBOX $t" </dev/null 2>&1 | head -1 | cut -c1-40)
  printf '  %-34s GNU/uutils: %-30s busybox: %s\n' "$t" "[$gnu]" "[$bb]"
done

cd / && rm -rf "$D"
