#!/usr/bin/env bash
# Battery 3 for foundations.bash-functions-and-scripts: settle three surprises from fn2.sh.
D=$(mktemp -d); cd "$D" || exit 1
echo "bash $BASH_VERSION"

echo '### A. why the INT trap did not run'
cat > s3.sh <<'EOF'
#!/usr/bin/env bash
trap 'echo "got INT"' INT
echo ready
sleep 3 &
wait
echo "finished"
EOF
echo -n 'started in the background by a script (SIGINT is ignored at entry): '
bash s3.sh > bg.out 2>&1 & pid=$!; sleep 1; kill -INT "$pid"; wait "$pid"; echo "status $?"; tr '\n' '|' < bg.out; echo
echo -n 'same trap with timeout -s INT (foreground-style): '
timeout -s INT 1 bash s3.sh 2>&1 | tr '\n' '|'; echo
echo -n 'the manual on signals ignored at entry: '; bash -c 'trap -p INT; echo "[no output above = no trap]"' &
wait
echo -n 'a trap on INT in a job started with SIGINT ignored: '; ( trap '' INT; bash -c 'trap "echo trapped" INT; kill -INT $$; echo "alive"' ) 2>&1 | tr '\n' ' '; echo

echo '### B. tee race with exec > >(tee ...)'
cat > l1.sh <<'EOF'
#!/usr/bin/env bash
exec > >(tee -a run.log) 2>&1
echo "line 1"
echo "line 2" >&2
EOF
bash l1.sh; echo "-- immediately after the script: run.log has $(wc -l < run.log 2>/dev/null || echo 0) line(s)"
sleep 0.5; echo "-- half a second later: $(wc -l < run.log) line(s)"
cat > l2.sh <<'EOF'
#!/usr/bin/env bash
{
  echo "line 1"
  echo "line 2" >&2
} 2>&1 | tee -a run2.log
EOF
bash l2.sh; echo "-- pipe to tee, immediately: run2.log has $(wc -l < run2.log) line(s)"
cat > l3.sh <<'EOF'
#!/usr/bin/env bash
exec 3>&1 4>&2
exec > >(tee -a run3.log) 2>&1
echo "line 1"
exec >&3 2>&4      # restore, closing the tee's input
wait               # bash 5: waits for the process substitution
EOF
bash l3.sh >/dev/null; echo "-- restore+wait: run3.log has $(wc -l < run3.log 2>/dev/null || echo 0) line(s)"
echo -n 'redirecting the whole script from outside is simplest: '; ( bash -c 'echo a; echo b >&2' ) > run4.log 2>&1; wc -l < run4.log

echo '### C. flock and inherited file descriptors'
cat > k3.sh <<'EOF'
#!/usr/bin/env bash
exec 9>"$1"
flock -n 9 || { echo "busy"; exit 1; }
sleep 30
EOF
cat > k4.sh <<'EOF'
#!/usr/bin/env bash
exec 9>"$1"
flock -n 9 || { echo "busy"; exit 1; }
sleep 30 9>&-          # the child does not inherit the lock descriptor
EOF
for s in k3 k4; do
  lock="$D/$s.lock"
  bash $s.sh "$lock" & p=$!; sleep 0.5; kill -KILL "$p"; wait "$p" 2>/dev/null
  echo -n "$s: after kill -9 of the script, can I take the lock? "
  bash -c "exec 9>'$lock'; flock -n 9 && echo yes || echo no"
  pkill -f 'sleep 30' 2>/dev/null; sleep 0.3
  echo -n "    after the leftover sleep is gone: "; bash -c "exec 9>'$lock'; flock -n 9 && echo yes || echo no"
done
echo -n 'flock around a single command: '; flock -n "$D/cmd.lock" echo "ran under lock"
echo -n 'flock -w waits for the lock (timeout seconds): '; ( flock "$D/w.lock" sleep 1 & sleep 0.2; flock -w 3 "$D/w.lock" echo "got it after waiting" ); wait

echo '### D. dot (source) in dash with a path'
printf 'helper() { echo "helper called"; }\n' > plainlib.sh
echo -n 'dash . plainlib.sh   : '; dash -c '. plainlib.sh; helper' 2>&1 | head -1
echo -n 'dash . ./plainlib.sh : '; dash -c '. ./plainlib.sh; helper' 2>&1 | head -1
echo -n 'dash with PATH=.:$PATH: '; dash -c 'PATH=.:$PATH; . plainlib.sh; helper' 2>&1 | head -1
echo -n 'bash . plainlib.sh   : '; bash -c '. plainlib.sh; helper' 2>&1 | head -1
echo -n 'bash --posix . plainlib.sh: '; bash --posix -c '. plainlib.sh; helper' 2>&1 | head -1

cd / && rm -rf "$D"
