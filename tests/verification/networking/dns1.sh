# Battery for networking.dns. THROWAWAY VM ONLY, as root. Installs dig (bind-utils) and dnsmasq, runs a
# private dnsmasq on 127.0.0.1 port 5353 with made-up names under wl.test, and stops it afterwards.
export LC_ALL=C
say() { printf '\n=== %s\n' "$*"; }
run() { printf '$ %s\n' "$*"; eval "$*" 2>&1 </dev/null; printf '[exit %s]\n' "$?"; }
. /etc/os-release; echo "$PRETTY_NAME"
dnf -y -q install bind-utils dnsmasq >/dev/null 2>&1; command -v dig dnsmasq || { echo "tools not available"; exit 1; }
dig -v 2>&1 | head -1
dnsmasq --keep-in-foreground --conf-file=/dev/null --port=5353 --listen-address=127.0.0.1 --bind-interfaces \
  --no-resolv --no-hosts --local=/wl.test/ --local-ttl=60 \
  --host-record=app.wl.test,192.0.2.10 --cname=www.wl.test,app.wl.test \
  --mx-host=wl.test,mail.wl.test,10 --host-record=mail.wl.test,192.0.2.25 >/tmp/wl-dnsmasq.log 2>&1 & D=$!
sleep 1
Q='dig @127.0.0.1 -p 5353'
say 'a normal answer, in full'
run "$Q app.wl.test"
say 'an alias'
run "$Q www.wl.test +noall +answer"
say 'a name that does not exist'
run "$Q nothere.wl.test +noall +comments"
say 'a name that exists but has no record of that type'
run "$Q app.wl.test AAAA +noall +comments"
run "$Q app.wl.test AAAA +short"
run "$Q nothere.wl.test +short"
say 'a server that will not answer for that name'
run "$Q example.org +noall +comments"
say 'no server there at all'
run "dig @10.255.255.1 app.wl.test +tries=1 +time=2"
run "dig @127.0.0.1 -p 5999 app.wl.test +tries=1 +time=2"
say 'reverse lookup'
run "$Q -x 192.0.2.10 +noall +answer"
say 'MX'
run "$Q wl.test MX +noall +answer"
say 'TCP'
run "$Q app.wl.test +tcp +noall +answer +stats | grep -E 'IN|SERVER'"
say 'dig and nslookup ignore the hosts file; getent does not'
cp /etc/hosts /root/wl-hosts.bak; echo '198.51.100.7 app.wl.test' >> /etc/hosts
run "$Q app.wl.test +short"
run 'getent hosts app.wl.test'
cp /root/wl-hosts.bak /etc/hosts; rm /root/wl-hosts.bak
say 'TTL from a caching resolver counts down'
run 'dig example.com A +noall +answer'
sleep 5
run 'dig example.com A +noall +answer'
run 'dig example.com A | grep -E "status:|flags:|SERVER"'
kill $D; wait $D 2>/dev/null
say 'after stopping the private server'
run "$Q app.wl.test +tries=1 +time=2"
