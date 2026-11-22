#!/bin/bash
# Security lesson battery 7: the threat-table ranker (run via bash -s). THREATS is substituted by the driver.
. /etc/os-release; echo "### $PRETTY_NAME  bash $BASH_VERSION  awk: $(awk --version 2>&1 | head -1)"
cat > /var/tmp/wl-threats.sh <<'WLEOF'
@@THREATS@@
WLEOF
chmod 755 /var/tmp/wl-threats.sh
T=$'\t'
cat > /var/tmp/lab.tsv <<EOF
# id${T}element${T}stride${T}threat${T}L${T}I${T}control${T}status
T1${T}ssh on the VM${T}S${T}someone guesses a password and logs in${T}3${T}3${T}key-only login, PasswordAuthentication no (wl-baseline.sh)${T}done
T2${T}samba share${T}I${T}a guest reads the family photos${T}2${T}3${T}valid users = @group, no guest access${T}done
T3${T}backups${T}T${T}ransomware encrypts the only backup${T}2${T}3${T}restic repo on a second disk plus an offline copy${T}planned
T4${T}repo signing key${T}S${T}the signing key leaks and a fake package is published${T}1${T}3${T}key kept offline, subkeys, rotation plan${T}open
T5${T}dns server${T}D${T}the resolver is flooded${T}1${T}2${T}listen on the LAN only${T}done
T6${T}logs${T}R${T}an intruder deletes the logs so nothing can be proved${T}2${T}2${T}ship logs to a second machine${T}open
T7${T}vm host${T}E${T}a guest escapes to the host${T}1${T}3${T}keep the hypervisor patched${T}open
EOF
S=/var/tmp/wl-threats.sh
echo "\$ wl-threats.sh lab.tsv"; $S /var/tmp/lab.tsv; echo "exit status $?"
echo "\$ wl-threats.sh lab.tsv 9"; $S /var/tmp/lab.tsv 9; echo "exit status $?"
echo "--- bad tables"
printf 'T1\tx\tQ\tbad letter\t2\t2\tc\topen\n' > /var/tmp/b1.tsv;  $S /var/tmp/b1.tsv; echo "exit status $?"
printf 'T1\tx\tS\tbad number\t4\t2\tc\topen\n' > /var/tmp/b2.tsv; $S /var/tmp/b2.tsv; echo "exit status $?"
printf 'T1\tx\tS\ttoo few fields\t2\t2\topen\n' > /var/tmp/b3.tsv; $S /var/tmp/b3.tsv; echo "exit status $?"
printf 'T1\tx\tS\ta\t2\t2\tc\topen\nT1\ty\tS\tb\t2\t2\tc\topen\n' > /var/tmp/b4.tsv; $S /var/tmp/b4.tsv; echo "exit status $?"
printf 'T1\tx\tS\ta\t2\t2\tc\tmaybe\n' > /var/tmp/b5.tsv; $S /var/tmp/b5.tsv; echo "exit status $?"
$S /var/tmp/none.tsv; echo "exit status $?"
rm -f /var/tmp/*.tsv /var/tmp/wl-threats.sh; echo done
