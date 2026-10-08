# Troubleshooting

Symptom-first troubleshooting for the whole build. The first half tells you what to run, in order, when you only know what is wrong ("the internet is down"). The second half is a lookup table of every specific failure met while building this, by area, with cause and fix.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | ASUS ZenWiFi XT8 on Asuswrt-Merlin (GNUton build 3004.388.10_2), Archer A7 on OpenWrt, Archer AX21 stock firmware, k3s v1.34.3+k3s1 on three Raspberry Pis and a Lima VM, MetalLB v0.15.3, kube-vip, Traefik, Pi-hole, Homebridge, Seerr with a Cloudflare tunnel |
| **Also works for** | Any subset. Each section says which module it concerns; skip the ones you do not have |
| **Time** | Two minutes for the health check; most faults are found within ten |
| **You need first** | SSH to a cluster server and to the router |

## How it works

Most faults in this build come from a small number of mechanisms. Knowing them makes the tables below make sense.

| Mechanism | What it causes | Detail |
| --- | --- | --- |
| Every device's DNS goes through Pi-hole, which runs on the cluster | "The internet is down" is nearly always DNS | [DNS design](../network/dns-design.md) |
| Cluster nodes must **not** use Pi-hole for their own DNS | A node that does cannot pull images after a restart, so Pi-hole cannot start: a deadlock | [DNS design](../network/dns-design.md) |
| k3s has a built-in load balancer (ServiceLB) that competes with MetalLB | Services answer on a node's address instead of the shared one | [Load balancers](../kubernetes/load-balancers.md) |
| Pi-hole runs as three pods, each with its own login sessions and statistics | Login loops, "wrong" numbers | [Pi-hole](../apps/pihole.md) |
| ASUS guest-network isolation is enforced in `ebtables`, and a Wi-Fi restart wipes custom rules | Homebridge loses the IoT devices after a router change | [Kasa across networks](../apps/homebridge-kasa-across-networks.md) |
| A pod on the host network cannot reach the cluster's IPv6 DNS address | Intermittent `getaddrinfo ENOTFOUND` in Homebridge plugins | [CoreDNS](../kubernetes/coredns.md) |
| With IPv6 disabled in the router GUI, the firmware blocks the router's own IPv6 output | Clients never receive the local IPv6 prefix | [Local-only IPv6](../network/local-only-ipv6.md) |
| A VPN on a laptop replaces its DNS and may arrive from another subnet | Home names do not resolve; node firewall refuses the laptop | [Client devices](../apps/client-devices.md) |
| Storage for Homebridge and Seerr lives on one node | Those apps are down whenever that node is | [k3s HA cluster](../kubernetes/k3s-ha-cluster.md) |
| Leftover k3s `server` folders, a VM joining on the wrong interface or under the wrong name | A server will not join or shows up twice | [k3s HA cluster](../kubernetes/k3s-ha-cluster.md), [Mac Lima VM](../hardware/mac-lima-vm.md) |
| Scribe's log rotation needs a folder nothing creates | The router log grows without limit | [Router logging](../network/router-logging.md) |

## Before you start

- Unless a section says otherwise, commands run on `server-1`. If `server-1` is the thing that is down, use `server-2` or `server-3`; every Pi is a server and has `kubectl`.
- Paste command blocks exactly as they are, starting at the left margin. One-line commands must stay on one line.
- Do not test a MetalLB address (`192.168.50.11`, `192.168.50.12`) with `ping`. A failed ping is normal. Use `nslookup` or `curl`.

## Steps

### Step 1. The two-minute health check

Run this first, whatever the symptom.

**Run on: server-1**

```bash
sudo kubectl get nodes -o wide
sudo kubectl get pods -A -o wide | grep -v -E 'Running|Completed'
sudo kubectl get svc -A | grep LoadBalancer
sudo kubectl -n pihole get pods -o wide
nslookup example.com 192.168.50.11
```

| What you see | Go to |
| --- | --- |
| `kubectl` itself does not answer | [Step 7](#step-7-kubectl-does-not-answer-or-a-node-is-notready) |
| A node is `NotReady` | [Step 7](#step-7-kubectl-does-not-answer-or-a-node-is-notready) |
| Pods are listed by the second command | Describe one: `sudo kubectl -n <namespace> describe pod <name> \| tail -20`. The last lines say why (`ImagePullBackOff`, `Pending`, `CrashLoopBackOff`): [Step 6](#step-6-a-pod-will-not-start) |
| A LoadBalancer shows `<pending>`, or a node's own address (.5, .6, .7) instead of .11 / .12 | The built-in load balancer is back, or MetalLB is down. [Load balancers](../kubernetes/load-balancers.md) |
| Pi-hole pods are not one per Pi | [Pi-hole](../apps/pihole.md), two pods on one node |
| `nslookup` fails | [Step 2](#step-2-the-internet-is-down-dns) |
| All five look right | The cluster is fine. The problem is on the device, the router or the path: [Step 2](#step-2-the-internet-is-down-dns), [Step 3](#step-3-a-web-page-of-mine-will-not-load) |

### Step 2. "The internet is down" (DNS)

Almost every "the internet is down" in a house that runs its own DNS is DNS. Work from the device outwards.

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
| Ping works, all three lookups fail | The device cannot reach any DNS server | Is it on the right Wi-Fi? Does it have a `192.168.50.x` address? |
| Second lookup (via `.11`) fails, third (via `1.1.1.1`) works | Pi-hole is not answering. The router's DNS Director normally redirects the third lookup to Pi-hole too, so this result usually means the device has a DNS Director exception | Continue below |
| Only the first (default) lookup fails | The device is using some other DNS server | macOS: `scutil --dns \| grep nameserver`. A VPN is the usual reason ([Client devices](../apps/client-devices.md)) |
| Everything works but one site does not | Pi-hole is blocking it | Pi-hole query log, then add the name to `whitelist:` in [values.yaml](../../files/pihole/values.yaml) and apply it |

If Pi-hole is not answering:

**Run on: server-1**

```bash
sudo kubectl -n pihole get pods -o wide
sudo kubectl -n pihole get svc
sudo kubectl -n pihole get events --sort-by=.lastTimestamp | tail -15
sudo kubectl -n metallb-system get pods -o wide
```

| Result | Meaning | Fix |
| --- | --- | --- |
| No pod is `2/2 Running` | Pi-hole is down everywhere | `describe pod`. Most likely an image pull failure (node DNS, [Step 6](#step-6-a-pod-will-not-start)) or the admin Secret is missing ([Pi-hole](../apps/pihole.md)) |
| Pods are `1/2` | The encryption sidecar or Pi-hole itself is failing | `sudo kubectl -n pihole logs <pod> -c cloudflared --tail=20` and `sudo kubectl -n pihole logs <pod> -c pihole --tail=40` |
| Pods fine, Services show `.11` | MetalLB is not announcing, or announces from a node with no healthy pod | `sudo kubectl -n metallb-system logs -l component=speaker --tail=30`. Restart the speakers: `sudo kubectl -n metallb-system rollout restart daemonset speaker` |
| Services show `<pending>` | MetalLB controller down or address pool missing | [Load balancers](../kubernetes/load-balancers.md) |
| Everything looks fine here | The fault is between the device and `.11` | From another device: `nslookup example.com 192.168.50.11`. If that works, it is the one device. If the node firewall is on, see [Step 8](#step-8-is-the-node-firewall-the-cause) |

**Emergency bypass**, to get the house working while you fix it. In the router GUI:

1. **LAN → DHCP Server → DNS Server 1** → `9.9.9.9`.
2. **LAN → DNS Director → Global Redirection** → **No Redirection**.
3. Apply.

Devices pick it up as they renew their lease; toggle Wi-Fi to force it.

> **Pitfall:** put both settings back afterwards (`192.168.50.11`, and the user-defined entry that points at Pi-hole). It is easy to leave DNS Server 1 changed after troubleshooting; check it whenever DNS behaves oddly.

### Step 3. A web page of mine will not load

Covers the Pi-hole UI, Homebridge and Seerr. Find which hop is broken, from the pod outwards.

**Run on: server-1**

```bash
sudo kubectl get ingress -A
sudo kubectl get svc -A | grep -E 'traefik|LoadBalancer'
curl -sI -H 'Host: pihole.home.example.com' http://192.168.50.12/admin/ | head -3
curl -sI -H 'Host: hb.home.example.com' http://192.168.50.12/ | head -3
curl -sI -H 'Host: request.example.com' http://192.168.50.12/ | head -3
```

The `curl` lines ask Traefik directly for each site by name, which takes DNS out of the picture.

| Result | Meaning | Fix |
| --- | --- | --- |
| `curl` cannot connect at all | Traefik is not on `192.168.50.12` | `sudo kubectl -n kube-system get pods \| grep traefik` and [Load balancers](../kubernetes/load-balancers.md) |
| `404 page not found` | Traefik is up but has no rule for that name | The Ingress is missing or has another host name. Apply the app's values file again |
| `502` or `Bad Gateway` | Traefik has the rule but the app does not answer | The pod is down, or (Homebridge) its own HTTPS is switched on |
| `301`, `302`, `307` or `200` | The cluster side is fine | The problem is the name or the client: next block |

**Run on: the device that cannot load the page**

```bash
nslookup pihole.home.example.com
curl -skI https://pihole.home.example.com/admin/ | head -3
```

| Result | Meaning | Fix |
| --- | --- | --- |
| Name does not resolve (`NXDOMAIN`) | The device is not asking Pi-hole | VPN laptop: `/etc/hosts` ([Client devices](../apps/client-devices.md)). Others: check which DNS server they use |
| Resolves to something other than `192.168.50.12` | Stale entry | An old `/etc/hosts` line, or an old `address=` line in the Pi-hole values file |
| Resolves, `curl` works, the browser does not | Browser state | Private window; clear cookies for that name; accept the certificate warning |
| Resolves, `curl` times out | The path is blocked | From a VPN: [Step 9](#step-9-reaching-the-house-from-a-vpn) |
| Seerr from outside shows a Cloudflare error page | Tunnel or route | `systemctl status cloudflared` on `server-1`; the tunnel's route URL must be `192.168.50.12` ([Seerr behind a Cloudflare tunnel](../apps/seerr-cloudflare-tunnel.md)) |

### Step 4. Pi-hole logs me in and throws me back out, or the numbers look wrong

**Run on: server-1**

```bash
sudo kubectl -n pihole get pods -o wide
for p in $(sudo kubectl -n pihole get pods -o name); do echo "$p: $(sudo kubectl -n pihole exec $p -c pihole -- pihole-FTL sqlite3 /etc/pihole/pihole-FTL.db 'select count(*), count(distinct client) from queries;')"; done
```

The second line prints, for each pod, how many queries it has logged and from how many clients.

| Result | Meaning | Fix |
| --- | --- | --- |
| Two pods on the same node | Lopsided placement after an upgrade | Delete one of the pair ([Pi-hole](../apps/pihole.md)) |
| One pod with thousands of queries, the others with a few | Normal. You may be looking at a standby | Use `http://192.168.50.11/admin` for the busy pod |
| Login loops on `http://192.168.50.11/admin` | More than one pod behind that address on one node | Fix the placement |
| Login loops on `https://pihole.home.example.com` | The sticky cookie is not reaching the browser | `curl -skI https://pihole.home.example.com/admin/ \| grep -i set-cookie` must show `pihole_pod`. If it does, clear the browser's cookies for the site |
| All counters are zero or tiny on every pod | The pods restarted recently | `AGE` column in the first command. Counters do not survive restarts |

> **Not verified:** on the test network the login worked after both the placement fix and a node firewall fix were made. Which of the two cured a VPN laptop's login loop was not separated.

### Step 5. A switch does not respond in the Home app

Use the address of the device that is failing.

**Run on: server-1**

```bash
ping -c 3 192.168.101.201
nc -vz -w 3 192.168.101.201 9999
sudo kubectl -n homebridge get pods -o wide
sudo kubectl -n homebridge logs deploy/homebridge --tail=40 | grep -i -E 'kasa|error|timeout'
```

| Result | Meaning | Fix |
| --- | --- | --- |
| Kasa works but cloud-backed devices (Wyze, a thermostat) lag or fail; the log has `getaddrinfo ENOTFOUND` / `EAI_AGAIN` | DNS inside the pod | [Step 11](#step-11-dns-inside-a-pod) |
| Every accessory says "No Response" | Homebridge itself | Is the pod running? Is `server-1` up? Open `http://192.168.50.5:8581` |
| Ping fails for **every** IoT device | The router rules are gone | On the router: `sh /jffs/scripts/kasa-guest-allow.sh`, then `sh /jffs/xt8-bootstrap.sh verify` |
| Ping fails for **one** device | That device is off the network or changed address | Vendor app; router client list; fix the DHCP reservation and the `manualDevices` entry |
| Ping works, port 9999 refused or `AuthenticationError` in the log | Newer device firmware wants the TP-Link account | Plugin settings ([Kasa across networks](../apps/homebridge-kasa-across-networks.md)) |
| Ping works from `server-1`, Homebridge still times out, the node firewall was recently turned on | The node firewall is refusing the replies | [Step 8](#step-8-is-the-node-firewall-the-cause) |
| Stopped right after a router Wi-Fi change | A Wi-Fi restart wiped the `ebtables` rules and the hook did not restore them | Same fix as "every device"; check `/jffs/scripts/service-event-end` exists and is executable |

### Step 6. A pod will not start

**Run on: server-1**

```bash
sudo kubectl -n <namespace> describe pod <name> | tail -25
```

| Last lines say | Meaning | Fix |
| --- | --- | --- |
| `ImagePullBackOff`, `ErrImagePull`, "no such host" | The **node** cannot resolve or reach the image registry | On that node: `grep nameserver /etc/resolv.conf` must show `1.1.1.1` / `9.9.9.9`, and `nslookup ghcr.io` must work ([DNS design](../network/dns-design.md), [Raspberry Pi](../hardware/raspberry-pi.md)) |
| `Pending`, "didn't match Pod's node affinity/selector" | A node label is missing | `sudo kubectl get nodes -L pihole-host,kube-vip-host` |
| `Pending`, "didn't match pod topology spread constraints" | The only free node is not eligible or not Ready | Is a Pi down? The pod schedules when it returns |
| `Pending`, "persistentvolumeclaim … not found" or "node affinity conflict" | A `local-path` volume lives on a different node | Homebridge and Seerr can only run on the node that holds their data (`server-1`) |
| `CreateContainerConfigError`, "secret … not found" | A Secret was not created | Pi-hole: create `pihole-admin` ([Pi-hole](../apps/pihole.md)) |
| `CrashLoopBackOff` | The app starts and dies | `sudo kubectl -n <namespace> logs <name> --previous --tail=40` |
| `OOMKilled` | Out of memory | Nodes with 2 GB of RAM are at the minimum. `sudo kubectl top nodes` |

### Step 7. kubectl does not answer, or a node is NotReady

**Run on: the node in question**

```bash
sudo systemctl status k3s --no-pager | head -12
sudo journalctl -u k3s --no-pager -n 40
ip -br addr show eth0
free -h
df -h /
```

| Result | Meaning | Fix |
| --- | --- | --- |
| k3s is `active`, `kubectl` on this node works, the floating address does not | kube-vip | `sudo kubectl -n kube-system get pods -o wide \| grep kube-vip`; use `--server https://192.168.50.5:6443` meanwhile |
| Log repeats "etcdserver: no leader" or "context deadline exceeded" | Quorum lost: fewer than three of the four servers are up | Bring another server back. Is the Mac asleep? With the Mac off, one more Pi down stops the control plane |
| Log shows "slow fdatasync" or "apply request took too long" again and again | The disk is too slow for etcd | A spinning hard drive over USB does this. Move the node to an SSD ([Raspberry Pi](../hardware/raspberry-pi.md)) |
| `eth0` has no `192.168.50.x` address | The node lost its address | Reach it over IPv6 from another Pi (`ssh pi@fd00:1234:5678:50::7`), then pin the address ([Raspberry Pi](../hardware/raspberry-pi.md)) |
| Fatal line naming files "newer than datastore" | Leftover server folder | Move `/var/lib/rancher/k3s/server` aside and install again ([k3s HA cluster](../kubernetes/k3s-ha-cluster.md)) |
| Disk at 100% | Logs or images filled it | `sudo k3s crictl rmi --prune`; `sudo journalctl --vacuum-size=200M` |
| The node is fine but shows `NotReady` from the others | The nodes cannot talk to each other | Firewall: [Step 8](#step-8-is-the-node-firewall-the-cause) |
| The Mac node is `NotReady` | The Mac slept, or the VM is stopped | Mac Terminal: `limactl list`, `limactl start k3s-vm` ([Mac Lima VM](../hardware/mac-lima-vm.md)) |

> **Not verified:** recovery from lost quorum (`sudo k3s server --cluster-reset`, optionally with `--cluster-reset-restore-path=<snapshot file>`) has not been run by the author. See [k3s HA cluster](../kubernetes/k3s-ha-cluster.md) and the k3s documentation before relying on it.

### Step 8. Is the node firewall the cause?

Applies if you turned on the host firewall from [Node firewall](../kubernetes/node-firewall.md). Suspect it when something worked, the firewall was enabled or re-enabled, and now a connection **to a node itself** times out; or when you arrive from a network other than `192.168.50.x`.

**Run on: the node**

```bash
sudo ufw status | head -1
sudo journalctl -k --since "10 min ago" | grep "UFW BLOCK" | tail -20
```

Then retry the failing thing while watching:

```bash
sudo journalctl -k -f | grep "UFW BLOCK"
```

| Result | Meaning | Fix |
| --- | --- | --- |
| `Status: inactive` | Not the firewall | Look elsewhere |
| Block lines with your client's address as `SRC` | The firewall is refusing you | Add the range: `sudo ufw allow from <range>`, and put it in [k3s-firewall.sh](../../files/firewall/k3s-firewall.sh) |
| Block lines with another **node's** address as `SRC` and `DPT` 7946, 2379, 2380, 10250 or 8472 | The firewall is breaking the cluster | The node list in the script is incomplete, typically for automatically generated IPv6 addresses ([Node firewall](../kubernetes/node-firewall.md)) |
| No block lines while it fails | Not the firewall | Routing, DNS, or the app |

The quickest proof either way is to switch it off on that node for a minute:

```bash
sudo ufw disable
```

Retry, then:

```bash
sudo ufw enable
```

`ufw disable` keeps the rules; `ufw enable` brings them back.

> **Not verified:** on the test cluster the firewall was active on the Pis but not checked on the Mac VM, and a known gap for nodes' automatically generated IPv6 addresses was still open. Nodes may also carry IPv6 addresses from a second prefix that the router does not hand out (for example from a smart-home Thread border router); the script knows nothing about those.

### Step 9. Reaching the house from a VPN

The example VPN subnet is `192.168.0.x`.

| Symptom | Cause | Fix |
| --- | --- | --- |
| SSH, Homebridge on 8581 or the Kubernetes API time out from `192.168.0.x` | The node firewall allows only `192.168.50.0/24` | Allow the VPN range (the script uses `192.168.0.0/16`) ([Node firewall](../kubernetes/node-firewall.md)) |
| Home names do not resolve on the VPN laptop | The VPN's DNS answers instead of Pi-hole, and returns NXDOMAIN | `/etc/hosts` entries from [work-mac-hosts.txt](../../files/clients/work-mac-hosts.txt) ([Client devices](../apps/client-devices.md)) |
| A name added for a new app does not resolve on the VPN laptop | `/etc/hosts` has no wildcards | Add the name to the `192.168.50.12` line |
| Works on home Wi-Fi, not from the VPN, and the firewall shows no blocks | The reply has no route back to the VPN subnet | On the node: `ip route get 192.168.0.10`. It should leave via `192.168.50.1` |

### Step 10. After a power cut or a router restart

Things come back in the wrong order. This is expected and settles by itself within about five minutes:

1. The router is up before the cluster nodes. Devices have no DNS until one Pi-hole pod is ready.
2. Each Pi-hole pod waits 60 seconds and then downloads its blocklists before it answers.
3. The nodes need their **own** DNS (`1.1.1.1` / `9.9.9.9`) to work at this point. This is the moment a node that depends on Pi-hole deadlocks ([DNS design](../network/dns-design.md)).

If it has not settled after ten minutes: run [Step 1](#step-1-the-two-minute-health-check), then on the router:

**Run on: the router**

```sh
sh /jffs/xt8-bootstrap.sh verify
```

After a router restart specifically, confirm the IoT access rules came back ([Step 5](#step-5-a-switch-does-not-respond-in-the-home-app)).

### Step 11. DNS inside a pod

Symptom: a Homebridge plugin logs `getaddrinfo ENOTFOUND` or `EAI_AGAIN`. The house has DNS and the cluster looks healthy, but an app inside a pod intermittently cannot look names up. The method works for any pod; the Homebridge UI has a terminal, which makes it the easy one.

**1. Which name servers does the pod use?**

**Run in: the pod's shell** (Homebridge UI → Terminal)

```bash
cat /etc/resolv.conf
```

| You see | Meaning |
| --- | --- |
| Only `nameserver 10.43.0.10`, `options ndots:1` | The correct state for Homebridge ([Homebridge](../apps/homebridge.md)). Go to part 2 |
| `10.43.0.10` **and** `fd00:1234:5678:4300::a`, `ndots:5` | The DNS block is missing from the values file. For a host-network pod that is the fault. Apply [values.yaml](../../files/homebridge/values.yaml) |
| `1.1.1.1` / `9.9.9.9` | The pod is using the node's own DNS, not the cluster's. Look at its `dnsPolicy` |

**2. Test each name server on its own, 20 times.** Same shell. It is one line; do not break it. It needs Node.js, which the Homebridge image has.

```bash
node -e 'const d=require("dns").promises;(async()=>{for(const s of process.argv.slice(1)){const r=new d.Resolver({timeout:2000,tries:1});r.setServers([s]);let ok=0,e={};for(let i=0;i<20;i++){try{await r.resolve4("api.wyzecam.com");ok++}catch(x){e[x.code]=(e[x.code]||0)+1}}console.log(s,"ok:",ok,JSON.stringify(e))}})()' 10.43.0.10 fd00:1234:5678:4300::a 1.1.1.1
```

Healthy answer, as observed on the test cluster after the fix:

```
10.43.0.10 ok: 20 {}
fd00:1234:5678:4300::a ok: 0 {"ECONNREFUSED":20}
1.1.1.1 ok: 20 {}
```

The middle line failing is **normal from a host-network pod** and stays that way ([CoreDNS](../kubernetes/coredns.md)). `ECONNREFUSED` is how Node reports "could not contact the server"; the real reason is "Network is unreachable".

| Result | Meaning | Next |
| --- | --- | --- |
| `10.43.0.10` fails, `1.1.1.1` works | CoreDNS, or the pod network to it | Part 3 |
| Both fail | The node has lost its way out, or the router is intercepting | [Step 2](#step-2-the-internet-is-down-dns) |
| Everything listed in `resolv.conf` passes | The failures come in bursts | Run it again when the log shows a fresh error |

**3. Look at CoreDNS.**

**Run on: server-1**

```bash
sudo kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
sudo kubectl -n kube-system get pod -l k8s-app=kube-dns -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.status.podIPs}{"\n"}{end}'
sudo kubectl -n kube-system get endpointslices -l kubernetes.io/service-name=kube-dns
sudo kubectl -n kube-system logs -l k8s-app=kube-dns --tail=100 | grep -v 'import glob'
```

| Result | Meaning | Fix |
| --- | --- | --- |
| Fewer than three pods, or all on one node | The replica count was reset | `sudo kubectl -n kube-system scale deployment coredns --replicas=3` |
| A pod with one address only; the IPv6 endpoint slice shows `<unset>` | The pod is older than the dual-stack conversion | `sudo kubectl -n kube-system rollout restart deployment coredns` |
| `i/o timeout` or `SERVFAIL` in the log | CoreDNS cannot reach its upstream, which is the node's own DNS | Node DNS ([DNS design](../network/dns-design.md)) |
| Only "No files matching import glob pattern" warnings | Normal | Nothing |

**4. Is it the route?**

**Run on: server-1**

```bash
ip -6 route get fd00:1234:5678:4300::a
ip -6 route show default
sudo ip6tables-save | grep -i '4300::a'
ping -6 -c 3 "$(sudo kubectl -n kube-system get pod -l k8s-app=kube-dns -o jsonpath='{.items[0].status.podIPs[1].ip}')"
```

"Network is unreachable", no default route, rules present, ping answers: that is this cluster's normal state. It proves the IPv6 pod network is fine and only the service address is unreachable from the host.

> **Not verified:** `sudo ip -6 route add fd00:1234:5678:4300::/112 dev cni0` on each node would in principle let host-network pods use the IPv6 cluster DNS address. It was not applied or tested, and it is not needed while the pod has an IPv4-only DNS block.

> **Not verified:** only CoreDNS was checked for being older than the dual-stack conversion. Other long-running pods may also be IPv4-only until restarted; the listing command is in [CoreDNS](../kubernetes/coredns.md).

**5. Did it stop?**

**Run in: the Homebridge UI terminal**

```bash
grep -E 'ENOTFOUND|EAI_AGAIN|401|Unauthorized' /var/lib/homebridge/homebridge.log | tail -5
```

Pass: nothing newer than the fix. Before the fix the test system logged an error roughly every half hour, so a few quiet hours is good evidence. Token renewals for cloud plugins happen through the day, so one clean day is the real test.

**Reading a long Homebridge log.** Most of it is Kasa polling. This hides the routine lines and counts what is left:

```bash
grep -viE 'Getting sys_info|Serializing device|Updated sys_info|getSysInfo HTTP|Skipping poll|Getting light info' /var/lib/homebridge/homebridge.log | sed -E 's/^\[[^]]+\] //' | sort | uniq -c | sort -rn | head -40
```

> **Pitfall:** do not search the log for "oom" without `-w`. It matches every line with "room" in it.

## Check it

After any fix, run [Step 1](#step-1-the-two-minute-health-check) again. For a full pass, run [Verification](verification.md).

## Pitfalls

| What happens | Why | How to avoid or recover |
| --- | --- | --- |
| A pasted multi-line command "is missing something" and sits at a `>` prompt | The closing `EOF` line was indented, so the shell never saw it | Every command block here starts at the left margin. Press Ctrl+C and paste again |
| A Helm upgrade removed settings | A partial values file was applied | Always apply the whole file from this repo |
| A long one-line command pasted into the Homebridge UI terminal ran as garbage | It was pasted as several lines | Paste it as one line |
| Ping to `192.168.50.11` or `.12` fails and looks like an outage | MetalLB addresses do not have to answer ping | Test with `nslookup` or `curl` |
| The emergency DNS bypass stays in place | It was not put back | Check DHCP DNS Server 1 and DNS Director after every DNS incident |
| A fix "works" from a VPN laptop but not from other devices, or the other way round | The VPN changes DNS and the source subnet | Test from an ordinary client first |

## Troubleshooting

Lookup tables by area: symptom, cause, fix. The linked page has the detail.

### DNS and Pi-hole

| Symptom | Cause | Fix |
| --- | --- | --- |
| Pi-hole login loops back to the login page | Three pods, each with its own sessions | Use `https://pihole.home.example.com/admin` (through Traefik, with a sticky cookie). [Pi-hole](../apps/pihole.md) |
| `pihole.home.example.com` does not resolve on a VPN laptop | The VPN's DNS proxy returns NXDOMAIN | `/etc/hosts`. [Client devices](../apps/client-devices.md) |
| Pi-hole UI answers on `192.168.50.5`, not `.11`; the `-ipv6` Services are `<pending>` | k3s ServiceLB took over | `disable: servicelb` on every server. [Load balancers](../kubernetes/load-balancers.md) |
| New Pi-hole pods `Pending` | The `pihole-host` label is missing | Label the nodes first, then upgrade. [Pi-hole](../apps/pihole.md) |
| Two Pi-hole pods on one node | Label race | Delete one of the pair |
| Two Pi-hole pods on one node after a Helm upgrade, none on another | Old and new pods were counted together during the rollout | Delete one; `matchLabelKeys: [pod-template-hash]` in the values file (not yet proven through an upgrade). [Pi-hole](../apps/pihole.md) |
| Pods `ImagePullBackOff` | The node's own DNS points at something dead | Node DNS `1.1.1.1` / `9.9.9.9`. [DNS design](../network/dns-design.md) |
| Dashboard shows a handful of queries and clients | You are on a standby pod; statistics are per pod | `http://192.168.50.11/admin` shows the busy one |
| Cannot SSH or open Homebridge on 8581 from a VPN (`192.168.0.x`) | The node firewall allowed only `192.168.50.0/24` | Allow `192.168.0.0/16`. [Node firewall](../kubernetes/node-firewall.md) |
| Pi-hole pod `1/2` after pulling a fresh image | A `cloudflared` build without `proxy-dns` | Keep `doh.tag: "2025.9.1"`. [Pi-hole](../apps/pihole.md) |
| Ping to `192.168.50.11` or `.12` fails | Normal for MetalLB addresses | Test with `nslookup` or `curl` |
| One device has no DNS at all | Its DNS Director rule is a user-defined entry that still points at an old address (for example a node's own address) that no longer answers DNS | Set every user-defined entry to `192.168.50.11`. [DNS design](../network/dns-design.md) |
| Devices get the wrong DNS server from DHCP | DHCP DNS Server 1 was changed during troubleshooting | Set it back to `192.168.50.11` |
| A change made in the Pi-hole UI disappeared | Pods rebuild from the values file | Make the change in the file |
| Hundreds of dnsmasq restarts in the router log | The dnscrypt-proxy manager add-on is back | Remove it. [ASUS ZenWiFi XT8](../hardware/asus-zenwifi-xt8.md) |
| Helm install of Pi-hole fails on the `-ipv6` Services | The cluster is not dual-stack | [k3s HA cluster](../kubernetes/k3s-ha-cluster.md) |
| A node's `resolv.conf` lists Pi-hole (`fd00:1234:5678:50::11` or `192.168.50.11`) | The node learned DNS from the router (DHCP or router advertisement) | Pin the node's DNS, and add the nodes as exceptions in DNS Director. [DNS design](../network/dns-design.md) |
| Bootstrap `verify` fails a DNS-over-TLS or "upstream is only" check | The WAN page and the `WAN_DNS`, `WAN_DNS2`, `WAN_DOT` values at the top of the script disagree | Make them agree. [DNS design](../network/dns-design.md) Step 4 |

### Web apps and Traefik

| Symptom | Cause | Fix |
| --- | --- | --- |
| Seerr: Cloudflare 502 Bad Gateway | The tunnel route pointed at `localhost:80`; Traefik is on `.12` | Route URL `192.168.50.12`. [Seerr behind a Cloudflare tunnel](../apps/seerr-cloudflare-tunnel.md) |
| Helm: "values don't meet the specifications of the schema" (Seerr) | Broken `httpRoute:` block | Use [values.yaml](../../files/seerr/values.yaml) as it is |
| Homebridge: Bad Gateway | "Enable HTTPS" is on in the Homebridge UI | Turn it off. [Homebridge](../apps/homebridge.md) |
| Homebridge only answers on `:8581` | The name points at a node address, or there is no Ingress | `hb.home.example.com` → `.12`, and the Ingress in the Homebridge values file |
| `http://` does not redirect | The middleware is missing in that namespace | `sudo kubectl apply -f files/traefik/middleware-redirect-https.yaml` |
| Browser certificate warning on home names | Traefik's self-signed certificate | Expected. Optional fix: a wildcard certificate for `*.home.example.com` with cert-manager and a DNS challenge (not done by the author) |
| An app that worked through Traefik stopped after moving to MetalLB | It used a node's own address | Point it at `192.168.50.12` |
| Traefik is no longer on `.12` after a k3s upgrade | k3s reset the bundled Traefik's Service; the address was only "second in line" | Pin it. [Load balancers](../kubernetes/load-balancers.md) (the pinning annotation is untested by the author) |

### Homebridge, Kasa and cameras

| Symptom | Cause | Fix |
| --- | --- | --- |
| "Timeout after 5 seconds connecting to the device: 192.168.101.x:9999", and ping from `server-1` fails | The `ebtables` ACCEPT rules are gone (Wi-Fi restart) or were never installed | On the router: `sh /jffs/scripts/kasa-guest-allow.sh`. [Kasa across networks](../apps/homebridge-kasa-across-networks.md) |
| A Kasa device never appears | Not in `manualDevices`; discovery cannot cross networks | [Kasa across networks](../apps/homebridge-kasa-across-networks.md) |
| `AuthenticationError (host=…)` | TP-Link account missing or wrong in the plugin | Plugin settings |
| Kasa stopped when the node firewall went on | The IoT network was not allowed on the Homebridge node | The current [k3s-firewall.sh](../../files/firewall/k3s-firewall.sh) allows it. [Node firewall](../kubernetes/node-firewall.md) |
| Two camera plugins listed | An old startup script line reinstalled `homebridge-camera-ffmpeg` | Uninstall the old one; make sure the startup script has no `npm install` line for it |
| Axis cameras show no picture, ffmpeg exit code 8 | Unsupported URL parameters | Use the plain `axis-media/media.amp` URL. [Homebridge cameras](../apps/homebridge-cameras.md) |
| Axis cameras buffer endlessly | `vcodec: copy` on the Axis stream | The `libx264` settings in [Homebridge cameras](../apps/homebridge-cameras.md) |
| Config "verification warning" | The pasted JSON was cut off | Paste the whole block |
| `getaddrinfo ENOTFOUND` / `EAI_AGAIN` for cloud names such as `api.wyzecam.com` or `api.honeywellhome.com`, a few times an hour | The host-network pod was given an IPv6 DNS address it cannot route to | The `dnsPolicy` / `dnsConfig` block in the Homebridge values file. [Homebridge](../apps/homebridge.md), [Step 11](#step-11-dns-inside-a-pod) |
| Resideo "Unauthorized Request", "status code 401", "Failed to refresh access token" | A token renewal hit a failed DNS lookup | Fix DNS first; it recovers at the next restart. Re-link the account only if it continues with no DNS errors. Re-linking by blanking the two tokens was suggested but not tried |
| Resideo settings page: "Config validation failed - you can still save your changes" | Unknown; the config loads and works | Close without saving. Hover over the underlined field to read which rule it fails |
| Kasa `[Errno 113] Connect call failed`, `[Errno 111]`, "No sys_info returned ... Marking offline" for a short spell | The device dropped off Wi-Fi or changed address. Common while devices are being moved between networks | [Step 5](#step-5-a-switch-does-not-respond-in-the-home-app). Reserve every device's address. A device that does it far more than the others probably has weak Wi-Fi (suspected, not confirmed) |
| "Could not (re-)create mDNS advertisement ... Local name collision" | The Avahi advertiser | Set the mDNS advertiser to Ciao. [Homebridge](../apps/homebridge.md) |
| Camera "Failed to fetch snapshot" | Seen on Axis cameras with 1080p settings | The 720p `libx264` settings in [Homebridge cameras](../apps/homebridge-cameras.md); turn on the camera's `debug` if it returns |
| "Homebridge process ended. Code: 143" many times | Clean restarts: config saves, UI restarts, a scheduled restart | Nothing. A crash would not be 143 |
| Helm: "error converting YAML to JSON: yaml: line N: did not find expected key" on the Homebridge values file | A `#` comment at the left margin inside the `startup.sh: \|` script ends the script early | Indent every line of the script, comments included. Check with `helm template homebridge k8s-at-home/homebridge -n homebridge -f files/homebridge/values.yaml > /dev/null && echo OK` |
| Accessories stuck pairing | mDNS advertised on cluster interfaces | Homebridge network interfaces: `eth0` only |
| Homebridge starts slowly, or fails to start when DNS is down | The startup script runs `apt-get` at every start | Drop that line if the image's own ffmpeg is enough |
| Failed logins in the Homebridge UI log | Mistyped passwords, or someone else on the network | Confirm they were yours; otherwise change the password |

### Cluster

| Symptom | Cause | Fix |
| --- | --- | --- |
| "permission denied" on `k3s.yaml` | No `sudo` | `sudo kubectl …` |
| k3s install: download failed | Short version `v1.34` | Full tag, `v1.34.3+k3s1` |
| "must share the same IP version" | `node-ip` has one address family | Give both the IPv4 and the IPv6 address |
| 401 "node not found", the agent waits forever | Stale certificates | `k3s-agent-uninstall.sh`, then rejoin |
| "… newer than datastore and could cause a cluster outage" | Old `/var/lib/rancher/k3s/server` folder | Move it aside, install again |
| Flannel "no IPv6" lease error after going dual-stack | Stale node record | Delete the node record during startup. [k3s HA cluster](../kubernetes/k3s-ha-cluster.md) |
| Mac node `NotReady`, or a duplicate Mac node | Missing `node-name`, so it first joined under the VM's host name | Delete the dead record. [Mac Lima VM](../hardware/mac-lima-vm.md) |
| Pods on the Mac cannot resolve names | `flannel-iface: eth0` (the VM's private NAT interface) | `lima0` |
| kube-vip installer hangs | It landed on the Mac while its network was broken | Cordon the Mac, delete the pod, uncordon |
| MetalLB controller `CrashLoopBackOff` | Wrong version | v0.15.3 |
| `kubectl apply` of the MetalLB config: webhook error | The controller is not ready | Wait, apply again |
| MetalLB "Suspect … has failed"; the Pi-hole IPv6 address keeps moving between nodes | Unexplained. A node firewall gap or the Mac VM's networking are the suspects | [Node firewall](../kubernetes/node-firewall.md), [Mac Lima VM](../hardware/mac-lima-vm.md) |
| Cluster DNS stops when one node is down | CoreDNS is back to one replica | Scale to three. [CoreDNS](../kubernetes/coredns.md) |
| `fd00:1234:5678:4300::a` answers nothing from any pod; the IPv6 endpoint slice for `kube-dns` is `<unset>` | The CoreDNS pod is older than the dual-stack conversion, so IPv4-only | `sudo kubectl -n kube-system rollout restart deployment coredns`. [CoreDNS](../kubernetes/coredns.md) |
| `fd00:1234:5678:4300::a` unreachable **from a node or a host-network pod** only: "Network is unreachable" | No route to the IPv6 service range on the host. Normal | IPv4-only DNS block for that pod. [CoreDNS](../kubernetes/coredns.md) |
| SSH to a Pi froze after `nmcli con up` | DHCP gave it a new address | `ssh pi@fd00:1234:5678:50::7` from another Pi, then pin the address |
| `limactl start`: sudoers out of sync | Sudoers was generated too early | Regenerate. [Mac Lima VM](../hardware/mac-lima-vm.md) |
| The Mac VM is down after the Mac restarts | Autostart was not enabled, or the Mac sleeps | `sudo pmset -a sleep 0 disablesleep 1` and `limactl autostart enable --condition=boot k3s-vm` (older Lima: `limactl start-at-login k3s-vm`). [Mac Lima VM](../hardware/mac-lima-vm.md) |
| An etcd member changed address | A server is on a DHCP address without a reservation | Reserve the address on the router for every server, including the VM |
| A node has swap active (`zram0`) | Image default | k3s tolerates it; noted only because it differs between nodes |
| Nodes show an IPv6 address from a prefix the router does not hand out | Another device is advertising a prefix, most likely a smart-home Thread border router (not confirmed) | Harmless for the cluster; matters only for firewall rules |

### Router and access points

| Symptom | Cause | Fix |
| --- | --- | --- |
| Clients get no `fd00:` address | IPv6 is off on `br0`, or the ip6tables OUTPUT rule is missing | On the router: `service restart_dnsmasq; service restart_firewall`, then `sh /jffs/xt8-bootstrap.sh verify`. [Local-only IPv6](../network/local-only-ipv6.md) |
| The router answers nothing over IPv6 | ip6tables OUTPUT policy is DROP | `service restart_firewall` |
| The OpenWrt AP shows no IPv6 on `br-lan` | Device-level `ipv6` not set, or only `reload` was used | Run [a7-ap-setup.sh](../../files/archer-a7/a7-ap-setup.sh). [TP-Link Archer A7 on OpenWrt](../hardware/tp-link-archer-a7-openwrt.md) |
| IPv6 ping to the stock-firmware AP times out | Expected; it has no IPv6 address in AP mode | Nothing. [TP-Link Archer AX21](../hardware/tp-link-archer-ax21.md) |
| Router web UI frozen | Too many simultaneous requests | Wait; open one page at a time |
| Random Wi-Fi drops about hourly | Roaming assistant at -55 dBm | Set it to -70 dBm |
| Roaming assistant (`roamast`) crashing repeatedly in the log | Seen for a few days on the test router, then stopped by itself | Nothing unless it returns |
| Router reboots every few days | AiProtection engine crash | Turn AiProtection off, or at least Two-Way IPS and Infected Device Prevention |
| `amtm` / Entware downloads hang | Unresolved; Skynet suspected | Disable Skynet briefly and retry |
| `cru l` on the AiMesh node shows no reboot job | `services-start` did not run at boot, or an AiMesh sync reset it | From your computer: `sh files/xt8/node/xt8-node-setup.sh 192.168.50.117 admin <SSH_PORT>`. [ASUS AiMesh node](../hardware/asus-aimesh-node.md) |
| An empty `cru l` on the main router although a reboot is scheduled | The GUI scheduler is run by the watchdog, not cron | `nvram get reboot_schedule_enable`. [Maintenance](maintenance.md) |
| "not giving name … because the name exists in …/.hostnames" | A device asked for an address other than the one reserved for its name | Make the reservation match, or wait for the lease to renew |
| A LAN port on the router keeps going up and down between 100 and 1000 Mbps | Marginal cable or device on that port | Swap the cable |
| `usb 3-1: device descriptor read/64, error -110` in the router log | The USB drive is timing out | Back it up; replace it if it repeats. The add-ons and the logs live on it |
| JFFS CRC errors in the log | Flash storage errors; stopped by themselves on the test router | If they return: back up JFFS, format it at next boot, restore |
| "own address as source" on `eth4`/`eth5`/`eth6`, tens of times a day | Not established | Low priority; no visible effect |
| UPnP notify timeouts to some computers | Cosmetic | Nothing |
| Web UI logins to the router from an unexpected subnet | Usually you, arriving through a VPN | Confirm; otherwise change the admin password |
| An app on one LAN machine cannot reach another through the router after enabling security features | AiProtection, or a VPN client's LAN exception on one of the machines, were the suspects; outcome not recorded | Test with AiProtection off |
| The live `/jffs/scripts/dnsmasq.postconf` is longer than the repo's copy | Something else (an add-on) appended lines | `cat /jffs/scripts/dnsmasq.postconf` on the router and compare with [dnsmasq.postconf](../../files/xt8/jffs-scripts/dnsmasq.postconf) |
| OpenWrt AP is back at `192.168.1.1` in routing mode | Factory reset, or a flash without keeping settings | Restore the backup, or run the setup script again |

### IoT network

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Home-IoT` on the OpenWrt AP shows grey bars and `---` in LuCI | No client is connected to it | Nothing. A BSSID and a **Disable** button mean it is broadcasting |
| A device joins the AP's `Home-IoT` but gets no address | Tagged VLAN 501 is not reaching the AP | `brctl show` on the router (`.501` members under `br1`), the AP's uplink port, any switch in between. [Isolated IoT network](../network/isolated-iot-network.md) |
| Ping from the LAN to every IoT device fails | The `ebtables` ACCEPT rules are gone | `sh /jffs/scripts/kasa-guest-allow.sh` on the router |
| IoT access breaks after any Wi-Fi setting change | A Wi-Fi restart wipes `ebtables`; the `service-event-end` hook should restore the rules | Check `/jffs/scripts/service-event-end` exists and is executable |
| One IoT device unreachable after a while | Its address changed ("Automatic IP") | Reserve an address for every IoT device that something on the LAN controls |
| A guest device can open `http://192.168.50.1` | Isolation is not in effect | [Isolated IoT network](../network/isolated-iot-network.md) |

### Logging

| Symptom | Cause | Fix |
| --- | --- | --- |
| `/opt/var/log/messages` is tens of MB; `logrotate.log` says "error creating stub state file /opt/var/lib/logrotate.status" | Scribe's logrotate has no state folder | On the router: `mkdir -p /opt/var/lib; /opt/sbin/logrotate /opt/etc/logrotate.conf`. [Router logging](../network/router-logging.md) |
| The state folder keeps disappearing | The USB drive was reformatted or is failing | Check the drive |
| `messages` is 0 bytes right after a rotation | Nothing has been logged yet | `logger test; sleep 2; ls -la /opt/var/log/messages*`. Only if the old file grew instead: `killall -HUP syslog-ng` |
| A large `messages-<date>` file is left on the USB drive | The first successful rotation | Delete it or let logrotate age it out |
| **System Log → IPv6** says "IPv6 Not enabled" | Expected; IPv6 is set up by script, not the GUI | `ip -6 neigh show dev br0` on the router. [Router logging](../network/router-logging.md) |
| No `RTR-ADVERT` lines in the log | A `quiet-ra` line is back in `/jffs/scripts/dnsmasq.postconf` | Comment it out, `service restart_dnsmasq` |
| `DHCPSOLICIT(br0)` repeating with no reply | A device wants DHCPv6; the router only does SLAAC (self-assigned addresses) | Nothing |
| The AiMesh node's log is empty after a reboot | The node has no USB drive and no Scribe; its log lives in memory | Expected |

## References

- [Kubernetes: Debug Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/): reading `describe pod` output and pod states such as Pending and CrashLoopBackOff.
- [Kubernetes: Troubleshooting clusters](https://kubernetes.io/docs/tasks/debug/debug-cluster/): node and control-plane level debugging.
- [Kubernetes: Debugging DNS resolution](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/): the upstream method for CoreDNS and pod `resolv.conf` problems.
- [MetalLB: Troubleshooting](https://metallb.io/troubleshooting/): why an address is not assigned or not announced, and how to read the speaker logs.
- [k3s: Networking services](https://docs.k3s.io/networking/networking-services): the bundled CoreDNS, Traefik and ServiceLB, and how ServiceLB is disabled.
- [k3s: Backup and restore](https://docs.k3s.io/datastore/backup-restore): read before attempting a cluster reset after lost quorum.
- [ufw manual page](https://manpages.ubuntu.com/manpages/noble/en/man8/ufw.8.html): the `ufw status`, `allow from`, `disable` and `enable` commands used in the firewall section.
- [Asuswrt-Merlin wiki: User scripts](https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts): the `service-event-end`, `firewall-start` and `dnsmasq.postconf` hooks referred to above.
- [Pi-hole documentation](https://docs.pi-hole.net/): the query log, allow lists and FTL database used in the DNS sections.
