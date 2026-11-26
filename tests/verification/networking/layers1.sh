# Battery for networking.models-and-protocols. THROWAWAY VM ONLY, as root. Three network namespaces:
# client -- router -- server, connected only to each other. Captures one HTTP request on both sides.
export LC_ALL=C
say() { printf '\n=== %s\n' "$*"; }
. /etc/os-release; echo "$PRETTY_NAME"
dnf -y -q install tcpdump >/dev/null 2>&1; command -v tcpdump || exit 1
ip netns add cli; ip netns add rtr; ip netns add srv
ip link add c0 type veth peer name r0; ip link add r1 type veth peer name s0
ip link set c0 netns cli; ip link set r0 netns rtr; ip link set r1 netns rtr; ip link set s0 netns srv
C='ip netns exec cli'; R='ip netns exec rtr'; S='ip netns exec srv'
$C ip link set c0 address 02:00:00:00:00:0c; $R ip link set r0 address 02:00:00:00:00:a0
$R ip link set r1 address 02:00:00:00:00:a1; $S ip link set s0 address 02:00:00:00:00:05
for n in "$C c0 192.168.1.20/24" "$R r0 192.168.1.1/24" "$R r1 198.51.100.1/24" "$S s0 198.51.100.7/24"; do
  set -- $n; ip netns exec $4 true 2>/dev/null; $1 $2 $3 $4 ip addr add $6 dev $5; $1 $2 $3 $4 ip link set $5 up; done
$C ip route add default via 192.168.1.1; $S ip route add default via 198.51.100.1
$R sysctl -q -w net.ipv4.ip_forward=1
mkdir -p /root/wlweb; echo hello > /root/wlweb/index.html
$S python3 -m http.server 80 --directory /root/wlweb >/dev/null 2>&1 & W=$!; sleep 1
say 'neighbour table before'
$C ip neigh show; echo "(entries: $($C ip neigh show | wc -l))"
$R timeout 6 tcpdump -l -n -e -v -i r0 'arp or tcp port 80' > /root/left.txt 2>/dev/null & A=$!
$R timeout 6 tcpdump -l -n -e -v -i r1 'arp or tcp port 80' > /root/right.txt 2>/dev/null & B=$!
sleep 1
say 'the request'
$C curl -sS -m 3 http://198.51.100.7/
wait $A $B 2>/dev/null
flat() { awk '/^[0-9]/{if(line)print line; line=$0; next}{sub(/^ +/," "); line=line $0} END{if(line)print line}' "$1" | sed 's/^[0-9:.]* //'; }
say 'client side of the router'; flat /root/left.txt | cut -c1-260 | head -9
say 'server side of the router'; flat /root/right.txt | cut -c1-260 | head -9
say 'neighbour table after'
$C ip neigh show
say 'route and TTL'
$C ping -c 1 -W 1 198.51.100.7 | grep ttl
$C ping -c 1 -W 1 -t 1 198.51.100.7 | grep -iE 'exceeded|ttl'
$C ping -c 1 -W 1 192.168.1.1 | grep ttl
say 'a UDP exchange for comparison'
$S timeout 3 python3 -c 'import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.bind(("0.0.0.0",9000)); d,a=s.recvfrom(100); s.sendto(b"pong",a)' & U=$!
$R timeout 3 tcpdump -l -n -i r0 'udp port 9000' > /root/udp.txt 2>/dev/null & Y=$!; sleep 0.8
$C python3 -c 'import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.settimeout(2); s.sendto(b"ping",("198.51.100.7",9000)); print(s.recv(100))'
wait $U $Y 2>/dev/null; sed 's/^[0-9:.]* //' /root/udp.txt
kill $W 2>/dev/null
ip netns del cli; ip netns del rtr; ip netns del srv; rm -rf /root/wlweb /root/left.txt /root/right.txt /root/udp.txt
say done
