# 12. Verification

Run after any rebuild or big change. "Client" means a personal device on the main Wi-Fi, not the work Mac on VPN.

## Network and DNS

| # | Test | Where | Command | Pass |
| --- | --- | --- | --- | --- |
| 1 | Router health | XT8 | `sh /jffs/xt8-bootstrap.sh verify` | 0 failed |
| 2 | Client got the IPv6 prefix | Client | `ifconfig \| grep "inet6 fd00"` | An address in `fd00:1234:5678:50::/64` |
| 3 | No IPv6 default route | Client | `netstat -rn -f inet6 \| grep default` | No line pointing at the XT8 |
| 4 | Pi-hole on IPv4 | Client | `nslookup example.com 192.168.50.11` | Answer |
| 5 | Pi-hole on IPv6 | Client | `nslookup example.com fd00:1234:5678:50::11` | Answer |
| 6 | Blocking | Client | `nslookup doubleclick.net` | `0.0.0.0` |
| 7 | Hard-coded DNS is redirected | Client | `dig @8.8.8.8 example.com`, then look at the Pi-hole query log | Answer arrives **and** the query is in the log |
| 8 | Router refuses IPv6 DNS | Client | `dig @fd00:1234:5678:50::1 example.com` | Refused or timed out |
| 9 | Upstream is DoH | k3sprimary | `sudo kubectl logs -n pihole deploy/pihole -c cloudflared --tail=20` | Connections to `https://1.1.1.1/dns-query`, no errors |
| 10 | Public leak test | Client | `https://www.dnsleaktest.com`, extended test | Only Cloudflare resolvers |
| 11 | Local names | Client | `nslookup k3sprimary` and `nslookup hb.home.example.com` | 192.168.50.5 and 192.168.50.12 |
| 12 | Guest isolation holds | Guest-network device | Open `http://192.168.50.1` | Fails |

Tests 2, 3, 5, 7, 8, 10 and 12 were still owed from a personal device when the September runbook was written. I have no record of them being run since.

## Cluster

**Paste on: k3sprimary.**

```bash
sudo kubectl get nodes -o wide
sudo kubectl get pods -A | grep -v -E 'Running|Completed'
sudo kubectl get svc -A | grep LoadBalancer
sudo kubectl get pods -n kube-system | grep svclb
sudo kubectl -n pihole get pods -o wide
sudo kubectl --server https://192.168.50.10:6443 get nodes
```

| Pass |
| --- |
| Four nodes `Ready`, all `control-plane,etcd` |
| Second command prints only the header |
| Exactly two addresses in use: 192.168.50.11 (and `::11`) for the `pihole-*` Services, 192.168.50.12 for `traefik` |
| Fourth command prints nothing (servicelb is off) |
| Three Pi-hole pods, one per Pi, `2/2` |
| The API answers on the floating address |

## Apps

| Test | Pass |
| --- | --- |
| `https://pihole.home.example.com/admin` | Loads; login **stays** logged in after clicking around |
| `http://pihole.home.example.com/admin` | Redirects to https |
| `https://hb.home.example.com` | Loads; all child bridges running |
| Toggle a Kasa switch in the Home app | Works within a second or two |
| `ping -c 3 192.168.101.201` from k3sprimary | Replies |
| Each camera in the Home app | Live picture |
| `https://request.example.com` from a phone on mobile data | Seerr loads |

## Failover (never run so far)

Do this when a few minutes of disruption is acceptable.

**Reboot funkyfresh** (`sudo reboot` on it). While it is down, on k3sprimary `sudo kubectl get nodes` still answers, and from a client `nslookup example.com 192.168.50.11` still answers.

**Reboot k3sprimary.** This is the real test. Expect: DNS keeps answering (the address moves to another Pi within seconds); `kubectl --server https://192.168.50.10:6443 get nodes` works from another node; Homebridge, Seerr and the Cloudflare tunnel are **down** until k3sprimary is back, because they live only there.

If DNS stops during either test, look at which node MetalLB announced from and at the speaker logs: `sudo kubectl -n metallb-system logs -l component=speaker --tail=50`.
