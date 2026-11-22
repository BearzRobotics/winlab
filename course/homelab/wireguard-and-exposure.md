*Draft for owner review.* The safest way to reach your home lab from outside is to **not expose it**: publish **one** small door that only answers to people holding the right key, and reach everything else (file shares, admin pages, SSH) through it. **WireGuard** is a modern VPN built for exactly that. This lesson builds a WireGuard tunnel between two **network namespaces** on one VM (a hub and a peer joined by a virtual cable standing in for the internet), shows what the tunnel does and does not allow, tests what a stranger without a key sees, and ends with a short checklist for deciding what to expose. Everything is inside the lab VMs; **no real network or router is changed.**

**What was tested, and where.** As root on **Ubuntu 24.04.5** (kernel 6.8.0-147, `wireguard-tools` **v1.0.20210914** from `apt-get install wireguard-tools`) and **AlmaLinux 9.8** (kernel 5.14.0-687, the same tools version from EPEL: `dnf install epel-release` then `dnf install wireguard-tools`). The `wireguard` kernel module loaded on both with `modprobe wireguard` (`lsmod` showed it). `tests/verification/homelab/hl4.sh`; output is real, keys shortened. **Not tested:** a real internet connection, **NAT and router port forwarding** (the namespaces are one hop apart), a firewall (the namespaces have none, and `firewalld` is not installed on the AlmaLinux image), IPv6, **routing a whole LAN through the hub** (`net.ipv4.ip_forward` and masquerading), full-tunnel versus split-tunnel DNS, `wg-quick@` as a **systemd service** (I ran `wg-quick up` by hand), key rotation, a phone or Windows client, throughput and MTU problems on real links, and dynamic DNS for a home address that changes.

## What WireGuard is, in five facts

- It runs as a **network interface** (`wg0`, here `wg-hub`) inside the kernel. Anything routed to that interface is encrypted and sent to the right peer.
- Each side has a **key pair**: a **private key** that never leaves the machine and a **public key** you give to the other side. There are no passwords or certificates to manage.
- **Cryptokey routing**: the project's home page describes it as "associating public keys with a list of tunnel IP addresses that are allowed inside the tunnel" (the **`AllowedIPs`** setting). It is both the routing table *and* the access list.
- It speaks **UDP** on one port you choose (51820 by default in the examples).
- It is deliberately quiet: the [protocol page](https://www.wireguard.com/protocol/) says the server "does not even respond at all to an unauthorized client; it is silent and invisible" (the sentence continues: "it is silent and invisible"). The [quickstart](https://www.wireguard.com/quickstart/) adds that "by default, WireGuard tries to be as silent as possible when not being used".

## Keys

Each side makes its own pair; only **public** keys are exchanged. The `umask 077` makes the files readable by you alone:

```text
$ umask 077
$ wg genkey | tee hub.key | wg pubkey > hub.pub
$ ls -l hub.key hub.pub | awk '{print $1, $9}'
-rw------- hub.key
-rw------- hub.pub
$ wc -c < hub.pub
45                                          (44 base64 characters and a newline)
```

A leaked **private** key lets someone be that machine; a leaked **public** key is harmless. Do not paste private keys into chats, tickets or scripts you share.

## The lab: two namespaces and a virtual cable

```text
 [wlpeer namespace]                 [wlhub namespace]
 wlv-peer 10.99.0.2  <----- veth ----->  wlv-hub 10.99.0.1     (the "internet": plain, unencrypted)
 wg-peer  10.8.0.2   <=== tunnel ===>   wg-hub  10.8.0.1       (WireGuard addresses)
```

```bash
ip netns add wlhub; ip netns add wlpeer
ip link add wlv-hub type veth peer name wlv-peer
ip link set wlv-hub netns wlhub; ip link set wlv-peer netns wlpeer
ip -n wlhub  addr add 10.99.0.1/24 dev wlv-hub;  ip -n wlhub  link set wlv-hub  up
ip -n wlpeer addr add 10.99.0.2/24 dev wlv-peer; ip -n wlpeer link set wlv-peer up
ip netns exec wlpeer ping -c1 -W2 10.99.0.1        # the plain link works: 1 received
```

(A namespace is a separate set of interfaces and routes; see [ip-netns(8)](https://man7.org/linux/man-pages/man8/ip-netns.8.html) and the WireGuard project's own page on [routing and network namespaces](https://www.wireguard.com/netns/), which I confirmed exists but did not follow step by step.)

## The configuration files

`wg-quick` reads one file per interface. **The file name is the interface name**: `wg-hub.conf` makes the interface `wg-hub`.

```text
# wg-hub.conf (the home hub)
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = <hub's private key>

[Peer]
# the laptop
PublicKey = <peer's public key>
AllowedIPs = 10.8.0.2/32

# wg-peer.conf (the laptop)
[Interface]
Address = 10.8.0.2/24
PrivateKey = <peer's private key>

[Peer]
# the home hub
PublicKey = <hub's public key>
Endpoint = 10.99.0.1:51820
AllowedIPs = 10.8.0.0/24
PersistentKeepalive = 25
```

Read them as two sentences. The hub says: "I listen on UDP 51820. The peer with this public key may use tunnel address `10.8.0.2` and nothing else." The laptop says: "To reach `10.8.0.0/24`, send to the hub at `10.99.0.1:51820`, and poke it every 25 seconds so a NAT in between keeps the path open." `PersistentKeepalive` matters for a laptop behind a home router (a NAT forgets idle UDP flows); the hub does not need it.

Bringing them up (inside each namespace):

```text
$ ip netns exec wlhub  wg-quick up conf/wg-hub.conf
[#] ip link add wg-hub type wireguard
[#] wg setconf wg-hub /dev/fd/63
[#] ip -4 address add 10.8.0.1/24 dev wg-hub
[#] ip link set mtu 1420 up dev wg-hub
```

(The same four steps for `wg-peer`.) `wg-quick` is a convenience script: it just runs those `ip` and `wg` commands. Note **`mtu 1420`**: the tunnel adds its own headers to every packet, so `wg-quick` sets the tunnel interface smaller than the usual 1500 (I did not look up the exact overhead). A wrong MTU is a classic cause of "ping works but big downloads hang"; I did not test that failure.

## It works, and what the tunnel shows

```text
$ ip netns exec wlpeer ping -c2 -W2 10.8.0.1
2 packets transmitted, 2 received, 0% packet loss
rtt min/avg/max/mdev = 0.513/0.660/0.807/0.147 ms
$ ip netns exec wlhub wg show
interface: wg-hub
  public key: n1diozRB...
  private key: (hidden)
  listening port: 51820

peer: 7YK+L/HR...
  endpoint: 10.99.0.2:47994
  allowed ips: 10.8.0.2/32
  latest handshake: 1 second ago
  transfer: 436 B received, 348 B sent
```

(AlmaLinux: `rtt` about 0.35 ms and the same `wg show` shape.) Three things on that screen are worth knowing how to read. **`latest handshake`** is the proof that the two sides authenticated each other; no handshake means the keys, the port or the path is wrong. **`endpoint`** is where the hub saw the peer come from (a random source port 47994): it **learns** the peer's address from the traffic, which is how roaming laptops work. **`transfer`** counts bytes, so you can see traffic move without capturing packets. `wg show` hides private keys by default (`(hidden)`).

The peer's routing table gained one line: `10.8.0.0/24 dev wg-peer proto kernel scope link src 10.8.0.2`. Traffic to the tunnel network goes into `wg-peer`; everything else (`10.99.0.0/24` here) still goes the normal way. That is a **split tunnel**: only the tunnel's addresses use the VPN. A **full tunnel** (`AllowedIPs = 0.0.0.0/0`) sends everything through the hub; it needs more setup (forwarding and NAT on the hub, DNS) that I did not test.

## `AllowedIPs` is also the access list

On the hub, send to a tunnel address that **no peer owns**:

```text
$ ip netns exec wlhub ping -c1 -W1 10.8.0.9
PING 10.8.0.9 (10.8.0.9) 56(84) bytes of data.
From 10.8.0.1 icmp_seq=1 Destination Host Unreachable
```

The hub does not know which key `10.8.0.9` belongs to, so it cannot encrypt a packet for it, and the packet is dropped. The same rule works in reverse: the project's home page says a packet received from a peer is allowed onto the interface only if its **source address** matches that peer's allowed IPs, "otherwise it's dropped" (I did not test spoofing). So `AllowedIPs = 10.8.0.2/32` on the hub is the whole firewall policy for that peer, at the tunnel layer. (It does not limit *which ports* the peer may reach inside the lab; that needs a firewall behind the tunnel.)

## A stranger without a registered key

I added a third namespace, `wlrogue`, with its own freshly generated key that the hub knows nothing about, and an endpoint pointing at the hub:

```text
$ ip netns exec wlrogue ping -c2 -W2 10.8.0.1
2 packets transmitted, 0 received, 100% packet loss
$ ip netns exec wlrogue bash -c 'exec 3<>/dev/udp/10.98.0.1/51820; echo hello >&3; timeout 2 cat <&3; echo "reply status $?"'
reply status 124                           (124 is timeout's "nothing arrived in 2 seconds")
$ ip netns exec wlhub wg show wg-hub peers | wc -l
1                                          (still only the one known peer)
```

The stranger could not reach anything, and a plain UDP datagram sent to the WireGuard port got **no answer at all**, as the protocol page says it should. That is what makes WireGuard a good single door: **a port scan sees nothing to talk to**. Be careful with the conclusion: for UDP, "no reply" also happens when a firewall drops the packet, so a scanner reports such ports as `open|filtered` (nmap's wording), not "closed"; I did not run a UDP scan here. Silence is a property of the protocol, not proof that nothing is there.

(One bug of mine, for the record: I generated the third config with `sed "s/^PrivateKey.*/PrivateKey = $(cat rogue.key)/"`. WireGuard keys are base64 and can contain `/`, so on Ubuntu the key broke the `sed` expression (`unknown option to s`), while on AlmaLinux the keys happened not to contain one and it worked by luck. Use a different delimiter (`s|a|b|`) when a value can contain the usual one.)

Taking the tunnel down:

```text
$ ip netns exec wlpeer wg-quick down conf/wg-peer.conf
[#] ip link delete dev wg-peer
$ ip netns exec wlpeer ping -c1 -W1 10.8.0.1
ping: connect: Network is unreachable
```

## What to expose, and what not to

Put the rest of the track to work. A short decision list for any service you consider reaching from outside:

1. **List what listens** (`ss -tlnp`, from `security.own-lab-recon`). Every line is a candidate door.
2. **Default answer: do not forward it from the router.** Reach it through the tunnel instead.
3. **If it must face the internet**, expose only things built for it, kept patched, with key-only logins (`security.linux-hardening-checks`), logs you read (`security.linux-logging-and-detection`) and a threat-table row (`security.threat-modelling`).
4. **Never expose, without a very good reason:** file sharing (SMB on 445, the previous lesson), remote desktop, database ports, admin web interfaces, `rpcbind` (111, which the AlmaLinux image listens on), DNS that answers anyone (an **open resolver** can be used to attack others), anything with a default password.
5. **Expose one UDP port for WireGuard** and nothing else, if you need access at all. Keep the private key off the shared systems.
6. **Check from outside**, with a scan you are authorised to run against your own address (see the scope lesson). A mistaken forward is easy to make and easy to find.
7. **Home routers are someone's firmware.** Remote administration of the router itself should be off; the router's own admin page is not yours to scan in this course.

I did not test any of this against a real router or the real internet; it is a list of habits that follow from the tested pieces.

## Common mistakes

- **Wrong `AllowedIPs`.** Too narrow on one side and traffic is dropped; too wide on the hub and a peer may claim addresses it should not.
- **Putting the private key where others can read it.** `umask 077`, and never share it.
- **No `PersistentKeepalive` for a peer behind NAT.** The path closes after a quiet period.
- **Expecting a handshake without traffic.** WireGuard is silent until it has something to send; `latest handshake` appears after the first packet.
- **Opening the UDP port and forgetting the firewall for everything else.** The tunnel does not restrict ports inside the lab.
- **Using `sed` with `/` on base64 data.**
- **Believing silence proves safety.** A silent UDP port reads as `open|filtered`, not "closed".
- **Reaching the hub's LAN without enabling forwarding.** Routing beyond the hub itself needs `ip_forward` and rules (not tested).

## Check yourself

1. Build the two-namespace tunnel. Show a handshake in `wg show` and explain each line.
2. Add a third peer with an unregistered key. What does it see, and what does the hub's `wg show` list?
3. What does `AllowedIPs = 10.8.0.2/32` on the hub control? What does it not control?
4. Why does the tunnel interface have MTU 1420?
5. Pick three services in your lab and decide for each: expose, tunnel, or keep internal. Say why.

## Not tested, and honest limits

Anything over a real network, router or NAT; a firewall; forwarding and full tunnels; DNS inside the tunnel; `wg-quick@` under systemd; Windows and phone clients; key rotation; performance. The two namespaces share one kernel, so this shows the configuration and behaviour, not the effect of real network conditions. A UDP scan of the WireGuard port was not run.
