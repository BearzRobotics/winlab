# Battery for networking.ports-and-firewalls. THROWAWAY VM ONLY, as root. Makes a second network namespace
# ("wlcli") joined by a virtual cable, so one VM can act as client and server, and adds its own nftables
# table. Removes both at the end.
export LC_ALL=C
say() { printf '\n=== %s\n' "$*"; }
. /etc/os-release; echo "$PRETTY_NAME"
dnf -y -q install nftables >/dev/null 2>&1; command -v nft python3 || { echo "nft not available"; exit 1; }
ip netns add wlcli
ip link add wlsrv type veth peer name wlc0
ip link set wlc0 netns wlcli
ip addr add 10.99.0.1/24 dev wlsrv; ip link set wlsrv up
ip netns exec wlcli ip addr add 10.99.0.2/24 dev wlc0
ip netns exec wlcli ip link set wlc0 up; ip netns exec wlcli ip link set lo up
python3 -m http.server 8081 --bind 0.0.0.0 >/dev/null 2>&1 & A=$!
python3 -m http.server 8082 --bind 127.0.0.1 >/dev/null 2>&1 & B=$!
sleep 1
try() { # label port
    printf '%-44s' "$1"; start=$(date +%s.%N)
    out=$(ip netns exec wlcli curl -sS -m 5 -o /dev/null -w 'HTTP status %{http_code}' "http://10.99.0.1:$2/" 2>&1); code=$?
    printf 'exit %-3s %5.2f s  %s\n' "$code" "$(awk -v a="$(date +%s.%N)" -v b="$start" "BEGIN{print a-b}")" "$out"; }
say 'listening sockets'
ss -tlnp | grep -E ':808[12]' | cut -c1-120
say 'from the other namespace, no firewall rules of mine'
try 'listening on 0.0.0.0:8081' 8081
try 'listening only on 127.0.0.1:8082' 8082
try 'nothing listening on 8083' 8083
say 'from the server itself'
curl -sS -m 5 -o /dev/null -w 'to 127.0.0.1:8082 HTTP %{http_code}\n' http://127.0.0.1:8082/ 2>&1
curl -sS -m 5 -o /dev/null -w 'to 10.99.0.1:8082 HTTP %{http_code}\n' http://10.99.0.1:8082/ 2>&1
nft add table inet wltest
nft 'add chain inet wltest in { type filter hook input priority 0; policy accept; }'
rule() { nft flush chain inet wltest in; nft add rule inet wltest in iifname wlsrv tcp dport 8081 $1; }
say 'the same listening port, with different firewall rules'
rule 'drop';                                     try 'rule: drop' 8081
rule 'reject with tcp reset';                    try 'rule: reject with tcp reset' 8081
rule 'reject';                                   try 'rule: reject (default: port unreachable)' 8081
rule 'reject with icmpx type admin-prohibited';  try 'rule: reject, admin-prohibited' 8081
nft flush chain inet wltest in;                  try 'rule removed' 8081
say 'ping is a different question'
nft add rule inet wltest in iifname wlsrv tcp dport 8081 drop
ip netns exec wlcli ping -c 1 -W 2 10.99.0.1 | tail -2
try 'port 8081 while ping works' 8081
say 'the rule counters tell you whether packets arrived'
nft flush chain inet wltest in; nft add rule inet wltest in iifname wlsrv tcp dport 8081 counter drop
try 'dropped, with a counter' 8081
nft list chain inet wltest in
say 'UDP: a client cannot tell dropped from listening-but-silent'
udp() { printf '%-34s' "$1"; ip netns exec wlcli python3 - "$2" <<'PY'
import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(3); s.connect(('10.99.0.1', int(sys.argv[1])))
try:
    s.send(b'x'); print(s.recv(100))
except Exception as e:
    print(type(e).__name__)
PY
}
nft flush chain inet wltest in
udp 'UDP, nothing listening' 8090
nft add rule inet wltest in iifname wlsrv udp dport 8090 drop
udp 'UDP, dropped by a rule' 8090
nft flush chain inet wltest in
python3 -c 'import socket,time; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.bind(("0.0.0.0",8090)); time.sleep(8)' & C=$!
sleep 0.5
udp 'UDP, listening but silent' 8090
kill $A $B $C 2>/dev/null; wait 2>/dev/null
nft delete table inet wltest
say 'firewalld with its default zone: what a blocked client is told'
dnf -y -q install firewalld >/dev/null 2>&1; systemctl start firewalld; firewall-cmd --state; firewall-cmd --version
firewall-cmd --get-default-zone; firewall-cmd --list-all
python3 -m http.server 8081 --bind 0.0.0.0 >/dev/null 2>&1 & D=$!; sleep 1
try 'firewalld running, port not opened' 8081
firewall-cmd -q --add-port=8081/tcp; try 'after --add-port=8081/tcp' 8081
firewall-cmd -q --reload; try 'after --reload (rule was runtime only)' 8081
kill $D; systemctl stop firewalld
ip netns del wlcli
say 'cleanup'; ip -br link | grep -c wlsrv; nft list tables | grep -c wltest
