#!/bin/bash
# Run INSIDE a Linux lab VM. Reports what the guest can reach. run-probe.ps1 appends the host values.
try() { # try NAME COMMAND... : prints REACHED or blocked
  local name=$1; shift
  if "$@" >/dev/null 2>&1; then echo "$name=REACHED"; else echo "$name=blocked"; fi
}
tcp() { timeout 6 bash -c "exec 3<>/dev/tcp/$1/$2"; }
try host-loopback-tcp4   tcp 10.0.2.2 "$TCP4"
try host-loopback-tcp6   tcp fec0::2 "$TCP6"
echo wl | timeout 3 bash -c "cat > /dev/udp/10.0.2.2/$UDP4" 2>/dev/null; echo "host-loopback-udp4=sent (see host side)"
try host-smb-via-gateway tcp 10.0.2.2 445
for ip in $LANIPS; do try "host-lan-address-smb" tcp "$ip" 445; done
try dns-lookup           timeout 8 getent ahostsv4 example.com
try internet-by-name     tcp example.com 443
try internet-by-ip       tcp 1.1.1.1 443
try internet-ping        ping -c 2 -W 3 1.1.1.1
try gateway-ping         ping -c 2 -W 3 10.0.2.2
echo "routes: $(ip -4 route | tr '\n' ';')"
# Raw DNS queries to QEMU's built-in resolver addresses (a common way to smuggle data out).
dnsq() { timeout 8 python3 -I -c '
import socket,sys
fam = socket.AF_INET6 if ":" in sys.argv[1] else socket.AF_INET
s = socket.socket(fam, socket.SOCK_DGRAM); s.settimeout(5)
q = b"\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01"
s.sendto(q, (sys.argv[1], 53)); r = s.recv(512)
sys.exit(0 if r[:2] == b"\x12\x34" and r[7] > 0 else 1)' "$1"; }
try raw-dns-ipv4         dnsq 10.0.2.3
try raw-dns-ipv6         dnsq fec0::3
echo "network-interfaces: $(ls /sys/class/net | tr '\n' ' ')"
