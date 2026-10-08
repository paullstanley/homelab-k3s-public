# DNS design

How a name lookup travels in this build, and why each piece is set the way it is. The result: every device on the network uses Pi-hole for DNS whether it wants to or not, the machines that run Pi-hole never depend on it, and upstream queries leave the house encrypted.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | ASUS ZenWiFi XT8 on GNUton Asuswrt-Merlin.ng 3004.388.10_2 (DNS Director), Pi-hole v6 on k3s behind a MetalLB address, cloudflared as the DNS-over-HTTPS proxy |
| **Also works for** | Any Asuswrt-Merlin router with DNS Director, and a Pi-hole on a single machine. Not tested by the author. The node-DNS rule applies to any setup where the DNS server runs on machines that also need DNS |
| **Time** | 20 minutes to set, once Pi-hole exists |
| **You need first** | [ASUS ZenWiFi XT8 router](../hardware/asus-zenwifi-xt8.md); [Pi-hole](../apps/pihole.md) |

## How it works

```
client ──DHCP says "DNS = 192.168.50.11"──▶ Pi-hole ──DNS-over-HTTPS (port 443)──▶ 1.1.1.1 / 1.0.0.1
client with hard-coded 8.8.8.8 ──port 53──▶ router's DNS Director ──redirect──▶ Pi-hole
cluster node ──own setting 1.1.1.1 / 9.9.9.9, DNS Director exception──▶ straight out
router itself ──▶ 9.9.9.9 (its own upstream)
```

| Piece | Setting | Why |
| --- | --- | --- |
| DHCP on the router | DNS Server 1 = `192.168.50.11`, DNS Server 2 blank, "Advertise router's IP" = No | Pi-hole is the **only** resolver clients are told about. A second server would be used at random and bypass the blocking |
| IPv6 router advertisements | DNS = `fd00:1234:5678:50::11` only | The same Pi-hole over IPv6. See [Local-only IPv6](local-only-ipv6.md) |
| DNS Director, global | User Defined 1 = `192.168.50.11` | DNS Director is the router feature that rewrites port 53 traffic. Devices with a hard-coded resolver are redirected to Pi-hole anyway |
| DNS Director, per device | User Defined 2 (`1.1.1.1`) or No Redirection | Exceptions for devices that must not depend on Pi-hole |
| DNS Director, User Defined 3 | `192.168.50.11` | A spare rule. It must point at something that answers DNS |
| Router's own upstream | `9.9.9.9`, DNSSEC on, "Connect to DNS Server automatically" = No | What the router itself uses, and what serves clients during the emergency bypass below |
| Router firewall, IPv6 | REJECT port 53 on the LAN bridge | The router must not become an IPv6 way around Pi-hole |
| Pi-hole upstream | cloudflared sidecar, DNS-over-HTTPS to `1.1.1.1` and `1.0.0.1` | Queries leave on port 443, encrypted, so the ISP cannot read them. Because it is not port 53, **Pi-hole needs no DNS Director exception** |
| Pi-hole pod's own DNS | `127.0.0.1`, then `1.1.1.1` | The pod resolves through itself, with an outside fallback while it starts |
| Pi-hole reverse lookups | Sent to the router for the LAN ranges | Names for devices not listed in Pi-hole's own host list |
| Cluster nodes' own DNS | `1.1.1.1` and `9.9.9.9`, auto-DNS ignored on IPv4 and IPv6 | See the next section |
| CoreDNS (cluster DNS) | Forwards outside names to the node's `/etc/resolv.conf` | So pods also do not depend on Pi-hole. See [CoreDNS](../kubernetes/coredns.md) |

### Why the cluster nodes must not use Pi-hole

It is a chicken-and-egg trap. To start a Pi-hole pod, a node may have to download the image, which needs DNS. If the node's DNS is Pi-hole, and Pi-hole is not running, the node cannot resolve the image registry, and Pi-hole can never start. The pods sit in `ImagePullBackOff`.

This is not theoretical. It happens when:

- the address the nodes used for DNS stops serving DNS (for example Pi-hole moves to a new address), or
- power returns after a cut: the router is up before the nodes, and every node needs DNS before the first Pi-hole pod is ready.

So each node is given outside resolvers, and two things that would quietly put Pi-hole back are blocked:

1. **The router's IPv6 advertisement.** It announces Pi-hole's IPv6 address as DNS. A node set only on the IPv4 side ends up with `1.1.1.1` and `fd00:1234:5678:50::11` in `/etc/resolv.conf`. `ipv6.ignore-auto-dns yes` stops that.
2. **DNS Director.** It redirects the node's port 53 traffic to Pi-hole whatever the node's own settings say. Each node needs a per-device rule.

As a further cushion, the Pi-hole chart is set to `pullPolicy: IfNotPresent`, so a node that already has the image can start Pi-hole without reaching the registry at all.

## Before you start

- Pi-hole must answer on `192.168.50.11` before you point DHCP at it. Until then the network has no DNS; see [the no-DNS window](#the-no-dns-window-during-a-rebuild).
- List the MAC addresses of the devices that need a DNS Director exception: every cluster node (including a VM node), and anything else that must keep working when Pi-hole is down.
- Decide how the router itself resolves: plain DNS to one server, or DNS-over-TLS. See Step 4.

## Steps

### Step 1. Hand out Pi-hole by DHCP and turn on DNS Director

The bootstrap script in [ASUS ZenWiFi XT8 router](../hardware/asus-zenwifi-xt8.md) sets all of these. By hand, in the router's web UI:

| Page | Setting | Value |
| --- | --- | --- |
| LAN > DHCP Server | DNS Server 1 | `192.168.50.11` |
| LAN > DHCP Server | DNS Server 2 | blank |
| LAN > DHCP Server | Advertise router's IP in addition to user-specified DNS | No |
| LAN > DNS Director | Enable | On |
| LAN > DNS Director | Global Redirection | User Defined 1 |
| LAN > DNS Director | User Defined 1 / 2 / 3 | `192.168.50.11` / `1.1.1.1` / `192.168.50.11` |

> **Pitfall:** do not add an IPv6 DNS server to the DHCP page as a "secondary". Clients already learn Pi-hole's IPv6 address from the router's advertisements, and it is the same Pi-hole.

### Step 2. Add the exceptions

In LAN > DNS Director, add one client rule per device, chosen by MAC address:

| Device | Rule |
| --- | --- |
| Each cluster node (`server-1` to `server-4`) | User Defined 2, or No Redirection |
| Your own computer while rebuilding | No Redirection (temporary) |

"No Redirection" lets the device use whatever resolver it is configured with. "User Defined 2" forces it to `1.1.1.1`. Either breaks the dependency on Pi-hole.

### Step 3. Give each cluster node its own resolvers

On Raspberry Pi OS with NetworkManager. Find the connection name first; it is the name printed next to `eth0`.

**Run on: each node**

```bash
nmcli -t -f NAME,DEVICE con show --active
```

Then set the resolvers and ignore the ones offered by DHCP and by router advertisements. Replace the connection name with yours.

**Run on: each node**

```bash
sudo nmcli con mod "Wired connection 1" ipv4.dns "1.1.1.1 9.9.9.9" ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes
sudo nmcli con up "Wired connection 1"
grep nameserver /etc/resolv.conf
```

Expected: exactly `nameserver 1.1.1.1` and `nameserver 9.9.9.9`. No `192.168.50.11` and no `fd00:` line. Your SSH session may pause for a moment on the `con up` line. The full node setup, including fixed addresses, is in [Raspberry Pi](../hardware/raspberry-pi.md) and [HA k3s cluster](../kubernetes/k3s-ha-cluster.md).

### Step 4. Choose the router's own upstream

This is what the router itself uses to resolve names, on WAN > Internet Connection.

**Option A: plain DNS (what the bootstrap script expects).**

| Setting | Value |
| --- | --- |
| Connect to DNS Server automatically | No |
| DNS Server 1 | `9.9.9.9` |
| DNSSEC | On |
| DNS Privacy Protocol | None |

**Option B: DNS-over-TLS (DoT).** The router runs a small encrypting forwarder (`stubby`; you will see it start in the log) and sends its queries over TLS on port 853.

| Setting | Value |
| --- | --- |
| DNS Privacy Protocol | DNS-over-TLS (DoT) |
| Server list | Pick the Cloudflare presets: `1.1.1.1` and `1.0.0.1`, TLS hostname `cloudflare-dns.com` |
| TLS Port | Leave blank (the default, 853, is used) |
| SPKI Fingerprint | Leave blank for Cloudflare |

> **Pitfall:** the bootstrap script's `verify` expects a single plain upstream. With DoT on it reports `FAIL  dnsmasq: upstream is 9.9.9.9 only`. That FAIL then means "DoT is on", not "something is broken". If you choose DoT, expect that one FAIL or adapt the check in the script. The script's `install` also sets the plain-DNS nvram values (`wan_dns1_x` and friends) every time it runs.

Which option matters less than it looks: client queries go to Pi-hole, and Pi-hole encrypts its own upstream. The router's own upstream only carries the router's own lookups, and client lookups during the emergency bypass.

### Step 5. Refuse DNS on the router over IPv6

The bootstrap script's `firewall-start` block does this. The rules, for reference:

**Run on: the router** (only if you are not using the bootstrap script; these are lost at the next firewall restart unless they are in `/jffs/scripts/firewall-start`)

```sh
ip6tables -I INPUT -i br0 -p udp --dport 53 -j REJECT
ip6tables -I INPUT -i br0 -p tcp --dport 53 -j REJECT
```

> **Why:** DNS Director's redirect is used here for IPv4. The router's dnsmasq also listens on the router's IPv6 address. Without these rules a client could send queries to `fd00:1234:5678:50::1` and skip Pi-hole.

## Check it

Run the client tests from a personal device on the main Wi-Fi, not from a machine on a VPN.

| # | Test | Run on | Command | Expected |
| --- | --- | --- | --- | --- |
| 1 | Router settings | the router | `sh /jffs/xt8-bootstrap.sh verify` | `0 failed` (or only the upstream FAIL if you chose DoT) |
| 2 | Pi-hole on IPv4 | your computer | `nslookup example.com 192.168.50.11` | An answer |
| 3 | Pi-hole on IPv6 | your computer | `nslookup example.com fd00:1234:5678:50::11` | An answer |
| 4 | Blocking | your computer | `nslookup doubleclick.net` | `0.0.0.0` |
| 5 | Hard-coded DNS is redirected | your computer | `dig @8.8.8.8 example.com`, then look at the Pi-hole query log | An answer arrives **and** the query is in Pi-hole's log |
| 6 | Router refuses IPv6 DNS | your computer | `dig @fd00:1234:5678:50::1 example.com` | Refused or timed out |
| 7 | Upstream is DNS-over-HTTPS | server-1 | `sudo kubectl logs -n pihole deploy/pihole -c cloudflared --tail=20` | Connections to `https://1.1.1.1/dns-query`, no errors |
| 8 | Public leak test | your computer | Open `https://www.dnsleaktest.com` and run the extended test | Only Cloudflare resolvers listed |
| 9 | Node is independent | each node | `grep nameserver /etc/resolv.conf` | `1.1.1.1` and `9.9.9.9` only |
| 10 | Node is not redirected | a node | `nslookup example.com 1.1.1.1` while watching the Pi-hole query log | The query does **not** appear in Pi-hole |

> **Not verified:** tests 3, 5, 6 and 8 had not been run from a personal device by the author when this was written. Test 10 was also not run. The commands and expected results are the design's intent.

A leak test (test 8) shows which resolvers the outside world sees your queries coming from. Any resolver other than Pi-hole's upstream means some device or path is bypassing Pi-hole.

## The no-DNS window during a rebuild

Between resetting the router and Pi-hole being ready, Pi-hole does not exist, so the network has no DNS. While you work:

1. Set your own computer's DNS to `9.9.9.9` by hand.
2. Add your computer to DNS Director as **No Redirection**.
3. Undo both afterwards.

The same window opens after a power cut or a router restart, and closes by itself, usually within about five minutes:

1. The router is up before the cluster nodes. Devices have no DNS until one Pi-hole pod is ready.
2. Each Pi-hole pod waits 60 seconds and then downloads its blocklists before it answers.
3. The nodes need their **own** DNS at this point. This is the moment a node that depends on Pi-hole deadlocks.

If it has not settled after ten minutes, see [Troubleshooting](../operations/troubleshooting.md).

### Emergency bypass

To get the network working while Pi-hole is being fixed, in the router's web UI:

1. LAN > DHCP Server > DNS Server 1: `9.9.9.9`.
2. LAN > DNS Director > Global Redirection: **No Redirection**.
3. Apply. Devices pick it up as they renew their lease; toggle Wi-Fi on a device to force it.

**Put both back afterwards**: `192.168.50.11` and User Defined 1. `verify` on the router fails until you do, which is a useful reminder.

## Pitfalls

| What happens | Why | Avoid or recover |
| --- | --- | --- |
| New Pi-hole pods sit in `ImagePullBackOff` | The node's own DNS points at Pi-hole or at an address that no longer serves DNS | Step 3 |
| A node's `resolv.conf` lists `fd00:1234:5678:50::11` next to `1.1.1.1` | It is taking Pi-hole from the router's IPv6 advertisement | `ipv6.ignore-auto-dns yes` (Step 3) |
| A node is set correctly but its queries still show in Pi-hole | DNS Director is redirecting it | Step 2 |
| A device has no DNS at all | Its DNS Director rule is a User Defined entry that points at a dead address. Seen when User Defined 3 was a cluster node's own address, which stopped answering DNS when the load balancer changed | Point every User Defined entry at a live resolver |
| `verify` fails "upstream is 9.9.9.9 only" | DoT is on, a second WAN DNS server is set, or dnscrypt-proxy is installed | Step 4; or [remove dnscrypt-proxy](../hardware/asus-zenwifi-xt8.md#removing-dnscrypt-proxy) |
| Ping to `192.168.50.11` fails | Normal for a MetalLB address | Test with `nslookup` |
| A VPN'd laptop cannot resolve local names | The VPN sends its DNS to the VPN's own resolver, which never asks Pi-hole | [Client devices](../apps/client-devices.md) |
| The whole cluster is down, so DNS is down | Three Pi-hole pods cover one node failing, not the cluster | Emergency bypass. An optional improvement, not done here, is a second Pi-hole outside the cluster |
| Devices keep the bypass resolver after you restore the settings | They hold their lease | Toggle Wi-Fi, or wait for the lease to renew |

## Troubleshooting

"The internet is down" is almost always DNS. Work from the device outwards.

**Run on: your computer** (the affected device)

```bash
ping -c 2 1.1.1.1
nslookup example.com
nslookup example.com 192.168.50.11
nslookup example.com 1.1.1.1
```

| Symptom | Cause | Fix |
| --- | --- | --- |
| Ping to `1.1.1.1` fails | Not DNS. The connection or the router | Router WAN status, modem, cables |
| Ping works, all three lookups fail | The device cannot reach any DNS | Is it on the right Wi-Fi? Does it have a `192.168.50.x` address? |
| Lookup via `.11` fails, lookup via `1.1.1.1` works | Pi-hole is not answering. DNS Director normally redirects the `1.1.1.1` lookup to Pi-hole too, so this result usually means the device has a DNS Director exception | Check the Pi-hole pods and MetalLB: [Pi-hole](../apps/pihole.md), [Troubleshooting](../operations/troubleshooting.md) |
| Only the default lookup fails | The device is using some other DNS server | On a Mac: `scutil --dns \| grep nameserver`. A VPN is the usual reason |
| Everything works but one site does not | Pi-hole is blocking it | Pi-hole query log, then allow the name in the Pi-hole values file |
| Hundreds of dnsmasq restarts in the router log | dnscrypt-proxy's manager | [Remove it](../hardware/asus-zenwifi-xt8.md#removing-dnscrypt-proxy) |

## Undo

To go back to a plain setup where the router answers DNS: set LAN > DHCP Server > DNS Server 1 to blank, "Advertise router's IP" to Yes, and DNS Director > Enable to Off. On each node, `sudo nmcli con mod "<connection>" ipv4.ignore-auto-dns no ipv6.ignore-auto-dns no ipv4.dns ""` and `sudo nmcli con up "<connection>"`. Note that the bootstrap script's `install` sets the Pi-hole values again whenever it runs.

## References

- [Asuswrt-Merlin wiki: DNS Director](https://github.com/RMerl/asuswrt-merlin.ng/wiki/DNS-Director): global redirection, "No Redirection" client rules and the three user-defined servers.
- [Pi-hole documentation](https://docs.pi-hole.net/): what Pi-hole is and how it resolves and blocks.
- [Pi-hole documentation: ASUS router](https://docs.pi-hole.net/routers/asus/): pointing an ASUS router's clients at Pi-hole.
- [Cloudflare: DNS over TLS](https://developers.cloudflare.com/1.1.1.1/dns-over-tls/): Cloudflare's addresses and port 853 for DoT.
- [Stubby](https://dnsprivacy.org/dns_privacy_daemon_-_stubby/): the DNS-over-TLS stub resolver the router runs when DoT is on.
- [Quad9: service addresses and features](https://www.quad9.net/service/service-addresses-and-features/): what `9.9.9.9` provides.
- [DNS leak test](https://www.dnsleaktest.com/): the public test used in the checks.
- [k3s: networking services](https://docs.k3s.io/networking/networking-services): CoreDNS as shipped with k3s.
