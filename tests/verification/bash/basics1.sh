#!/usr/bin/env bash
# Battery for foundations.bash-basics (GNU coreutils on Ubuntu 26.04 under WSL2). Temp folder only.
D=$(mktemp -d); cd "$D" || exit 1
echo "bash $BASH_VERSION; $(ls --version | head -1)"
args() { printf '%d args:' "$#"; printf ' [%s]' "$@"; echo; }

echo '### 1. help'
type cd ls help | sed 's/^/  /'
echo "  help cd (first line): $(help cd | head -1)"
echo "  ls --help (first 2 lines): $(ls --help | head -2 | tr '\n' '|')"
echo -n '  man installed? '; command -v man >/dev/null && echo yes || echo no
echo -n '  nano/vi/vim: '; for e in nano vi vim; do command -v $e >/dev/null && echo -n "$e "; done; echo
echo -n '  a missing command: '; nosuchcommand 2>&1; echo "  status $?"
echo -n '  command -v vs type vs which for a builtin: '; command -v cd; type -t cd; which cd 2>&1 | head -1

echo '### 2. where you are'
mkdir -p "$D/work/sub"; cd "$D/work" || exit
echo "pwd=${PWD#$D}  OLDPWD=${OLDPWD:-unset}"
cd sub; echo "in sub: ${PWD#$D}"; cd -  >/dev/null; echo "cd - went back to ${PWD#$D}"
cd; echo "cd with no argument -> $PWD"; cd "$D/work"
echo -n 'cd ~ and cd "$HOME" equal: '; [ ~ = "$HOME" ] && echo yes
echo -n 'cd to a missing folder: '; cd nowhere 2>&1; echo "status $?"
echo -n 'cd with a space unquoted: '; mkdir "my folder"; cd my folder 2>&1 | head -1; cd "my folder" && echo "quoted works" && cd ..

echo '### 3. ls and reading its output'
touch a.txt .hidden; mkdir dir1; echo hello > data.txt; chmod 640 data.txt; ln -s data.txt link.txt
ls; echo "--- ls -a"; ls -a | tr '\n' ' '; echo
echo "--- ls -l"; ls -l | sed 's/ dakota / USER /g; s/ [A-Za-z]\{3\} [ 0-9]\{2\} [0-9:]\{5\} / DATE /'
echo "--- ls -ld dir1 (the folder itself): $(ls -ld dir1 | cut -c1-10)"
echo "--- ls -lh sizes, -S by size, -t by time, -R recursive"; head -c 3000 /dev/zero > big.bin; ls -lhS | sed -n '2,3p' | awk '{print $5, $9}'
echo -n '--- ls with no matching name: '; ls nosuchfile 2>&1; echo "status $?"
echo -n '--- ls *.txt when none match: '; ( cd dir1; ls *.txt 2>&1 )
echo "--- file and stat"; file data.txt link.txt dir1 big.bin | sed "s#$D/##"
stat -c '%n: %s bytes, mode %a, links %h' data.txt

echo '### 4. making, copying, moving, removing'
mkdir -p p/q/r; echo "mkdir -p made: $(find p -type d | tr '\n' ' ')"
echo -n 'mkdir without -p on a deep path: '; mkdir x/y/z 2>&1
echo one > f1; cp f1 f2; echo "cp keeps the original: $(cat f1) $(cat f2)"
echo two > f2; cp f1 f2; echo "cp overwrote f2 silently: $(cat f2)"
echo two > f2; cp -n f1 f2; echo "cp -n did not overwrite: $(cat f2)"
echo -n 'cp -i would ask: '; echo n | cp -i f1 f2 2>&1; echo
echo -n 'cp a folder without -r: '; cp dir1 dir2 2>&1
cp -r dir1 dir2; echo "cp -r: $(ls -d dir2)"
mkdir dest; cp -r dir1 dest; echo "cp -r into an EXISTING folder nests it: $(find dest | tr '\n' ' ')"
rm -rf dest; mv f1 renamed; echo "mv renames: $(ls renamed)"
mv renamed dir1/; echo "mv moves into a folder: $(ls dir1)"
echo moved > a1; echo target > a2; mv a1 a2; echo "mv onto an existing file replaced it: $(cat a2)"
echo -n 'rm a folder without -r: '; rm dir1 2>&1
echo -n 'rmdir a non-empty folder: '; rmdir dir1 2>&1
rm -r dir1; echo "rm -r removed it: $(ls -d dir1 2>&1 | head -1)"
echo -n 'rm of a missing file: '; rm nosuch 2>&1; echo "status $?"; echo -n 'rm -f of a missing file: '; rm -f nosuch; echo "status $?"
echo -n 'rm -i asks: '; touch askme; echo n | rm -i askme 2>&1; echo; ls askme
echo '--- a file named -rf.txt and a file named "my file.txt"'
touch -- -rf.txt "my file.txt" keep1 keep2
echo -n '  ls * : '; ls * | tr '\n' '|'; echo
echo -n '  rm *.txt tries to read -rf.txt as options? '; ( rm *.txt 2>&1 ) | head -2; echo "  left: $(ls | tr '\n' ' ')"
touch -- -rf.txt "my file.txt"
echo -n '  rm -- -rf.txt: '; rm -- -rf.txt && echo ok; echo -n '  rm ./my\ file.txt: '; rm ./my\ file.txt && echo ok
echo -n '  rm my file.txt (unquoted, two names): '; touch "my file.txt" my file.txt; rm my file.txt 2>&1; ls my* 2>&1 | head -2
rm -f my file.txt "my file.txt"
echo '--- links'
echo content > orig; ln orig hard; ln -s orig soft
echo "link counts: $(stat -c '%h' orig) (orig and hard share one file); soft is its own file pointing at: $(readlink soft)"
rm orig; echo -n "after rm orig: hard still reads: $(cat hard); soft: "; cat soft 2>&1
ls -l soft | awk '{print "soft shows as:", $1, $9, $10, $11}'
find . -maxdepth 1 -xtype l | sed 's/^/broken link found by find -xtype l: /'

echo '### 5. looking inside files'
seq 1 20 > nums.txt
echo "head -3: $(head -3 nums.txt | tr '\n' ' ')  tail -3: $(tail -3 nums.txt | tr '\n' ' ')  head -n -17 (all but last 17): $(head -n -17 nums.txt | tr '\n' ' ')"
echo "sed -n 5,7p: $(sed -n '5,7p' nums.txt | tr '\n' ' ')"
printf 'one two\nthree four five\n' > words.txt
echo "wc: lines=$(wc -l < words.txt) words=$(wc -w < words.txt) bytes=$(wc -c < words.txt)"
echo "wc file prints the name: $(wc -l words.txt)"; echo "wc from stdin does not: [$(wc -l < words.txt)]"
printf 'caf\xc3\xa9\n' > utf.txt; echo "wc -c=$(wc -c < utf.txt) wc -m=$(wc -m < utf.txt) (bytes vs characters)"
printf 'tab\there\r\nline2  \n' > hidden.txt; echo "cat -A shows hidden characters:"; cat -A hidden.txt | sed 's/^/  /'
echo -n 'tail -f follows a growing file (3 s): '; : > grow.log; ( for i in 1 2 3; do echo "line $i" >> grow.log; sleep 0.4; done ) & timeout 2 tail -f grow.log | tr '\n' ' '; wait; echo
echo -n 'cat on a missing file: '; cat nosuch 2>&1; echo -n 'less/more: not testable non-interactively; '; command -v less >/dev/null && echo "less is installed"

echo '### 6. permissions'
touch pf; mkdir pd
echo "default file mode: $(stat -c '%a' pf), default folder mode: $(stat -c '%a' pd), umask: $(umask)"
chmod u+x pf; echo "chmod u+x:  $(ls -l pf | cut -c1-10)"; chmod go-r pf; echo "chmod go-r: $(ls -l pf | cut -c1-10)"
chmod 755 pf; echo "chmod 755:  $(ls -l pf | cut -c1-10)"; chmod 600 pf; echo "chmod 600:  $(ls -l pf | cut -c1-10)"
( umask 077; touch private; mkdir privdir; echo "umask 077 -> file $(stat -c '%a' private), folder $(stat -c '%a' privdir)" )
echo 'echo ran' > noexec.sh; echo -n 'run without x: '; ./noexec.sh 2>&1; echo -n 'run with bash noexec.sh: '; bash noexec.sh
chmod +x noexec.sh; echo -n 'after chmod +x: '; ./noexec.sh 2>&1
echo -n 'a script needs a shebang? this one has none: '; ./noexec.sh
chmod 000 pf; echo -n 'cat a file with mode 000 as myself: '; cat pf 2>&1; chmod 600 pf
echo -n 'folder without x cannot be entered: '; chmod 600 pd; ls pd 2>&1 | head -1; cd pd 2>&1 | head -1; chmod 755 pd
echo "id: $(id | sed 's/groups=.*//')"; echo "whoami: $(whoami)"; echo "groups: $(groups | wc -w) groups"
echo -n 'sudo needs a password here: '; sudo -n true 2>&1 | head -1

echo '### 7. the environment and PATH'
echo "PATH has $(echo "$PATH" | tr ':' '\n' | wc -l) entries; first three: $(echo "$PATH" | cut -d: -f1-3)"
echo -n 'type -a ls: '; type -a ls | head -2 | tr '\n' '|'; echo
mkdir -p mybin; printf '#!/usr/bin/env bash\necho "my tool ran"\n' > mybin/mytool; chmod +x mybin/mytool
echo -n 'mytool not on PATH: '; mytool 2>&1; echo -n 'with ./ : '; ./mybin/mytool
echo -n 'PATH=$PATH:mybin for ONE command: '; PATH="$PATH:$D/work/mybin" mytool; echo -n 'afterwards: '; mytool 2>&1
export PATH="$PATH:$D/work/mybin"; echo -n 'after export PATH: '; mytool
echo -n 'a variable is not visible to a child unless exported: '; v=plain; bash -c 'echo "[${v:-not set}]"'; export v; echo -n 'exported: '; bash -c 'echo "[${v:-not set}]"'
echo -n 'VAR=value command sets it for that command only: '; MYVAR=once bash -c 'echo "$MYVAR"'; echo "afterwards: [${MYVAR:-unset}]"
echo -n 'env vs shell variables: '; unexported=1; env | grep -c '^unexported='
echo -n 'alias in a script (non-interactive): '; bash -c 'alias hi="echo alias-ran"; hi' 2>&1 | head -1
echo -n 'alias used right away in -i: '; bash -ic 'alias hi="echo alias-ran"; hi' 2>&1 | head -1

echo '### 8. redirection and pipes'
echo out > o.txt; echo "> truncates: $(cat o.txt)"; echo more >> o.txt; echo ">> appends: $(tr '\n' ' ' < o.txt)"
ls nosuch > out.txt 2> err.txt; echo "stdout file: [$(cat out.txt)] stderr file: [$(cat err.txt)]"
ls nosuch o.txt > both.txt 2>&1; echo "2>&1 after > : both in one file: $(tr '\n' ' ' < both.txt)"
ls nosuch o.txt 2>&1 > only-out.txt; echo "  ORDER matters: with 2>&1 BEFORE > the error went to the screen (above) and the file holds: $(cat only-out.txt)"
ls nosuch o.txt &> all.txt; echo "&> (bash): $(wc -l < all.txt) lines"
echo -n '/dev/null discards: '; ls nosuch 2>/dev/null; echo "status $?"
printf 'b\na\nb\nc\nb\n' > list.txt
echo "sort | uniq -c | sort -rn: $(sort list.txt | uniq -c | sort -rn | head -2 | tr '\n' '|')"
echo "tee writes AND passes on: $(echo hi | tee t.txt) / file: $(cat t.txt)"
echo -n 'the classic trap, sort f > f: '; cp list.txt keep.txt; sort keep.txt > keep.txt; echo "file now has $(wc -l < keep.txt) lines (was 5)"
( set -C; echo x > o.txt ) 2>&1 | sed 's/.*: //' | head -1
echo -n '; && || : '; true; echo -n "a "; false || echo -n "b "; true && echo -n "c "; false && echo -n "NOT"; echo
echo -n 'a && b || c is not if/else: '; true && false || echo "c ran although the test passed"
echo -n 'pipeline status is the LAST command: '; false | true; echo "$?  PIPESTATUS: ${PIPESTATUS[*]}"
echo -n 'stdin from a file vs cat: '; wc -l < list.txt; echo -n 'useless cat: '; cat list.txt | wc -l
echo -n '|& pipes both streams: '; ls nosuch |& wc -l
echo -n 'command substitution and quotes: '; today=$(date +%F); echo "${today:0:2}.. (a date)"

echo '### 9. processes and jobs'
echo "my shell: PID $$, parent $PPID"
sleep 30 & bg=$!; echo "started background job, \$!=$bg"; jobs 2>&1 | head -1
ps -o pid,ppid,stat,comm -p $bg | tail -1 | awk '{print "ps shows: pid", $1, "ppid", $2, "stat", $3, "cmd", $4}'
kill $bg; wait $bg 2>/dev/null; echo "killed with TERM, wait status $? (128+15)"
sleep 30 & bg=$!; kill -KILL $bg; wait $bg 2>/dev/null; echo "kill -KILL status $?"
echo -n 'kill -l (first 6): '; kill -l | tr '\n' ' ' | cut -c1-70; echo
echo -n 'pgrep finds by name: '; sleep 31 & p=$!; pgrep -f 'sleep 31' | wc -l | tr '\n' ' '; kill $p; echo
echo -n 'ps -ef lines: '; ps -ef | wc -l; echo -n 'ps columns: '; ps -ef | head -1
echo -n 'a job survives the shell only with nohup/setsid: '; command -v nohup >/dev/null && echo "nohup present"
echo -n 'wait for several jobs: '; ( sleep 0.3; exit 3 ) & ( sleep 0.1; exit 0 ) & wait; echo "after wait: $?"
echo -n 'timeout: '; timeout 1 sleep 5; echo "status $? (124 = timed out)"

echo '### 10. finding things'
mkdir -p tree/a tree/b; echo "needle here" > tree/a/one.txt; echo "nothing" > tree/b/two.txt; echo "Needle again" > tree/b/three.log; touch -d '10 days ago' tree/b/old.txt
echo "find by name  : $(find tree -name '*.txt' | sort | tr '\n' ' ')"
echo "find iname    : $(find tree -iname 'THREE*' | tr '\n' ' ')"
echo "find -type f  : $(find tree -type f | wc -l) files, -type d: $(find tree -type d | wc -l) folders"
echo "find -mtime +5: $(find tree -type f -mtime +5)"
echo "find -size    : $(find . -maxdepth 1 -type f -size +2k | tr '\n' ' ')"
echo "find -exec    : $(find tree -name '*.txt' -exec wc -l {} + | tail -1)"
echo -n 'find with a space in names, -print0 | xargs -0: '; touch "tree/a/sp ace.txt"; find tree -name '*.txt' -print0 | xargs -0 ls | wc -l
echo -n 'xargs without -0 on that name: '; find tree -name 'sp*' | xargs ls 2>&1 | head -2 | tr '\n' ' '; echo
echo "grep -r        : $(grep -r needle tree | tr '\n' ' ')"
echo "grep -ri       : $(grep -ri needle tree | wc -l) matches"
echo "grep -rn       : $(grep -rn needle tree/a)"
echo "grep -rl       : $(grep -rli needle tree | sort | tr '\n' ' ')"
echo "grep -c        : $(grep -c nothing tree/b/two.txt); grep -v: $(grep -v nothing tree/b/two.txt | wc -l); grep -w: $(echo 'a needles' | grep -cw needle)"
echo -n 'grep -E alternation: '; printf 'cat\ndog\nbird\n' | grep -E 'cat|bird' | tr '\n' ' '; echo
echo -n 'grep status (found 0, not found 1, error 2): '; grep -q needle tree/a/one.txt; echo -n "$? "; grep -q zzz tree/a/one.txt; echo -n "$? "; grep -q x /nonexistent 2>/dev/null; echo "$?"
echo -n 'which / command -v: '; command -v grep ls | tr '\n' ' '; echo
echo -n 'locate installed? '; command -v locate >/dev/null && echo yes || echo no

echo '### 11. system information'
echo "uname -sr: $(uname -sr | sed 's/[0-9.-]*microsoft.*/<kernel>/')"; echo "hostname set: $([ -n "$(hostname)" ] && echo yes)"
echo "date +%F: $(date +%F | sed 's/[0-9]/N/g'), date -d '1 day ago' works: $(date -d '1 day ago' +%F >/dev/null 2>&1 && echo yes)"
echo -n 'df -h header: '; df -h / | head -1; echo -n 'du -sh of a folder: '; du -sh tree | awk '{print $1}'; echo -n 'free -h header: '; free -h | head -1
echo -n 'uptime format: '; uptime | sed 's/[0-9]/N/g' | cut -c1-40

echo '### 12. first script'
cat > hello.sh <<'EOF'
#!/usr/bin/env bash
# greet each argument
if [ "$#" -eq 0 ]; then
    echo "usage: hello.sh NAME..." >&2
    exit 2
fi
for who in "$@"; do
    echo "Hello, $who!"
done
EOF
chmod +x hello.sh
./hello.sh Alice Bob; ./hello.sh; echo "status $?"; ./hello.sh "Mary Ann"
echo -n 'bash -n hello.sh: '; bash -n hello.sh && echo "syntax ok"
echo -n 'bash -x trace: '; bash -x hello.sh Zed 2>&1 | tr '\n' '|'; echo
printf '#!/usr/bin/env bash\nname=$1\necho "Hi, $nmae"\n' > typo.sh; echo -n 'a typo in a variable name (silent): '; bash typo.sh Bob; echo -n 'with set -u: '; bash -u typo.sh Bob 2>&1
printf '#!/usr/bin/env bash\nread -r -p "Name? " n\necho "Hello $n"\n' > ask.sh; echo -n 'read from stdin: '; echo Pat | bash ask.sh 2>&1 | tr '\n' ' '; echo
echo -n 'script run with sh instead (dash): '; sh hello.sh Dee
echo -n 'syntax error message: '; printf 'if true; then echo a\n' > bad.sh; bash bad.sh 2>&1 | sed "s#$D/##"
echo -n 'command not found inside a script, and it keeps going: '; printf '#!/usr/bin/env bash\nlss\necho "next line still runs"\n' > nf.sh; bash nf.sh 2>&1 | sed "s#$D/##" | tr '\n' '|'; echo
echo -n 'echo vs printf with a leading dash and backslashes: '; v='-n'; echo "$v" | wc -c | tr '\n' ' '; printf '%s\n' "$v"
echo -n 'echo -e is a bash/GNU habit: '; echo -e 'a\tb'
echo "script exit status: $(bash -c 'exit 7'; echo $?)"

echo '### 13. interactive-only features, tested with bash -i'
printf 'echo first\n!!\n' | bash -i 2>&1 | grep -v '^$' | head -4 | tr '\n' '|'; echo
echo "(Tab completion, Ctrl-R search, Ctrl-C/Ctrl-D/Ctrl-L and the arrow keys need a real terminal; they are listed in the lesson, not tested here.)"

cd / && rm -rf "$D"
