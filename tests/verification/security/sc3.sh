#!/bin/bash
# Security lesson battery 3: own-lab recon with ss, bash /dev/tcp, nmap; and a lynis audit (run as root via bash -s)
. /etc/os-release; echo "### $PRETTY_NAME"
if command -v apt-get >/dev/null; then
  apt-get update >/tmp/upd.log 2>&1; DEBIAN_FRONTEND=noninteractive apt-get install -y nmap lynis >/tmp/inst.log 2>&1; tail -1 /tmp/inst.log
else
  dnf -y install epel-release >/tmp/inst.log 2>&1; dnf -y install nmap lynis >>/tmp/inst.log 2>&1; tail -2 /tmp/inst.log
fi
nmap --version | head -1; lynis show version

echo "### 1. what is listening (ss)"
ss -tlnp | sed 's/  */ /g'
echo "### 2. start an extra listener on all addresses, then look again"
cd /tmp && nohup python3 -m http.server 8080 --bind 0.0.0.0 >/tmp/http.log 2>&1 &
sleep 1.5
ss -tlnp | sed 's/  */ /g' | grep -E ':8080|State'

echo "### 3. a port check with only bash"
check() { (exec 3<>/dev/tcp/$1/$2) 2>/dev/null && echo "$2 open" || echo "$2 closed"; }
for p in 22 80 8080 8081; do check 127.0.0.1 $p; done
echo "--- scan 1-1024 with a bash loop"
time ( for p in $(seq 1 1024); do (exec 3<>/dev/tcp/127.0.0.1/$p) 2>/dev/null && echo "open $p"; done )

echo "### 4. nmap on this machine only"
nmap -sT -p 1-1024,8080 127.0.0.1 2>&1 | grep -vE '^(Starting|Host is up)'
echo "--- version detection and reasons"
nmap -sT -sV -p 22,8080 --reason 127.0.0.1 2>&1 | grep -E 'PORT|open|closed|Service|Nmap done'
echo "--- all 65535 ports (time it)"
time nmap -sT -p- 127.0.0.1 2>&1 | grep -E '^[0-9]+/|Nmap done'
echo "--- the HTTP banner by hand"
printf 'HEAD / HTTP/1.0\r\n\r\n' | (exec 3<>/dev/tcp/127.0.0.1/8080; cat >&3; timeout 2 cat <&3) | head -4
kill %1 2>/dev/null; sleep 0.5; ss -tln | grep -c ':8080 '

echo "### 5. lynis"
lynis audit system --quick --no-colors >/tmp/lynis.out 2>&1; echo "exit $?"
grep -E 'Hardening index|Tests performed|Warnings|Suggestions' /tmp/lynis.out | sed 's/\x1b\[[0-9;]*m//g' | head -8
echo "--- the report files"
ls -l /var/log/lynis.log /var/log/lynis-report.dat | awk '{print $1, $3, $9}'
grep -E '^(warning|suggestion)\[\]' /var/log/lynis-report.dat | head -6 | cut -c1-150
echo done
