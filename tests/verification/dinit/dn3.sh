#!/usr/bin/env bash
# Battery 3 for the dinit lessons: redo of reload/unload and ordering (files rewritten with cat: BSD sed -i does not work like GNU),
# release, templates, variables, logging, stopping, options, readiness, chain-to. Run as root in the Chimera VM (dinit 0.22.0).
D=/etc/dinit.d
dinitctl() { timeout 20 /usr/bin/dinitctl "$@"; }
export -f dinitctl
cleanup() {
  for s in $(dinitctl list 2>/dev/null | grep -o 'wl-[A-Za-z0-9@._-]*'); do dinitctl stop --force --ignore-unstarted "$s" >/dev/null 2>&1; done
  for i in 1 2 3; do for s in $(dinitctl list 2>/dev/null | grep -o 'wl-[A-Za-z0-9@._-]*'); do dinitctl unload "$s" >/dev/null 2>&1; done; done
  rm -rf $D/wl-* $D/boot.d/wl-* /tmp/wl-* /var/log/wl-*
}
trap cleanup EXIT
cleanup
sh_() { echo "\$ $1"; local out rc; out=$(bash -c "$1" 2>&1); rc=$?; [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/  /'; [ "$rc" != 0 ] && echo "  [rc=$rc]"; return 0; }
echo "dinit: $(dinit --version | head -1)"; id -un

echo '### 1. Changing a service file (files rewritten with cat)'
mk() { printf 'type = process\ncommand = /bin/sh -c "echo %s; sleep 1000"\nlog-type = buffer\n' "$1" > $D/wl-chg; }
mk v1; dinitctl start wl-chg >/dev/null; sleep 0.3; dinitctl catlog wl-chg --clear >/dev/null
mk v2
sh_ 'dinitctl restart wl-chg >/dev/null 2>&1; sleep 0.3; echo "file says v2; restart only:"; dinitctl catlog wl-chg --clear | tail -1'
mk v3
sh_ 'dinitctl reload wl-chg; dinitctl restart wl-chg >/dev/null 2>&1; sleep 0.3; echo "file says v3; reload then restart:"; dinitctl catlog wl-chg --clear | tail -1'
mk v4
sh_ 'dinitctl stop wl-chg >/dev/null; dinitctl unload wl-chg; dinitctl start wl-chg >/dev/null; sleep 0.3; echo "file says v4; stop, unload, start:"; dinitctl catlog wl-chg --clear | tail -1; dinitctl stop wl-chg >/dev/null'
mk v5
sh_ 'dinitctl reload wl-chg; dinitctl start wl-chg >/dev/null; sleep 0.3; echo "file says v5; (stopped) reload then start:"; dinitctl catlog wl-chg --clear | tail -1; dinitctl stop wl-chg >/dev/null'
mk v6
sh_ 'dinitctl start wl-chg >/dev/null; sleep 0.3; dinitctl status wl-chg | sed -n "2p"; dinitctl catlog wl-chg --clear | tail -1; echo "start on an already-loaded stopped service reads the file again? ->"'
echo '-- start of a stopped service whose file changed: is there a warning?'
mk v7
sh_ 'dinitctl stop wl-chg >/dev/null; dinitctl start wl-chg 2>&1; sleep 0.3; dinitctl catlog wl-chg --clear | tail -1; dinitctl stop wl-chg >/dev/null'
echo '-- a failed service: fix the program path (file rewritten)'
printf 'type = process\ncommand = /usr/bin/slepe 1000\n' > $D/wl-fix
sh_ 'dinitctl start wl-fix 2>&1 | head -1'
printf 'type = process\ncommand = /usr/bin/sleep 1000\n' > $D/wl-fix
sh_ 'dinitctl start wl-fix 2>&1; echo "start without reload: rc=$?"; dinitctl is-started wl-fix; dinitctl stop wl-fix >/dev/null 2>&1'
sh_ 'dinitctl reload wl-fix; dinitctl start wl-fix 2>&1; echo "after reload: rc=$?"; dinitctl is-started wl-fix; dinitctl stop wl-fix >/dev/null 2>&1'
printf 'type = process\ncommand = /usr/bin/slepe 1000\n' > $D/wl-fix2
dinitctl start wl-fix2 >/dev/null 2>&1
printf 'type = process\ncommand = /usr/bin/sleep 1000\n' > $D/wl-fix2
sh_ 'dinitctl unload wl-fix2; dinitctl start wl-fix2 2>&1; echo "after unload: rc=$?"; dinitctl stop wl-fix2 >/dev/null 2>&1'
echo '-- changing the TYPE of a loaded service'
printf 'type = process\ncommand = /bin/sleep 1000\n' > $D/wl-ty
dinitctl start wl-ty >/dev/null
printf 'type = scripted\ncommand = /bin/true\n' > $D/wl-ty
sh_ 'dinitctl reload wl-ty; echo "rc=$?"'

echo '### 2. release, wake and explicit activation with a pristine service'
printf 'type = process\ncommand = /bin/sleep 1000\n' > $D/wl-act
sh_ 'dinitctl start wl-act >/dev/null; dinitctl status wl-act | sed -n "3p"; dinitctl release wl-act; sleep 0.5; dinitctl is-started wl-act | head -1; dinitctl status wl-act | sed -n "2,3p"'
sh_ 'dinitctl wake wl-act; sleep 0.5; dinitctl is-started wl-act | head -1; dinitctl status wl-act | sed -n "2,3p"'
printf 'type = process\ncommand = /bin/sleep 1001\ndepends-on: wl-act\n' > $D/wl-actdep
sh_ 'dinitctl stop --force wl-act >/dev/null 2>&1; dinitctl start wl-actdep >/dev/null; dinitctl status wl-act | sed -n "3p"; dinitctl stop wl-actdep >/dev/null; dinitctl is-started wl-act | head -1'
sh_ 'dinitctl start wl-act >/dev/null; dinitctl start wl-actdep >/dev/null; dinitctl release wl-act; sleep 0.5; dinitctl is-started wl-act | head -1; dinitctl stop wl-actdep >/dev/null; sleep 0.5; dinitctl is-started wl-act | head -1'

echo '### 3. Ordering with after: (files written with cat)'
for n in 1 2 3; do printf 'type = scripted\ncommand = /bin/sh -c "echo o%s-start >> /tmp/wl-order; sleep 0.6; echo o%s-end >> /tmp/wl-order"\n' $n $n > $D/wl-o$n; done
printf 'type = internal\nwaits-for: wl-o1\nwaits-for: wl-o2\nwaits-for: wl-o3\n' > $D/wl-otop
rm -f /tmp/wl-order
sh_ 'dinitctl start wl-otop >/dev/null; cat /tmp/wl-order | tr "\n" " "; dinitctl stop wl-otop >/dev/null'
for s in wl-o1 wl-o2 wl-o3 wl-otop; do dinitctl unload $s >/dev/null 2>&1; done
for n in 1 2 3; do printf 'type = scripted\ncommand = /bin/sh -c "echo o%s-start >> /tmp/wl-order; sleep 0.6; echo o%s-end >> /tmp/wl-order"\n' $n $n > $D/wl-o$n; done
printf 'after: wl-o1\n' >> $D/wl-o2
printf 'after: wl-o2\n' >> $D/wl-o3
rm -f /tmp/wl-order
sh_ 'dinitctl start wl-otop >/dev/null; cat /tmp/wl-order | tr "\n" " "; dinitctl stop wl-otop >/dev/null'
echo '-- after: on a service that is NOT being started adds no dependency'
printf 'type = process\ncommand = /bin/sleep 1000\nafter: wl-o1\n' > $D/wl-aft
sh_ 'dinitctl start wl-aft; dinitctl list | grep -c "wl-o1"; dinitctl is-started wl-o1 | head -1; dinitctl stop wl-aft >/dev/null'
echo '-- before: the same ordering from the other side'
for s in wl-o1 wl-o2 wl-o3 wl-otop; do dinitctl unload $s >/dev/null 2>&1; done
for n in 1 2 3; do printf 'type = scripted\ncommand = /bin/sh -c "echo o%s-start >> /tmp/wl-order; sleep 0.6; echo o%s-end >> /tmp/wl-order"\n' $n $n > $D/wl-o$n; done
printf 'before: wl-o1\n' >> $D/wl-o3
printf 'before: wl-o3\n' >> $D/wl-o2
rm -f /tmp/wl-order
sh_ 'dinitctl start wl-otop >/dev/null; cat /tmp/wl-order | tr "\n" " "; dinitctl stop wl-otop >/dev/null'

echo '### 4. Service templates and variable substitution'
printf 'type = process\ncommand = /bin/sh -c "echo instance=$1 name=\\"$1\\" >> /tmp/wl-tpl.log; sleep 1000"\n' > $D/wl-tpl@
cat $D/wl-tpl@
rm -f /tmp/wl-tpl.log
sh_ 'dinitctl start wl-tpl@alpha; dinitctl start wl-tpl@beta; sleep 0.3; sort /tmp/wl-tpl.log; dinitctl list | grep "wl-tpl" | sed "s/pid: [0-9]*/pid: <pid>/"'
sh_ 'dinitctl start wl-tpl 2>&1 | head -2'
cat > /tmp/wl-envf <<'EOF'
GREETING=hello
NAME=from-file
EOF
cat > $D/wl-var <<'EOF'
type = scripted
env-file = /tmp/wl-envf
command = /bin/echo plain $GREETING braced ${GREETING} default ${UNSETVAR:-fallback} other ${NAME:+set} literal $$HOME word[$GREETING] "quoted $GREETING"
log-type = buffer
EOF
sh_ 'dinitctl start wl-var; dinitctl catlog wl-var'
cat > $D/wl-split <<'EOF'
type = scripted
env-file = /tmp/wl-envf
command = /bin/echo $/GREETING_LIST|$GREETING_LIST|
log-type = buffer
EOF
printf 'GREETING_LIST=a b  c\n' > /tmp/wl-envf2
cat > $D/wl-split <<'EOF'
type = scripted
env-file = /tmp/wl-envf2
command = /bin/sh -c "printf '[%s]' $/GREETING_LIST; echo; printf '[%s]' $GREETING_LIST; echo"
log-type = buffer
EOF
sh_ 'dinitctl start wl-split; dinitctl catlog wl-split'
printf 'type = scripted\ncommand = /bin/sh -c "echo SETVAR=$SETVAR_X"\nlog-type = buffer\n' > $D/wl-senv
sh_ 'dinitctl setenv SETVAR_X=before; dinitctl start wl-senv >/dev/null; dinitctl catlog wl-senv --clear; dinitctl setenv SETVAR_X=after; dinitctl stop wl-senv >/dev/null; dinitctl start wl-senv >/dev/null; dinitctl catlog wl-senv --clear; dinitctl unsetenv SETVAR_X'
printf 'type = scripted\ncommand = /bin/echo cmd=$SETVAR_Y\nlog-type = buffer\n' > $D/wl-senv2
sh_ 'dinitctl setenv SETVAR_Y=one; dinitctl start wl-senv2 >/dev/null; dinitctl catlog wl-senv2 --clear; dinitctl setenv SETVAR_Y=two; dinitctl stop wl-senv2 >/dev/null; dinitctl start wl-senv2 >/dev/null; dinitctl catlog wl-senv2 --clear; dinitctl unsetenv SETVAR_Y'

echo '### 5. Logging'
printf 'type = process\ncommand = /bin/sh -c "echo to-logfile; echo to-stderr >&2; sleep 1000"\nlogfile = /var/log/wl-log.txt\n' > $D/wl-lf
sh_ 'dinitctl start wl-lf >/dev/null; sleep 0.3; cat /var/log/wl-log.txt; ls -l /var/log/wl-log.txt | cut -c1-10; dinitctl stop wl-lf >/dev/null; dinitctl start wl-lf >/dev/null; sleep 0.3; wc -l < /var/log/wl-log.txt | tr -d " "; dinitctl stop wl-lf >/dev/null'
printf 'type = process\ncommand = /bin/sh -c "echo to-logfile; sleep 1000"\nlogfile = /var/log/wl-log2.txt\nlogfile-permissions = 640\nlogfile-uid = nobody\n' > $D/wl-lf2
sh_ 'dinitctl start wl-lf2 >/dev/null; sleep 0.3; ls -l /var/log/wl-log2.txt | cut -c1-30; dinitctl stop wl-lf2 >/dev/null'
printf 'type = process\ncommand = /bin/sh -c "echo to-logfile; sleep 1000"\nlogfile = /var/log/wl-nodir/log.txt\n' > $D/wl-lf3
sh_ 'dinitctl start wl-lf3; echo "rc=$?"; dinitctl status wl-lf3 | tail -2'
printf 'type = process\ncommand = /bin/sh -c "i=0; while [ $i -lt 200 ]; do echo line-$i; i=$((i+1)); done; sleep 1000"\nlog-type = buffer\nlog-buffer-size = 100\n' > $D/wl-buf
sh_ 'dinitctl start wl-buf >/dev/null; sleep 0.5; dinitctl catlog wl-buf | wc -c | tr -d " "; dinitctl catlog wl-buf | tail -3; dinitctl catlog --clear wl-buf >/dev/null; dinitctl catlog wl-buf | wc -c | tr -d " "; dinitctl stop wl-buf >/dev/null'
printf 'type = process\ncommand = /bin/sh -c "echo discarded; sleep 1000"\nlog-type = none\n' > $D/wl-none
sh_ 'dinitctl start wl-none >/dev/null; sleep 0.3; dinitctl catlog wl-none 2>&1 | head -2; dinitctl stop wl-none >/dev/null'
echo '-- pipe and consumer-of: one service logs for another'
printf 'type = process\ncommand = /bin/sh -c "echo producer-line-1; sleep 0.3; echo producer-line-2; sleep 1000"\nlog-type = pipe\n' > $D/wl-prod
printf 'type = process\ncommand = /bin/sh -c "while read l; do echo consumed:$l >> /tmp/wl-consumed; done"\nconsumer-of = wl-prod\n' > $D/wl-cons
rm -f /tmp/wl-consumed
sh_ 'dinitctl start wl-cons >/dev/null; dinitctl start wl-prod >/dev/null; sleep 1; cat /tmp/wl-consumed; dinitctl stop wl-prod >/dev/null; dinitctl stop wl-cons >/dev/null 2>&1'

echo '### 6. Stopping: stop-timeout, term-signal, stop-command, signal'
cat > /tmp/wl-stubborn.sh <<'EOF'
#!/bin/sh
trap '' TERM
echo "stubborn up"
while :; do sleep 1; done
EOF
chmod +x /tmp/wl-stubborn.sh
printf 'type = process\ncommand = /tmp/wl-stubborn.sh\nstop-timeout = 3\nlog-type = buffer\n' > $D/wl-stub
sh_ 'dinitctl start wl-stub >/dev/null; sleep 0.4; s=$(date +%s); dinitctl stop wl-stub; e=$(date +%s); echo "stop took $((e-s)) s"; dinitctl status wl-stub | sed -n "2p"'
sh_ 'dinitctl start wl-stub >/dev/null; sleep 0.3; s=$(date +%s); dinitctl stop wl-stub 2>&1 | head -2; e=$(date +%s); echo "took $((e-s)) s"'
cat > /tmp/wl-hup.sh <<'EOF'
#!/bin/sh
trap 'echo got-HUP' HUP
trap 'echo got-TERM; exit 0' TERM
trap 'echo got-USR1' USR1
echo up
while :; do sleep 0.2; done
EOF
chmod +x /tmp/wl-hup.sh
printf 'type = process\ncommand = /tmp/wl-hup.sh\nlog-type = buffer\nterm-signal = HUP\n' > $D/wl-sig
sh_ 'dinitctl start wl-sig >/dev/null; sleep 0.4; dinitctl signal USR1 wl-sig; dinitctl signal HUP wl-sig; sleep 0.5; dinitctl catlog wl-sig --clear | tr "\n" " "'
sh_ 'dinitctl signal --list | tr "\n" " " | cut -c1-200'
sh_ 'dinitctl signal NOSUCH wl-sig 2>&1 | head -2'
printf 'type = process\ncommand = /tmp/wl-hup.sh\nlog-type = buffer\nstop-command = /bin/sh -c "echo stop-command-ran >> /tmp/wl-stopcmd; kill -TERM $(cat /tmp/wl-pid)"\n' > $D/wl-sc
sh_ 'dinitctl stop wl-sig >/dev/null; sleep 0.3; dinitctl catlog wl-sig --clear | tr "\n" " "'
echo '-- term-signal = none and the signal that was sent (HUP made the script exit above because it handled HUP only by printing; see output)'

echo '### 7. Options and limits'
cat > /tmp/wl-info.sh <<'EOF'
#!/bin/sh
echo "user=$(id -un) uid=$(id -u) cwd=$(pwd)"
echo "nofile=$(ulimit -n) nice=$(nice) "
grep -E "^(NoNewPrivs|CapEff|CapBnd)" /proc/self/status | tr '\n' ' '; echo
echo "oom_score_adj=$(cat /proc/self/oom_score_adj)"
EOF
chmod +x /tmp/wl-info.sh
printf 'type = scripted\ncommand = /tmp/wl-info.sh\nlog-type = buffer\n' > $D/wl-opt0
printf 'type = scripted\ncommand = /tmp/wl-info.sh\nlog-type = buffer\nrun-as = nobody\nworking-dir = /var/tmp\nrlimit-nofile = 256:512\nnice = 10\noom-score-adj = 300\noptions: no-new-privs\n' > $D/wl-opt1
sh_ 'dinitctl start wl-opt0 >/dev/null; dinitctl catlog wl-opt0'
sh_ 'dinitctl start wl-opt1 2>&1 | head -3; dinitctl catlog wl-opt1'
printf 'type = scripted\ncommand = /tmp/wl-info.sh\nlog-type = buffer\nrun-as = nobody\ncapabilities = ^CAP_NET_BIND_SERVICE\n' > $D/wl-cap
sh_ 'dinitctl start wl-cap 2>&1 | head -3; dinitctl catlog wl-cap | tail -3'
printf 'type = scripted\ncommand = /bin/true\nrun-as = no-such-user\n' > $D/wl-nouser
sh_ 'dinitctl start wl-nouser 2>&1 | head -4'
printf 'type = process\ncommand = /tmp/does-not-exist.sh\nworking-dir = /nonexistent\n' > $D/wl-nowd
sh_ 'dinitctl start wl-nowd 2>&1 | head -5'

echo '### 8. Readiness, timeouts, chain-to, include'
cat > /tmp/wl-ready.sh <<'EOF'
#!/bin/sh
sleep 2
echo ready >&3
sleep 1000
EOF
chmod +x /tmp/wl-ready.sh
printf 'type = process\ncommand = /tmp/wl-ready.sh\nready-notification = pipefd:3\n' > $D/wl-rdy
printf 'type = process\ncommand = /tmp/wl-ready.sh\n' > $D/wl-nordy
sh_ 's=$(date +%s.%N); dinitctl start wl-rdy >/dev/null; e=$(date +%s.%N); printf "with ready-notification: start took %.1f s\n" $(echo "$e - $s" | bc -l 2>/dev/null || echo 0); dinitctl stop wl-rdy >/dev/null'
sh_ 's=$(date +%s); dinitctl start wl-nordy >/dev/null; e=$(date +%s); echo "no ready-notification: start took $((e-s)) s"; dinitctl stop wl-nordy >/dev/null'
printf 'type = process\ncommand = /tmp/wl-ready.sh\nready-notification = pipefd:3\nstart-timeout = 1\n' > $D/wl-slow
sh_ 'dinitctl start wl-slow 2>&1 | head -3; dinitctl status wl-slow | sed -n "2,4p"'
printf 'type = scripted\ncommand = /bin/sh -c "echo first >> /tmp/wl-chain"\nchain-to = wl-chained\n' > $D/wl-ch1
printf 'type = process\ncommand = /bin/sh -c "echo second >> /tmp/wl-chain; sleep 1000"\n' > $D/wl-chained
rm -f /tmp/wl-chain
sh_ 'dinitctl start wl-ch1 >/dev/null 2>&1; sleep 1; cat /tmp/wl-chain | tr "\n" " "; dinitctl list | grep -E "wl-ch1|wl-chained" | sed "s/pid: [0-9]*/pid: <pid>/"'
printf 'common-setting\n' > /dev/null
printf 'restart = false\nrestart-delay = 0.1\n' > /tmp/wl-common.inc
printf 'type = process\ncommand = /bin/sh -c "exit 1"\n@include /tmp/wl-common.inc\n' > $D/wl-inc
sh_ 'dinitctl start wl-inc >/dev/null 2>&1; sleep 0.8; dinitctl status wl-inc | sed -n "2p"; dinit-check wl-inc 2>&1 | tail -2'
echo '### done'
