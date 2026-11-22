#!/bin/bash
# Home-lab battery 4: WireGuard between two network namespaces (run as root via bash -s)
. /etc/os-release; echo "### $PRETTY_NAME  kernel $(uname -r)"
if command -v apt-get >/dev/null; then
  apt-get update >/tmp/upd.log 2>&1; DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard-tools >/tmp/inst.log 2>&1; tail -1 /tmp/inst.log
else
  dnf -y install epel-release >/tmp/inst.log 2>&1; dnf -y install wireguard-tools >>/tmp/inst.log 2>&1; tail -1 /tmp/inst.log
fi
wg --version; modprobe wireguard 2>&1; lsmod | grep -E '^wireguard' | awk '{print $1, $2}'

W=/var/tmp/wl-wg; rm -rf $W; mkdir -p $W; cd $W; umask 077
echo "### 1. keys (each side makes its own pair; only public keys are exchanged)"
wg genkey | tee hub.key | wg pubkey > hub.pub
wg genkey | tee peer.key | wg pubkey > peer.pub
wg genkey | tee rogue.key | wg pubkey > rogue.pub
ls -l hub.key hub.pub | awk '{print $1, $9}'
wc -c < hub.pub

echo "### 2. two namespaces joined by a veth pair (the 'internet' between them)"
for n in wlhub wlpeer; do ip netns del $n 2>/dev/null; ip netns add $n; done
mkdir -p /etc/netns/wlhub /etc/netns/wlpeer
ip link add wlv-hub type veth peer name wlv-peer
ip link set wlv-hub netns wlhub; ip link set wlv-peer netns wlpeer
ip -n wlhub addr add 10.99.0.1/24 dev wlv-hub; ip -n wlhub link set wlv-hub up; ip -n wlhub link set lo up
ip -n wlpeer addr add 10.99.0.2/24 dev wlv-peer; ip -n wlpeer link set wlv-peer up; ip -n wlpeer link set lo up
ip netns exec wlpeer ping -c1 -W2 10.99.0.1 | grep -E 'transmitted'

echo "### 3. wg-quick style config files"
cat > hub.conf <<EOF
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = $(cat hub.key)

[Peer]
# the laptop
PublicKey = $(cat peer.pub)
AllowedIPs = 10.8.0.2/32
EOF
cat > peer.conf <<EOF
[Interface]
Address = 10.8.0.2/24
PrivateKey = $(cat peer.key)

[Peer]
# the home hub
PublicKey = $(cat hub.pub)
Endpoint = 10.99.0.1:51820
AllowedIPs = 10.8.0.0/24
PersistentKeepalive = 25
EOF
# wg-quick wants the file name to be the interface name
mkdir -p conf; cp hub.conf conf/wg-hub.conf; cp peer.conf conf/wg-peer.conf
ip netns exec wlhub wg-quick up $W/conf/wg-hub.conf 2>&1 | sed 's/PrivateKey = .*/PrivateKey = <hidden>/' | cut -c1-110
ip netns exec wlpeer wg-quick up $W/conf/wg-peer.conf 2>&1 | cut -c1-110

echo "### 4. the tunnel"
ip netns exec wlpeer ping -c2 -W2 10.8.0.1 | grep -E 'transmitted|rtt'
echo "--- wg show on the hub (keys shortened)"
ip netns exec wlhub wg show | sed -E 's/(public key: |peer: )(.{8}).*/\1\2.../'
echo "--- interface details"
ip -n wlhub -d addr show wg-hub | grep -E 'wireguard|mtu|inet ' | sed 's/  */ /g'
echo "--- routes in the peer namespace"
ip -n wlpeer route | sed 's/  */ /g'

echo "### 5. AllowedIPs is also the access list"
echo "--- hub sends to an address no peer owns:"
ip netns exec wlhub ping -c1 -W1 10.8.0.9 2>&1 | head -2

echo "### 6. a stranger without a registered key"
ip netns add wlrogue 2>/dev/null; ip link add wlv-r1 type veth peer name wlv-r2
ip link set wlv-r1 netns wlhub; ip link set wlv-r2 netns wlrogue
ip -n wlhub addr add 10.98.0.1/24 dev wlv-r1; ip -n wlhub link set wlv-r1 up
ip -n wlrogue addr add 10.98.0.2/24 dev wlv-r2; ip -n wlrogue link set wlv-r2 up; ip -n wlrogue link set lo up
sed "s|^PrivateKey.*|PrivateKey = $(cat rogue.key)|;s|10.8.0.2|10.8.0.3|;s|10.99.0.1|10.98.0.1|" peer.conf > conf/wg-rogue.conf
ip netns exec wlrogue wg-quick up $W/conf/wg-rogue.conf >/dev/null 2>&1
ip netns exec wlrogue ping -c2 -W2 10.8.0.1 2>&1 | grep -E 'transmitted'
echo "--- plain UDP junk to the WireGuard port gets no answer at all"
ip netns exec wlrogue bash -c 'exec 3<>/dev/udp/10.98.0.1/51820; echo hello >&3; timeout 2 cat <&3; echo "reply status $?"'
echo "--- hub still lists only the one known peer"
ip netns exec wlhub wg show wg-hub peers | wc -l

echo "### 7. take it down"
ip netns exec wlpeer wg-quick down $W/conf/wg-peer.conf 2>&1 | tail -1
ip netns exec wlpeer ping -c1 -W1 10.8.0.1 2>&1 | head -2
for n in wlhub wlpeer wlrogue; do ip netns del $n; done; rm -rf /etc/netns/wlhub /etc/netns/wlpeer $W; echo done
