*Draft for owner review.* Most "the network is down" reports are really one of four things: no address, wrong gateway, wrong DNS, or a blocked port. This lesson gives you the model and the routine to tell them apart, using only tools that ship with Windows and Linux. It is the overview; the lessons on subnetting, DHCP, DNS, routing and ports go deep on each layer, and this one shows how to use them together.

Addresses in the examples are samples; the layout is real output.

## The layers you actually use

| Layer | Question it answers | Typical evidence | Deep lesson |
|---|---|---|---|
| Link | Is there a connection to the local network? | adapter status, cable or Wi-Fi state | models and protocols |
| Address (IP) | Does this machine have a usable address and mask? | `ipconfig`, `ip addr` | subnetting, DHCP |
| Routing | Can it reach other networks? | default gateway, `route print`, `ip route` | routing and gateways |
| Names (DNS) | Does a name turn into an address? | `nslookup`, `Resolve-DnsName`, `getent hosts` | DNS |
| Transport | Is the service port reachable? | `Test-NetConnection -Port`, `ss -tln` | ports and firewalls |

Test from the bottom up. Each layer you prove narrows the problem, and a fault at a lower layer makes every layer above it look broken. A dead cable looks like "DNS is down" to the user.

## Addresses

An IPv4 address has four numbers (`192.168.1.20`) and a **prefix length** (`/24`, the mask `255.255.255.0`) that says which part names the network ([RFC 791](https://www.rfc-editor.org/rfc/rfc791) defines IPv4; the subnetting lesson covers the arithmetic). Machines on the same network talk directly; anything else goes to the **default gateway**.

Private ranges, not routed on the internet ([RFC 1918](https://www.rfc-editor.org/rfc/rfc1918)): `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`. An address starting `169.254` is **link-local** ([RFC 3927](https://www.rfc-editor.org/rfc/rfc3927)): the machine asked for one by DHCP and got no answer, so it made one up. Windows calls that APIPA.

**DHCP** hands out an address, mask, gateway and DNS servers automatically. A **static** address is typed in by an administrator. Two machines with the same address cause intermittent failures that are hard to read from either one.

### Reading your own configuration

Windows, Command Prompt and PowerShell:

```
ipconfig /all
Get-NetIPConfiguration
Get-NetIPAddress -AddressFamily IPv4 | Format-Table InterfaceAlias,IPAddress,PrefixLength,PrefixOrigin
```

```
InterfaceAlias IPAddress    PrefixLength PrefixOrigin
-------------- ---------    ------------ ------------
Wi-Fi          192.168.1.20           24         Dhcp
```

`PrefixOrigin` tells you where the address came from: `Dhcp`, `Manual`, or `WellKnown` for the link-local fallback. See [`ipconfig`](https://learn.microsoft.com/windows-server/administration/windows-commands/ipconfig) and [`Get-NetIPConfiguration`](https://learn.microsoft.com/powershell/module/nettcpip/get-netipconfiguration).

Linux:

```
ip -br addr
ip route show
```

```
lo       UNKNOWN  127.0.0.1/8 ::1/128
wlan0    UP       192.168.1.20/24
```

The brief (`-br`) form shows each interface, its state and its addresses on one line. See [ip(8)](https://man7.org/linux/man-pages/man8/ip.8.html).

## Names

**DNS** turns a name into an address (the DNS lesson explains how). Before asking DNS, machines check a local list (`C:\Windows\System32\drivers\etc\hosts`, `/etc/hosts`); a stale line there overrides DNS silently. On Linux `/etc/nsswitch.conf` sets the order ([nsswitch.conf(5)](https://man7.org/linux/man-pages/man5/nsswitch.conf.5.html)).

```
nslookup example.com                  # Windows and Linux; asks a DNS server directly
Resolve-DnsName example.com           # PowerShell, returns objects
getent hosts example.com              # Linux, follows nsswitch like applications do
```

If you can reach an address but not a name, the problem is names. If neither works, go lower. Note that `nslookup` ignores the hosts file, while applications do not.

## Ports and services

A service listens on a **port** (HTTP 80, HTTPS 443, SSH 22, RDP 3389, DNS 53). Reaching the machine does not mean reaching the service. The official list is the [IANA port registry](https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.xhtml).

```
Test-NetConnection server01 -Port 3389     # Windows
ss -tln                                    # Linux: what is listening here
```

Three outcomes: connected; refused (the host answered, nothing is listening or it was rejected); timed out (usually a firewall dropping packets). Telling refused from timed out is the most useful single skill here, and the ports and firewalls lesson develops it. See [`Test-NetConnection`](https://learn.microsoft.com/powershell/module/nettcpip/test-netconnection).

## A bottom-up routine

Run these in order and stop at the first failure.

| Step | Windows | Linux | Passing looks like |
|---|---|---|---|
| 1. Link and address | `ipconfig`, `Get-NetAdapter` | `ip -br addr` | adapter up; a sensible address and prefix, not `169.254` |
| 2. Gateway | `ping <gateway>` | `ping <gateway>` | replies; the gateway is inside your subnet |
| 3. Beyond the gateway | `ping 1.1.1.1` | `ping 1.1.1.1` | replies (if ping is blocked, try `Test-NetConnection 1.1.1.1 -Port 443`) |
| 4. A name | `Resolve-DnsName example.com` | `getent hosts example.com` | an address comes back |
| 5. The port | `Test-NetConnection host -Port N` | `nc -vz host N` | `TcpTestSucceeded : True` |

Write down which step first fails. That is your finding, and it picks the lesson to open next:

| First failing step | Probable cause | Next lesson |
|---|---|---|
| 1 | no link, DHCP failure, wrong static address | DHCP, subnetting |
| 2 | wrong gateway or mask, gateway down | routing and gateways |
| 3 | no default route, upstream fault, ICMP blocked | routing and gateways |
| 4 | DNS server wrong, hosts-file override | DNS |
| 5 | service down, bound to loopback, firewall | ports and firewalls |

## A worked example

A user reports "I can't open the intranet site". You run the routine:

1. `ipconfig` shows `192.168.1.20`, mask `255.255.255.0`. Fine.
2. `ping 192.168.1.1` replies. The gateway is up.
3. `ping 1.1.1.1` replies. Routing out works.
4. `Resolve-DnsName intranet.corp.example` returns "DNS name does not exist". **First failure: names.**
5. You try the configured server's address directly: `nslookup intranet.corp.example 192.168.1.1` also fails, but `nslookup intranet.corp.example 10.0.0.53` (the company DNS) answers.

Finding: this laptop's DHCP handed out the router as DNS server instead of the company server, so internal names are unknown to it. Not a network outage at all. The fix is in the DHCP options or the adapter's DNS setting, and you reached it in five commands.

## Common mistakes

- **Starting at the top.** Testing the website first and guessing, instead of climbing from the address.
- **Trusting `ping` as the only test.** It can be blocked while the service works, and it proves nothing about a port.
- **Reading `169.254` as "the network is down".** It says DHCP failed for this machine; check the link and the server.
- **Forgetting the hosts file.** It overrides DNS and `nslookup` will not show it.
- **Changing several things at once.** You then cannot tell which one fixed it.

## Check yourself

1. A machine has `169.254.7.9`. What happened?
2. Ping to an IP works, ping to its name fails. Which layer is at fault?
3. Connection refused versus timed out: what does each suggest?
4. `Get-NetIPAddress` shows `PrefixOrigin : Manual`. What does that mean for DHCP troubleshooting?
5. Which step of the routine do you reach for after steps 1 to 3 pass but a website name will not open?

**Answers.** (1) It asked for an address by DHCP, got no answer, and gave itself a link-local one. (2) Names (DNS, or the hosts file). (3) Refused: the host is reachable but nothing listens on that port; timed out: packets were dropped on the way, usually by a firewall or a routing fault. (4) The address was typed in, not leased, so DHCP is not the cause. (5) Step 4, resolving the name, then step 5 for the port.

## Practice

Work through the routine on a lab VM: record the output of each step and write down the first one that fails, or that none does. Then open the lab `labs.gateway-route-override` and use the table above to say which step it should break before you run it.
