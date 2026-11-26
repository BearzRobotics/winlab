# Battery for networking.addressing-and-names. THROWAWAY VM ONLY, as root: adds one hosts-file line and
# removes it.
export LC_ALL=C
say() { printf '\n=== %s\n' "$*"; }
run() { printf '$ %s\n' "$*"; eval "$*" 2>&1 </dev/null; printf '[exit %s]\n' "$?"; }
. /etc/os-release; echo "$PRETTY_NAME"
run 'ip -br addr'
run 'ip -4 addr show scope global'
run 'ip route show'
gw=$(ip route show default | awk '{print $3; exit}')
run "ping -c 2 -W 2 $gw"
run 'ping -c 2 -W 2 1.1.1.1'
run 'grep -v "^#" /etc/resolv.conf'
run 'grep ^hosts /etc/nsswitch.conf'
say 'three outcomes of a TCP connection'
run 'command -v nc curl'
run 'time curl -sS -m 5 -o /dev/null http://127.0.0.1:8999/'
run 'time curl -sS -m 5 -o /dev/null http://10.255.255.1/'
run "time bash -c 'exec 3<>/dev/tcp/127.0.0.1/22 && head -1 <&3'"
run 'ss -tln'
say 'hosts file'
cp /etc/hosts /root/wl-hosts.bak
echo '192.0.2.77 wl-test.example' >> /etc/hosts
run 'getent hosts wl-test.example'
run 'command -v dig nslookup host'
command -v nslookup >/dev/null && run 'nslookup wl-test.example'
command -v dig >/dev/null && run 'dig +short wl-test.example'
run 'ping -c 1 -W 1 wl-test.example'
cp /root/wl-hosts.bak /etc/hosts; rm /root/wl-hosts.bak
run 'getent hosts wl-test.example'
say 'a name that does not exist'
run 'getent hosts no-such-name.invalid'
run 'curl -sS -m 5 http://no-such-name.invalid/'
