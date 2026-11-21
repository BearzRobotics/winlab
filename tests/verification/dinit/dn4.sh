#!/usr/bin/env bash
# Battery 4 for the dinit lessons: redone tests (ordering, templates, splitting, runtime env, buffer size, consumer-of, chain-to, include)
# and where dinit logs. Run as root in the Chimera VM (dinit 0.22.0).
D=/etc/dinit.d
dinitctl() { timeout 20 /usr/bin/dinitctl "$@"; }
export -f dinitctl
unload_all() { for i in 1 2 3 4; do for s in $(dinitctl list 2>/dev/null | grep -o 'wl-[A-Za-z0-9@._-]*' | sort -r); do dinitctl unload "$s" >/dev/null 2>&1; done; done; }
cleanup() {
  for s in $(dinitctl list 2>/dev/null | grep -o 'wl-[A-Za-z0-9@._-]*'); do dinitctl stop --force --ignore-unstarted "$s" >/dev/null 2>&1; done
  unload_all
  rm -rf $D/wl-* $D/boot.d/wl-* /tmp/wl-* /var/log/wl-*
}
trap cleanup EXIT
cleanup
sh_() { echo "\$ $1"; local out rc; out=$(bash -c "$1" 2>&1); rc=$?; [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/  /'; [ "$rc" != 0 ] && echo "  [rc=$rc]"; return 0; }
echo "dinit: $(dinit --version | head -1)"; id -un

echo '### 1. Ordering with after: and before: (unload dependents first)'
mko() { for n in 1 2 3; do printf 'type = scripted\ncommand = /bin/sh -c "echo o%s-start >> /tmp/wl-order; sleep 0.6; echo o%s-end >> /tmp/wl-order"\n' $n $n > $D/wl-o$n; done
        printf 'type = internal\nwaits-for: wl-o1\nwaits-for: wl-o2\nwaits-for: wl-o3\n' > $D/wl-otop; }
run() { rm -f /tmp/wl-order; dinitctl start wl-otop >/dev/null 2>&1; cat /tmp/wl-order | tr '\n' ' '; echo; dinitctl stop wl-otop >/dev/null 2>&1; }
mko; echo "no ordering:       $(run)"
dinitctl unload wl-otop >/dev/null; for n in 1 2 3; do dinitctl unload wl-o$n >/dev/null; done
mko; printf 'after: wl-o1\n' >> $D/wl-o2; printf 'after: wl-o2\n' >> $D/wl-o3
echo "after (o2 after o1, o3 after o2): $(run)"
dinitctl unload wl-otop >/dev/null; for n in 1 2 3; do dinitctl unload wl-o$n >/dev/null; done
mko; printf 'before: wl-o1\n' >> $D/wl-o3; printf 'before: wl-o3\n' >> $D/wl-o2
echo "before (o2 before o3 before o1):  $(run)"
dinitctl unload wl-otop >/dev/null; for n in 1 2 3; do dinitctl unload wl-o$n >/dev/null; done

echo '### 2. Templates (file named without the @argument)'
printf 'type = process\ncommand = /bin/sh -c "echo instance=$1 >> /tmp/wl-tpl.log; sleep 1000"\n' > $D/wl-tpl
rm -f /tmp/wl-tpl.log
sh_ 'dinitctl start wl-tpl@alpha; dinitctl start wl-tpl@beta; sleep 0.3; sort /tmp/wl-tpl.log; dinitctl list | grep "wl-tpl" | sed "s/pid: [0-9]*/pid: <pid>/"'
sh_ 'dinitctl start wl-tpl 2>&1 | head -2; dinitctl list | grep -c "wl-tpl "; dinitctl stop wl-tpl@alpha wl-tpl@beta >/dev/null 2>&1'
printf 'type = process\ncommand = /bin/sleep ${1:-100}\nlogfile = /var/log/wl-tplb.log\n' > $D/wl-tplb
sh_ 'dinitctl start wl-tplb >/dev/null; dinitctl start wl-tplb@7 >/dev/null; dinitctl list | grep wl-tplb | sed "s/pid: [0-9]*/pid: <pid>/"; ps -eo args | grep "[s]leep 100$\|[s]leep 7$" | tr "\n" ";"; dinitctl stop wl-tplb wl-tplb@7 >/dev/null 2>&1'
sh_ 'dinitctl enable wl-tpl@gamma 2>&1 | head -3; ls -l /etc/dinit.d/boot.d | grep wl- | sed "s/.* wl-/wl-/"; dinitctl disable wl-tpl@gamma >/dev/null 2>&1'

echo '### 3. $/VAR splits a value into arguments; $VAR keeps it as one'
printf 'LIST=a b  c\n' > /tmp/wl-envlist
printf 'type = scripted\nenv-file = /tmp/wl-envlist\ncommand = /usr/bin/printf [%%s] $LIST\nlog-type = buffer\n' > $D/wl-one
printf 'type = scripted\nenv-file = /tmp/wl-envlist\ncommand = /usr/bin/printf [%%s] $/LIST\nlog-type = buffer\n' > $D/wl-many
sh_ 'dinitctl start wl-one >/dev/null; dinitctl catlog wl-one | tr -d "\n"; echo; dinitctl start wl-many >/dev/null; dinitctl catlog wl-many | tr -d "\n"; echo'
sh_ 'cat /etc/dinit.d/wl-many | sed -n "3p"'

echo '### 4. setenv and the activation environment (a script reads the real environment)'
printf '#!/bin/sh\necho "SETVAR_Z=$SETVAR_Z"\n' > /tmp/wl-printenv.sh; chmod +x /tmp/wl-printenv.sh
printf 'type = scripted\ncommand = /tmp/wl-printenv.sh\nlog-type = buffer\n' > $D/wl-penv
sh_ 'dinitctl setenv SETVAR_Z=first; dinitctl start wl-penv >/dev/null; dinitctl catlog wl-penv --clear; dinitctl setenv SETVAR_Z=second; dinitctl stop wl-penv >/dev/null; dinitctl start wl-penv >/dev/null; dinitctl catlog wl-penv --clear; dinitctl unsetenv SETVAR_Z; dinitctl stop wl-penv >/dev/null; dinitctl start wl-penv >/dev/null; dinitctl catlog wl-penv --clear; dinitctl stop wl-penv >/dev/null'
echo '-- substitution happens ONCE, when the service is loaded'
printf 'type = scripted\ncommand = /bin/echo substituted:$SETVAR_W\nlog-type = buffer\n' > $D/wl-sub
sh_ 'dinitctl setenv SETVAR_W=one; dinitctl start wl-sub >/dev/null; dinitctl catlog wl-sub --clear; dinitctl setenv SETVAR_W=two; dinitctl stop wl-sub >/dev/null; dinitctl start wl-sub >/dev/null; dinitctl catlog wl-sub --clear; dinitctl stop wl-sub >/dev/null; dinitctl unload wl-sub; dinitctl start wl-sub >/dev/null; dinitctl catlog wl-sub --clear; dinitctl unsetenv SETVAR_W'

echo '### 5. log-buffer-size and consumer-of (scripts in files, so $ is not substituted)'
cat > /tmp/wl-many.sh <<'EOF'
#!/bin/sh
i=0
while [ $i -lt 200 ]; do echo "line-$i"; i=$((i+1)); done
sleep 1000
EOF
chmod +x /tmp/wl-many.sh
printf 'type = process\ncommand = /tmp/wl-many.sh\nlog-type = buffer\nlog-buffer-size = 100\n' > $D/wl-buf
sh_ 'dinitctl start wl-buf >/dev/null; sleep 0.5; dinitctl catlog wl-buf | wc -c | tr -d " "; dinitctl catlog wl-buf | head -2; dinitctl catlog wl-buf --clear >/dev/null; dinitctl catlog wl-buf | wc -c | tr -d " "; dinitctl stop wl-buf >/dev/null'
printf 'type = process\ncommand = /tmp/wl-many.sh\nlog-type = buffer\n' > $D/wl-buf2
sh_ 'dinitctl start wl-buf2 >/dev/null; sleep 0.5; dinitctl catlog wl-buf2 | wc -l | tr -d " "; dinitctl catlog wl-buf2 | head -1; dinitctl stop wl-buf2 >/dev/null'
cat > /tmp/wl-prod.sh <<'EOF'
#!/bin/sh
echo producer-line-1
sleep 0.3
echo producer-line-2
sleep 1000
EOF
cat > /tmp/wl-cons.sh <<'EOF'
#!/bin/sh
while read l; do echo "consumed:$l" >> /tmp/wl-consumed; done
EOF
chmod +x /tmp/wl-prod.sh /tmp/wl-cons.sh
printf 'type = process\ncommand = /tmp/wl-prod.sh\nlog-type = pipe\n' > $D/wl-prod
printf 'type = process\ncommand = /tmp/wl-cons.sh\nconsumer-of = wl-prod\n' > $D/wl-cons
rm -f /tmp/wl-consumed
sh_ 'dinitctl start wl-cons >/dev/null; dinitctl start wl-prod >/dev/null; sleep 1; cat /tmp/wl-consumed; dinitctl stop wl-prod >/dev/null; dinitctl stop wl-cons >/dev/null 2>&1'

echo '### 6. chain-to and @include'
printf 'type = process\ncommand = /bin/sh -c "echo first >> /tmp/wl-chain"\nrestart = false\nchain-to = wl-chained\n' > $D/wl-ch1
printf 'type = process\ncommand = /bin/sh -c "echo second >> /tmp/wl-chain; sleep 1000"\n' > $D/wl-chained
rm -f /tmp/wl-chain
sh_ 'dinitctl start wl-ch1 >/dev/null 2>&1; sleep 1.2; cat /tmp/wl-chain | tr "\n" " "; dinitctl list | grep -E "wl-ch1|wl-chained" | sed "s/pid: [0-9]*/pid: <pid>/"'
printf 'type = scripted\ncommand = /bin/sh -c "echo first >> /tmp/wl-chain2"\nchain-to = wl-chained2\n' > $D/wl-chs
printf 'type = process\ncommand = /bin/sh -c "sleep 1000"\n' > $D/wl-chained2
rm -f /tmp/wl-chain2
sh_ 'dinitctl start wl-chs >/dev/null 2>&1; sleep 1; cat /tmp/wl-chain2 | tr "\n" " "; dinitctl list | grep -E "wl-chs|wl-chained2" | sed "s/pid: [0-9]*/pid: <pid>/"'
printf 'restart = false\n' > /tmp/wl-common.inc
printf 'type = process\ncommand = /bin/sh -c "echo run >> /tmp/wl-inc.log; sleep 0.1; exit 1"\nrestart-delay = 0.1\nrestart-limit-count = 0\n@include /tmp/wl-common.inc\n' > $D/wl-inc
printf 'type = process\ncommand = /bin/sh -c "echo run >> /tmp/wl-noinc.log; sleep 0.1; exit 1"\nrestart-delay = 0.1\nrestart-limit-count = 0\n' > $D/wl-noinc
rm -f /tmp/wl-inc.log /tmp/wl-noinc.log
sh_ 'dinitctl start wl-inc >/dev/null 2>&1; dinitctl start wl-noinc >/dev/null 2>&1; sleep 2; echo "with @include (restart = false): $(wc -l < /tmp/wl-inc.log | tr -d " ") runs; without: $(wc -l < /tmp/wl-noinc.log | tr -d " ") runs"; dinitctl stop --ignore-unstarted wl-noinc >/dev/null 2>&1'
sh_ 'printf "type = process\ncommand = /bin/sleep 5\n@include /tmp/wl-nonexistent.inc\n" > /etc/dinit.d/wl-incbad; dinitctl start wl-incbad 2>&1 | head -2; dinit-check wl-incbad 2>&1 | tail -3'
sh_ 'printf "type = process\ncommand = /bin/sleep 5\n@include-opt /tmp/wl-nonexistent.inc\n" > /etc/dinit.d/wl-incopt; dinitctl start wl-incopt 2>&1 | head -2; dinitctl stop wl-incopt >/dev/null'

echo '### 7. Where dinit logs its own messages'
sh_ 'ls /var/log | tr "\n" " "; echo; dinitctl is-started syslog-ng | head -1'
sh_ 'ls -l /dev/log 2>&1 | cut -c1-60; ls /usr/lib/dinit.d | grep -i -E "log|syslog"'
sh_ 'cat /usr/lib/dinit.d/syslog-ng 2>&1 | head -12'
sh_ 'dinitctl enable syslog-ng 2>&1 | tail -2; sleep 1; dinitctl is-started syslog-ng | head -1; ls /var/log | tr "\n" " "'
printf 'type = process\ncommand = /usr/bin/slepe 100\n' > $D/wl-logbad
sh_ 'dinitctl start wl-logbad >/dev/null 2>&1; sleep 1; grep -i "wl-logbad" /var/log/messages 2>&1 | tail -4 | cut -c1-170'
printf 'type = process\ncommand = /bin/sleep 100\n' > $D/wl-logok
sh_ 'dinitctl start wl-logok >/dev/null 2>&1; dinitctl stop wl-logok >/dev/null 2>&1; sleep 1; grep -i "wl-logok" /var/log/messages 2>&1 | tail -4 | cut -c1-170'
sh_ 'dinitctl start wl-nonexistent-xyz >/dev/null 2>&1; sleep 0.5; tail -3 /var/log/messages | cut -c1-170'
printf 'type = process\ncommand = /bin/sleep 5\nbogus-setting = 1\n' > $D/wl-logbogus
sh_ 'dinitctl start wl-logbogus >/dev/null 2>&1; sleep 0.5; grep -i "wl-logbogus" /var/log/messages | tail -3 | cut -c1-200'
sh_ 'dinitctl disable syslog-ng 2>&1 | tail -1; dinitctl stop syslog-ng >/dev/null 2>&1; dinitctl is-started syslog-ng | head -1'
echo '### done'
