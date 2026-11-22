#!/bin/bash
# wl-triage.sh: collect volatile and persistent evidence on a Linux host, most volatile first.
# Usage: wl-triage.sh OUTDIR   (run as root; it only reads, and writes into OUTDIR)
# Write the evidence to a different disk or a mounted share when you can: writing to the suspect disk changes it.
set -u
out=${1:?usage: wl-triage.sh OUTDIR}
mkdir -p "$out" && chmod 700 "$out"
run() { local name=$1; shift; { echo "# $(date -u +%FT%TZ)  $*"; "$@" 2>&1; } > "$out/$name.txt"; }

# 1. most volatile first: time, who is on, processes, network, kernel
run 00-time        date -u
run 01-uptime      uptime
run 02-who         w
run 03-processes   ps -eo pid,ppid,user,lstart,stat,args --forest
run 04-sockets     ss -tunap
run 05-addresses   ip -br addr
run 06-routes      ip route
run 07-modules     lsmod
# processes running a deleted or temporary file
{ echo "# processes whose executable is deleted or in a temp directory"
  for p in /proc/[0-9]*; do
    exe=$(readlink "$p/exe" 2>/dev/null) || continue
    case $exe in *" (deleted)"|/tmp/*|/var/tmp/*|/dev/shm/*) echo "${p#/proc/} $exe";; esac
  done; } > "$out/08-odd-exe.txt"

# 2. persistence: the places a foothold survives a reboot
run 10-passwd      getent passwd
run 11-uid0        awk -F: '$3 == 0 { print $1 }' /etc/passwd
run 12-sudoers     grep -rHv '^#\|^$' /etc/sudoers /etc/sudoers.d
{ echo "# authorized_keys files"; for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do [ -f "$f" ] && { echo "== $f ($(stat -c '%y' "$f"))"; cut -c1-80 "$f"; }; done; } > "$out/13-authkeys.txt"
run 14-cron        bash -c 'for f in /etc/crontab /etc/cron.d/* /var/spool/cron/* /var/spool/cron/crontabs/*; do [ -f "$f" ] && { echo "== $f"; grep -v "^#" "$f"; }; done'
run 15-timers      systemctl list-timers --all --no-pager
run 16-units-local bash -c 'ls -l --time-style=long-iso /etc/systemd/system/*.service /etc/systemd/system/*.timer 2>/dev/null'
run 17-enabled     systemctl list-unit-files --state=enabled --no-pager

# 3. logs: copy, do not trust the originals alone
run 20-last        last -F -n 30
run 21-lastb       lastb -F -n 30
run 22-journal-auth journalctl --no-pager -o short-iso -n 300 _COMM=sshd _COMM=sudo _COMM=su

# 4. files changed recently under the places attackers write
run 30-recent-etc  find /etc /usr/local /root /home /tmp /var/tmp -xdev -type f -mtime -2 -printf '%TY-%Tm-%Td %TH:%TM  %u:%g  %m  %p\n'
run 31-suid        find / -xdev -type f -perm -4000 -printf '%m %u %p\n'

# 5. seal the evidence
( cd "$out" && sha256sum *.txt > SHA256SUMS )
echo "collected $(ls "$out" | wc -l) files in $out"
