# Battery for networking.routing-and-gateways. THROWAWAY VM ONLY, as root. Routes only to single test
# addresses and 203.0.113.0/24; removes them. Never touches the default route.
export LC_ALL=C
run() { printf '$ %s\n' "$*"; eval "$*" 2>&1 </dev/null; printf '[exit %s]\n' "$?"; }
. /etc/os-release; echo "$PRETTY_NAME"
run 'ip route show'
run 'ip route get 10.0.2.3'
run 'ip route get 1.1.1.1'
run 'ping -c 2 -W 2 1.1.1.1'
run 'ip route add 1.1.1.1/32 via 10.0.2.50'
run 'ip route get 1.1.1.1'
run 'ping -c 2 -W 2 1.1.1.1'
run 'ip neigh show'
run 'ip route del 1.1.1.1/32'
run 'ip route add 203.0.113.0/24 via 10.0.2.2 metric 1'
run 'ip route add 203.0.113.77/32 via 10.0.2.3 metric 500'
run 'ip route get 203.0.113.77'
run 'ip route get 203.0.113.78'
run 'ip route del 203.0.113.0/24'
run 'ip route del 203.0.113.77/32'
run 'ip route add blackhole 203.0.113.0/24'
run 'ip route get 203.0.113.5'
run 'ping -c 1 -W 1 203.0.113.5'
run 'ip route del blackhole 203.0.113.0/24'
run 'ip route show'
