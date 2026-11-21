#!/usr/bin/env bash
# Battery 2 for foundations.bash-text-processing: sed, awk, xargs, a log-analysis pipeline, portability. Temp folder only.
D=$(mktemp -d); cd "$D" || exit 1
echo "bash $BASH_VERSION; $(sed --version | head -1); awk -> $(readlink -f "$(command -v awk)" | sed 's#.*/##') ($(awk --version 2>&1 | head -1 | cut -c1-30)); mawk present: $(command -v mawk >/dev/null && echo yes)"
BUSYBOX="$HOME/tools/busybox"
args() { printf '%d args:' "$#"; printf ' [%s]' "$@"; echo; }

printf 'host=db1\nport=5432\n# comment\nuser=admin\n\npassword=s3cr3t\n' > app.conf
printf 'one\ntwo\nthree\nfour\nfive\n' > n.txt

echo '### 1. sed: substitute'
echo "s/two/2/: $(sed 's/two/2/' n.txt | tr '\n' ' ')"
printf 'a a a\n' > aaa.txt; echo "first only vs g vs 2nd: $(sed 's/a/X/' aaa.txt) / $(sed 's/a/X/g' aaa.txt) / $(sed 's/a/X/2' aaa.txt) / from 2nd on: $(sed 's/a/X/2g' aaa.txt)"
echo "& is the match: $(echo 'abc' | sed 's/b/[&]/')   groups (BRE): $(echo 'john smith' | sed 's/\(.*\) \(.*\)/\2, \1/')   groups (-E): $(echo 'john smith' | sed -E 's/(.*) (.*)/\2, \1/')"
echo "other delimiters for paths: $(echo '/usr/bin' | sed 's|/usr|/opt|')   escaped slash: $(echo '/usr/bin' | sed 's/\/usr/\/opt/')"
echo "case-insensitive I and GNU case conversion: $(echo 'Hello' | sed 's/hello/bye/I')  $(echo 'hello world' | sed 's/\b./\U&/g')  $(echo 'ABC' | sed 's/.*/\L&/')"
echo "-n with p prints only matches: $(sed -n 's/^port=//p' app.conf)   /re/p: $(sed -n '/^user/p' app.conf)"
echo -n "-n 's/x/y/p' without -n prints twice: "; echo abc | sed 's/b/X/p' | tr '\n' ' '; echo
echo "empty pattern reuses the last regex: $(echo 'aXb' | sed '/X/s//-/')"

echo '### 2. sed: addresses and commands'
echo "line 2: $(sed -n 2p n.txt)  last: $(sed -n '$p' n.txt)  2-4: $(sed -n 2,4p n.txt | tr '\n' ' ')  from 4 to end: $(sed -n '4,$p' n.txt | tr '\n' ' ')  odd lines 1~2: $(sed -n '1~2p' n.txt | tr '\n' ' ')"
echo "delete 2 and 4-5: $(sed '2d;4,5d' n.txt | tr '\n' ' ')   keep all but comments/blanks: $(sed '/^#/d;/^$/d' app.conf | tr '\n' ' ')"
echo "regex range /two/,/four/: $(sed -n '/two/,/four/p' n.txt | tr '\n' ' ')   2,+1: $(sed -n '2,+1p' n.txt | tr '\n' ' ')   negate !: $(sed -n '2!p' n.txt | tr '\n' ' ')"
echo "insert i, append a, change c: $(sed '2i\>>' n.txt | sed -n 2p) $(sed '2a\<<' n.txt | sed -n 3p) $(sed '2c\CHANGED' n.txt | sed -n 2p)"
echo "quit early q (fast on big files): $(sed 2q n.txt | tr '\n' ' ')   count lines: $(sed -n '$=' n.txt)"
echo "several commands with -e or ;: $(sed -e 's/one/1/' -e 's/two/2/' n.txt | head -2 | tr '\n' ' ')"
echo "y/// transliterates: $(echo 'hello' | sed 'y/el/ip/')   w writes matches to a file: $(sed -n '/o/w o.txt' n.txt; tr '\n' ' ' < o.txt)"
echo "reverse lines with the hold space (tac): $(sed -n '1!G;h;$p' n.txt | tr '\n' ' ')"
echo "join all lines: $(sed ':a;N;$!ba;s/\n/,/g' n.txt)   join pairs: $(sed 'N;s/\n/+/' n.txt | tr '\n' ' ')"
echo "squeeze blank lines: $(printf 'a\n\n\n\nb\n' | sed '/^$/N;/^\n$/D' | tr '\n' '|')"
echo "show hidden characters with l: $(printf 'a\tb \r\n' | sed -n l)"
echo "remove CR / trailing spaces / leading spaces: $(printf 'x  \r\n' | sed 's/\r$//;s/ *$//' | od -c | head -1 | cut -c9-)  $(echo '   lead' | sed 's/^ *//')"
echo "number lines of matches: $(sed -n '/o/=' n.txt | tr '\n' ' ')   print line numbers + text: $(grep -n o n.txt | tr '\n' ' ')"

echo '### 3. sed -i (in place) and its dangers'
cp app.conf c1.conf; sed -i 's/db1/db2/' c1.conf; echo "-i edited in place: $(grep host c1.conf)"
cp app.conf c2.conf; sed -i.bak 's/db1/db3/' c2.conf; echo "-i.bak keeps a backup: $(grep host c2.conf) / $(grep host c2.conf.bak) ($(ls c2.conf* | tr '\n' ' '))"
echo "-i on several files: $(cp app.conf x1; cp app.conf x2; sed -i 's/db1/Z/' x1 x2; grep -h host x1 x2 | tr '\n' ' ')"
echo -n "-i on a symlink replaces the link with a file: "; cp app.conf real; ln -s real lnk; sed -i 's/db1/L/' lnk; [ -L lnk ] && echo "still a link" || echo "no longer a link (a regular file now)"
echo -n "-i with a typo in the program leaves the file alone: "; cp app.conf c3.conf; sed -i 's/db1/' c3.conf 2>&1 | head -1 | cut -c1-60; cmp -s app.conf c3.conf && echo "file unchanged"
echo -n "sed without -i never changes the file: "; sed 's/db1/X/' app.conf >/dev/null; grep -c db1 app.conf
echo -n "the BSD/macOS difference: GNU 'sed -i EXPR' vs BSD 'sed -i \"\" EXPR' (BSD needs a suffix argument). busybox: "; cp app.conf bb.conf; $BUSYBOX sed -i 's/db1/bb/' bb.conf && grep host bb.conf

echo '### 4. sed and shell variables'
x='a.b'; echo "metachar in a variable: $(echo 'aXb a.b' | sed "s/$x/[&]/g")   (the . matched X too)"
esc=$(printf '%s' "$x" | sed 's/[.[\*^$/]/\\&/g'); echo "escaped first: $(echo 'aXb a.b' | sed "s/$esc/[&]/g")"
v='x/y'; echo -n "a / in the variable breaks the s command: "; echo 'z' | sed "s/z/$v/" 2>&1 | head -1 | cut -c1-70
echo -n "use another delimiter: "; echo 'z' | sed "s|z|$v|"
v='a&b'; echo "& in the replacement means the match: $(echo 'z' | sed "s/z/$v/")   escaped: $(echo 'z' | sed 's/z/a\&b/')"
echo -n "single quotes stop the shell expanding \$: "; echo 'cost $5' | sed 's/\$5/five/'
echo -n "double quotes expand it before sed sees it: "; five=9; echo 'cost 9' | sed "s/$five/nine/"

echo '### 5. awk basics'
printf 'alice 30 NY\nbob 25 LA\ncarol 41 NY\n' > p.txt
echo "fields: $(awk '{print $1, $2}' p.txt | tr '\n' ';')   last field: $(awk '{print $NF}' p.txt | tr '\n' ' ')   whole line \$0: $(awk 'NR==2{print $0}' p.txt)"
echo "-F separator: $(awk -F: '{print $1}' /etc/passwd | head -2 | tr '\n' ' ')   multi-char regex FS: $(echo 'a1b22c' | awk -F'[0-9]+' '{print $1,$2,$3}')   tab: $(printf 'a\tb c\n' | awk -F'\t' '{print $2}')"
echo "pattern + action: $(awk '$2 > 28 {print $1}' p.txt | tr '\n' ' ')   regex: $(awk '/NY/ {print $1}' p.txt | tr '\n' ' ')   field regex: $(awk '$3 ~ /^N/ {print $1}' p.txt | tr '\n' ' ')   negated: $(awk '$3 !~ /NY/ {print $1}' p.txt)"
echo "NR and NF: $(awk '{print NR": "NF" fields"}' p.txt | tr '\n' ';')   END: $(awk 'END{print NR" lines, last line: "$0}' p.txt)"
echo "sum and average: $(awk '{s+=$2} END{print s, s/NR}' p.txt)   max: $(awk 'NR==1||$2>m{m=$2;n=$1} END{print n, m}' p.txt)"
echo "BEGIN, -v, and printf: $(awk -v min=26 'BEGIN{print "start"} $2>=min{printf "%-6s|%3d|\n", $1, $2}' p.txt | tr '\n' ' ')"
echo "OFS and rebuilding \$0: $(awk 'BEGIN{OFS=","} {$1=$1; print}' p.txt | tr '\n' ';')   change a field: $(awk '{$2=$2+1; print}' p.txt | head -1)"
echo "count by key (associative array): $(awk '{c[$3]++} END{for(k in c) print k, c[k]}' p.txt | sort | tr '\n' ';')"
echo "sum by key: $(awk '{s[$3]+=$2} END{for(k in s) print k, s[k]}' p.txt | sort | tr '\n' ';')"
echo "dedupe keeping order: $(printf 'b\na\nb\nc\na\n' | awk '!seen[$0]++' | tr '\n' ' ')"
echo "string functions: length $(echo hello | awk '{print length($0)}') substr $(echo hello | awk '{print substr($0,2,3)}') index $(echo hello | awk '{print index($0,"ll")}') toupper $(echo hello | awk '{print toupper($0)}') split $(echo 'a:b:c' | awk '{n=split($0,p,":"); print n, p[2]}')"
echo "sub/gsub: $(echo 'a-b-c' | awk '{gsub(/-/,"+"); print}')   match(): $(echo 'abc123' | awk '{if (match($0,/[0-9]+/)) print substr($0,RSTART,RLENGTH)}')"
echo "ranges: $(awk '/bob/,/carol/ {print $1}' p.txt | tr '\n' ' ')   skip header: $(awk 'NR>1{print $1}' p.txt | tr '\n' ' ')   every 2nd: $(awk 'NR%2==0{print $1}' p.txt)"
echo "two files, FNR vs NR: $(awk 'FNR==1{print FILENAME": first line"}' n.txt p.txt | tr '\n' ';')   lookup join: $(printf '1 admin\n2 user\n' > roles.txt; printf '1 alice\n2 bob\n' | awk 'NR==FNR{r[$1]=$2; next} {print $2, r[$1]}' roles.txt - | tr '\n' ';')"
echo "key=value config: $(awk -F= '!/^#/ && NF==2 {print $1" -> "$2}' app.conf | tr '\n' ';')   one value: $(awk -F= '$1=="port"{print $2}' app.conf)"
echo "unset variable is empty AND zero: $(awk 'BEGIN{print x+0, "[" x "]"}')"
echo "numeric vs string comparison of FIELDS: 10 vs 9 -> $(echo '10 9' | awk '{print ($1>$2) ? "numeric: 10 > 9" : "string: 10 < 9"}')   of a constant string: $(awk 'BEGIN{a="10"; b="9"; print (a>b) ? "10>9" : "string compare: 10<9"}')"
echo "integer division does not exist: $(awk 'BEGIN{print 7/2, int(7/2), 7%2}')   big numbers: $(awk 'BEGIN{print 2^53+1, 2^31}')   printf %d of a large value: $(awk 'BEGIN{printf "%d\n", 2^40}')"
echo "getline from a command: $(awk 'BEGIN{"echo hi" | getline x; print x}')   system(): $(awk 'BEGIN{r=system("exit 3"); print "status", r}')"
echo "ENVIRON: $(HOME=/h awk 'BEGIN{print ENVIRON["HOME"]}')"

echo '### 6. awk and shell variables'
x='NY'; echo "-v passes a value safely: $(awk -v k="$x" '$3==k{print $1}' p.txt | tr '\n' ' ')"
echo "interpolating into the program: $(awk "\$3==\"$x\"{print \$1}" p.txt | tr '\n' ' ')   (works until the value has a quote)"
y='x" || 1 || "'; echo -n "injection through string interpolation: "; awk "\$3==\"$y\"{print \$1}" p.txt | tr '\n' ' '; echo "(printed every line)"
echo "-v processes backslash escapes: $(awk -v s='a\tb' 'BEGIN{print s}' | od -c | head -1 | cut -c9-)   ENVIRON does not: $(s='a\tb' awk 'BEGIN{print ENVIRON["s"]}')"

echo '### 7. CSV and quoted fields'
printf 'name,qty\n"Smith, John",3\nplain,4\n' > q.csv
echo "naive -F, on a quoted comma: $(awk -F, 'NR==2{print NF" fields; first="$1}' q.csv)   (should be 2 fields)"
echo -n "gawk FPAT handles it (gawk only): "; gawk 'BEGIN{FPAT="([^,]+)|(\"[^\"]+\")"} NR==2{print NF" fields; first="$1}' q.csv
echo -n "mawk and busybox awk with FPAT: "; mawk 'BEGIN{FPAT="x"} NR==2{print NF}' q.csv 2>&1 | head -1 | cut -c1-50

echo '### 8. xargs'
printf 'a\nb\nc\nd\ne\n' > list.txt
echo "default: all args at once: $(xargs < list.txt | head -1)   -n2: $(xargs -n2 < list.txt | tr '\n' '|')   -I{} one per call: $(xargs -I{} echo '<{}>' < list.txt | tr '\n' ' ')"
echo -n "quotes in input are interpreted by default: "; echo "it's" | xargs echo 2>&1 | head -1 | cut -c1-50; echo -n "   with -d '\\n': "; echo "it's" | xargs -d '\n' echo
echo -n "empty input runs the command once (GNU) unless -r: "; xargs echo ran < /dev/null; xargs -r echo ran < /dev/null; echo "(-r printed nothing)"
echo -n "exit status when a command fails: "; printf 'a\nb\n' | xargs -n1 sh -c 'exit 1' _ 2>/dev/null; echo "$? (123 = at least one invocation failed)"
echo -n "-P runs in parallel: "; start=$(date +%s%N); printf '1\n1\n1\n1\n' | xargs -P4 -n1 sleep >/dev/null; end=$(date +%s%N); echo "4 x sleep 1 took $(( (end-start)/1000000000 )) s with -P4"
echo -n "-0 with find -print0: "; touch "a b" "c'd"; find . -maxdepth 1 \( -name 'a b' -o -name "c'd" \) -print0 | xargs -0 ls | tr '\n' '|'; echo
echo -n "{} inside a quoted shell command is an injection risk: "; printf 'x; echo INJECTED\n' | xargs -I{} sh -c 'echo {}' 2>&1 | tr '\n' '|'; echo; echo -n "   safe: pass as an argument: "; printf 'x; echo INJECTED\n' | xargs -I{} sh -c 'echo "$1"' _ {} | tr '\n' '|'; echo
echo -n "maximum command line is large but finite: "; getconf ARG_MAX

echo '### 9. a log-analysis pipeline'
cat > access.log <<'EOF'
10.0.0.1 - - [21/Nov/2026:10:01:02 +0000] "GET /index.html HTTP/1.1" 200 1024
10.0.0.2 - - [21/Nov/2026:10:01:05 +0000] "GET /missing HTTP/1.1" 404 128
10.0.0.1 - - [21/Nov/2026:10:02:00 +0000] "POST /login HTTP/1.1" 200 256
10.0.0.3 - - [21/Nov/2026:11:00:10 +0000] "GET /api/x HTTP/1.1" 500 64
10.0.0.1 - - [21/Nov/2026:11:00:11 +0000] "GET /index.html HTTP/1.1" 304 0
10.0.0.2 - - [21/Nov/2026:11:30:00 +0000] "GET /api/y HTTP/1.1" 500 80
EOF
echo "requests per IP:          $(awk '{print $1}' access.log | sort | uniq -c | sort -rn | sed 's/^ *//' | tr '\n' ';')"
echo "status code counts:       $(awk '{print $9}' access.log | sort | uniq -c | sort -k2n | sed 's/^ *//' | tr '\n' ';')"
echo "5xx lines:                $(awk '$9 ~ /^5/' access.log | wc -l)   (grep -c ' 5[0-9][0-9] ': $(grep -c ' 5[0-9][0-9] ' access.log))"
echo "bytes per IP:             $(awk '{b[$1]+=$10} END{for(i in b) print i, b[i]}' access.log | sort | tr '\n' ';')"
echo "requests per hour:        $(awk -F'[ :]' '{print $5}' access.log | sort | uniq -c | sed 's/^ *//' | tr '\n' ';')"
echo "top paths:                $(awk '{print $7}' access.log | sort | uniq -c | sort -rn | head -2 | sed 's/^ *//' | tr '\n' ';')"
echo "paths with errors:        $(awk '$9>=400 {print $7, $9}' access.log | tr '\n' ';')"
echo "extract the date with sed: $(sed -n '1s/.*\[\([^:]*\):.*/\1/p' access.log)   the request line: $(sed -n '1s/.*"\(.*\)".*/\1/p' access.log)"
echo "same job without awk (cut works only with a single-char delimiter): $(cut -d' ' -f1 access.log | sort -u | tr '\n' ' ')"
echo "grep -o to extract: $(grep -oE '"[A-Z]+ [^ ]+' access.log | sort | uniq -c | sort -rn | head -1 | sed 's/^ *//')"

echo '### 10. speed: the right tool'
seq 1 100000 > big.txt
t() { local s e; s=$(date +%s%N); "$@" >/dev/null; e=$(date +%s%N); echo -n "$(( (e-s)/1000000 )) ms"; }
echo "count lines: wc -l $(t wc -l big.txt)  | awk 'END{print NR}' $(t awk 'END{print NR}' big.txt)  | grep -c '' $(t grep -c '' big.txt)"
echo "while read loop doing the same, 100000 lines: $(t bash -c 'n=0; while IFS= read -r _; do n=$((n+1)); done < big.txt; echo $n')"
echo "sum: awk $(t awk '{s+=$1} END{print s}' big.txt)  | bash loop $(t bash -c 's=0; while read -r x; do s=$((s+x)); done < big.txt; echo $s')"

echo '### 11. other implementations'
cmpt() { for impl in "gawk" "mawk" "$BUSYBOX awk"; do out=$($impl "$1" </dev/null 2>&1 | head -1 | cut -c1-40); printf '  %-14s %s\n' "${impl##*/}" "[$out]"; done; }
echo "-- length of an array (gawk extension in old awks), gensub, asort, strftime:"
for prog in 'BEGIN{a[1];a[2]; print length(a)}' 'BEGIN{print gensub(/a/,"b","g","aaa")}' 'BEGIN{n=asort(a); print n}' 'BEGIN{print strftime("%Y")>"/dev/null"; print "ok"}' 'BEGIN{printf "%d\n", 2^40}' 'BEGIN{print toupper("x"), tolower("Y")}' 'BEGIN{print substr("hello",0,2)}'; do echo "  program: $prog"; cmpt "$prog"; done
echo "-- sed: -E, \\+, -z, -s and --debug on GNU, and busybox sed:"
for prog in "echo aab | sed -E 's/a+/X/'" "echo aab | sed 's/a\\+/X/'" "echo aab | sed -n '/a/{p;q}'" "printf 'a\\nb\\n' | sed -z 's/\\n/,/g'" "echo Hello | sed 's/hello/x/I'" "echo hello | sed 's/.*/\\U&/'"; do
  g=$(bash -c "$prog" 2>&1 | head -1 | cut -c1-30); b=$(bash -c "${prog//sed/$BUSYBOX sed}" 2>&1 | head -1 | cut -c1-40); printf '  %-46s GNU: %-12s busybox: %s\n' "$prog" "[$g]" "[$b]"
done

cd / && rm -rf "$D"
