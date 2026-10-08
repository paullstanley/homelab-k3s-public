# Client devices: VPN laptops, per-device DNS and browsers

Most devices need nothing: they take their address and DNS server from the router and everything works. This page covers the exceptions: a work laptop on a corporate VPN that cannot resolve your home names, devices with their own DNS rules, computers that need a setting for local IPv6, browser problems with the home web apps, and reaching the house from another network.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | macOS (a managed work MacBook on an always-on corporate VPN; personal Macs), Windows Server with a manually set IPv6 address, phones and other DHCP clients. Home names served by Pi-hole, web apps behind Traefik on `192.168.50.12` |
| **Also works for** | Linux and Windows laptops on a VPN, using their own hosts file (`/etc/hosts`, `C:\Windows\System32\drivers\etc\hosts`). The idea is the same; the commands here are macOS and are the only ones tested by the author |
| **Time** | 5 minutes per device |
| **You need first** | Local names that resolve on the LAN: [Pi-hole](pihole.md) and [DNS design](../network/dns-design.md). For IPv6 items: [Local-only IPv6](../network/local-only-ipv6.md) |

## How it works

A device finds `pihole.home.example.com` by asking its DNS server. On the home network that is Pi-hole, which knows the home names. Three things can get in the way:

- **A VPN that takes over DNS.** Corporate VPN clients usually send every DNS query to the company's resolver (in this build, a proxy at an `fddd:...` IPv6 address on the laptop itself). That resolver has never heard of `home.example.com` and answers NXDOMAIN ("no such name"). The laptop never asks Pi-hole. Nothing is wrong with Pi-hole.
- **The hosts file comes first.** On macOS, Linux and Windows, the system resolver looks in the hosts file before asking any DNS server. Names listed there resolve whatever the VPN does.
- **Per-device DNS rules on the router.** A router can force each device's DNS to a chosen server (DNS Director on Asuswrt-Merlin). A device whose rule points at a server that no longer exists has no DNS at all.

## Before you start

- List the home names you use and the address each should resolve to. Every web app behind Traefik resolves to Traefik's address (`192.168.50.12`); the Kubernetes API name resolves to its floating address (`192.168.50.10`).
- On a managed work machine, check that editing the hosts file is allowed by your employer's policy.

## Steps

### Step 1. A work laptop on a VPN: add home names to the hosts file

The lines to add are kept in [`files/clients/work-mac-hosts.txt`](../../files/clients/work-mac-hosts.txt):

```
192.168.50.12 pihole.home.example.com hb.home.example.com traefik.home.example.com
192.168.50.10 k3s.home.example.com
```

**Run on: your computer** (macOS Terminal), one command at a time.

Back up the current file:

```bash
sudo cp /etc/hosts /etc/hosts.bak
```

Remove old home lines. This clears stale entries, such as a name that used to point at a node's own address:

```bash
sudo sed -i '' '/home\.example\.com/d' /etc/hosts
```

Add the current ones:

```bash
sudo tee -a /etc/hosts <<'EOF'
192.168.50.12 pihole.home.example.com hb.home.example.com traefik.home.example.com
192.168.50.10 k3s.home.example.com
EOF
```

Flush the DNS cache and check:

```bash
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
dscacheutil -q host -a name pihole.home.example.com
```

Expected: `ip_address: 192.168.50.12`.

> **Pitfall:** do not check with `nslookup` (or `dig`). They query DNS servers directly, skip the hosts file, and will still say NXDOMAIN.

> **Pitfall:** the closing `EOF` line must start at the left margin. If it is indented, the shell never sees it and sits at a `>` prompt. Press Ctrl+C and paste again.

Things to know about this approach:

- The hosts file has no wildcards. Every new app behind Traefik must be added to the `192.168.50.12` line, on every such laptop.
- On a managed machine the file can be reset by management software. If the names stop resolving one day, check the file first.
- An alternative that needs no hosts file on any machine is a public, DNS-only wildcard record `*.home` → `192.168.50.12` in your domain's DNS. It publishes a private address in public DNS, which is harmless but visible. **Not verified:** this was considered and not done.

### Step 2. Per-device DNS exceptions

If the router forces DNS per device (DNS Director on Asuswrt-Merlin; see [DNS design](../network/dns-design.md) and [ASUS ZenWiFi XT8](../hardware/asus-zenwifi-xt8.md)):

- The global rule sends everything to Pi-hole (`192.168.50.11`).
- A device with an exception (for example "No Redirection", or a user-defined server) follows its own rule. Typical exceptions are the cluster nodes themselves, so that their DNS does not depend on the Pi-hole they host.
- Every user-defined server must point at something that still answers DNS.

> **Pitfall:** a user-defined rule that pointed at a node's own address (`192.168.50.5`) kept "working" while k3s ServiceLB published Pi-hole on every node. Once Pi-hole moved to its floating address, that address stopped answering DNS and every device on that rule had **no DNS at all**. After any change to where DNS lives, review each user-defined server and the per-device list.

> **Pitfall:** do not add an IPv6 DNS server to the router's DHCP page as a "secondary". Clients already learn Pi-hole's IPv6 address from the router's advertisements, and it is the same Pi-hole.

### Step 3. Macs: let them use local IPv6

**If you also have [local-only IPv6](../network/local-only-ipv6.md):** System Settings → Network → the active service → Details → TCP/IP → **Configure IPv6: Automatically**. Not "Link-Local Only", which would discard the local IPv6 address and the IPv6 DNS server.

Check:

**Run on: your computer** (macOS Terminal)

```bash
ifconfig | grep "inet6 fd00"
scutil --dns | grep "nameserver\[" | sort -u
```

Expected: at least one `fd00:1234:5678:50:` address, and both `192.168.50.11` and `fd00:1234:5678:50::11` as name servers.

A Mac that serves something under a fixed IPv6 address (for example a media server that Pi-hole has a name for) needs a manual address instead: Configure IPv6 **Manually**, address `fd00:1234:5678:50::2`, prefix length `64`, router blank. Keep that address stable, because the name in Pi-hole points at it.

### Step 4. Windows machines with a fixed IPv6 address

**If you also have [local-only IPv6](../network/local-only-ipv6.md):** Adapter → Properties → Internet Protocol Version 6 (TCP/IPv6) → Properties:

| Field | Value |
| --- | --- |
| IPv6 address | a free address in the prefix, for example `fd00:1234:5678:50::16` |
| Subnet prefix length | `64` |
| Default gateway | blank |
| Preferred DNS server | `fd00:1234:5678:50::11` (see note) |

The gateway stays blank because there is no IPv6 route off the LAN.

> **Not verified:** the IPv6 DNS server value used on the Windows machines in this build was not recorded. Pi-hole's IPv6 address is the logical value. A domain controller that must resolve through itself is a special case; follow your directory's own DNS guidance.

### Step 5. Everything else

Phones, tablets, TVs and other DHCP clients need nothing. Devices on the guest/IoT network get no IPv6.

### Step 6. kubectl from a laptop

Copy `/etc/rancher/k3s/k3s.yaml` from a server to `~/.kube/config` on the laptop and change its `server:` line to the floating API address:

```yaml
    server: https://192.168.50.10:6443
```

That file is the cluster's admin key. Keep it out of any repository and out of chats. On a VPN laptop, `k3s.home.example.com` is in the hosts file from Step 1.

## Browser issues with the home web apps

| What you see | Why | What to do |
| --- | --- | --- |
| Certificate warning on `https://pihole.home.example.com`, `https://hb.home.example.com` | Traefik serves its built-in self-signed certificate | Expected. Accept the warning once per browser. To remove it for good you need a real certificate for `*.home.example.com`, for example cert-manager with a Let's Encrypt **DNS** challenge. An HTTP challenge cannot work for names that only exist inside the house. **Not verified:** this was not built |
| Pi-hole login returns to the login page | The sticky cookie `pihole_pod`, which pins your browser to one Pi-hole pod, is missing, blocked or stale | Clear cookies for the site, or try a private window. Check the cookie is offered: `curl -skI https://pihole.home.example.com/admin/ \| grep -i set-cookie` must show `pihole_pod`. Details: [Pi-hole](pihole.md) |
| Pi-hole dashboard shows almost no queries | Your cookie pins you to a standby pod | Delete the `pihole_pod` cookie, or open `http://192.168.50.11/admin` |
| The name resolves and `curl` works, but the browser does not load the page | Browser state: cached redirect, old cookie, or the certificate warning not yet accepted | Private window; clear cookies for that name; accept the warning |
| The browser ignores the hosts file | The browser's own "secure DNS" (DNS-over-HTTPS) setting bypasses the system resolver | Turn secure DNS off in that browser for this machine. This is general browser behaviour, not something observed in the tested build |

## Reaching the house from a VPN or another subnet

When you are connected through a VPN, your traffic can arrive at the home devices from a different range than the LAN. In this build, VPN clients arrived from `192.168.0.x` while the LAN is `192.168.50.0/24`.

| Symptom | Cause | Fix |
| --- | --- | --- |
| SSH to a node, Homebridge on `:8581`, or the Kubernetes API time out from the VPN range | The node's host firewall allowed only `192.168.50.0/24`. Anything addressed to a node itself was refused | Allow the wider range (`192.168.0.0/16` here). [Node firewall](../kubernetes/node-firewall.md) |
| Home names do not resolve | The VPN's DNS answers instead of Pi-hole | Step 1 |
| A name for a new app does not resolve | The hosts file has no wildcards | Add the name to the `192.168.50.12` line |
| Works on home Wi-Fi, not from the VPN, and the firewall shows no blocks | The reply has no route back to the VPN subnet | **Run on: server-1** `ip route get 192.168.0.10`. It should leave via `192.168.50.1` |
| Pi-hole web login loops only from the VPN laptop | Seen together with the firewall range problem and a lopsided Pi-hole pod placement. Both were fixed at the same time, so which one cured it was not separated | Fix both: [Node firewall](../kubernetes/node-firewall.md), [Pi-hole](pihole.md) |

To see whether a node firewall is refusing you, watch its log while you retry:

**Run on: server-1**

```bash
sudo journalctl -k -f | grep "UFW BLOCK"
```

Lines with your client's address as `SRC` mean the firewall is refusing you.

## Check it

**Run on: your computer**

```bash
dscacheutil -q host -a name hb.home.example.com
curl -skI https://pihole.home.example.com/admin/ | head -3
```

Expected: `ip_address: 192.168.50.12`, and an HTTP status line (`200` or `302`), not a timeout.

On a device **not** on a VPN, plain DNS should work without any hosts file:

```bash
nslookup hb.home.example.com
```

Expected: `192.168.50.12`.

## Pitfalls

| What happens | Why | Avoid or recover |
| --- | --- | --- |
| "Pi-hole's HTTPS does not resolve" on one laptop only | That laptop is on a VPN; its DNS never reaches Pi-hole | Step 1. Do not go looking for a fault in Pi-hole |
| A name resolves to an old address | A stale hosts line, or an old `address=` line in the Pi-hole values file | Step 1 removes old lines first; check the values file |
| `nslookup` says NXDOMAIN after editing the hosts file | `nslookup` skips the hosts file | Use `dscacheutil -q host -a name <name>` (macOS) or `getent hosts <name>` (Linux) |
| Names stop resolving on a managed laptop | The hosts file was reset | Re-apply Step 1 |
| A device has no DNS at all | Its per-device rule points at a dead server | Step 2 |
| The whole house has no DNS and you need it back now | Pi-hole is down | The emergency bypass in [Pi-hole](pihole.md), "Troubleshooting" |

## Troubleshooting

Find out what a device is really using.

**Run on: the affected device**

```bash
ping -c 2 1.1.1.1
nslookup example.com
nslookup example.com 192.168.50.11
nslookup example.com 1.1.1.1
```

| Result | Meaning | Next |
| --- | --- | --- |
| Ping to `1.1.1.1` fails | Not DNS. The connection or the router | Router WAN status, modem, cables |
| Ping works, all three lookups fail | The device cannot reach any DNS | Is it on the right Wi-Fi? Does it have a `192.168.50.x` address? |
| Second lookup (via `.11`) fails, third (via `1.1.1.1`) works | Pi-hole is not answering. If the router redirects all DNS to Pi-hole, the third would fail too, so this result usually means the device has a per-device exception | [Pi-hole](pihole.md) |
| Only the first (default) lookup fails | The device uses some other DNS server | Mac: `scutil --dns \| grep nameserver`. A VPN is the usual reason |
| Everything works but one site does not | Pi-hole is blocking it | Pi-hole query log, then the allowlist |

More: [Troubleshooting](../operations/troubleshooting.md).

## Undo

**Run on: your computer**

```bash
sudo cp /etc/hosts.bak /etc/hosts
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

This restores the hosts file saved in Step 1. Remove `~/.kube/config` from a laptop that should no longer have cluster access.

## References

- [hosts(5) Linux manual page](https://man7.org/linux/man-pages/man5/hosts.5.html): the hosts file format (one address, then names; no wildcards). macOS uses the same format.
- [Asuswrt-Merlin wiki: DNS Director](https://github.com/RMerl/asuswrt-merlin.ng/wiki/DNS-Director): forcing devices to specific DNS servers, globally and per device.
- [K3s: Cluster access](https://docs.k3s.io/cluster-access): copying `k3s.yaml` to another machine and changing the `server` address.
- [Traefik: Kubernetes Ingress routing configuration](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/ingress/): the sticky-cookie annotation behind the `pihole_pod` cookie.
