# Verification

A single checklist that proves the whole build works: network, DNS, local IPv6, the isolated network, the cluster, the load balancers and the apps. Run it after a rebuild, after a firmware or k3s upgrade, and after any change you are not sure about.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | ASUS ZenWiFi XT8 on Asuswrt-Merlin (GNUton build 3004.388.10_2), OpenWrt and stock-firmware access points, k3s v1.34.3+k3s1 on three Raspberry Pis and one Lima VM, MetalLB v0.15.3, kube-vip, Pi-hole, Homebridge, Seerr |
| **Also works for** | Any subset of the build. Skip the groups for modules you do not have. Client commands are written for macOS; Linux equivalents are noted. Not tested by the author on other clients |
| **Time** | 15 minutes without the failover tests; allow 30 more for failover |
| **You need first** | Whichever modules you built. Each group below links to its page |

## How it works

Each check is a row: what is tested, where to run it, the command, and the result that counts as a pass. The groups go from the bottom of the stack upwards, so the first failing row is usually the cause of the later ones.

"Client" means an ordinary device on the main Wi-Fi that gets its settings from the router. A laptop on a VPN is not a valid client for these tests, because the VPN replaces its DNS and routes ([Client devices](../apps/client-devices.md)).

## Before you start

- Have a client on the main Wi-Fi, a device on the IoT/guest Wi-Fi, and a phone that can switch to mobile data.
- Have SSH to the router and to `server-1`.
- If `server-1` is the thing that is down, run the cluster commands on `server-2` or `server-3`. Every Pi is a server and has `kubectl`.
- Know how to open the Pi-hole query log (`https://pihole.home.example.com/admin`, **Query Log**).

> **Not verified:** the author confirmed tests 1, 4, 6, 9 and 11 and the cluster and app groups. Tests 2, 3, 5, 7, 8, 10 and 12 were written from the design and are not recorded as having been run from a personal client. The failover group has never been run. Treat a failure in those rows as a real finding, not as your mistake.

## Steps

### Step 1. Network and DNS

Details: [DNS design](../network/dns-design.md), [ASUS ZenWiFi XT8](../hardware/asus-zenwifi-xt8.md), [Pi-hole](../apps/pihole.md).

| # | Test | Run on | Command | Pass |
| --- | --- | --- | --- | --- |
| 1 | Router health | The router | `sh /jffs/xt8-bootstrap.sh verify` | `0 failed` |
| 4 | Pi-hole answers on IPv4 | Client | `nslookup example.com 192.168.50.11` | An answer |
| 6 | Blocking works | Client | `nslookup doubleclick.net` | `0.0.0.0` |
| 7 | Hard-coded DNS is redirected to Pi-hole | Client | `dig @8.8.8.8 example.com`, then look at the Pi-hole query log | The answer arrives **and** the query is in the Pi-hole log |
| 9 | Pi-hole's upstream is encrypted (DNS over HTTPS) | server-1 | `sudo kubectl logs -n pihole deploy/pihole -c cloudflared --tail=20` | Connections to `https://1.1.1.1/dns-query`, no errors |
| 10 | Public leak test | Client | Open `https://www.dnsleaktest.com` and run the extended test | Only Cloudflare resolvers listed |
| 11 | Local names resolve | Client | `nslookup server-1` and `nslookup hb.home.example.com` | `192.168.50.5` and `192.168.50.12` |

The test numbers are kept stable across this page, so the gaps (2, 3, 5, 8, 12) are in the next two groups.

> **Pitfall:** do not test `192.168.50.11` or `192.168.50.12` with `ping`. MetalLB addresses do not have to answer ping. Use `nslookup` or `curl`.

> **Note:** the bootstrap script's `verify` checks the router's upstream against three values at the top of the script (`WAN_DNS`, `WAN_DNS2`, `WAN_DOT`). As shipped it expects DNS over TLS to Cloudflare, which is what this build uses. If you chose otherwise, change those values or the check fails ([DNS design](../network/dns-design.md) Step 4).

### Step 2. Local IPv6

Skip this group if you did not set up [Local-only IPv6](../network/local-only-ipv6.md).

| # | Test | Run on | Command | Pass |
| --- | --- | --- | --- | --- |
| 2 | Client got the local prefix | Client | macOS: `ifconfig \| grep "inet6 fd00"`. Linux: `ip -6 addr \| grep fd00` | An address in `fd00:1234:5678:50::/64` |
| 3 | No IPv6 default route | Client | macOS: `netstat -rn -f inet6 \| grep default`. Linux: `ip -6 route show default` | No line pointing at the router. The prefix is local only; a default route would send internet traffic into a dead end |
| 5 | Pi-hole answers on IPv6 | Client | `nslookup example.com fd00:1234:5678:50::11` | An answer |
| 8 | The router refuses DNS on IPv6 | Client | `dig @fd00:1234:5678:50::1 example.com` | Refused or timed out. Clients must use Pi-hole, not the router |
| | Router sees IPv6 neighbours | The router | `ip -6 neigh show dev br0` | Client addresses listed. The GUI page **System Log → IPv6** says "IPv6 Not enabled"; that is expected, because IPv6 is set up by script and not through the GUI |
| | OpenWrt AP has IPv6 on its bridge | ap-openwrt | `ip -6 addr show br-lan` | An `fd00:1234:5678:50:` address |

An IPv6 ping to the stock-firmware AP times out. That is expected: in access point mode it has no IPv6 address of its own, and its Wi-Fi clients still get IPv6 from the router because it bridges.

### Step 3. Isolation

Details: [Isolated IoT network](../network/isolated-iot-network.md), [Kasa across networks](../apps/homebridge-kasa-across-networks.md).

| # | Test | Run on | Command | Pass |
| --- | --- | --- | --- | --- |
| 12 | Guest isolation holds | A device on `Home-IoT` | Open `http://192.168.50.1` | Fails to load |
| | IoT device gets an IoT address | A device on `Home-IoT`, once through the router and once through the extra AP | Look at its Wi-Fi details | An address in `192.168.101.0/24` |
| | VLAN reaches the extra AP | The router | `brctl show` | The `.501` interfaces are members of `br1` |
| | Controlled access from the LAN still works | server-1 | `ping -c 3 192.168.101.201` (use one of your IoT devices) | Replies |
| | Same, on the device's control port | server-1 | `nc -vz -w 3 192.168.101.201 9999` | Connection succeeds (Kasa devices) |

> **Not verified:** a client receiving a `192.168.101.x` address through the OpenWrt AP's `Home-IoT` SSID was not reported by the author. The SSID was confirmed broadcasting only.

### Step 4. Cluster

Details: [k3s HA cluster](../kubernetes/k3s-ha-cluster.md), [CoreDNS](../kubernetes/coredns.md).

**Run on: server-1**

```bash
sudo kubectl get nodes -o wide
sudo kubectl get pods -A | grep -v -E 'Running|Completed'
sudo kubectl -n pihole get pods -o wide
sudo kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
sudo kubectl -n kube-system get pod -l k8s-app=kube-dns -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.status.podIPs}{"\n"}{end}'
sudo kubectl -n kube-system get endpointslices -l kubernetes.io/service-name=kube-dns
```

| Command | Pass |
| --- | --- |
| `get nodes` | Four nodes `Ready`, all with roles `control-plane,etcd` |
| `get pods -A \| grep -v` | Prints only the header line |
| `-n pihole get pods` | Three Pi-hole pods, one per Pi, each `2/2` |
| `get pods -l k8s-app=kube-dns` | Three CoreDNS pods `Running`, on different nodes, at least one on a Pi |
| `jsonpath ... podIPs` | Every CoreDNS pod has two addresses: a `10.42.x.x` and an `fd00:1234:5678:42xx::` one |
| `get endpointslices` | Both `kube-dns` endpoint slices (IPv4 and IPv6) list endpoints, not `<unset>` |

### Step 5. Load balancers

Details: [Load balancers](../kubernetes/load-balancers.md).

**Run on: server-1**

```bash
sudo kubectl get svc -A | grep LoadBalancer
sudo kubectl get pods -n kube-system | grep svclb
sudo kubectl --server https://192.168.50.10:6443 get nodes
```

| Command | Pass |
| --- | --- |
| `get svc ... LoadBalancer` | Exactly two addresses in use: `192.168.50.11` (and `fd00:1234:5678:50::11`) for the `pihole-*` Services, `192.168.50.12` for `traefik`. No `<pending>`, no node address (.5, .6, .7) |
| `grep svclb` | Prints nothing. The k3s built-in load balancer (ServiceLB) is off |
| `--server https://192.168.50.10:6443` | The API answers on the floating address (kube-vip) |

### Step 6. Apps

Details: [Pi-hole](../apps/pihole.md), [Homebridge](../apps/homebridge.md), [Homebridge cameras](../apps/homebridge-cameras.md), [Seerr behind a Cloudflare tunnel](../apps/seerr-cloudflare-tunnel.md).

| Test | Run on | Command or action | Pass |
| --- | --- | --- | --- |
| Pi-hole UI over HTTPS | Client browser | `https://pihole.home.example.com/admin` | Loads; the login **stays** logged in after clicking around |
| HTTP redirects | Client browser | `http://pihole.home.example.com/admin` | Redirects to `https` |
| Sticky cookie is set | Client | `curl -skI https://pihole.home.example.com/admin/ \| grep -i set-cookie` | A line containing `pihole_pod` |
| Homebridge UI | Client browser | `https://hb.home.example.com` | Loads; all child bridges running |
| Homebridge pod DNS | Homebridge UI → Terminal | `cat /etc/resolv.conf` | One name server, `10.43.0.10`; `options ndots:1`; no `fd00:` line |
| No fresh DNS or auth errors | Homebridge UI → Terminal | `grep -E 'ENOTFOUND\|EAI_AGAIN\|401\|Unauthorized' /var/lib/homebridge/homebridge.log \| tail -5` | Nothing newer than the last redeploy |
| A switch on the IoT network | Home app | Toggle a Kasa switch | Responds within a second or two |
| Cameras | Home app | Open each camera | Live picture |
| Seerr from outside | Phone on mobile data | `https://request.example.com` | Seerr loads |
| Cloudflare tunnel service | server-1 | `systemctl status cloudflared` | `active (running)` |

### Step 7. Failover

> **Not verified:** the author has never run these tests. No node has been rebooted to prove failover. The expected results below follow from the design.

Do this when a few minutes of disruption is acceptable.

1. **Reboot one Pi that is not `server-1`.**

   **Run on: server-2**

   ```bash
   sudo reboot
   ```

   While it is down:

   | Run on | Command | Pass |
   | --- | --- | --- |
   | server-1 | `sudo kubectl get nodes` | Still answers; `server-2` shows `NotReady` |
   | Client | `nslookup example.com 192.168.50.11` | Still answers |

   Wait for `server-2` to be `Ready` again before the next test.

2. **Reboot `server-1`.** This is the real test, because `server-1` holds the apps that live on one node only.

   | Run on | Command | Pass |
   | --- | --- | --- |
   | Client | `nslookup example.com 192.168.50.11` | Keeps answering; the address moves to another Pi within seconds |
   | server-2 | `sudo kubectl --server https://192.168.50.10:6443 get nodes` | Answers from another node |
   | Client | Homebridge, Seerr, the Cloudflare tunnel | **Down** until `server-1` is back. Expected: their storage and the tunnel service live only there |

3. If DNS stops during either test, find which node MetalLB announced the address from and read the speaker logs.

   **Run on: any server that is up**

   ```bash
   sudo kubectl -n metallb-system logs -l component=speaker --tail=50
   ```

## Check it

The build passes when every row above passes. Record the date and the k3s and firmware versions next to your result, so the next run has something to compare with.

## Pitfalls

| What happens | Why | What to do |
| --- | --- | --- |
| Tests fail from a laptop on a VPN | The VPN's DNS and routes replace the home ones | Use a device that is not on a VPN |
| Test 7 "passes" because an answer arrives | An answer alone proves nothing; the redirect is only proven when the query shows in the Pi-hole log | Always check the log |
| Pi-hole query log does not show your test query | Three pods keep separate logs and statistics | Look at `http://192.168.50.11/admin`, which is the pod currently holding the address |
| The second cluster command lists pods just after a restart | Pi-hole pods wait 60 seconds and download blocklists before they are ready | Wait five minutes after a power cut or restart, then test |
| Failover test stops the control plane | With the Mac VM off or asleep, three servers remain and quorum needs two; one more down still works, two more does not | Check `limactl list` on the Mac before rebooting a Pi |
| CoreDNS shows one pod after an upgrade | The replica count is set by command, not by a file | [CoreDNS](../kubernetes/coredns.md) |

## Troubleshooting

A failed row is a symptom. Look it up in [Troubleshooting](troubleshooting.md), which starts from symptoms and links back to the module pages.

## References

- [k3s: Networking services](https://docs.k3s.io/networking/networking-services): what CoreDNS, Traefik and ServiceLB do in k3s and how ServiceLB is disabled, which the load balancer checks rely on.
- [k3s: etcd-snapshot](https://docs.k3s.io/cli/etcd-snapshot): take a snapshot before the failover tests.
- [MetalLB: Troubleshooting](https://metallb.io/troubleshooting/): how to find out why an address is not assigned or announced.
- [Kubernetes: Debugging DNS resolution](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/): the upstream method behind the CoreDNS checks.
- [DNS leak test: what is a DNS leak](https://www.dnsleaktest.com/what-is-a-dns-leak.html): what test 10 measures.
- [Pi-hole documentation](https://docs.pi-hole.net/): the query log and blocking behaviour used in tests 6 and 7.
