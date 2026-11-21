#!/usr/bin/env bash
# Battery 2 for the dinit lessons: reload vs unload, restart matrix, smooth-recovery, service types, dependencies.
# Run as root in the Chimera Linux lab VM (dinit 0.22.0). Test services are wl-*.
D=/etc/dinit.d
dinitctl() { timeout 20 /usr/bin/dinitctl "$@"; }
export -f dinitctl
cleanup() {
  for s in $(dinitctl list 2>/dev/null | grep -o 'wl-[A-Za-z0-9@._-]*'); do dinitctl stop --force --ignore-unstarted "$s" >/dev/null 2>&1; done
  for i in 1 2 3; do for s in $(dinitctl list 2>/dev/null | grep -o 'wl-[A-Za-z0-9@._-]*'); do dinitctl unload "$s" >/dev/null 2>&1; done; done
  rm -rf $D/wl-* $D/boot.d/wl-* /tmp/wl-*
}
trap cleanup EXIT
cleanup
sh_() { echo "\$ $1"; local out rc; out=$(bash -c "$1" 2>&1); rc=$?; [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/  /'; [ "$rc" != 0 ] && echo "  [rc=$rc]"; return 0; }
pidof_() { dinitctl status "$1" 2>/dev/null | grep "Process ID" | grep -o '[0-9]*$'; }
echo "dinit: $(dinit --version | head -1)"; id -un; echo "sleep: $(command -v sleep)"

echo '### 1. Changing a service file: reload versus unload'
cat > $D/wl-chg <<'EOF'
type = process
command = /bin/sh -c "echo v1; sleep 1000"
log-type = buffer
EOF
dinitctl start wl-chg >/dev/null; sleep 0.3
sed -i 's/v1/v2/' $D/wl-chg
sh_ 'dinitctl catlog wl-chg --clear | tail -1; dinitctl restart wl-chg >/dev/null; sleep 0.3; echo "after restart, no reload:"; dinitctl catlog wl-chg --clear | tail -1'
sh_ 'dinitctl reload wl-chg; dinitctl restart wl-chg >/dev/null; sleep 0.3; echo "after reload + restart:"; dinitctl catlog wl-chg --clear | tail -1'
sed -i 's/v2/v3/' $D/wl-chg
sh_ 'dinitctl stop wl-chg >/dev/null; dinitctl unload wl-chg; dinitctl start wl-chg >/dev/null; sleep 0.3; echo "after stop + unload + start:"; dinitctl catlog wl-chg --clear | tail -1'
sed -i 's/v3/v4/' $D/wl-chg
sh_ 'dinitctl stop wl-chg >/dev/null; dinitctl reload wl-chg; dinitctl start wl-chg >/dev/null; sleep 0.3; echo "after stop + reload + start:"; dinitctl catlog wl-chg --clear | tail -1; dinitctl stop wl-chg >/dev/null'
echo '-- a failed service: fix the program path'
cat > $D/wl-fix <<'EOF'
type = process
command = /usr/bin/slepe 1000
EOF
sh_ 'dinitctl start wl-fix 2>&1 | head -2'
sed -i 's#/usr/bin/slepe#/usr/bin/sleep#' $D/wl-fix
sh_ 'ls -l /usr/bin/sleep | cut -c1-60; dinitctl start wl-fix; echo "rc=$?"'
sh_ 'dinitctl reload wl-fix; dinitctl start wl-fix; echo "rc=$?"; dinitctl is-started wl-fix'
sh_ 'dinitctl stop wl-fix >/dev/null 2>&1; dinitctl unload wl-fix; sed -i "s#sleep 1000#sleep 1000#" /etc/dinit.d/wl-fix; dinitctl start wl-fix; echo "rc=$?"; dinitctl stop wl-fix >/dev/null'
echo '-- unload refuses while there are dependents'
cat > $D/wl-base <<'EOF'
type = internal
EOF
cat > $D/wl-top <<'EOF'
type = internal
depends-on: wl-base
EOF
dinitctl start wl-top >/dev/null
sh_ 'dinitctl stop wl-top >/dev/null; dinitctl unload wl-base; echo "rc=$?"'
sh_ 'dinitctl unload wl-top; dinitctl unload wl-base; echo "rc=$?"'

echo '### 2. Restart matrix: restart = yes / on-failure / no, for six endings'
cat > /tmp/wl-how.sh <<'EOF'
#!/bin/sh
echo started >> "$1"
sleep 0.1
case "$2" in
  exit0) exit 0 ;;
  exit1) exit 1 ;;
  term)  kill -TERM $$ ;;
  kill)  kill -KILL $$ ;;
  usr1)  kill -USR1 $$ ;;
  abrt)  kill -ABRT $$ ;;
esac
EOF
chmod +x /tmp/wl-how.sh
cols="exit0 exit1 term kill usr1 abrt"
for pol in yes on-failure no; do for c in $cols; do
cat > $D/wl-m-$pol-$c <<EOF
type = process
command = /tmp/wl-how.sh /tmp/wl-m-$pol-$c.log $c
restart = $pol
restart-delay = 0.1
restart-limit-count = 0
EOF
done; done
for pol in yes on-failure no; do for c in $cols; do dinitctl start --no-wait wl-m-$pol-$c >/dev/null 2>&1; done; done
sleep 3
printf '  %-12s' "restart ="; for c in $cols; do printf '%-12s' "$c"; done; echo
for pol in yes on-failure no; do
  printf '  %-12s' "$pol"
  for c in $cols; do
    n=$(wc -l < /tmp/wl-m-$pol-$c.log 2>/dev/null | tr -d ' ')
    [ "${n:-0}" -ge 3 ] && v=restarts || v=stays-down
    printf '%-12s' "$v"
  done; echo
done
sh_ 'for c in exit0 exit1 term kill usr1 abrt; do printf "%s: " $c; dinitctl status wl-m-no-$c | sed -n "2p" | sed "s/^ *//"; done'
for pol in yes on-failure no; do for c in $cols; do dinitctl stop --force --ignore-unstarted wl-m-$pol-$c >/dev/null 2>&1; done; done

echo '### 3. The default restart value, and a manual stop'
cat > $D/wl-default <<'EOF'
type = process
command = /bin/sh -c "echo run >> /tmp/wl-default.log; sleep 100"
EOF
rm -f /tmp/wl-default.log
sh_ 'dinitctl start wl-default >/dev/null; sleep 0.3; kill -9 $(dinitctl status wl-default | grep "Process ID" | grep -o "[0-9]*$"); sleep 2; echo "runs after a kill -9: $(wc -l < /tmp/wl-default.log | tr -d " ")"; dinitctl status wl-default | sed -n "2p"'
sh_ 'dinitctl stop wl-default; sleep 2; echo "runs after a manual stop: $(wc -l < /tmp/wl-default.log | tr -d " ")"; dinitctl is-started wl-default'

echo '### 4. smooth-recovery: dependents are not stopped when the process dies'
for sr in false true; do
cat > $D/wl-sr-$sr <<EOF
type = process
command = /bin/sleep 1000
smooth-recovery = $sr
restart-delay = 0.2
EOF
cat > $D/wl-srdep-$sr <<EOF
type = process
command = /bin/sleep 1001
depends-on: wl-sr-$sr
EOF
done
for sr in false true; do
  sh_ "dinitctl start wl-srdep-$sr >/dev/null; d1=\$(dinitctl status wl-srdep-$sr | grep 'Process ID' | grep -o '[0-9]*\$'); p1=\$(dinitctl status wl-sr-$sr | grep 'Process ID' | grep -o '[0-9]*\$'); kill -9 \$p1; sleep 1.5; d2=\$(dinitctl status wl-srdep-$sr | grep 'Process ID' | grep -o '[0-9]*\$'); p2=\$(dinitctl status wl-sr-$sr | grep 'Process ID' | grep -o '[0-9]*\$'); echo \"smooth-recovery=$sr: service pid changed: \$([ \$p1 != \$p2 ] && echo yes || echo no); dependent pid changed (it was restarted): \$([ \"\$d1\" != \"\$d2\" ] && echo yes || echo no)\"; dinitctl stop wl-srdep-$sr >/dev/null 2>&1"
done

echo '### 5. Service types'
cat > $D/wl-scr <<'EOF'
type = scripted
command = /bin/sh -c "echo start-ran >> /tmp/wl-scr.log"
stop-command = /bin/sh -c "echo stop-ran >> /tmp/wl-scr.log"
EOF
rm -f /tmp/wl-scr.log
sh_ 'dinitctl start wl-scr; dinitctl status wl-scr | sed -n "2,3p"; dinitctl stop wl-scr; cat /tmp/wl-scr.log | tr "\n" " "'
cat > $D/wl-scr-fail <<'EOF'
type = scripted
command = /bin/sh -c "exit 3"
EOF
sh_ 'dinitctl start wl-scr-fail; echo "rc=$?"; dinitctl status wl-scr-fail'
cat > /tmp/wl-daemon.sh <<'EOF'
#!/bin/sh
( sleep 1000 </dev/null >/dev/null 2>&1 & echo $! > /tmp/wl-daemon.pid )
exit 0
EOF
chmod +x /tmp/wl-daemon.sh
cat > $D/wl-bg <<'EOF'
type = bgprocess
command = /tmp/wl-daemon.sh
pid-file = /tmp/wl-daemon.pid
EOF
sh_ 'dinitctl start wl-bg; dinitctl status wl-bg | sed "s/Process ID: [0-9]*/Process ID: <pid>/"; test "$(cat /tmp/wl-daemon.pid)" = "$(dinitctl status wl-bg | grep "Process ID" | grep -o "[0-9]*\$")" && echo "dinit supervises the PID from the pid-file"; dinitctl stop wl-bg; sleep 0.3; kill -0 $(cat /tmp/wl-daemon.pid) 2>&1 | head -1'
cat > $D/wl-int <<'EOF'
type = internal
depends-on: wl-int-dep
EOF
cat > $D/wl-int-dep <<'EOF'
type = process
command = /bin/sleep 1000
EOF
sh_ 'dinitctl start wl-int; dinitctl status wl-int | sed -n "2,3p"; dinitctl list | grep "wl-int" | sed "s/pid: [0-9]*/pid: <pid>/"; dinitctl stop wl-int; dinitctl list | grep "wl-int"'
cat > $D/wl-trig <<'EOF'
type = triggered
EOF
sh_ 'timeout 4 dinitctl start wl-trig; echo "start rc=$? (124 = still waiting)"; dinitctl status wl-trig | sed -n "2p"'
sh_ 'dinitctl trigger wl-trig; sleep 0.3; dinitctl status wl-trig | sed -n "2p"; dinitctl stop wl-trig >/dev/null'
sh_ 'dinitctl --no-wait start wl-trig; dinitctl status wl-trig | sed -n "2p"; dinitctl untrigger wl-trig; dinitctl stop wl-trig >/dev/null 2>&1'

echo '### 6. Dependencies'
cat > $D/wl-db <<'EOF'
type = process
command = /bin/sleep 1000
EOF
cat > $D/wl-need <<'EOF'
type = process
command = /bin/sleep 1001
depends-on: wl-db
EOF
cat > $D/wl-ms <<'EOF'
type = process
command = /bin/sleep 1002
depends-ms: wl-db
EOF
cat > $D/wl-waits <<'EOF'
type = process
command = /bin/sleep 1003
waits-for: wl-db
EOF
st() { for s in "$@"; do printf '%s=%s ' "${s#wl-}" "$(dinitctl is-started $s 2>&1 | head -1)"; done; echo; }
export -f st
echo '-- starting a dependent starts the dependency'
sh_ 'dinitctl start wl-need >/dev/null; st wl-db wl-need; dinitctl status wl-db | sed -n "3p"'
echo '-- stopping the dependency: refused while a hard dependent runs'
sh_ 'dinitctl stop wl-db; echo "rc=$?"; st wl-db wl-need'
sh_ 'dinitctl stop --force wl-db; echo "rc=$?"; st wl-db wl-need'
echo '-- stopping the dependent stops a dependency nobody else activated'
sh_ 'dinitctl start wl-need >/dev/null; dinitctl stop wl-need >/dev/null; st wl-db wl-need'
echo '-- but an explicitly started dependency stays up'
sh_ 'dinitctl start wl-db >/dev/null; dinitctl start wl-need >/dev/null; dinitctl stop wl-need >/dev/null; st wl-db wl-need; dinitctl stop wl-db >/dev/null'
echo '-- milestone and waits-for: stopping the dependency afterwards has no effect on the dependent'
sh_ 'dinitctl start wl-ms >/dev/null; dinitctl start wl-waits >/dev/null; st wl-db wl-ms wl-waits; dinitctl stop --force wl-db >/dev/null 2>&1; st wl-db wl-ms wl-waits'
sh_ 'dinitctl stop wl-ms wl-waits >/dev/null 2>&1; dinitctl stop --ignore-unstarted wl-db >/dev/null 2>&1; st wl-db'
echo '-- a dependency that FAILS to start'
cat > $D/wl-dbbad <<'EOF'
type = process
command = /usr/bin/slepe
EOF
for t in need:depends-on ms:depends-ms waits:waits-for; do n=${t%%:*}; k=${t#*:}
cat > $D/wl-x$n <<EOF
type = process
command = /bin/sleep 1004
$k: wl-dbbad
EOF
done
sh_ 'dinitctl start wl-xneed; echo "depends-on rc=$?"; dinitctl is-started wl-xneed'
sh_ 'dinitctl start wl-xms; echo "depends-ms rc=$?"; dinitctl is-started wl-xms'
sh_ 'dinitctl start wl-xwaits; echo "waits-for rc=$?"; dinitctl is-started wl-xwaits; dinitctl stop wl-xwaits >/dev/null'
echo '-- the dependent of a failed dependency in dinitctl list'
sh_ 'dinitctl list | grep -E "wl-x|wl-dbbad"'
echo '-- ordering with after/before (no dependency implied)'
for n in 1 2 3; do
cat > $D/wl-o$n <<EOF
type = scripted
command = /bin/sh -c "echo o$n-start >> /tmp/wl-order; sleep 0.6; echo o$n-end >> /tmp/wl-order"
EOF
done
printf 'after: wl-o1\n' >> $D/wl-o2
printf 'after: wl-o2\n' >> $D/wl-o3
cat > $D/wl-otop <<'EOF'
type = internal
waits-for: wl-o3
waits-for: wl-o2
waits-for: wl-o1
EOF
rm -f /tmp/wl-order
sh_ 'dinitctl start wl-otop; cat /tmp/wl-order | tr "\n" " "'
dinitctl stop wl-otop >/dev/null 2>&1
rm -f /tmp/wl-order
for n in 1 2 3; do sed -i '/^after:/d' $D/wl-o$n; done
dinitctl unload wl-o1 >/dev/null 2>&1; dinitctl unload wl-o2 >/dev/null 2>&1; dinitctl unload wl-o3 >/dev/null 2>&1; dinitctl unload wl-otop >/dev/null 2>&1
sh_ 'dinitctl start wl-otop; sleep 0.3; echo "without after:"; cat /tmp/wl-order | tr "\n" " "'
dinitctl stop wl-otop >/dev/null 2>&1
echo '-- wake, release, pin'
sh_ 'dinitctl wake wl-db; dinitctl status wl-db | sed -n "3p"; dinitctl release wl-db; st wl-db'
sh_ 'dinitctl start wl-db >/dev/null; dinitctl release wl-db; st wl-db; dinitctl status wl-db | sed -n "3p"'
sh_ 'dinitctl start --pin wl-db >/dev/null; dinitctl stop wl-db; echo "rc=$?"; st wl-db; dinitctl unpin wl-db; dinitctl stop wl-db >/dev/null; st wl-db'
echo '-- add-dep and rm-dep at run time (not persistent)'
cat > $D/wl-solo <<'EOF'
type = process
command = /bin/sleep 1005
EOF
sh_ 'dinitctl start wl-db >/dev/null; dinitctl start wl-solo >/dev/null; dinitctl add-dep need wl-solo wl-db; echo "rc=$?"; dinitctl stop wl-db; echo "stop rc=$?"; dinitctl rm-dep need wl-solo wl-db; echo "rm rc=$?"; dinitctl stop wl-db; st wl-db wl-solo'
sh_ 'dinitctl stop wl-solo >/dev/null 2>&1; dinitctl add-dep need wl-solo wl-db; echo "add-dep to a stopped dependency rc=$?"'
echo '### done'
