#!/bin/bash
# Networking lessons: run the Linux commands the lessons show, on a lab VM (Ubuntu or AlmaLinux), as root via bash -s.
# Prints each command with its output and exit status so the lesson text can be compared with reality.
. /etc/os-release; echo "### $PRETTY_NAME  kernel $(uname -r)"
run() { echo "\$ $*"; "$@" 2>&1 | head -${LINES_MAX:-14}; echo "[exit ${PIPESTATUS[0]}]"; }
IF=$(ip -o -4 route show default | awk '{print $5; exit}'); echo "default interface: $IF"

echo "### addressing-and-names / subnetting / routing"
run ip -br addr
run ip route show
run getent hosts example.com
run ss -tln

echo "### dhcp: the lesson shows ip addr show eth0 and nmcli device show eth0"
run ip addr show "$IF"
echo "--- is the interface called eth0?"; ip link show eth0 >/dev/null 2>&1 && echo "eth0 exists" || echo "no eth0 here (the lesson's example name)"
command -v nmcli >/dev/null && { run nmcli device show "$IF"; } || echo "nmcli: not installed"
command -v networkctl >/dev/null && run networkctl status "$IF"
echo "--- which network manager?"; systemctl is-active NetworkManager systemd-networkd 2>&1

echo "### dns: nslookup, resolvectl, dig"
command -v nslookup >/dev/null && { run nslookup example.com; run nslookup -type=NS example.com; } || echo "nslookup: not installed"
command -v resolvectl >/dev/null && { run resolvectl query example.com; LINES_MAX=18 run resolvectl status; } || echo "resolvectl: not installed"
command -v dig >/dev/null && run dig example.com MX @1.1.1.1 +short || echo "dig: not installed (bind-utils / dnsutils)"

echo "### ports-and-firewalls: ss -tlnp"
run ss -tlnp

echo "### routing: ip route add / del (a route via an unreachable gateway)"
run ip route add 10.20.0.0/16 via 192.168.1.3
run ip route show
run ip route del 10.20.0.0/16
echo "--- a route via a reachable gateway (the default gateway), then delete"
GW=$(ip -o -4 route show default | awk '{print $3; exit}')
run ip route add 10.20.0.0/16 via "$GW"
run ip route show 10.20.0.0/16
run ip route del 10.20.0.0/16

echo "### firewall"
if [ -f /etc/os-release ] && grep -qi 'ubuntu' /etc/os-release; then
  echo "--- ufw (Ubuntu)"
  command -v ufw >/dev/null || { apt-get install -y ufw >/dev/null 2>&1; }
  run ufw status verbose
  run ufw allow 22/tcp
  run ufw allow from 192.168.1.0/24 to any port 8080 proto tcp
  run ufw status verbose
  run ufw delete allow 8080/tcp
  run ufw status numbered
  echo "--- ufw enable (22 is allowed first)"; run ufw --force enable
  run ufw status verbose
  ssh_ok=$(ss -tln | grep -c ':22 ') ; echo "sshd still listening: $ssh_ok"
  run ufw --force disable
else
  echo "--- firewalld (AlmaLinux): is it installed?"
  rpm -q firewalld || { dnf -y install firewalld >/tmp/fw-inst.log 2>&1; tail -1 /tmp/fw-inst.log; rpm -q firewalld; }
  systemctl enable --now firewalld 2>&1 | tail -1
  run firewall-cmd --state
  run firewall-cmd --get-active-zones
  run firewall-cmd --list-all
  run firewall-cmd --add-service=http
  echo "--- runtime has it, permanent does not:"; firewall-cmd --list-services; firewall-cmd --permanent --list-services
  run firewall-cmd --reload
  echo "--- after reload (runtime rule lost):"; firewall-cmd --list-services
  run firewall-cmd --permanent --add-service=http
  run firewall-cmd --reload
  echo "--- after permanent + reload:"; firewall-cmd --list-services
  run firewall-cmd --permanent --add-port=8080/tcp
  firewall-cmd --reload >/dev/null; firewall-cmd --list-ports
  # cleanup
  firewall-cmd --permanent --remove-service=http >/dev/null; firewall-cmd --permanent --remove-port=8080/tcp >/dev/null; firewall-cmd --reload >/dev/null
  systemctl disable --now firewalld >/dev/null 2>&1; echo "firewalld removed from the running state"
fi
echo done
