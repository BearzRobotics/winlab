#!/bin/bash
# Security lesson battery 5: the scope guard (run via bash -s). SCOPE is substituted by the driver.
. /etc/os-release; echo "### $PRETTY_NAME  bash $BASH_VERSION"
cat > /var/tmp/wl-scope.sh <<'WLEOF'
@@SCOPE@@
WLEOF
chmod 755 /var/tmp/wl-scope.sh
cat > /var/tmp/lab.scope <<'EOF'
# WinLab home lab, written down before any testing
allow 127.0.0.1          # this machine
allow 10.0.2.0/24        # the VM's own network
allow 192.168.50.0/24    # the lab LAN
deny  192.168.50.1       # the router: not part of the exercise
EOF
S=/var/tmp/wl-scope.sh
t() { echo "\$ wl-scope.sh lab.scope $*"; $S /var/tmp/lab.scope "$@"; echo "exit status $?"; }
t 127.0.0.1 10.0.2.15
t 192.168.50.10 192.168.50.1
t 8.8.8.8
t 192.168.50.10 8.8.8.8
t example.com
t 10.0.2.256
t 192.168.51.1
echo "--- bad scope files"
printf 'allow 0.0.0.0/0\n' > /var/tmp/bad1.scope; $S /var/tmp/bad1.scope 127.0.0.1; echo "exit status $?"
printf 'allow 10.0.0.0/8\n' > /var/tmp/bad2.scope; $S /var/tmp/bad2.scope 10.1.1.1; echo "exit status $?"
printf 'permit 10.0.0.1\n' > /var/tmp/bad3.scope; $S /var/tmp/bad3.scope 10.0.0.1; echo "exit status $?"
printf 'allow 10.0.0.999\n' > /var/tmp/bad4.scope; $S /var/tmp/bad4.scope 10.0.0.1; echo "exit status $?"
printf 'deny 10.0.0.1\n' > /var/tmp/bad5.scope; $S /var/tmp/bad5.scope 10.0.0.1; echo "exit status $?"
$S /var/tmp/missing.scope 10.0.0.1; echo "exit status $?"
echo "--- use it as a gate in front of a scan"
scan() { $S /var/tmp/lab.scope "$@" >/dev/null || { echo "not scanning: out of scope"; return 1; }; for h in "$@"; do (exec 3<>/dev/tcp/$h/22) 2>/dev/null && echo "$h:22 open" || echo "$h:22 closed"; done; }
scan 127.0.0.1; scan 127.0.0.1 8.8.8.8
rm -f /var/tmp/*.scope /var/tmp/wl-scope.sh; echo done
