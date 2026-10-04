# 11. Client devices

## The work MacBook (on the company VPN)

The VPN sends the Mac's DNS to its own proxy (`fddd:dddd::…`), which answers NXDOMAIN for `home.example.com` names. The Mac never asks Pi-hole. `/etc/hosts` is checked first, so the home names go there.

**Paste on: Mac Terminal**, one at a time.

Back up the current file:

```bash
sudo cp /etc/hosts /etc/hosts.bak
```

Remove old home lines (this clears stale entries such as Pi-hole on .11 or Homebridge on .5):

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

Flush the cache and check:

```bash
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
dscacheutil -q host -a name pihole.home.example.com
```

It should print `ip_address: 192.168.50.12`. **Do not check with `nslookup`**: it skips the hosts file and will still say NXDOMAIN.

The same two lines are in [`clients/work-mac-hosts.txt`](../clients/work-mac-hosts.txt).

- `/etc/hosts` has no wildcards. Every new app behind Traefik must be added to the `192.168.50.12` line.
- It is a managed machine. If the names stop resolving one day, check whether the file was reset.
- An alternative that needs no hosts file on any machine: a DNS-only record `*.home` → 192.168.50.12 in Cloudflare. It publishes a private address in public DNS, which is harmless but visible. Not done.

## Other Macs

System Settings → Network → the active service → Details → TCP/IP → **Configure IPv6: Automatically**. Not "Link-Local Only", which would discard the local IPv6 address and the IPv6 DNS server.

Check in Terminal:

```bash
ifconfig | grep "inet6 fd00"
scutil --dns | grep "nameserver\[" | sort -u
```

Expect at least one `fd00:1234:5678:50:` address and both `192.168.50.11` and `fd00:1234:5678:50::11` as nameservers.

The server Mac's wired interface is `en8`. A fixed `fd00:1234:5678:50::2` is set by: Configure IPv6 **Manually**, address `fd00:1234:5678:50::2`, prefix length 64, router blank. Pi-hole serves `shows`, `movies` and `plex` on that address, so keep it.

## Windows servers (dc01, ca01)

Adapter → Properties → Internet Protocol Version 6 (TCP/IPv6) → Properties:

| Field | dc01 | ca01 |
| --- | --- | --- |
| IPv6 address | `fd00:1234:5678:50::16` | `fd00:1234:5678:50::17` |
| Subnet prefix length | 64 | 64 |
| Default gateway | blank | blank |
| Preferred DNS server | not recorded | not recorded |

The gateway stays blank because there is no IPv6 route off the LAN. The DNS value you entered was never written down; open the dialog on dc01 and record it here.

## Everything else

Phones, tablets, TVs and other DHCP clients need nothing. Guest-network devices get no IPv6.

Do not add an IPv6 DNS server to the router's DHCP page as a "secondary". Clients already learn Pi-hole's IPv6 address from the router's advertisements, and it is the same Pi-hole.

## kubectl from a laptop

Copy `/etc/rancher/k3s/k3s.yaml` from k3sprimary to `~/.kube/config` on the laptop and change its `server:` line to `https://192.168.50.10:6443`. That file is the cluster's admin key: keep it out of this repo.
