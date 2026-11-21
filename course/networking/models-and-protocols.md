*Draft for owner review.* "The network" is not one thing. It is a stack of small jobs, each done by a different piece of software or hardware, and each able to fail on its own. Once you can say which job a symptom belongs to, you know which tool to reach for. This lesson gives you that map. Later lessons go deep on each part.

Addresses in the examples are samples. Documentation ranges (`192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`) and `192.168.1.0/24` stand in for real addresses. The command output formats are real.

## Why layers

Sending a web page across the world involves electrical signals, wireless radio, addressing, routing, reliable delivery and an application that understands HTTP. No single program does all of that. Networking splits it into **layers**. Each layer:

- does one job,
- offers a simple service to the layer above it,
- uses the layer below it without caring how it works.

That is why a web browser works the same over Wi-Fi, Ethernet or a mobile connection: the browser only deals with the top layer, and the lower layers change underneath it.

## Two models

The **OSI model** has seven layers. It is a teaching and troubleshooting vocabulary: people say "that is a layer 2 problem" all the time. The **TCP/IP model** has four layers and describes what the internet actually runs. They line up like this:

| OSI layer | Name | TCP/IP layer | What it does | Examples |
|---|---|---|---|---|
| 7 | Application | Application | the service the user wants | HTTP, DNS, SMTP, SSH, SMB |
| 6 | Presentation | Application | data format, encryption | TLS, character encodings |
| 5 | Session | Application | starting and ending conversations | session handling inside TLS, RPC |
| 4 | Transport | Transport | delivery between programs, ports | TCP, UDP |
| 3 | Network | Internet | addressing and routing between networks | IP, ICMP, routers |
| 2 | Data link | Link | delivery on one local network, MAC addresses | Ethernet, Wi-Fi, switches |
| 1 | Physical | Link | signals on a wire, fibre or radio | cables, NICs, hubs, radio |

A memory aid, top to bottom: **A**ll **P**eople **S**eem **T**o **N**eed **D**ata **P**rocessing. Do not worry about layers 5 and 6; in practice you will say "layer 7" for anything application-level.

Where things live:

- A **hub** repeats bits (layer 1). Almost never seen now.
- A **switch** forwards frames by MAC address (layer 2).
- A **router** forwards packets by IP address between networks (layer 3).
- A **firewall** filters at layer 3 and 4 (addresses and ports), and application-aware ones at layer 7.
- A **wireless access point** joins Wi-Fi clients to a wired network (layers 1 and 2).

## Encapsulation: wrapping data on the way out

When a program sends data, each layer wraps what it received from above with its own **header** (and, at layer 2, a trailer). The receiver unwraps in reverse. Each layer has a name for its unit of data (the **PDU**):

| Layer | Unit | What the header adds |
|---|---|---|
| Application | data | the request itself, for example an HTTP request |
| Transport | **segment** (TCP) or **datagram** (UDP) | source and destination **port**, sequence numbers (TCP) |
| Network | **packet** | source and destination **IP address**, TTL |
| Data link | **frame** | source and destination **MAC address**, error check |
| Physical | bits | electrical, optical or radio signal |

The two addresses do different jobs, and confusing them is the most common beginner mistake:

- The **IP address** ([RFC 791](https://www.rfc-editor.org/rfc/rfc791)) names the final destination and stays the same end to end.
- The **MAC address** names only the next hop on the current local network and is rewritten at every router.

So when you browse to a site across the internet, your frame is addressed to your *router's* MAC address, but the packet inside is addressed to the *server's* IP address.

## TCP and UDP

The transport layer chooses between two behaviours.

**TCP** (Transmission Control Protocol, [RFC 9293](https://www.rfc-editor.org/rfc/rfc9293)) is **connection-oriented and reliable**. It numbers data, acknowledges it, resends what is lost and delivers it in order. Web, mail, file transfer and remote administration use it, because losing a byte would corrupt the result.

Before any data flows, TCP does a **three-way handshake**:

1. Client sends **SYN** ("I want to talk, my starting number is X").
2. Server answers **SYN-ACK** ("OK, mine is Y, I got X").
3. Client sends **ACK** ("got Y").

Closing uses **FIN** (or **RST** to abort at once). These flags matter when you troubleshoot: a **refused** connection means the server's side answered the SYN with a **RST** (nothing is listening, or a firewall rejected it); a **timed-out** connection means no answer came back at all (a firewall dropped it, or there is no route).

**UDP** (User Datagram Protocol, [RFC 768](https://www.rfc-editor.org/rfc/rfc768)) is **connectionless**. It just sends a datagram and does not check that it arrived. That is faster and lighter, so it suits things where a late answer is worse than a lost one, or where the application handles loss itself: DNS queries, DHCP, NTP time, voice and video, and many games.

| | TCP | UDP |
|---|---|---|
| Connection set-up | yes (handshake) | no |
| Delivery guaranteed and in order | yes | no |
| Overhead | higher | lower |
| Typical use | web, mail, SSH, file shares | DNS, DHCP, NTP, streaming, VoIP |

## Ports: which program

An IP address finds a machine. A **port number** (0 to 65535) finds the program on it. A connection is identified by four things: source IP, source port, destination IP, destination port. Your browser picks a random **ephemeral** source port (usually above 49152 on Windows and 32768 on Linux) and connects to the server's **well-known** port.

The official list is the [IANA port registry](https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.xhtml). Ports are grouped as **well-known** (0 to 1023), **registered** (1024 to 49151) and **dynamic/ephemeral** (49152 up). You do not need all of them. Know these cold:

| Port | Protocol | Service | Notes |
|---|---|---|---|
| 20, 21 | TCP | FTP | file transfer, cleartext; avoid |
| 22 | TCP | SSH | encrypted remote shell, also SFTP and SCP |
| 23 | TCP | Telnet | remote shell in cleartext; avoid |
| 25 | TCP | SMTP | mail between servers |
| 53 | UDP and TCP | DNS | UDP for normal queries, TCP for large answers and zone transfers |
| 67, 68 | UDP | DHCP | 67 is the server, 68 the client |
| 69 | UDP | TFTP | simple file transfer, used for network boot and devices |
| 80 | TCP | HTTP | web, cleartext |
| 88 | TCP and UDP | Kerberos | Active Directory authentication |
| 110, 995 | TCP | POP3, POP3 over TLS | mail download |
| 123 | UDP | NTP | time synchronisation |
| 135 | TCP | RPC endpoint mapper | Windows management traffic |
| 143, 993 | TCP | IMAP, IMAP over TLS | mail access |
| 161, 162 | UDP | SNMP | device monitoring; 162 carries traps |
| 389, 636 | TCP | LDAP, LDAP over TLS | directory access |
| 443 | TCP | HTTPS | web over TLS |
| 445 | TCP | SMB | Windows file and printer sharing |
| 514 | UDP | Syslog | log forwarding |
| 587 | TCP | SMTP submission | mail clients sending mail |
| 3389 | TCP | RDP | Windows Remote Desktop |
| 5985, 5986 | TCP | WinRM | PowerShell remoting over HTTP, HTTPS |

The service is not always on its usual port. A port number is a convention; the protocol is what matters. That is why you check what is *actually* listening rather than assuming.

## ICMP: the network talking about itself

`ping` and `tracert` ([ping](https://learn.microsoft.com/windows-server/administration/windows-commands/ping), [tracert](https://learn.microsoft.com/windows-server/administration/windows-commands/tracert)) use **ICMP** ([RFC 792](https://www.rfc-editor.org/rfc/rfc792)), a layer 3 helper protocol that carries error and test messages ("destination unreachable", "echo request", "time exceeded"). ICMP has no ports. This explains a common puzzle:

```
Test-NetConnection -ComputerName 127.0.0.1 -Port 9

ComputerName           : 127.0.0.1
RemoteAddress          : 127.0.0.1
RemotePort             : 9
InterfaceAlias         : Loopback Pseudo-Interface 1
SourceAddress          : 127.0.0.1
PingSucceeded          : True
PingReplyDetails (RTT) : 0 ms
TcpTestSucceeded       : False
```

`PingSucceeded : True` and `TcpTestSucceeded : False` at once ([`Test-NetConnection`](https://learn.microsoft.com/powershell/module/nettcpip/test-netconnection) reference). The host is reachable (layer 3 works) but nothing is accepting connections on TCP port 9 (layer 4). A working ping does **not** mean the service works, and a failing ping does not always mean the host is down: many firewalls block ICMP on purpose.

## Local delivery: MAC addresses, ARP and switches

On one local network, devices find each other by **MAC address**, a 48-bit hardware address written like `1a-5a-fc-83-01-3b` (Windows) or `1a:5a:fc:83:01:3b` (Linux). The first half identifies the maker.

Before your computer can send a frame to a neighbour or to its gateway, it must learn that machine's MAC from its IP. It asks by broadcasting **ARP** ([RFC 826](https://www.rfc-editor.org/rfc/rfc826); Windows [`arp`](https://learn.microsoft.com/windows-server/administration/windows-commands/arp)) ("who has 192.168.1.1? tell 192.168.1.20") and remembers the answer in the **ARP cache**:

```
arp -a

Interface: 192.168.1.20 --- 0xf
  Internet Address      Physical Address      Type
  192.168.1.1           aa-bb-cc-00-11-22     dynamic
  192.168.1.255         ff-ff-ff-ff-ff-ff     static
  224.0.0.22            01-00-5e-00-00-16     static
```

In PowerShell, [`Get-NetNeighbor`](https://learn.microsoft.com/powershell/module/nettcpip/get-netneighbor)` -AddressFamily IPv4` shows the same table with a state column (`Reachable`, `Stale`, `Permanent`). On Linux, `ip neigh` ([ip-neighbour(8)](https://man7.org/linux/man-pages/man8/ip-neighbour.8.html)).

A **switch** learns which MAC address is on which of its ports by watching source addresses, then sends each frame only out of the port that leads to its destination. A frame for an unknown destination, and every **broadcast** (destination `ff-ff-ff-ff-ff-ff`), goes out of every port. The set of devices that receive each other's broadcasts is a **broadcast domain**. A router separates broadcast domains. This is why subnets and routers exist, which the next lessons cover.

If ARP fails you see the symptom "destination host unreachable" from your own address, or a gateway that cannot be reached even though the address looks right.

## Reading what is open on a machine

The transport layer is where a service becomes visible. This lists what a machine is *listening* on, using only built-in tools ([`netstat`](https://learn.microsoft.com/windows-server/administration/windows-commands/netstat)):

```
netstat -an

Active Connections

  Proto  Local Address          Foreign Address        State
  TCP    0.0.0.0:135            0.0.0.0:0              LISTENING
  TCP    0.0.0.0:445            0.0.0.0:0              LISTENING
  TCP    0.0.0.0:5985           0.0.0.0:0              LISTENING
```

`0.0.0.0` means "on every address of this machine". A line such as `127.0.0.1:8080` means the service accepts connections **only from the machine itself**; that is a very common reason "it works locally but not from the network".

[`Get-NetTCPConnection`](https://learn.microsoft.com/powershell/module/nettcpip/get-nettcpconnection) can also tell you which program owns the port:

```
Get-NetTCPConnection -State Listen -LocalPort 135

LocalAddress LocalPort  State OwningProcess
------------ ---------  ----- -------------
::                 135 Listen          1892
0.0.0.0            135 Listen          1892

(Get-Process -Id 1892).ProcessName
svchost
```

On Linux, `ss -tlnp` ([ss(8)](https://man7.org/linux/man-pages/man8/ss.8.html)) does it (`-t` TCP, `-l` listening, `-n` numbers, `-p` process; `-p` needs `sudo` to show other users' processes).

## Putting the layers to work

When something does not work, ask which job failed:

| Symptom | Layer to suspect | First check |
|---|---|---|
| No link light, "network cable unplugged", Wi-Fi not connected | 1 and 2 | adapter status, cable, Wi-Fi state |
| Cannot reach other machines on the same network | 2 and 3 | IP address and mask, `arp -a`, duplicate address |
| Can reach the local network, not other networks | 3 | default gateway, routing table |
| Can ping a site by address but not by name | 7 (DNS) | `nslookup`, DNS server setting |
| Name resolves, ping works, page will not load | 4 and 7 | port reachable? service running? firewall? |
| One program fails, others are fine | 7 | the application's own log and configuration |

Test from the bottom up, and stop at the first layer that fails. The next lesson turns this table into a routine you can follow on a real machine.

## Common mistakes

- **Treating ping as proof the service works.** It proves layer 3 only.
- **Mixing up the two addresses.** The MAC changes at every hop; the IP does not.
- **Assuming a port number identifies the service.** Check what is listening and which process owns it.
- **Forgetting the direction.** A firewall rule that allows a client to connect out does not allow connections in.
- **Reading `127.0.0.1` as "the network."** It is the machine talking to itself and proves nothing about the network.

## Check yourself

1. At which layer does a switch work? A router? Which address does each one use to decide where to send something?
2. A colleague says "I can ping the server but the website is down." Name two layers where the fault could be and one command for each.
3. Why does DNS use UDP for most queries but TCP for some?
4. What is the difference between a connection that is *refused* and one that *times out*?
5. A service is listening on `127.0.0.1:8080`. Can another computer on the network reach it? Why?
6. You send a packet to a server on the internet. Whose MAC address is in the frame, and whose IP address is in the packet?

**Answers.** (1) Switch: layer 2, MAC address. Router: layer 3, IP address. (2) Layer 4 (port closed or blocked: `Test-NetConnection -Port 80`) and layer 7 (the web service itself failing: its error log, or a request that returns an error code). (3) A small question and answer fit in one datagram, which is cheap and fast; an answer too large for one datagram, or a bulk transfer such as a zone transfer, needs TCP's reliability. (4) Refused: the host answered with a reset, so it is reachable but nothing accepts that port (or a firewall rejects it). Timed out: no reply at all, which points to a firewall dropping packets, a wrong address or no route. (5) No: it accepts only local connections. (6) The MAC address of your router (the next hop); the IP address of the server.

## Practice

There is no lab for this lesson on its own; it supplies the vocabulary for the labs in the lessons that follow. When you finish `networking.addressing-and-names`, return here and try to name the layer of each lab problem before you start.
