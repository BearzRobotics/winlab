# Battery for networking.dhcp. THROWAWAY VM ONLY, as root. A private DHCP server (dnsmasq) and two clients
# in their own network namespaces, joined by a bridge that is not connected to anything else.
export LC_ALL=C
say() { printf '\n=== %s\n' "$*"; }
. /etc/os-release; echo "$PRETTY_NAME"
# SELinux confines dhclient and stops it using this test folder; permissive for this throwaway VM only.
setenforce 0; getenforce
dnf -y -q install dnsmasq tcpdump dhcp-client >/dev/null 2>&1
command -v dnsmasq tcpdump dhclient || { echo "tools not available"; exit 1; }
ip link add wlbr type bridge; ip link set wlbr up
ip netns add wlserver; ip netns add wlc1; ip netns add wlc2
join() { ip link add "v$1" type veth peer name "e$1"; ip link set "v$1" master wlbr up; ip link set "e$1" netns "$2"; ip netns exec "$2" ip link set "e$1" name eth0; ip netns exec "$2" ip link set eth0 up; ip netns exec "$2" ip link set lo up; }
join s wlserver; join 1 wlc1; join 2 wlc2
ip netns exec wlserver ip addr add 192.168.77.1/24 dev eth0
mkdir -p /root/wldhcp; cd /root/wldhcp || exit 1
# The client script only sets the address and route inside the namespace; it must not touch the VM's DNS settings.
cat > client.sh <<'SH'
#!/bin/sh
case "$reason" in
 BOUND|RENEW|REBIND|REBOOT) ip addr replace "$new_ip_address/${new_subnet_mask:-24}" dev "$interface"; [ -n "$new_routers" ] && ip route replace default via "${new_routers%% *}"
   echo "client got: reason=$reason ip=$new_ip_address mask=$new_subnet_mask router=$new_routers dns=$new_domain_name_servers lease=$new_dhcp_lease_time server=$new_dhcp_server_identifier" >> /root/wldhcp/$interface-${WLNAME}.txt ;;
 *) echo "client event: $reason" >> /root/wldhcp/$interface-${WLNAME}.txt ;;
esac
SH
chmod +x client.sh; chcon -t dhcpc_script_exec_t client.sh 2>/dev/null; true
server() { # range-end extra...
  rm -f leases; ip netns exec wlserver dnsmasq --keep-in-foreground --conf-file=/dev/null --port=0 --interface=eth0 --bind-interfaces \
    --dhcp-range=192.168.77.100,$1,255.255.255.0,2m --dhcp-option=option:router,192.168.77.1 --dhcp-option=option:dns-server,192.168.77.1 \
    --dhcp-leasefile=/root/wldhcp/leases --dhcp-authoritative --log-dhcp --log-facility=- --no-ping "${@:2}" > server.log 2>&1 & S=$!; sleep 1; }
client() { # namespace
  : > eth0-$1.txt; timeout 25 ip netns exec $1 env WLNAME=$1 dhclient -4 -1 -v -sf /root/wldhcp/client.sh -pf /root/wldhcp/$1.pid -lf /root/wldhcp/$1.lease -e WLNAME=$1 eth0 > $1.log 2>&1; echo "dhclient exit: $?"; }
stopc() { [ -f $1.pid ] && kill $(cat $1.pid) 2>/dev/null; rm -f $1.pid $1.lease; ip netns exec $1 ip addr flush dev eth0; }

say 'the four messages, captured on the wire'
server 192.168.77.150
ip netns exec wlserver tcpdump -l -n -i eth0 -vv 'udp port 67 or udp port 68' > capture.txt 2>/dev/null & T=$!; sleep 1
client wlc1
sleep 2
echo '--- client output'; grep -E 'DHCP|bound' wlc1.log
echo '--- what the client was given'; cat eth0-wlc1.txt
ip netns exec wlc1 ip -4 addr show eth0; ip netns exec wlc1 ip route
echo '--- capture, shortened'; grep -aE '^[0-9]|BOOTP|DHCP-Message|Requested-IP|Server-ID|Lease-Time|Your-IP|0\.0\.0\.0|255\.255\.255\.255' capture.txt | sed 's/^[0-9:.]* //' | cut -c1-140
echo '--- server log (message lines)'; grep -E 'DHCP(DISCOVER|OFFER|REQUEST|ACK|NAK)' server.log | sed 's/^.*dnsmasq-dhcp[^:]*: [0-9]* //'
echo '--- lease file'; cat leases

say 'renewal: waiting past half of the 2 minute lease'
: > capture.txt; : > server.log.mark; lines=$(wc -l < server.log)
sleep 75
tail -n +$((lines+1)) server.log | grep -E 'DHCP(DISCOVER|OFFER|REQUEST|ACK|NAK)' | sed 's/^.*dnsmasq-dhcp[^:]*: [0-9]* //'
echo '--- addresses in the renewal packets'; grep -aE ' > ' capture.txt | sed 's/^ *//' | cut -c1-90 | head -4
cat eth0-wlc1.txt
kill $T; stopc wlc1; kill $S; wait $S 2>/dev/null

say 'no server at all'
client wlc1; grep -E 'DHCPDISCOVER|No DHCPOFFERS|No working leases' wlc1.log | head -8
echo '--- the interface afterwards'; ip netns exec wlc1 ip -4 addr show eth0; echo "(IPv4 lines: $(ip netns exec wlc1 ip -4 addr show eth0 | grep -c inet))"
stopc wlc1

say 'a scope with one address and two clients'
server 192.168.77.100
client wlc1; cat eth0-wlc1.txt
client wlc2; grep -E 'DHCPDISCOVER|No DHCPOFFERS' wlc2.log | head -3
echo '--- server log'; grep -E 'DHCP(DISCOVER|OFFER|REQUEST|ACK|NAK)|no address' server.log | sed 's/^.*dnsmasq-dhcp[^:]*: [0-9]* //' | sort | uniq -c
stopc wlc1; stopc wlc2; kill $S; wait $S 2>/dev/null

say 'a reservation by hardware address'
mac=$(ip netns exec wlc2 cat /sys/class/net/eth0/address)
server 192.168.77.150 --dhcp-host=$mac,192.168.77.200
client wlc2; cat eth0-wlc2.txt
stopc wlc2; kill $S; wait $S 2>/dev/null

kill $S 2>/dev/null
ip netns del wlserver; ip netns del wlc1; ip netns del wlc2; ip link del wlbr
cd /; rm -rf /root/wldhcp
say 'cleaned up'; ip -br link | grep -c wlbr
