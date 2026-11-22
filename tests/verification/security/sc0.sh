#!/bin/bash
# probe: what is installed, is there internet
. /etc/os-release; echo "$PRETTY_NAME"
for c in auditd auditctl ausearch aureport rsyslogd lastb nmap ss sshd fail2ban-client lynis aa-status getenforce curl nc dig; do printf '%s: ' "$c"; command -v $c || echo none; done
ls /var/log | tr '\n' ' '; echo
timeout 8 curl -sI https://deb.debian.org -o /dev/null -w 'internet http=%{http_code}\n' || echo "no internet"
systemctl is-active ssh sshd rsyslog auditd 2>&1 | tr '\n' ' '; echo
