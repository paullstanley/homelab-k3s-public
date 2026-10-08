# Local-only IPv6 when the ISP provides none

You end up with every device on the LAN holding an IPv6 address in a private range, and an IPv6 DNS server, while all internet traffic stays on IPv4. This is what you want when your ISP gives you no IPv6 but something on your network needs it locally, for example a dual-stack Kubernetes cluster or a DNS server that should answer on both protocols.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | ASUS ZenWiFi XT8 on GNUton Asuswrt-Merlin 3004.388.10_2 as the router; an OpenWrt 25.12.5 access point; Raspberry Pi OS / Debian nodes using NetworkManager |
| **Also works for** | Any Asuswrt-Merlin router with JFFS custom scripts (same hooks, same dnsmasq). Not tested by the author on other models. The dnsmasq lines apply to any dnsmasq-based router; the kernel and firewall parts are specific to how ASUS firmware behaves with IPv6 disabled |
| **Time** | 30 minutes for the router, plus a few minutes per fixed device |
| **You need first** | SSH access to the router and JFFS custom scripts enabled: [ASUS ZenWiFi XT8](../hardware/asus-zenwifi-xt8.md). An IPv6-capable DNS server on the LAN if you want to advertise one; the example is [Pi-hole](../apps/pihole.md) |

## How it works

**The address range.** A ULA (unique local address) prefix is the IPv6 equivalent of `192.168.x.x`: a range inside `fd00::/8` that is never routed on the internet. You pick one /48 for your site and use one /64 of it for the LAN. The example is `fd00:1234:5678::/48`, with `fd00:1234:5678:50::/64` on the LAN.

**How clients get addresses.** The router sends router advertisements (RAs): small periodic messages that say "this prefix is on this link". Each client then builds its own address inside the prefix. That is SLAAC (stateless address autoconfiguration). No DHCPv6 address server is involved.

**Why there is no IPv6 internet.** An RA also carries a "router lifetime". A lifetime above zero tells clients "use me as your IPv6 default route". Here it is set to **zero**, so clients take the prefix and the DNS server but install **no IPv6 default route**. A client asked to reach an IPv6 internet address has nowhere to send it and uses IPv4 at once. Without this, clients would try IPv6 first, wait for it to fail, and every connection would feel slow.

**Why it is done from scripts.** On ASUS firmware every IPv6 mode in the web UI either needs a prefix from the ISP or makes the router advertise itself as the IPv6 DNS server. So the UI stays on **Disable**, and three small pieces do the work underneath it:

| Piece | Does |
| --- | --- |
| Kernel settings on the LAN bridge `br0` | Turn IPv6 back on for the LAN only (the firmware turns it off when the UI says Disable) and give the router its own address |
| dnsmasq options | Send the advertisements: prefix, lifetime zero, DNS server |
| `ip6tables` rules | Open exactly what is needed. With IPv6 disabled the firmware sets all three IPv6 policies (INPUT, OUTPUT, FORWARD) to DROP |

Asuswrt-Merlin runs user scripts from `/jffs/scripts/` at fixed moments. `dnsmasq.postconf` runs every time dnsmasq starts, just before it reads its generated config; `firewall-start` runs after every firewall restart. Putting the pieces there makes them survive reboots and service restarts.

## Before you start

1. **Pick a prefix.** Generate a random /48 inside `fd00::/8` rather than inventing a memorable one; RFC 4193 requires the 40 bits after `fd` to be random so that two sites never collide. Then choose one /64 for the LAN. A handy habit, used here, is to make the fourth group match the IPv4 subnet (`:50:` for `192.168.50.x`).
2. **Plan the fixed addresses.** Give fixed devices short addresses that mirror their IPv4 ones:

| Device | IPv4 | IPv6 |
| --- | --- | --- |
| Router | `192.168.50.1` | `fd00:1234:5678:50::1` |
| OpenWrt access point | `192.168.50.3` | `fd00:1234:5678:50::3` |
| Stock-firmware access point | `192.168.50.4` | none |
| `server-1`, `server-2`, `server-3` | `.5`, `.6`, `.7` | `::5`, `::6`, `::7` |
| DNS server (Pi-hole) | `192.168.50.11` | `fd00:1234:5678:50::11` |

3. **Decide the IPv6 DNS server.** The example advertises only the Pi-hole. If you have no IPv6 DNS server, leave the `option6:dns-server` line out; clients then keep using their IPv4 DNS server.
4. **Take a router backup** (settings file and JFFS) before changing scripts. See [Backups and secrets](../operations/backups-and-secrets.md).

## Steps

### Step 1. Router UI settings

| Page | Setting | Value |
| --- | --- | --- |
| IPv6 | Connection type | **Disable** |
| Administration → System | Enable JFFS custom scripts and configs | Yes |
| Administration → System | Enable SSH | LAN only |

> **Pitfall:** The IPv6 page must stay on Disable. Every other mode either needs an ISP prefix or makes the router advertise itself as DNS.

### Step 2. Install the router scripts

There are two ways. Both give the same result.

**Option A: the bootstrap script.** [`files/xt8/xt8-bootstrap.sh`](../../files/xt8/xt8-bootstrap.sh) writes these scripts together with everything else that router needs, sets the related `nvram` values (`ipv6_service=disabled`, an empty IPv6 firewall rule list, and the Pi-hole as IPv6 DNS in case native IPv6 is ever enabled), restarts the services and verifies the result. Edit the values at the top (`ULA_NET`, `DOMAIN` and so on) and follow [ASUS ZenWiFi XT8](../hardware/asus-zenwifi-xt8.md). It only owns the text between its two marker lines in each hook file, so other add-ons' lines survive.

> **Not verified:** The bootstrap script was syntax-checked and run against stand-in commands, not on a real router. The rules it installs are the ones in Option B, which were entered by hand on a real router and confirmed working. Do the first real run when you have time to watch it.

**Option B: by hand.** Reference copies of the files are in [`files/xt8/jffs-scripts/`](../../files/xt8/jffs-scripts/). Those copies read their addresses from `homenet.conf` and show only the block this repo owns. The self-contained versions below are equivalent.

> **Pitfall:** `/jffs/scripts/dnsmasq.postconf` and `/jffs/scripts/firewall-start` are shared hook files. Add-ons such as Skynet keep their own lines in them. **Add to an existing file; do not overwrite it.** Check first with `cat /jffs/scripts/firewall-start`.

Log in to the router. Add `-p <SSH_PORT>` if you changed the SSH port from 22.

**Run on: your computer.**

```sh
ssh admin@192.168.50.1
```

Put this in `/jffs/scripts/dnsmasq.postconf` (create the file with the first line `#!/bin/sh` if it does not exist; if it exists, add everything below that line).

**Run on: the router**, in an editor such as `vi /jffs/scripts/dnsmasq.postconf`.

```sh
#!/bin/sh
CONFIG="$1"
. /usr/sbin/helper.sh
# Kernel: IPv6 on br0 (the firmware has it off while IPv6 = Disable in the UI),
# and never autoconfigure from anyone else's router advertisements.
echo 0 > /proc/sys/net/ipv6/conf/br0/disable_ipv6
echo 0 > /proc/sys/net/ipv6/conf/br0/accept_ra
echo 0 > /proc/sys/net/ipv6/conf/br0/autoconf
ip -6 addr show dev br0 | grep -q "fd00:1234:5678:50::1/64" || ip -6 addr add "fd00:1234:5678:50::1/64" dev br0
# dnsmasq: advertise the ULA /64 with router lifetime 0 (no IPv6 default route),
# SLAAC only, and the Pi-hole as the one and only IPv6 DNS server.
pc_append "enable-ra" "$CONFIG"
pc_append "ra-param=br0,0,0" "$CONFIG"
pc_append "dhcp-range=::,constructor:br0,ra-stateless,64,12h" "$CONFIG"
pc_append "dhcp-option=option6:dns-server,[fd00:1234:5678:50::11]" "$CONFIG"
pc_append "dhcp-option=option6:domain-search,home.example.com" "$CONFIG"
```

Put this in `/jffs/scripts/firewall-start`, under the same rule about existing content.

```sh
#!/bin/sh
# With IPv6 = Disable the firmware sets ip6tables INPUT/OUTPUT/FORWARD policy DROP.
# Allow only: ICMPv6 (RA/NDP/ping) and DHCPv6 in from the LAN; refuse DNS to the
# router over IPv6 (clients must use the Pi-hole); let the router talk on br0.
for R in "-p udp --dport 53 -j REJECT" "-p tcp --dport 53 -j REJECT" \
         "-p udp --dport 547 -j ACCEPT" "-p ipv6-icmp -j ACCEPT"; do
  ip6tables -D INPUT -i br0 $R 2>/dev/null
  ip6tables -I INPUT -i br0 $R
done
# Nothing from the LAN is ever routed out another interface over IPv6
ip6tables -D FORWARD -i br0 ! -o br0 -j DROP 2>/dev/null
ip6tables -I FORWARD -i br0 ! -o br0 -j DROP
# Without this the router cannot send RAs or answer pings (OUTPUT policy is DROP)
ip6tables -D OUTPUT -o br0 -j ACCEPT 2>/dev/null
ip6tables -I OUTPUT -o br0 -j ACCEPT
ip6tables -D INPUT -i lo -j ACCEPT 2>/dev/null; ip6tables -I INPUT -i lo -j ACCEPT
ip6tables -D OUTPUT -o lo -j ACCEPT 2>/dev/null; ip6tables -I OUTPUT -o lo -j ACCEPT
```

Make both executable and apply them.

**Run on: the router.**

```sh
chmod a+rx /jffs/scripts/dnsmasq.postconf /jffs/scripts/firewall-start
service restart_dnsmasq
service restart_firewall
```

### What each line does

`dnsmasq.postconf`:

| Line | Why |
| --- | --- |
| `disable_ipv6 = 0` on `br0` | With IPv6 on Disable in the UI the firmware turns IPv6 off on `br0`. This turns it back on for the LAN only |
| `accept_ra = 0`, `autoconf = 0` | The router never configures itself from another device's advertisements |
| `ip -6 addr add fd00:1234:5678:50::1/64` (only if not already there) | The router's own address. dnsmasq builds the advertised prefix from it |
| `enable-ra` | dnsmasq sends router advertisements |
| `ra-param=br0,0,0` | The last value is the router lifetime. Zero: clients get addresses but **no IPv6 default route**, so internet traffic stays on IPv4 |
| `dhcp-range=::,constructor:br0,ra-stateless,64,12h` | Advertise whatever /64 is on `br0`, for SLAAC, with stateless DHCPv6 for options only. `ra-names` (which would make dnsmasq guess DNS names for SLAAC addresses) is deliberately left out |
| `dhcp-option=option6:dns-server,[fd00:1234:5678:50::11]` | The Pi-hole is the only IPv6 DNS server advertised |
| `dhcp-option=option6:domain-search,home.example.com` | The local search domain over IPv6 too |
| no `quiet-ra` line | Deliberate. dnsmasq then logs every advertisement it sends. See [Advertisement logging](#advertisement-logging) |

`firewall-start`:

| Rule | Why |
| --- | --- |
| `INPUT -i br0` udp and tcp port 53 REJECT | The router refuses DNS over IPv6, so it cannot become a way around the Pi-hole |
| `INPUT -i br0` udp 547 ACCEPT | Stateless DHCPv6 requests from clients |
| `INPUT -i br0` ICMPv6 ACCEPT | Neighbor discovery, router solicitations and ping |
| `FORWARD -i br0 ! -o br0 DROP` | LAN IPv6 is never routed anywhere else |
| `OUTPUT -o br0 ACCEPT` | **The one that caused trouble.** With IPv6 disabled the firmware sets the IPv6 OUTPUT policy to DROP. Without this rule the router cannot send advertisements or answer pings, and clients never get the prefix |
| `INPUT -i lo` and `OUTPUT -o lo` ACCEPT | The router's own loopback traffic |
| Every rule is delete-then-insert | Repeated firewall restarts never stack duplicates |

> **Pitfall:** "The router is not sending advertisements" was the symptom that cost the most time here. dnsmasq was configured correctly and running, and the address was on `br0`, yet no client got a prefix. The root cause was the `ip6tables` OUTPUT policy of DROP. If clients get no `fd00:` address, check the OUTPUT rule before anything in dnsmasq.

### Step 3. If you also have an OpenWrt access point

A bridged access point passes the router's advertisements to its Wi-Fi clients without any configuration. The only decisions are about the access point itself: give it one static address, and make sure it **advertises nothing** and has no prefix of its own.

[`files/archer-a7/a7-ap-setup.sh`](../../files/archer-a7/a7-ap-setup.sh) does this; the full walkthrough is on [Archer A7 on OpenWrt](../hardware/tp-link-archer-a7-openwrt.md). The IPv6 part by hand:

**Run on: the access point** (`ssh root@192.168.50.3`).

```sh
uci show network | grep "name='br-lan'"
```

That prints the bridge's device section, for example `network.@device[0].name='br-lan'`. Use that index in the fourth line below.

```sh
uci -q delete network.globals.ula_prefix
uci set network.lan.ipv6='1'
uci set network.@device[0].ipv6='1'
uci -q delete network.lan.ip6assign
uci -q delete network.lan.ip6addr
uci set network.lan.ip6addr='fd00:1234:5678:50::3/64'
uci set network.lan.delegate='0'
uci set dhcp.lan.ra='disabled'
uci set dhcp.lan.dhcpv6='disabled'
uci set dhcp.lan.ndp='disabled'
uci commit network
uci commit dhcp
/etc/init.d/odhcpd disable; /etc/init.d/odhcpd stop
/etc/init.d/network restart
```

| Setting | Why |
| --- | --- |
| `ula_prefix` deleted | OpenWrt's own random prefix would give clients a second IPv6 range |
| device-level `ipv6='1'` on `br-lan` | **Required.** Without it the bridge stays IPv6-off |
| `ip6addr` deleted then set | A static management address with no IPv6 gateway. Deleting first prevents a duplicate |
| `ra`, `dhcpv6`, `ndp` disabled, `odhcpd` off | The access point never advertises |
| `network restart` | **`network reload` was not enough** to bring IPv6 up on the bridge |

### Step 4. If you also have a stock-firmware access point

Stock consumer firmware in access point mode often has no IPv6 settings at all. The [Archer AX21](../hardware/tp-link-archer-ax21.md) is one: it has no IPv6 address and an IPv6 ping to it times out. That is expected. Its Wi-Fi clients still get IPv6 from the router because it bridges. Leave it out of the address plan.

### Step 5. If you also have servers that need fixed IPv6 addresses

Servers that others must find by address (cluster nodes, for example) get a short static address **in addition** to automatic configuration. On a Debian-family system managed by NetworkManager, one command sets both protocols. `ipv6.method auto` with `ipv6.addresses` keeps SLAAC and adds the fixed address; `ipv6.ignore-auto-dns yes` stops the node from taking the advertised DNS server.

**Run on: server-1.**

```sh
nmcli -t -f NAME,DEVICE con show --active
sudo nmcli con mod "Wired connection 1" ipv4.method manual ipv4.addresses 192.168.50.5/24 ipv4.gateway 192.168.50.1 ipv4.dns "1.1.1.1 9.9.9.9" ipv4.ignore-auto-dns yes ipv6.method auto ipv6.addresses "fd00:1234:5678:50::5/64" ipv6.ignore-auto-dns yes
sudo nmcli con up "Wired connection 1"
```

The first command prints the connection name; it may be `netplan-eth0` or something else instead of `Wired connection 1`. Use `::6` and `.6` on `server-2`, `::7` and `.7` on `server-3`. The reasons for the DNS choices, and the rest of node preparation, are on [Raspberry Pi](../hardware/raspberry-pi.md) and [k3s HA cluster](../kubernetes/k3s-ha-cluster.md).

> **Pitfall:** If a node's `/etc/resolv.conf` lists `fd00:1234:5678:50::11`, the node is still taking the DNS server from the router's advertisement. `ipv6.ignore-auto-dns yes` is what stops it. This matters when the DNS server runs on those same nodes: a node must not need the cluster's DNS in order to start the cluster.

> **Pitfall:** Run `nmcli con up` on a connection that is still on DHCP and the node may come back on a different IPv4 address, freezing your SSH session. The static IPv6 address is the way back in: from another machine on the LAN, `ssh <user>@fd00:1234:5678:50::7`. Setting `ipv4.method manual` with the address, as above, prevents it.

A node configured this way has more than one address in the LAN prefix: the fixed one and at least one generated by SLAAC. It may use a generated one as the source when it talks to a neighbor. That matters if you run a host firewall that lists nodes by address; see [Node firewall](../kubernetes/node-firewall.md).

A virtual machine or any device you leave fully automatic gets a long SLAAC address built from its MAC address, for example `fd00:1234:5678:50:5055:55ff:fe15:f169`. It is stable as long as the MAC address is.

## Check it

### On the router

**Run on: the router.**

```sh
ip -6 addr show dev br0
ip -6 route | grep '^default'
grep -E '^(enable-ra|ra-param|dhcp-range=::|dhcp-option=option6)' /etc/dnsmasq.conf
ip6tables -S OUTPUT | grep -- '-o br0 -j ACCEPT'
ip6tables -S FORWARD | grep -- '-i br0 ! -o br0 -j DROP'
ip6tables -S INPUT | grep -- '--dport 53 -j REJECT'
```

| Command | Expected |
| --- | --- |
| `ip -6 addr` | `fd00:1234:5678:50::1/64` and a link-local `fe80::` address |
| `ip -6 route \| grep '^default'` | Nothing |
| `grep ... /etc/dnsmasq.conf` | `enable-ra`, `ra-param=br0,0,0`, the `dhcp-range` line and both `option6` lines |
| The three `ip6tables` commands | One matching rule each (two for port 53: udp and tcp) |

If you used the bootstrap script, `sh /jffs/xt8-bootstrap.sh verify` runs the same checks and prints PASS or FAIL for each.

> **Pitfall:** You cannot test the Pi-hole's IPv6 address from the router itself. The router's own `ip6tables` INPUT policy drops the reply. Test it from a client.

### From a client

On a personal device on the main Wi-Fi (the commands are for macOS; on Linux use `ip -6 addr` and `ip -6 route`).

**Run on: your computer.**

```sh
ifconfig | grep "inet6 fd00"
netstat -rn -f inet6 | grep default
nslookup example.com fd00:1234:5678:50::11
dig @fd00:1234:5678:50::1 example.com
```

| Command | Expected |
| --- | --- |
| `ifconfig` | An address in `fd00:1234:5678:50::/64` |
| `netstat` | No line pointing at the router. (Lines for `fe80::%utun` tunnel interfaces belong to the operating system and do not count) |
| `nslookup` against the Pi-hole's IPv6 address | An answer |
| `dig` against the router's IPv6 address | Refused or timed out |

> **Not verified:** The router-side checks were run on the tested router. The four client-side checks are the intended acceptance test, but the author has no record of running them from a personal device. Cluster nodes on the same LAN did receive addresses in the prefix and did reach each other and the router over it.

Do not test from a work laptop on a VPN: VPN clients commonly disable or override local IPv6.

## Seeing IPv6 on the router

**System Log → IPv6 says "IPv6 Not enabled" and always will.** That page only fills in when IPv6 is enabled in the UI, which must stay on Disable. The same information over SSH:

**Run on: the router.**

```sh
ip -6 addr show dev br0
ip -6 neigh show dev br0
ip -6 route
```

The first is the router's own addresses. The second is every client's IPv6 address with its MAC address, which answers "which device has which address". The third must have no `default` line.

### Advertisement logging

With no `quiet-ra` line in the dnsmasq config, the system log gets a line for each advertisement:

| Line | Meaning |
| --- | --- |
| `RTR-ADVERT(br0) fd00:1234:5678:50::` | The router announced the prefix. A burst after each dnsmasq restart, then one every few minutes |
| `RTR-SOLICIT(br0)` | A client asked for an advertisement, usually on joining or waking |
| `DHCPSOLICIT(br0)` repeating with no reply | A device is asking for a DHCPv6 address. The router only does SLAAC, so nothing answers. Harmless |

This is the quickest proof that advertisements are leaving the router. The lines name the interface, not the client. To silence them, add `pc_append "quiet-ra" "$CONFIG"` to `dnsmasq.postconf` (outside the bootstrap script's marker lines, if you use it) and run `service restart_dnsmasq`. Where the log lives, how to watch it and how it is rotated: [Router logging](router-logging.md).

## A second ULA prefix on the LAN

After this is working you may find that devices have addresses in **two** `fd` prefixes: yours, and one you never configured (for illustration, `fd00:aaaa:bbbb:cccc::/64`). The router is not handing out the second one, so something else on the LAN is sending its own router advertisements.

The usual source is a Thread border router: a smart-home hub such as an Apple TV or a HomePod that connects a low-power Thread mesh to the LAN and advertises a prefix so that the two can reach each other. It is harmless for normal use and you should not try to block it; smart-home accessories depend on it.

It matters in two places:

- **Host firewalls that list trusted sources by prefix.** A rule that allows only your own /64 does not cover traffic sourced from the other prefix. See [Node firewall](../kubernetes/node-firewall.md).
- **Reading address lists.** A device showing an unfamiliar `fd` address is not misconfigured.

To see who is advertising, capture router advertisements for a few minutes on any Linux machine on the LAN and read the source address and the prefix in each. ICMPv6 type 134 is a router advertisement.

**Run on: server-1.**

```sh
sudo tcpdump -i eth0 -vv -n 'icmp6 and ip6[40] == 134'
```

The source is a link-local `fe80::` address; match it to a device with `ip -6 neigh show dev br0` on the router.

> **Not verified:** On the tested network the second prefix was seen on every node and the router was ruled out as its source. A Thread border router is the likely origin, but the actual device was not identified.

## Pitfalls

| What happens | Why | Avoid or recover |
| --- | --- | --- |
| Clients get no `fd00:` address although dnsmasq is configured | `ip6tables` OUTPUT policy is DROP; the advertisements never leave the router | The `OUTPUT -o br0 ACCEPT` rule in `firewall-start`. `service restart_firewall` |
| The router answers nothing over IPv6, not even ping | Same cause | Same fix |
| IPv6 on `br0` goes off by itself | The firmware, or an add-on manager action (amtm), re-applied "IPv6 disabled" to the bridge | `service restart_dnsmasq` re-runs `dnsmasq.postconf` and turns it back on |
| You enable an IPv6 mode in the UI to "see what it shows" | The router starts advertising itself as IPv6 DNS, or waits for an ISP prefix that never comes | Set it back to Disable, then restart dnsmasq and the firewall |
| System Log → IPv6 is blank | That page needs IPv6 enabled in the UI | Use the SSH commands above |
| Rules stack up after many firewall restarts | Insert without delete | Keep the delete-then-insert pattern |
| Another add-on's lines vanish from a hook file | The file was overwritten instead of appended to | Restore from your JFFS backup; re-add your block below theirs |
| Every connection is slow to start | The router lifetime is not zero, so clients try IPv6 to the internet first | `ra-param=br0,0,0`; check with `grep ra-param /etc/dnsmasq.conf` |
| The router web UI freezes while you check things | Several simultaneous requests | One page at a time |
| The OpenWrt access point has no IPv6 on `br-lan` | Device-level `ipv6` flag missing, or only `network reload` was used | Step 3 |
| Clients have a third prefix | The OpenWrt access point's `ula_prefix` was not deleted and it is advertising | Step 3 |
| `ip -6 neigh flush ... nud failed` does nothing on the router | BusyBox's `ip` has no working form of it | The loop below |

Clearing failed neighbor entries on the router (stale entries can linger after you renumber or move a device). It lists entries in state FAILED and deletes them one by one.

**Run on: the router.**

```sh
ip -6 neigh show nud failed | while read a b c d; do ip -6 neigh del "$a" dev "$c"; done
```

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Clients get no `fd00:` address | `br0` IPv6 off, or the OUTPUT rule missing | `service restart_dnsmasq; service restart_firewall`, then the router checks |
| Router answers nothing over IPv6 | `ip6tables` OUTPUT policy DROP | `service restart_firewall`; confirm `firewall-start` is executable |
| `br0` has no `::1/64` address, or a dnsmasq option is missing | `dnsmasq.postconf` did not run | `service restart_dnsmasq`, wait 5 seconds, check again. If still failing: `cat /jffs/scripts/dnsmasq.postconf`, confirm the lines are there, the file is executable, and JFFS custom scripts are enabled |
| An `ip6tables` rule is missing | `firewall-start` did not run | `service restart_firewall`, wait 10 seconds, check again |
| Client has an address but `nslookup` against `::11` fails | The DNS server is down, or does not listen on IPv6 | Test its IPv4 address; see [Pi-hole](../apps/pihole.md). The Pi-hole address does not answer ping, so test with `nslookup` |
| Client has an IPv6 default route through the router | Router lifetime not zero | `ra-param=br0,0,0` |
| System Log → IPv6 says "IPv6 Not enabled" | Expected | `ip -6 neigh show dev br0` |
| No `RTR-ADVERT` lines in the log | A `quiet-ra` line is in `dnsmasq.postconf` | Comment it out, `service restart_dnsmasq` |
| `DHCPSOLICIT(br0)` repeating with no reply | One device wants DHCPv6; the router only does SLAAC | Nothing |
| IPv6 ping to a stock-firmware access point times out | It has no IPv6 address | Nothing |
| The OpenWrt access point's address appears twice | `ip6addr` set twice | `uci -q delete network.lan.ip6addr; uci set network.lan.ip6addr='fd00:1234:5678:50::3/64'; uci commit network; /etc/init.d/network restart` |
| A node's `resolv.conf` lists the advertised DNS server | `ipv6.ignore-auto-dns` not set | Step 5 |
| Devices have an `fd` address you did not configure | Another device advertises its own prefix | [A second ULA prefix on the LAN](#a-second-ula-prefix-on-the-lan) |

More symptoms across the whole build: [Troubleshooting](../operations/troubleshooting.md).

## Undo

**On the router.** Remove the lines you added from `/jffs/scripts/dnsmasq.postconf` and `/jffs/scripts/firewall-start` (or run `sh /jffs/xt8-bootstrap.sh uninstall` if you used the bootstrap script; it removes its blocks, leaves `nvram` untouched and switches IPv6 on `br0` off). Then:

**Run on: the router.**

```sh
echo 1 > /proc/sys/net/ipv6/conf/br0/disable_ipv6
service restart_dnsmasq
service restart_firewall
```

Clients drop their `fd00:` addresses when the prefix lifetime runs out, or at once on reconnecting.

**On the OpenWrt access point.** `uci -q delete network.lan.ip6addr; uci commit network; /etc/init.d/network restart`.

**On a node.** `sudo nmcli con mod "Wired connection 1" ipv6.addresses ""`, then `sudo nmcli con up "Wired connection 1"`. Do not do this on a member of a dual-stack cluster; the cluster configuration names that address.

## References

- [RFC 4193: Unique Local IPv6 Unicast Addresses](https://www.rfc-editor.org/rfc/rfc4193): defines ULA prefixes and the requirement to generate the 40-bit global ID randomly.
- [RFC 4861: Neighbor Discovery for IP version 6](https://www.rfc-editor.org/rfc/rfc4861): router advertisements; section 4.2 states that a router lifetime of zero means "not a default router".
- [RFC 4862: IPv6 Stateless Address Autoconfiguration](https://www.rfc-editor.org/rfc/rfc4862): how clients build their own addresses from an advertised prefix (SLAAC).
- [dnsmasq manual page](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html): `--enable-ra`, `--ra-param`, the `ra-stateless` and `constructor:` forms of `--dhcp-range`, `--dhcp-option` with `option6:`, and `--quiet-ra`.
- [Asuswrt-Merlin wiki: Custom config files](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Custom-config-files): postconf scripts such as `dnsmasq.postconf`, and the `pc_append` helper from `helper.sh`.
- [Asuswrt-Merlin wiki: User scripts](https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts): how to enable JFFS scripts and when `firewall-start` and the other hooks run.
- [gnuton/asuswrt-merlin.ng](https://github.com/gnuton/asuswrt-merlin.ng): the Asuswrt-Merlin fork that supports the ZenWiFi XT8, the firmware this page was done on.
- [openwrt/odhcpd](https://github.com/openwrt/odhcpd): the `ra`, `dhcpv6` and `ndp` options disabled on the OpenWrt access point.
