# Battery for networking.subnetting: two hosts on one wire with different masks. THROWAWAY VM ONLY, as root.
export LC_ALL=C
say() { printf '\n=== %s\n' "$*"; }
run() { printf '$ %s\n' "$*"; eval "$*" 2>&1 </dev/null; printf '[exit %s]\n' "$?"; }
. /etc/os-release; echo "$PRETTY_NAME"
dnf -y -q install tcpdump >/dev/null 2>&1
say 'ipcalc'
run 'command -v ipcalc'
run 'ipcalc -n -b -m 172.16.45.200/21'
ip netns add wla; ip netns add wlb
ip link add vea type veth peer name veb; ip link set vea netns wla; ip link set veb netns wlb
A='ip netns exec wla'; B='ip netns exec wlb'
$A ip addr add 192.168.1.20/24 dev vea;  $A ip link set vea up
$B ip addr add 192.168.1.200/25 dev veb; $B ip link set veb up
say 'A thinks B is local; B thinks A is not'
run "$A ip route get 192.168.1.200"
run "$B ip route get 192.168.1.20"
run "$A ping -c 2 -W 1 192.168.1.200"
say 'did the request arrive at B?'
$B timeout 4 tcpdump -l -n -i veb 'icmp or arp' > /root/wlcap.txt 2>/dev/null & T=$!; sleep 1
$A ping -c 2 -W 1 192.168.1.20 >/dev/null 2>&1; $A ping -c 2 -W 1 192.168.1.200 >/dev/null 2>&1
wait $T 2>/dev/null; sed 's/^[0-9:.]* //' /root/wlcap.txt | head -8; rm -f /root/wlcap.txt
say 'same masks'
$B ip addr flush dev veb; $B ip addr add 192.168.1.200/24 dev veb
run "$A ping -c 2 -W 1 192.168.1.200"
ip netns del wla; ip netns del wlb
