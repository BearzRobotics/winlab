#!/bin/bash
# Home-lab battery 1: dnsmasq as a DNS (and DHCP) server on a lab network (run as root via bash -s)
. /etc/os-release; echo "### $PRETTY_NAME"
if command -v apt-get >/dev/null; then
  apt-get update >/tmp/upd.log 2>&1
  echo "### 0. install dnsmasq on Ubuntu: what happens with systemd-resolved already on port 53?"
  DEBIAN_FRONTEND=noninteractive apt-get install -y dnsmasq dnsutils isc-dhcp-client >/tmp/inst.log 2>&1; tail -2 /tmp/inst.log
  systemctl is-active dnsmasq; journalctl -u dnsmasq --no-pager -o cat -n 6 | cut -c1-160
else
  dnf -y install dnsmasq bind-utils dhcp-client >/tmp/inst.log 2>&1; tail -2 /tmp/inst.log
fi
dnsmasq --version | head -1
ss -ulnp | grep ':53 ' | sed 's/  */ /g'

echo "### 1. a lab zone on loopback"
cat > /etc/dnsmasq.d/lab.conf <<'EOF'
listen-address=127.0.0.1
bind-interfaces
no-resolv
server=10.0.2.3
domain=lab.test
local=/lab.test/
address=/nas.lab.test/192.168.50.10
host-record=pi.lab.test,192.168.50.11
cname=files.lab.test,nas.lab.test
address=/ads.example/0.0.0.0
cache-size=1000
log-queries
EOF
dnsmasq --test 2>&1
systemctl restart dnsmasq; sleep 1; systemctl is-active dnsmasq
ss -ulnp | grep ':53 ' | sed 's/  */ /g'
q() { echo "\$ dig @127.0.0.1 $*"; dig @127.0.0.1 "$@" 2>&1 | grep -vE '^;|^$'; }
q nas.lab.test +short
q files.lab.test +noall +answer
q -x 192.168.50.11 +short
q -x 192.168.50.10 +short
echo "--- name in the local domain that does not exist: answered locally, not forwarded"
dig @127.0.0.1 nobody.lab.test | grep -E 'status|ANSWER:'
q ads.example +short
echo "--- a public name is forwarded"
dig @127.0.0.1 example.com +noall +answer +stats | grep -E 'IN|Query time'
echo "--- second time comes from the cache"
dig @127.0.0.1 example.com +noall +answer +stats | grep -E 'Query time'
journalctl -u dnsmasq --no-pager -o cat --since "-1min" | grep -E 'example.com|cached' | cut -c1-110 | head -6

echo "### 2. bad config is caught by --test"
echo 'bogus-option=1' > /etc/dnsmasq.d/bad.conf
dnsmasq --test; echo "plain --test exit $?"
dnsmasq --test --conf-dir=/etc/dnsmasq.d; echo "with --conf-dir exit $?"
rm /etc/dnsmasq.d/bad.conf

echo "### 3. DHCP, on a private veth pair in network namespaces (the lab VM's own network is untouched)"
systemctl stop dnsmasq
ip netns del wllan 2>/dev/null; ip link del wlveth0 2>/dev/null
head -2 /etc/resolv.conf | tail -1 > /tmp/wl-resolv-before
mkdir -p /etc/netns/wllan; : > /etc/netns/wllan/resolv.conf
ip netns add wllan
ip link add wlveth0 type veth peer name wlveth1
ip link set wlveth1 netns wllan
ip addr add 192.168.50.1/24 dev wlveth0; ip link set wlveth0 up
ip netns exec wllan ip link set lo up; ip netns exec wllan ip link set wlveth1 up
MAC=$(ip netns exec wllan cat /sys/class/net/wlveth1/address)
cat > /tmp/wl-dhcp.conf <<EOF
interface=wlveth0
bind-interfaces
no-resolv
domain=lab.test
local=/lab.test/
dhcp-range=192.168.50.100,192.168.50.150,12h
dhcp-option=option:router,192.168.50.1
dhcp-option=option:dns-server,192.168.50.1
dhcp-host=$MAC,pi,192.168.50.11
dhcp-leasefile=/tmp/wl-dnsmasq.leases
log-dhcp
EOF
dnsmasq -C /tmp/wl-dhcp.conf --test 2>&1
dnsmasq -C /tmp/wl-dhcp.conf --pid-file=/tmp/wl-dnsmasq.pid; sleep 1
echo "--- client asks for an address"
ip netns exec wllan dhclient -v -1 wlveth1 2>&1 | grep -E 'DHCP|bound|Listening' | cut -c1-110
ip netns exec wllan ip -br addr show wlveth1
echo "--- host resolv.conf unchanged? (before: $(cat /tmp/wl-resolv-before | head -1))"; grep -c 192.168.50.1 /etc/resolv.conf
echo "--- resolv.conf seen inside the namespace"; ip netns exec wllan cat /etc/resolv.conf
echo "--- the lease file"
cat /tmp/wl-dnsmasq.leases
echo "--- the name is now answered"
dig @192.168.50.1 pi.lab.test +short
dig @192.168.50.1 -x 192.168.50.11 +short
echo "--- what dnsmasq logged"
journalctl --no-pager -o cat -t dnsmasq-dhcp --since "-2min" | cut -c1-120 | head -8
kill $(cat /tmp/wl-dnsmasq.pid); ip netns exec wllan dhclient -x wlveth1 2>/dev/null
ip netns del wllan; ip link del wlveth0 2>/dev/null; rm -rf /etc/netns/wllan
rm -f /tmp/wl-dhcp.conf /tmp/wl-dnsmasq.leases /etc/dnsmasq.d/lab.conf
systemctl stop dnsmasq; echo done
