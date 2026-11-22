*Draft for owner review.* Almost every client on every network gets its address from DHCP rather than from a person typing it in. When DHCP works nobody notices it; when it does not, a machine has no usable network and the symptoms look like a dozen other problems. This lesson shows how the exchange works, how to read what it gave you, and how to tell a DHCP fault from everything else.

Addresses in the examples are samples; the field names and layout are real output.

## What DHCP does

**DHCP** (Dynamic Host Configuration Protocol, [RFC 2131](https://www.rfc-editor.org/rfc/rfc2131); the options it carries are in [RFC 2132](https://www.rfc-editor.org/rfc/rfc2132)) lets a machine that knows nothing about its network ask for everything it needs:

- an **IP address** and **subnet mask**,
- the **default gateway** (the router),
- the **DNS servers** and a DNS suffix,
- a **lease time**: how long it may keep the address,
- and optionally many other settings (time servers, boot files, and so on).

A **DHCP server** keeps a pool of addresses and hands them out. Microsoft's server role is described in the [DHCP overview](https://learn.microsoft.com/windows-server/networking/technologies/dhcp/dhcp-top); on small networks the server is usually built into the router. The same protocol is used by Windows, Linux, phones and printers.

## The four-step exchange (DORA)

A client with no address cannot talk to anyone, so the first messages are **broadcasts**. DHCP uses **UDP**: the server listens on port **67** and the client on port **68**.

| Step | Name | Direction | What it says |
|---|---|---|---|
| 1 | **D**iscover | client to everyone (broadcast) | "Is there a DHCP server? I need an address." Sent from `0.0.0.0`. |
| 2 | **O**ffer | server to client | "You may have 192.168.1.20 for 8 hours, with these settings." |
| 3 | **R**equest | client to everyone (broadcast) | "I accept the offer from that server." Broadcast, so any other server that also made an offer knows it was not chosen. |
| 4 | **A**cknowledge | server to client | "Confirmed. The lease starts now." |

Only after the Acknowledge does the client configure its interface. Because step 1 is a broadcast, and broadcasts stop at a router, **a DHCP server must be on the client's own network, or a router must forward the request** (see relay agents below).

## Leases and renewal

The address is *leased*, not owned. The lease has a length (8 hours in the example below, set by the administrator; many home routers use 24 hours). The client does not wait for expiry:

- At about **50 %** of the lease (called T1) it asks its server directly to **renew**.
- If that fails, at about **87.5 %** (T2) it broadcasts to *any* server to **rebind**.
- If the lease expires with no answer, it must stop using the address.

Those percentages are the defaults in [RFC 2131](https://www.rfc-editor.org/rfc/rfc2131); servers can change them. This is why a DHCP server that is down for an hour usually causes no immediate problem for machines that are already running, and why the failures appear later, for machines that restart or whose lease ran out.

## Reading a lease on Windows

[`ipconfig /all`](https://learn.microsoft.com/windows-server/administration/windows-commands/ipconfig) shows every adapter. The DHCP-related lines for one adapter:

```
Wireless LAN adapter Wi-Fi:

   Description . . . . . . . . . . . : Realtek 8821CE Wireless LAN 802.11ac PCI-E NIC
   Physical Address. . . . . . . . . : 14-5A-FC-83-01-3B
   DHCP Enabled. . . . . . . . . . . : Yes
   Autoconfiguration Enabled . . . . : Yes
   IPv4 Address. . . . . . . . . . . : 192.168.1.20(Preferred)
   Subnet Mask . . . . . . . . . . . : 255.255.255.0
   Lease Obtained. . . . . . . . . . : Friday, November 20, 2026 10:55:23 PM
   Lease Expires . . . . . . . . . . : Saturday, November 21, 2026 6:55:23 AM
   Default Gateway . . . . . . . . . : 192.168.1.1
   DHCP Server . . . . . . . . . . . : 192.168.1.1
   DNS Servers . . . . . . . . . . . : 192.168.1.1
```

Read it as a checklist:

- **DHCP Enabled : Yes** means the address came from a server. `No` means someone typed it in (a static address), and this lesson's fault-finding does not apply.
- **Lease Obtained / Lease Expires** give the lease window. Here it is eight hours.
- **DHCP Server** names the machine that answered. If this is an address you do not recognise, see "rogue servers" below.
- **Default Gateway** and **DNS Servers** came from the same offer.

For a tidier summary use [`Get-NetIPConfiguration`](https://learn.microsoft.com/powershell/module/nettcpip/get-netipconfiguration):

```
Get-NetIPConfiguration

InterfaceAlias       : Wi-Fi
InterfaceIndex       : 17
InterfaceDescription : Realtek 8821CE Wireless LAN 802.11ac PCI-E NIC
IPv4Address          : 192.168.1.20
IPv4DefaultGateway   : 192.168.1.1
DNSServer            : 192.168.1.1
```

## Reading a lease on Linux

`ip addr` marks an address that came from DHCP as `dynamic` and shows how long is left (`valid_lft`), counting down:

```
ip addr show eth0

2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 08:00:27:4e:66:a1 brd ff:ff:ff:ff:ff:ff
    inet 192.168.1.20/24 brd 192.168.1.255 scope global dynamic noprefixroute eth0
       valid_lft 28403sec preferred_lft 28403sec
```

A static address shows `valid_lft forever` and no `dynamic`. See [ip-address(8)](https://man7.org/linux/man-pages/man8/ip-address.8.html). On AlmaLinux and most desktop Ubuntu, **NetworkManager** manages the interface, and [`nmcli`](https://networkmanager.dev/docs/api/latest/nmcli.html) can show the options the server sent:

```
nmcli device show eth0
```

**Tested** (2026-11-22; `tests/verification/networking/nl1.sh`). The interface name `eth0` is only an example. On the **AlmaLinux 9.8** lab VM it really was `eth0` (with the alternative name `enp0s3`), `ip addr show eth0` showed `scope global dynamic noprefixroute eth0` with `valid_lft 86362sec`, and `nmcli device show eth0` worked (`GENERAL.CONNECTION: System eth0`, `IP4.GATEWAY: 10.0.2.2`, `IP4.DNS[1]: 10.0.2.3`). On **Ubuntu Server 24.04.5** the interface was `enp0s3`, there was **no `nmcli`** (NetworkManager was inactive; `systemd-networkd` was active with a netplan-generated configuration), `ip addr show enp0s3` showed `dynamic` with `valid_lft 86361sec`, and `networkctl status enp0s3` printed `State: routable (configured)`. I did not look for the `DHCP4.OPTION[...]` lines on AlmaLinux (the part of `nmcli` output I cut off) and did not test a static address.

The `IP4.*` lines give the address, gateway and DNS, and the `DHCP4.OPTION[...]` lines list each option the server supplied (for example `routers`, `domain_name_servers`, `dhcp_lease_time`). Ubuntu Server may use a different network manager (netplan with systemd-networkd), but `ip addr` reads the same either way.

## Scopes, exclusions, reservations and relays

If you administer the server, these are the words you will meet:

- A **scope** is the range of addresses the server may give out for one subnet, for example `192.168.1.100` to `192.168.1.200`, plus the options (gateway, DNS) given with it.
- An **exclusion** removes addresses from that range because something else uses them (a printer with a static address, say). Forgetting this is how two devices end up with the same address.
- A **reservation** always gives one specific device (identified by its MAC address) the same address. It is better than a static address on the device, because the setting lives in one place.
- A **relay agent** (on a router, often called an "IP helper") receives the client's broadcast and forwards it to a DHCP server on another network, adding the address of the client's subnet so the server chooses the right scope. This is how one server can serve many subnets.

## When DHCP fails

**The clearest sign is an address in `169.254.0.0/16`** ([RFC 3927](https://www.rfc-editor.org/rfc/rfc3927)). When a Windows client gets no answer, it gives itself a link-local address (Microsoft calls it APIPA), and `ipconfig` shows it labelled `Autoconfiguration IPv4 Address`:

```
   Autoconfiguration IPv4 Address. . : 169.254.18.7(Preferred)
   Subnet Mask . . . . . . . . . . . : 255.255.0.0
   Default Gateway . . . . . . . . . :
```

There is no gateway, so the machine can talk only to others on the same link. Work out why the Discover got no answer:

| Symptom | Likely cause | Check |
|---|---|---|
| `169.254.x.x`, one machine | cable, Wi-Fi, switch port, or a disabled adapter | link status first; try another port or cable |
| `169.254.x.x`, many machines at once | the DHCP server is down, or its service stopped | the server, or the router's status page |
| `169.254.x.x` on one VLAN or subnet only | no relay agent for that subnet | the router's relay setting for that subnet |
| address in the right range but no internet | wrong gateway or DNS handed out | compare `Default Gateway` and `DNS Servers` with what they should be |
| address in the **wrong** range | a **rogue** DHCP server answered first (for example someone plugged in a home router) | the `DHCP Server` field; if it is not your server, find the device |
| "address already in use" or intermittent loss | two devices with the same address: a static address inside the scope, with no exclusion | `arp -a`, compare MAC addresses for the same IP |
| works, then fails after hours | the lease expired and could not be renewed | when the server was last reachable |
| scope exhausted (new machines get nothing, old ones work) | the pool is full of stale leases | lease time too long for guest or phone networks |

Note that a missing or wrong answer is the **server side**; a client that never sends a Discover (disabled adapter, DHCP turned off on the client) is a different fault, and `DHCP Enabled : No` shows it at once.

## Releasing and renewing the lease

On Windows, from an elevated Command Prompt:

```
ipconfig /release
ipconfig /renew
```

`/release` gives up the address at once; `/renew` asks for one again. **Do not run `/release` over a remote session** (Remote Desktop, SSH, WinRM). The session travels over that very address, so releasing it cuts you off, and if the renew then fails you cannot reach the machine to repair it. Use these on a console, or schedule a renew rather than releasing first.

On Linux, with NetworkManager, bringing the connection down and up again (`nmcli connection down` then `up` for the connection name) repeats the DHCP exchange. The same caution applies over SSH.

A related command, `ipconfig /flushdns`, clears the DNS cache and has nothing to do with DHCP; it is covered in the DNS lesson.

## Static or DHCP?

| | DHCP | Static |
|---|---|---|
| Servers, printers, network gear | use a reservation | acceptable if documented |
| Laptops, phones, visitors | yes | no |
| Needs a working server | yes | no |
| Risk | rogue server, exhausted scope | duplicate addresses, drift from the documented plan |

Whatever you choose, **write it down**: an address plan that lists which ranges are DHCP, which are reserved and which are static prevents most address conflicts.

## Common mistakes

- **Giving a static address inside the DHCP range** without an exclusion. The server will hand the same address to someone else.
- **Blaming DHCP for every `169.254` address** without looking at the link first; a cable fault looks identical.
- **Releasing the lease over a remote session.**
- **Ignoring the `DHCP Server` field**, so a rogue server goes unnoticed for days.
- **A very long lease on a busy guest network**, which fills the pool with machines that left hours ago.

## Check yourself

1. Why does the Discover message go out as a broadcast from `0.0.0.0`?
2. A machine has `Lease Obtained` at 9:00 and `Lease Expires` at 17:00. About when does it first try to renew?
3. Three machines in the same office suddenly show `169.254.x.x`. What is the most likely common cause? What if it is only one machine?
4. What does a relay agent add to the forwarded request, and why?
5. Your colleague's laptop got an address in `10.0.0.0/24` but your network is `192.168.1.0/24`. What do you suspect, and which `ipconfig` field proves it?
6. Why is releasing a lease over Remote Desktop a bad idea?

**Answers.** (1) The client has no address yet and does not know where a server is, so it must broadcast, and `0.0.0.0` is the only source address it can use. (2) About 13:00, at 50 % of the lease. (3) A shared fault: the DHCP server or the link to it (a switch, the router). One machine: its own link or adapter. (4) The address of the interface the request came in on (the client's subnet), so the server picks the right scope and returns an address valid there. (5) A rogue DHCP server (often a home router plugged into the wall); the `DHCP Server` field shows its address. (6) The session runs over the address you are releasing, so you lose the connection, and if renewal then fails you cannot reach the machine.

## Practice

There is no scenario lab for DHCP itself yet; the lab VMs use QEMU's built-in DHCP on their private NAT network, so a broken-DHCP lab would need the multi-VM network described in decision record 0008. Until then, on a lab VM read your own lease with `ipconfig /all` or `ip addr`, write down the lease start, end and server, and say which fields you would compare against the address plan. The related lab `labs.gateway-route-override` covers a wrong gateway, which is the failure you meet when a DHCP server hands out bad options.
