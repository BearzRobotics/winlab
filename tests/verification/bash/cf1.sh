#!/usr/bin/env bash
# Battery for foundations.bash-control-flow (bash 5.3.9; dash/busybox for the portable subset). Temp folder only.
D=$(mktemp -d); cd "$D" || exit 1
echo "bash $BASH_VERSION"
args() { printf '%d args:' "$#"; printf ' [%s]' "$@"; echo; }
BUSYBOX="$HOME/tools/busybox"
shopt -s extglob   # must be on its own line before any code that uses extglob patterns

echo '### 1. if tests a COMMAND'
if grep -q root /etc/passwd; then echo "grep succeeded -> then branch"; fi
if ! grep -q zzzzz /etc/passwd; then echo "! negates the status"; fi
if grep -q root /etc/passwd && [ -r /etc/passwd ]; then echo "&& inside the condition"; fi
if true | false; then echo "pipeline true"; else echo "pipeline status is the LAST command's: else branch"; fi
if cd /nonexistent 2>/dev/null; then echo yes; else echo "cd failed -> else (status $?)"; fi
echo -n 'an empty then branch: '; bash -c 'if true; then
fi' 2>&1 | sed 's/^bash: //'
echo -n 'with : (the no-op) instead: '; if true; then :; fi; echo ok
echo -n 'the status after the whole if with no branch taken: '; if false; then echo; fi; echo "$?"
echo -n 'if on a command with output you do not want: '; if ls /etc >/dev/null 2>&1; then echo "use >/dev/null 2>&1 or grep -q"; fi
echo -n '[ is a real program too: '; type -t '['; ls -l /usr/bin/'[' 2>/dev/null | awk '{print $NF}' | head -1
echo -n 'test and [ are the same: '; test 1 -eq 1 && [ 1 -eq 1 ] && echo same

echo '### 2. the [ ] traps'
v=""; echo -n '[ $v = x ] with empty v: '; bash -c 'v=""; [ $v = x ]' 2>&1 | sed 's/^bash: line 1: //'
echo -n '[ -n $v ] with empty v (always true): '; [ -n $v ] && echo true
v="two words"; echo -n '[ $v = x ] with spaces: '; bash -c 'v="two words"; [ $v = x ]' 2>&1 | sed 's/^bash: line 1: //'
echo -n '[ "$v" = "x" ] quoted: '; [ "$v" = "x" ] || echo "false, cleanly"
echo -n 'numbers with = and -eq: '; [ 10 = 10.0 ] || echo -n "[10 = 10.0] false; "; [ 10 -eq 10 ] && echo "[10 -eq 10] true"
echo -n '-eq on a non-number: '; bash -c '[ abc -eq 1 ]; echo "status $?"' 2>&1 | sed 's/^bash: line 1: //'
echo -n '[ 9 \> 10 ] compares as STRINGS: '; [ 9 \> 10 ] && echo "9 > 10 (lexical)"
echo -n '[ 9 -gt 10 ]: '; [ 9 -gt 10 ] || echo "false (numeric)"
echo -n '> unescaped in [ ] is a redirection: '; rm -f 10; [ 9 > 10 ]; echo "status $?, created file: $(ls 10 2>/dev/null)"; rm -f 10
echo -n 'leading zero: [ 010 -eq 10 ] -> '; [ 010 -eq 10 ] && echo "equal (decimal in [ ])" || echo "not equal"; echo -n '              (( 010 == 8 )) -> '; (( 010 == 8 )) && echo "equal (octal in (( )))"
echo -n '-a and -o are ambiguous: '; [ -n "$HOME" -a -n "$PATH" ] && echo "work here; prefer [ ... ] && [ ... ]"
echo -n 'the argument that looks like an operator: '; x='!'; [ "$x" = "!" ] && echo "[ ! = ! ] true"; x='-n'; [ "$x" = "-n" ] && echo "[ -n = -n ] true"
echo -n '[ with a missing space: '; bash -c '[ -f /etc/passwd]' 2>&1 | sed 's/^bash: line 1: //'
echo -n 'if [ ... ] without spaces around brackets: '; bash -c 'if [-f /etc/passwd]; then echo yes; fi' 2>&1 | sed 's/^bash: line 1: //'

echo '### 3. file tests'
mkdir d; echo data > f; : > empty; ln -s f lnk; ln -s nowhere broken; chmod 000 noperm 2>/dev/null; touch noperm; chmod 000 noperm; printf '#!/bin/sh\n' > x.sh; chmod +x x.sh
for t in e f d L h r w x s; do
  printf '  -%s: ' "$t"
  for n in f d empty lnk broken noperm x.sh nosuch; do [ -"$t" "$n" ] && printf '%s ' "$n"; done; echo
done
echo -n '  -e on a broken symlink is false, -L true: '; [ -e broken ] || echo -n "-e false; "; [ -L broken ] && echo "-L true"
touch -d '2 days ago' old; touch new
echo -n '  -nt / -ot: '; [ new -nt old ] && echo -n "new is newer; "; [ old -ot new ] && echo -n "old is older; "; echo
ln f hard; echo -n '  -ef (same file): '; [ f -ef hard ] && echo "f and hard are the same file"
echo -n '  a directory with -f: '; [ -f d ] || echo "false (use -e or -d)"
echo -n '  -z and -n: '; [ -z "" ] && echo -n "-z empty; "; [ -n "x" ] && echo "-n non-empty"
echo -n '  -w on a read-only file as the owner: '; chmod 444 f; [ -w f ] || echo "false"; chmod 644 f
echo -n '  test-then-use is a race (TOCTOU): '; echo "the file can change between [ -f ] and the use"

echo '### 4. [[ ]]'
v="two words"; echo -n '[[ $v = x ]] with spaces, unquoted: '; [[ $v = x ]] || echo "false, no error"
unset e; echo -n '[[ $e = x ]] unset: '; [[ $e = x ]] || echo "false, no error"
echo -n '[[ -n $e ]]: '; [[ -n $e ]] || echo "false (correct, unlike [ -n $e ])"
f=report.log
echo -n '== is a PATTERN on the right: '; [[ $f == *.log ]] && echo "report.log matches *.log"
echo -n 'quoted right side is LITERAL: '; [[ $f == "*.log" ]] || echo "no match against the literal text *.log"
pat='*.log'; echo -n 'a variable on the right is a pattern unless quoted: '; [[ $f == $pat ]] && echo -n "unquoted matches; "; [[ $f == "$pat" ]] || echo "quoted does not"
echo -n '[[ ... ]] and [ ... ] with = and *: '; a='x'; b='*'; [[ $a = $b ]] && echo "[[ x = * ]] is TRUE (pattern)"; [ "$a" = "$b" ] || echo "[ x = * ] false"
echo -n '=~ regex: '; s="build-1234.tar.gz"; if [[ $s =~ ^build-([0-9]+)\.tar\.gz$ ]]; then echo "number=${BASH_REMATCH[1]} whole=${BASH_REMATCH[0]}"; fi
echo -n 'regex in a variable (the safe way): '; re='^([a-z]+)-([0-9]+)'; [[ $s =~ $re ]] && echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
echo -n 'quoting the regex makes it LITERAL: '; [[ $s =~ "^build" ]] || echo "no match (the ^ was literal text)"
echo -n 'BASH_REMATCH is reset on each match: '; [[ abc =~ (b) ]]; echo -n "${BASH_REMATCH[1]} then "; [[ abc =~ zzz ]]; echo "[${BASH_REMATCH[1]-}] after a failed match"
echo -n '&& || ( ) inside [[ ]]: '; [[ -f f && ( -r f || -x f ) ]] && echo "ok"
echo -n '< > compare strings (locale): '; [[ apple < banana ]] && echo -n "apple<banana; "; [[ 9 > 10 ]] && echo "9 > 10 as strings"
echo -n '-v tests that a variable is SET: '; x=""; [[ -v x ]] && echo -n "empty-but-set is set; "; [[ -v nosuchvar ]] || echo "unset is not"
echo -n 'numeric -eq in [[ ]] evaluates arithmetic: '; n=2+3; [[ $n -eq 5 ]] && echo "'2+3' -eq 5 is TRUE (it was evaluated as an expression)"; [ "$n" -eq 5 ] 2>&1 | sed 's/^.*: //' | head -1
echo -n 'a glob is not expanded inside [[ ]]: '; touch aa ab; [[ aa == a* ]] && echo "pattern matching, no file expansion"
echo -n '[[ ]] is a keyword, not a command: '; type -t '[['
echo -n 'a regex with a space needs a variable: '; re='a b'; [[ "a b" =~ $re ]] && echo match

echo '### 5. (( )) and numbers'
n=7; (( n > 5 )) && echo "(( n > 5 )) true, no \$ needed"
(( n % 2 )) && echo "odd (non-zero = true)"
(( n += 3 )); echo "(( n += 3 )) -> $n"
echo -n 'ternary: '; echo $(( n > 5 ? 1 : 0 ))
echo -n '(( ))'"'"'s status is inverted: '; (( 0 )); echo -n "(( 0 )) -> $?; "; (( 5 )); echo "(( 5 )) -> $?"
echo -n 'strings in (( )): '; s=abc; (( s == 0 )) && echo "'abc' counts as 0 (an unset or text name is 0)"
echo -n 'no floating point: '; bash -c '(( 3.5 > 2 ))' 2>&1 | sed 's/^bash: line 1: //' | head -1

echo '### 6. case'
cat > c1.sh <<'EOF'
classify() {
  case $1 in
    [0-9]*)        echo "starts with a digit" ;;
    *.log|*.txt)   echo "a log or a text file" ;;
    [[:upper:]]*)  echo "starts upper case" ;;
    "")            echo "empty" ;;
    -h|--help)     echo "help" ;;
    *)             echo "something else" ;;
  esac
}
for w in 42abc app.log Notes.txt Zed "" --help hello "two words" 'a b.log'; do printf '[%s] -> ' "$w"; classify "$w"; done
EOF
bash c1.sh
echo -n 'case is a glob match, NOT a regex: '; case "aaa" in a+) echo "a+ matched";; *) echo "a+ is the literal text a+";; esac
echo -n 'quote a variable pattern for a literal: '; p='*'; case "xyz" in $p) echo -n "unquoted * matches everything; ";; esac; case "xyz" in "$p") echo "matched";; *) echo "quoted * only matches a literal *";; esac
echo -n 'first match wins: '; case "abc" in a*) echo -n "a*; ";; abc) echo -n "abc; ";; esac; echo
echo -n ';& falls through (bash 4+): '; case 1 in 1) echo -n "one ";& 2) echo -n "two ";& 3) echo -n "three ";; 4) echo -n "NOT";; esac; echo
echo -n ';;& keeps testing later patterns: '; case "ab" in a*) echo -n "a* ";;& *b) echo -n "*b ";; *) echo -n "NOT";; esac; echo
echo -n 'nocasematch: '; shopt -s nocasematch; case "YES" in yes) echo "YES matched yes";; esac; shopt -u nocasematch
echo -n 'no match and no *) : '; case "q" in a) echo a;; esac; echo "status $?"
echo -n 'case on the number of arguments: '; set -- a b; case $# in 0) echo none;; 1) echo one;; *) echo "$# args";; esac; set --
echo -n 'extglob inside case: '; case "photo.png" in *.@(png|jpg)) echo "an image";; esac; shopt -u extglob
echo -n 'a case branch without ;; at the last item is allowed: '; case 1 in 1) echo yes; esac

echo '### 7. for'
echo -n 'for with a word list: '; for c in red "dark green" blue; do echo -n "[$c]"; done; echo
echo -n 'for with no "in" iterates "$@": '; set -- "a b" c; for x; do echo -n "[$x]"; done; echo; set --
echo -n 'unquoted $* in for: '; set -- "a b" c; for x in $*; do echo -n "[$x]"; done; echo; echo -n 'quoted "$@": '; for x in "$@"; do echo -n "[$x]"; done; echo; set --
echo -n 'C-style: '; for ((i = 0; i < 3; i++)); do echo -n "$i "; done; echo "(i=$i after)"
echo -n 'brace range: '; for i in {1..3}; do echo -n "$i "; done; echo
echo -n 'a glob with no match runs ONCE with the pattern: '; for f in *.nomatch; do echo "[$f]"; done
echo -n 'guard: '; for f in *.nomatch; do [ -e "$f" ] || continue; echo found; done; echo "skipped"
echo -n 'nullglob: '; ( shopt -s nullglob; for f in *.nomatch; do echo "body"; done; echo "zero iterations" )
echo -n 'for over $(ls) with a space in a name: '; touch "sp ace"; for f in $(ls sp*); do echo -n "[$f]"; done; echo
echo -n 'for over a glob: '; for f in sp*; do echo -n "[$f]"; done; echo
echo -n 'the loop variable survives the loop: '; for z in 1 2 3; do :; done; echo "z=$z"
echo -n 'status after a for loop = the last body command: '; for q in 1; do false; done; echo "$?"; echo -n 'empty list: '; for q in; do :; done; echo "$?"
echo -n 'changing the list while iterating does not change it: '; L=(a b c); for e in "${L[@]}"; do L+=(x); done; echo "${#L[@]} items after 3 iterations"
echo -n 'seq vs ((: '; n=3; for i in $(seq 1 $n); do echo -n "$i "; done; for ((i=1;i<=n;i++)); do echo -n "$i "; done; echo

echo '### 8. while, until, break, continue'
i=0; while (( i < 3 )); do echo -n "$i "; ((i++)); done; echo "(while)"
i=0; until (( i >= 3 )); do echo -n "$i "; ((i++)); done; echo "(until)"
echo -n 'break 2 leaves both loops: '; for a in 1 2 3; do for b in 1 2 3; do [ $b = 2 ] && continue 2; [ $a = 3 ] && break 2; echo -n "$a$b "; done; done; echo
echo -n 'continue skips: '; for i in 1 2 3 4; do (( i % 2 )) && continue; echo -n "$i "; done; echo
echo -n 'while true with break and a counter: '; n=0; while :; do ((++n >= 4)) && break; done; echo "n=$n"
echo -n 'the status of a while loop that never ran: '; while false; do :; done; echo "$?"
echo -n 'retry with a limit: '; attempt=0; max=3; until [ "$attempt" -ge "$max" ] || false; do attempt=$((attempt+1)); sleep 0.05; done; echo "gave up after $attempt attempts"
echo -n 'a retry that succeeds on the 2nd try: '; n=0; try() { n=$((n+1)); [ $n -ge 2 ]; }; until try; do :; done; echo "succeeded on attempt $n"

echo '### 9. reading lines'
printf 'one\ntwo\nthree' > nonl.txt
echo -n 'last line has no newline, naive loop: '; while IFS= read -r line; do echo -n "[$line]"; done < nonl.txt; echo
echo -n 'with || [ -n "$line" ]: '; while IFS= read -r line || [ -n "$line" ]; do echo -n "[$line]"; done < nonl.txt; echo
printf '  lead and trail  \n a\\b \n' > sp.txt
echo -n 'plain read: '; while read line; do echo -n "[$line]"; done < sp.txt; echo
echo -n 'IFS= read -r: '; while IFS= read -r line; do echo -n "[$line]"; done < sp.txt; echo
printf 'alice:1001:/bin/bash\nbob:1002:/bin/sh\n' > pw.txt
echo -n 'fields: '; while IFS=: read -r user uid shell; do echo -n "$user($uid,$shell) "; done < pw.txt; echo
echo -n 'a command inside the loop that reads stdin eats the rest: '; seq 1 5 > five.txt; while read -r n; do echo -n "got $n; "; cat > /dev/null; done < five.txt; echo
echo -n 'fixed with </dev/null on the inner command: '; while read -r n; do echo -n "got $n; "; cat < /dev/null > /dev/null; done < five.txt; echo
echo -n 'ssh-style stdin theft, shown with sed: '; while read -r n; do echo -n "got $n; "; sed -n 1p >/dev/null; done < five.txt; echo
echo -n 'reading from a variable with a here-string: '; data=$'x\ny'; while IFS= read -r l; do echo -n "[$l]"; done <<< "$data"; echo
echo -n 'pipeline loses variables, < <() keeps them: '; c=0; printf 'a\nb\n' | while read -r _; do ((c++)); done; echo -n "pipe c=$c; "; c=0; while read -r _; do ((c++)); done < <(printf 'a\nb\n'); echo "process-sub c=$c"
echo -n 'NUL-safe loop over find: '; touch "x y" $'new\nline'; n=0; while IFS= read -r -d '' f; do ((n++)); done < <(find . -maxdepth 1 -name 'x*' -o -name 'new*' | tr '\n' '\0' | head -c 0; find . -maxdepth 1 \( -name 'x y' -o -name 'new*' \) -print0); echo "$n names read, including one with a newline in it"
echo -n 'mapfile into an array: '; mapfile -t rows < pw.txt; echo "${#rows[@]} rows, first: ${rows[0]}"
echo -n 'read splits into many variables, the last takes the rest: '; read -r a b c <<< "1 2 3 4 5"; echo "a=$a b=$b c=$c"

echo '### 10. read with timeouts and defaults'
echo -n 'read -t 1 with no input: '; read -t 1 ans < <(sleep 3); echo "status $? (greater than 128 = timeout), ans=[${ans-}]"
echo -n 'read -t with input: '; read -t 1 ans <<< "yes"; echo "status $?, ans=$ans"
echo -n 'read -n 1 reads one char: '; read -r -n 1 ch <<< "xyz"; echo "[$ch]"
echo -n 'a default answer: '; read -r ans <<< ""; ans=${ans:-no}; echo "$ans"
echo -n 'REPLY when no name is given: '; read -r <<< "typed"; echo "$REPLY"
echo -n 'read from a file that does not exist: '; read -r x < /nonexistent 2>&1 | sed 's/^.*: //'; echo
echo -n 'read -p prompt goes to stderr and only when stdin is a terminal: '; echo hi | { read -r -p "Name? " n 2>&1; echo "[$n]"; }

echo '### 11. grouping and short forms'
echo -n 'cmd || { ...; } : '; false || { echo -n "group runs; "; echo "as one unit"; }
echo -n '( ) is a subshell, { } is not: '; x=1; ( x=2 ); echo -n "after ( ): x=$x; "; { x=3; }; echo "after { }: x=$x"
echo -n 'cd in a subshell does not move you: '; ( cd / ); [ "$PWD" = "$D" ] && echo "still in the temp folder"
echo -n 'if on one line: '; if [ -f f ]; then echo yes; else echo no; fi
echo -n 'the && || shorthand is fine for ONE side: '; [ -d d ] && echo "d exists"; [ -d nosuch ] || echo "nosuch missing"
echo -n 'die idiom: '; bash -c 'cd /nonexistent 2>/dev/null || { echo "cannot cd" >&2; exit 1; }; echo "not reached"' 2>&1; echo "status $?"
echo -n 'set -e does not fire inside an if condition: '; bash -c 'set -e; if false; then :; fi; false || true; echo "survived; a bare false would have exited"'
echo -n 'set -e and a failing left side of &&: '; bash -c 'set -e; false && echo x; echo "survived"'
echo -n 'set -e and a failing last command of a function: '; bash -c 'set -e; f() { false; echo "inside after false"; }; if f; then :; fi; echo "survived"' 2>&1

echo '### 12. select'
echo -n 'select menu (input 2 then EOF): '; PS3="pick: "; select s in alpha beta gamma; do echo "chose [$s] reply=[$REPLY]"; break; done <<< "2" 2>&1 | tr '\n' ' '; echo
echo -n 'select with an invalid choice: '; ( select s in a b; do echo "s=[$s] REPLY=[$REPLY]"; break; done <<< $'9\n1' 2>&1 | tr '\n' '|' ); echo

echo '### 13. portable subset in dash and busybox ash'
t() { for sh in "bash" "dash" "$BUSYBOX ash"; do out=$($sh -c "$2" 2>&1); rc=$?; out=${out//$'\n'/ | }; printf '  %-12s rc=%-3s %s\n' "${sh##*/}" "$rc" "${out:0:90}"; done; }
echo "# $1"; echo '-- for without in:'; t x 'set -- a b; for x; do echo -n "[$x]"; done; echo'
echo '-- break 2:'; t x 'for a in 1 2; do for b in 1 2; do break 2; done; done; echo done'
echo '-- case with [[:digit:]] and |:'; t x 'case 5 in [[:digit:]]|x) echo digit;; esac'
echo '-- until and while read -r:'; t x 'i=0; until [ $i -ge 2 ]; do i=$((i+1)); done; echo $i; printf "a b\nc\n" | while read -r x y; do echo "$x/$y"; done'
echo '-- last line without newline:'; t x 'printf "one\ntwo" | { while read -r l; do echo -n "[$l]"; done; echo; }'
echo '-- last line without newline, with the guard:'; t x 'printf "one\ntwo" | { while read -r l || [ -n "$l" ]; do echo -n "[$l]"; done; echo; }'
echo '-- [[ ]]:'; t x '[[ a == a ]] && echo ok'
echo '-- (( )):'; t x 'n=3; (( n > 2 )) && echo big'
echo '-- C-style for:'; t x 'for ((i=0;i<2;i++)); do echo -n $i; done; echo'
echo '-- select:'; t x 'echo 1 | select x in a b; do echo $x; break; done'
echo '-- ;& in case:'; t x 'case 1 in 1) echo one ;& 2) echo two ;; esac'
echo '-- [ -nt ] and [ -ef ] (not POSIX but common):'; t x 'touch a; touch b; [ b -nt a ] && echo newer; [ a -ef a ] && echo same'
echo '-- [ -a ] and [ == ]:'; t x '[ a == a ] && echo eqeq'
echo '-- the one-line arithmetic test with $(( )) in [ ]:'; t x 'n=5; [ $((n % 2)) -eq 1 ] && echo odd'

cd / && rm -rf "$D"
