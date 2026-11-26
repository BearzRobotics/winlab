# Battery for foundations.bash-basics: output that learners are asked to read. Run in a lab VM.
export LC_ALL=C
run() { printf '$ %s\n' "$*"; eval "$*" 2>&1 </dev/null; printf '[exit %s]\n' "$?"; }
. /etc/os-release; echo "$PRETTY_NAME"
run 'su - labadmin -c id'
run 'uname -sr'
run 'df -h / /boot 2>/dev/null'
run 'free -h'
run 'uptime'
run 'nproc'
run 'ps -ef | head -4'
sleep 40 & p=$!
run "ps -o pid,ppid,user,stat,etime,%cpu,%mem,rss,args -p $p"
run 'ps -eo pid,user,%cpu,%mem,rss,comm --sort=-rss | head -5'
kill $p; wait $p 2>/dev/null
d=$(mktemp -d); cd "$d" || exit 1
printf 'one\n' > a; mkdir sub; ln -s a soft
run 'ls -la'
run 'du -sh .'
run 'ls -ld /tmp /etc/shadow /usr/bin/passwd'
echo '=== the two redirection orders'
run 'ls nosuch a > both.txt 2>&1; cat both.txt'
run 'ls nosuch a 2>&1 > only.txt; echo "--- file has:"; cat only.txt'
cd /; rm -rf "$d"
