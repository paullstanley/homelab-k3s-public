# 14. Troubleshooting

Two parts. **Part A** is how to work out what is wrong when you only know the symptom: what to run, in order, and what each answer means. **Part B** is the lookup table of every specific failure this network has had.

Unless it says otherwise, commands go on k3sprimary. If k3sprimary is the thing that is down, use funkyfresh or k3snode2; every Pi is a server and has `kubectl`.

# Part A. Working out what is wrong

## A0. The two-minute health check

Run this first, whatever the symptom.

```bash
sudo kubectl get nodes -o wide
sudo kubectl get pods -A -o wide | grep -v -E 'Running|Completed'
sudo kubectl get svc -A | grep LoadBalancer
sudo kubectl -n pihole get pods -o wide
nslookup example.com 192.168.50.11
```

| What you see | Go to |
| --- | --- |
| `kubectl` itself does not answer | A6 |
| A node is `NotReady` | A6 |
| Pods listed by the second command | Describe one: `sudo kubectl -n <namespace> describe pod <name> \| tail -20`. The last lines say why (`ImagePullBackOff`, `Pending`, `CrashLoopBackOff`); look the word up in Part B |
| A LoadBalancer shows `<pending>` or a node's own address (.5, .6, .7) instead of .11 / .12 | The built-in load balancer is back, or MetalLB is down. [06](06-load-balancers.md) |
| Pi-hole pods not one-per-Pi | [07](07-pihole.md), "Two pods on one Pi" |
| `nslookup` fails | A1 |
| All five look right | The cluster is fine. The problem is on the device, the router or the path: A2, A3 |

## A1. "The internet is down" (DNS)

Almost every "internet is down" in this house is DNS. Work from the device outwards.

**On the affected device**, test with and without a name:

```bash
ping -c 2 1.1.1.1
nslookup example.com
nslookup example.com 192.168.50.11
nslookup example.com 1.1.1.1
```

| Result | Meaning | Next |
| --- | --- | --- |
| Ping to 1.1.1.1 fails | Not DNS. The connection or the router | Router WAN status, modem, cables |
| Ping works, all three lookups fail | The device cannot reach any DNS | Is it on the right Wi-Fi? Does it have a 192.168.50.x address? |
| Second lookup (via .11) fails, third (via 1.1.1.1) works | Pi-hole is not answering. Note: DNS Director normally redirects the third one to Pi-hole too, so this result usually means the device has a DNS Director exception | Continue below |
| Only the first (default) lookup fails | The device is using some other DNS server | Mac: `scutil --dns \| grep nameserver`. A VPN is the usual reason ([11](11-clients.md)) |
| Everything works but one site does not | Pi-hole is blocking it | Pi-hole query log, then add it to `whitelist:` in `pihole/values.yaml` |

**On k3sprimary**, if Pi-hole is not answering:

```bash
sudo kubectl -n pihole get pods -o wide
sudo kubectl -n pihole get svc
sudo kubectl -n pihole get events --sort-by=.lastTimestamp | tail -15
sudo kubectl -n metallb-system get pods -o wide
```

| Result | Meaning | Fix |
| --- | --- | --- |
| No pod is `2/2 Running` | Pi-hole is down everywhere | `describe pod`; most likely image pull (node DNS, A5) or the admin Secret is missing ([07](07-pihole.md) Step 2) |
| Pods are `1/2` | The encryption sidecar or Pi-hole itself is failing | `sudo kubectl -n pihole logs <pod> -c cloudflared --tail=20` and `-c pihole --tail=40` |
| Pods fine, Services show .11 | MetalLB is not announcing, or announcing from a Pi with no healthy pod | `sudo kubectl -n metallb-system logs -l component=speaker --tail=30`. Restart the speakers: `sudo kubectl -n metallb-system rollout restart daemonset speaker` |
| Services show `<pending>` | MetalLB controller down or pool missing | [06](06-load-balancers.md) Step 1 |
| Everything looks fine here | The fault is between the device and .11 | From another device: `nslookup example.com 192.168.50.11`. If that works, it is the one device. If the node firewall is on, see A7 |

**Emergency bypass**, to get the house working while you fix it: on the XT8, LAN → DHCP Server → DNS Server 1 → `9.9.9.9`, and LAN → DNS Director → Global Redirection → **No Redirection**. Apply. Devices pick it up as they renew (toggle Wi-Fi to force it). **Put both back afterwards** (192.168.50.11 and User Defined 1).

## A2. A web page of mine will not load

Covers Pi-hole's UI, Homebridge and Seerr. Find out which hop is broken, from the pod outwards.

```bash
sudo kubectl get ingress -A
sudo kubectl get svc -A | grep -E 'traefik|LoadBalancer'
curl -sI -H 'Host: pihole.home.example.com' http://192.168.50.12/admin/ | head -3
curl -sI -H 'Host: hb.home.example.com' http://192.168.50.12/ | head -3
curl -sI -H 'Host: request.example.com' http://192.168.50.12/ | head -3
```

| Result | Meaning | Fix |
| --- | --- | --- |
| `curl` cannot connect at all | Traefik is not on 192.168.50.12 | `sudo kubectl -n kube-system get pods \| grep traefik` and [06](06-load-balancers.md) Step 2 |
| `404 page not found` | Traefik is up but has no rule for that name | The Ingress is missing or has another host name. Re-apply the app's values file |
| `502` or `Bad Gateway` | Traefik has the rule but the app does not answer | The pod is down, or (Homebridge) its own HTTPS is switched on |
| `301`, `302`, `307` or `200` | The cluster side is fine | The problem is the name or the client: next block |

**On the device that cannot load the page:**

```bash
nslookup pihole.home.example.com
curl -skI https://pihole.home.example.com/admin/ | head -3
```

| Result | Meaning | Fix |
| --- | --- | --- |
| Name does not resolve (`NXDOMAIN`) | The device is not asking Pi-hole | Work Mac: `/etc/hosts` ([11](11-clients.md)). Others: check which DNS server they use |
| Resolves to something other than 192.168.50.12 | Stale entry | Old `/etc/hosts` line, or an old `address=` line in `pihole/values.yaml` |
| Resolves, `curl` works, browser does not | Browser state | Private window; clear cookies for that name; accept the certificate warning |
| Resolves, `curl` times out | The path is blocked | From VPN: A7 |
| Seerr from outside shows a Cloudflare error page | Tunnel or route | `systemctl status cloudflared` on k3sprimary; route URL must be `192.168.50.12` ([09](09-seerr-and-cloudflare.md)) |

## A3. I can log in to Pi-hole but it throws me back out, or the numbers look wrong

```bash
sudo kubectl -n pihole get pods -o wide
for p in $(sudo kubectl -n pihole get pods -o name); do echo "$p: $(sudo kubectl -n pihole exec $p -c pihole -- pihole-FTL sqlite3 /etc/pihole/pihole-FTL.db 'select count(*), count(distinct client) from queries;')"; done
```

| Result | Meaning | Fix |
| --- | --- | --- |
| Two pods on the same node | Lopsided placement after an upgrade | Delete one of the pair ([07](07-pihole.md)) |
| One pod with thousands of queries, others with a few | Normal. You may be looking at a standby | Use `http://192.168.50.11/admin` for the busy pod |
| Login loops on `http://192.168.50.11/admin` | More than one pod behind that address on one Pi | Fix the placement |
| Login loops on `https://pihole.home.example.com` | The sticky cookie is not reaching the browser | `curl -skI https://pihole.home.example.com/admin/ \| grep -i set-cookie` must show `pihole_pod`. If it does, clear the browser's cookies for the site |
| All counters are zero or tiny on every pod | The pods restarted recently | `AGE` column in the first command. Counters do not survive restarts |

## A4. A light switch does not respond in the Home app

```bash
ping -c 3 192.168.101.201
nc -vz -w 3 192.168.101.201 9999
sudo kubectl -n homebridge get pods -o wide
sudo kubectl -n homebridge logs deploy/homebridge --tail=40 | grep -i -E 'kasa|error|timeout'
```

Use the address of the switch that is failing ([01](01-inventory.md)).

| Result | Meaning | Fix |
| --- | --- | --- |
| Kasa works but Wyze devices or the thermostat lag or fail; log has `getaddrinfo ENOTFOUND` / `EAI_AGAIN` | DNS inside the pod | A10 |
| Every accessory says "No Response" | Homebridge itself | Is the pod running? Is k3sprimary up? Open `http://192.168.50.5:8581` |
| Ping fails for **every** Kasa device | The router rules are gone | On the XT8: `sh /jffs/scripts/kasa-guest-allow.sh`, then `sh /jffs/xt8-bootstrap.sh verify` |
| Ping fails for **one** device | That device is off the network or changed address | Kasa app; XT8 client list; fix the reservation and `manualDevices` |
| Ping works, port 9999 refused or `AuthenticationError` in the log | Newer firmware wants the TP-Link account | Plugin settings ([08](08-homebridge.md) 5c) |
| Ping works from k3sprimary, Homebridge still times out, firewall recently turned on | The node firewall is refusing the replies | A7 |
| Stopped right after a router Wi-Fi change | A Wi-Fi restart wiped the `ebtables` rules and the hook did not restore them | Same fix as the second row; check `/jffs/scripts/service-event-end` exists and is executable |

## A5. A pod will not start

```bash
sudo kubectl -n <namespace> describe pod <name> | tail -25
```

| Last lines say | Meaning | Fix |
| --- | --- | --- |
| `ImagePullBackOff`, `ErrImagePull`, "no such host" | The **node** cannot resolve or reach the registry | On that node: `grep nameserver /etc/resolv.conf` must be 1.1.1.1 / 9.9.9.9, and `nslookup ghcr.io` must work ([04](04-k3s-cluster.md) Step 2) |
| `Pending`, "didn't match Pod's node affinity/selector" | A label is missing | `sudo kubectl get nodes -L pihole-host,kube-vip-host` |
| `Pending`, "didn't match pod topology spread constraints" | The only free Pi is not eligible or not Ready | Is a Pi down? It will schedule when the Pi returns |
| `Pending`, "persistentvolumeclaim … not found" or "node affinity conflict" | A `local-path` volume lives on a different node | Homebridge and Seerr can only run on k3sprimary |
| `CreateContainerConfigError`, "secret … not found" | A Secret was not created | Pi-hole: [07](07-pihole.md) Step 2 |
| `CrashLoopBackOff` | The app starts and dies | `sudo kubectl -n <namespace> logs <name> --previous --tail=40` |
| `OOMKilled` | Out of memory | The 2 GB Pis. `sudo kubectl top nodes` |

## A6. `kubectl` does not answer, or a node is NotReady

**On the node in question:**

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
| Log shows "slow fdatasync" or "apply request took too long" again and again | The disk is too slow for etcd | k3sprimary's hard drive ([04](04-k3s-cluster.md)) |
| `eth0` has no 192.168.50.x address | The node lost its address | Reach it over IPv6 from another Pi (`ssh pi@fd00:1234:5678:50::7`), pin the address ([04](04-k3s-cluster.md) Step 2) |
| Fatal line naming files "newer than datastore" | Leftover server folder | [04](04-k3s-cluster.md), last section |
| Disk at 100% | Logs or images filled it | `sudo k3s crictl rmi --prune`; `sudo journalctl --vacuum-size=200M` |
| Node is fine but shows NotReady from the others | The nodes cannot talk to each other | Firewall: A7 |
| The Mac node is NotReady | The Mac slept, or the VM is stopped | Mac Terminal: `limactl list`, `limactl start k3s-mac` |

## A7. Is the node firewall the cause?

Suspect it when something worked, the firewall was (re)enabled, and now a connection **to a Pi itself** times out; or when you arrive from a network other than 192.168.50.x.

```bash
sudo ufw status | head -1
sudo journalctl -k --since "10 min ago" | grep "UFW BLOCK" | tail -20
```

Retry the failing thing while watching:

```bash
sudo journalctl -k -f | grep "UFW BLOCK"
```

| Result | Meaning | Fix |
| --- | --- | --- |
| `Status: inactive` | Not the firewall | Look elsewhere |
| Block lines with your client's address as `SRC` | The firewall is refusing you | Add the range: `sudo ufw allow from <range>`, and put it in the script ([10](10-firewall.md)) |
| Block lines with another **node's** address as `SRC` and `DPT` 7946, 2379, 2380, 10250 or 8472 | The firewall is breaking the cluster | [10](10-firewall.md), "Open problem" |
| No block lines while it fails | Not the firewall | Routing, DNS, or the app |

The quickest proof either way is to switch it off on that node for a minute: `sudo ufw disable`, retry, `sudo ufw enable`.

## A8. Reaching the house from the VPN

| Symptom | Cause | Fix |
| --- | --- | --- |
| SSH, Homebridge on 8581 or the API time out from 192.168.0.x | Node firewall range | Now 192.168.0.0/16 ([10](10-firewall.md)) |
| Home names do not resolve on the work Mac | The VPN's DNS answers instead of Pi-hole | `/etc/hosts` ([11](11-clients.md)) |
| A name was added for a new app and does not resolve on the work Mac | `/etc/hosts` has no wildcards | Add the name to the 192.168.50.12 line |
| Works on home Wi-Fi, not from VPN, firewall shows no blocks | The reply has no route back to the VPN subnet | On the Pi: `ip route get 192.168.0.10`. It should leave via 192.168.50.1 |

## A9. After a power cut or a router restart

Things come back in the wrong order. Expected, and it settles by itself within about five minutes:

1. The router is up before the Pis. Devices have no DNS until one Pi-hole pod is ready.
2. Each Pi-hole pod waits 60 seconds and then downloads its blocklists before it answers.
3. The Pis need their **own** DNS (1.1.1.1 / 9.9.9.9) to work at this point. This is the moment a node that depends on Pi-hole deadlocks ([04](04-k3s-cluster.md) Step 2).

If it has not settled after ten minutes: A0, then on the XT8 `sh /jffs/xt8-bootstrap.sh verify`. After a router restart specifically, confirm the Kasa rules came back (A4).

## A10. A Homebridge plugin logs `getaddrinfo ENOTFOUND` or `EAI_AGAIN` (DNS inside a pod)

The house has DNS, the cluster looks healthy, but an app inside a pod intermittently cannot look names up. This is the path that found the 6 October 2026 fault. It works for any pod; the Homebridge UI has a terminal, which makes it the easy one.

**1. Which name servers does the pod use? Paste in: the pod's shell** (Homebridge UI → Terminal).

```bash
cat /etc/resolv.conf
```

| You see | Meaning |
| --- | --- |
| Only `nameserver 10.43.0.10`, `options ndots:1` | Homebridge's correct state ([08](08-homebridge.md) Step 1). Go to step 2 |
| `10.43.0.10` **and** `fd00:1234:5678:4300::a`, `ndots:5` | The DNS block is missing from the values file. For a host-network pod that is the fault. Apply `Homebridge/values.yaml` |
| `1.1.1.1` / `9.9.9.9` | The pod is using the node's own DNS, not the cluster's. Look at its `dnsPolicy` |

**2. Test each name server on its own, 20 times. Same shell.** One line; do not break it. Needs Node, which the Homebridge image has.

```bash
node -e 'const d=require("dns").promises;(async()=>{for(const s of process.argv.slice(1)){const r=new d.Resolver({timeout:2000,tries:1});r.setServers([s]);let ok=0,e={};for(let i=0;i<20;i++){try{await r.resolve4("api.wyzecam.com");ok++}catch(x){e[x.code]=(e[x.code]||0)+1}}console.log(s,"ok:",ok,JSON.stringify(e))}})()' 10.43.0.10 fd00:1234:5678:4300::a 1.1.1.1
```

Healthy answer on 6 October after the fix:

```
10.43.0.10 ok: 20 {}
fd00:1234:5678:4300::a ok: 0 {"ECONNREFUSED":20}
1.1.1.1 ok: 20 {}
```

The middle line failing is **normal from a host-network pod** and stays that way ([04](04-k3s-cluster.md) Step 8). `ECONNREFUSED` is how Node reports "could not contact the server"; the real reason is "Network is unreachable".

| Result | Meaning | Next |
| --- | --- | --- |
| `10.43.0.10` fails, `1.1.1.1` works | CoreDNS, or the pod network to it | Step 3 |
| Both fail | The node has lost its way out, or the router is intercepting | A1 |
| Everything listed in `resolv.conf` passes | The failures come in bursts | Run it again when the log shows a fresh error |

**3. Look at CoreDNS. Paste on: k3sprimary.**

```bash
sudo kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
sudo kubectl -n kube-system get pod -l k8s-app=kube-dns -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.status.podIPs}{"\n"}{end}'
sudo kubectl -n kube-system get endpointslices -l kubernetes.io/service-name=kube-dns
sudo kubectl -n kube-system logs -l k8s-app=kube-dns --tail=100 | grep -v 'import glob'
```

| Result | Meaning | Fix |
| --- | --- | --- |
| Fewer than three pods, or all on one node | Replica count was reset | `sudo kubectl -n kube-system scale deployment coredns --replicas=3` |
| A pod with one address only; IPv6 endpoint slice shows `<unset>` | The pod is older than dual-stack | `sudo kubectl -n kube-system rollout restart deployment coredns` |
| `i/o timeout` or `SERVFAIL` in the log | CoreDNS cannot reach its upstream, which is the node's own DNS | Node DNS, [04](04-k3s-cluster.md) Step 2 |
| Only "No files matching import glob pattern" warnings | Normal | Nothing |

**4. Is it the route? Paste on: k3sprimary.**

```bash
ip -6 route get fd00:1234:5678:4300::a
ip -6 route show default
sudo ip6tables-save | grep -i '4300::a'
ping -6 -c 3 "$(sudo kubectl -n kube-system get pod -l k8s-app=kube-dns -o jsonpath='{.items[0].status.podIPs[1].ip}')"
```

"Network is unreachable", no default route, rules present, ping answers: that is this cluster's normal state. It proves the IPv6 pod network is fine and only the service address is unreachable from the host.

**5. Did it stop? Paste in: the Homebridge UI terminal.**

```bash
grep -E 'ENOTFOUND|EAI_AGAIN|401|Unauthorized' /var/lib/homebridge/homebridge.log | tail -5
```

Nothing newer than the fix. Before the fix there was an error roughly every half hour, so a few quiet hours is good evidence.

**Reading a long Homebridge log.** Most of it is Kasa polling. This hides the routine lines and counts what is left:

```bash
grep -viE 'Getting sys_info|Serializing device|Updated sys_info|getSysInfo HTTP|Skipping poll|Getting light info' /var/lib/homebridge/homebridge.log | sed -E 's/^\[[^]]+\] //' | sort | uniq -c | sort -rn | head -40
```

Do not search the log for "oom" without `-w`; it matches every line with "room" in it.

# Part B. Lookup: symptom → cause → fix

Everything that has gone wrong on this network, in one table per area. The linked page has the detail.

## DNS and Pi-hole

| Symptom | Cause | Fix |
| --- | --- | --- |
| Pi-hole login loops back to the login page | Three pods, each with its own sessions | Use `https://pihole.home.example.com/admin` (Traefik, sticky cookie). [07](07-pihole.md) |
| `pihole.home.example.com` does not resolve on the work Mac | VPN DNS proxy returns NXDOMAIN | `/etc/hosts`. [11](11-clients.md) |
| Pi-hole UI answers on 192.168.50.5, not .11; `-ipv6` Services `<pending>` | k3s servicelb took over | `disable: servicelb` on every server. [06](06-load-balancers.md) |
| New Pi-hole pods `Pending` | `pihole-host` label missing | Label the Pis. [07](07-pihole.md) |
| Two Pi-hole pods on one Pi | Label race | Delete one of the pair |
| Pods `ImagePullBackOff` | The node's own DNS points at something dead | Node DNS 1.1.1.1 / 9.9.9.9. [04](04-k3s-cluster.md) |
| Dashboard shows a handful of queries and clients | You are on a standby pod; stats are per pod | `http://192.168.50.11/admin` shows the busy one. [07](07-pihole.md) |
| Two Pi-hole pods on one Pi after a helm upgrade | Old and new pods counted together during the rollout | Delete one; `matchLabelKeys` in the values file. [07](07-pihole.md) |
| Cannot SSH or open Homebridge on 8581 from the VPN (192.168.0.x) | Node firewall allowed only 192.168.50.0/24 | 192.168.0.0/16. [10](10-firewall.md) |
| Pi-hole pod `1/2` after pulling a fresh image | A cloudflared build without `proxy-dns` | Keep `doh.tag: "2025.9.1"`. [07](07-pihole.md) |
| Ping to 192.168.50.11 or .12 fails | Normal for MetalLB addresses | Test with `nslookup` or `curl` |
| A device has no DNS at all | Its DNS Director rule is "User Defined 3", which pointed at 192.168.50.5 | Set User Defined 3 to 192.168.50.11. [02](02-router-xt8.md) |
| A change made in the Pi-hole UI disappeared | Pods rebuild from `values.yaml` | Make the change in the file |
| Hundreds of dnsmasq restarts in the XT8 log | dnscrypt-proxy manager is back | [02](02-router-xt8.md), last section |
| helm install of Pi-hole fails on the `-ipv6` Services | Cluster is not dual-stack | [04](04-k3s-cluster.md) |

## Web apps and Traefik

| Symptom | Cause | Fix |
| --- | --- | --- |
| Seerr: Cloudflare 502 Bad Gateway | Tunnel route pointed at `localhost:80`; Traefik is on .12 now | Route URL `192.168.50.12`. [09](09-seerr-and-cloudflare.md) |
| helm: "values don't meet the specifications of the schema" (Seerr) | Broken `httpRoute:` block | Use `Seerr/values.yaml` as is |
| Homebridge: Bad Gateway | "Enable HTTPS" is on in the Homebridge UI | Turn it off. [08](08-homebridge.md) |
| Homebridge only answers on `:8581` | Name points at .5, or no Ingress | `hb.home.example.com` → .12 and the Ingress in `Homebridge/values.yaml` |
| `http://` does not redirect | Middleware missing in that namespace | `sudo kubectl apply -f traefik/middleware-redirect-https.yaml` |
| Browser certificate warning on home names | Traefik's self-signed certificate | Expected. Optional fix in [09](09-seerr-and-cloudflare.md) |
| An app that worked through Traefik stopped after the HA work | It used a node's own address | Point it at 192.168.50.12 |

## Homebridge, Kasa, cameras

| Symptom | Cause | Fix |
| --- | --- | --- |
| "Timeout after 5 seconds connecting to the device: 192.168.101.x:9999", ping from k3sprimary fails | The `ebtables` ACCEPT rules are gone (Wi-Fi restart) or never installed | On the XT8: `sh /jffs/scripts/kasa-guest-allow.sh`. [02](02-router-xt8.md) |
| Kasa device never appears | Not in `manualDevices`; discovery cannot cross networks | [08](08-homebridge.md), 5c |
| `AuthenticationError (host=…)` | TP-Link account missing or wrong in the plugin | Plugin settings |
| Kasa stopped when the node firewall went on | IoT network not allowed on k3sprimary | Current `k3s-firewall.sh` allows it. [10](10-firewall.md) |
| Two camera plugins listed | The old startup script reinstalled `homebridge-camera-ffmpeg` | Uninstall the old one; the script line is removed |
| Axis cameras show no picture, ffmpeg exit code 8 | Unsupported URL parameters | Use the plain `axis-media/media.amp` URL |
| Axis cameras buffer endlessly | `vcodec: copy` on the Axis stream | `libx264` settings in [08](08-homebridge.md) |
| Config "verification warning" | The pasted JSON was cut off | Paste the whole block |
| `getaddrinfo ENOTFOUND` / `EAI_AGAIN` for `api.wyzecam.com` or `api.honeywellhome.com`, a few times an hour | The host-network pod was given an IPv6 DNS address it cannot route to | The `dnsPolicy` / `dnsConfig` block in `Homebridge/values.yaml`. [08](08-homebridge.md) Step 1, A10 |
| Resideo "Unauthorized Request", "status code 401", "Failed to refresh access token" | A token renewal hit a failed DNS lookup | Fix DNS first; it recovers at the next restart. Re-link only if it continues with no DNS errors. [08](08-homebridge.md) Step 6 |
| Resideo settings page: "Config validation failed - you can still save your changes" | Unknown; the config loads and works | Close without saving |
| Kasa `[Errno 113] Connect call failed`, `[Errno 111]`, "No sys_info returned ... Marking offline" for a short spell | The switch dropped off Wi-Fi or changed address. Common while the devices were being moved from 192.168.50.x to 192.168.101.x (1 to 5 October) | A4. Reserve the address ([08](08-homebridge.md) 5b). 192.168.101.201 (MB ceiling fan) was the worst |
| "Could not (re-)create mDNS advertisement ... Local name collision" | The Avahi advertiser | mDNS advertiser: Ciao. [08](08-homebridge.md) Step 3 |
| Camera "Failed to fetch snapshot" | Seen on both Axis cameras until 4 October, with the old 1080p settings | Current settings in [08](08-homebridge.md) Step 7; turn on the camera's `debug` if it returns |
| "Homebridge process ended. Code: 143" many times | Clean restarts: config saves, UI restarts, the 05:00 schedule | Nothing. A crash would not be 143 |
| helm: "error converting YAML to JSON: yaml: line N: did not find expected key" on `Homebridge/values.yaml` | A `#` comment at the left margin inside the `startup.sh: \|` script ends the script early | Indent every line of the script, comments included. Check with `helm template homebridge k8s-at-home/homebridge -n homebridge -f values.yaml > /dev/null && echo OK` |
| Accessories stuck pairing | mDNS advertised on cluster interfaces | Network Interfaces: `eth0` only |

## Cluster

| Symptom | Cause | Fix |
| --- | --- | --- |
| "permission denied" on `k3s.yaml` | No `sudo` | `sudo kubectl …` |
| k3s install: download failed | Short version `v1.34` | `v1.34.3+k3s1` |
| "must share the same IP version" | `node-ip` has one family | Both addresses |
| 401 "node not found", agent waits forever | Stale certificates | `k3s-agent-uninstall.sh`, rejoin |
| "… newer than datastore and could cause a cluster outage" | Old `/var/lib/rancher/k3s/server` folder | Move it aside, install again |
| Flannel "no IPv6" lease error after going dual-stack | Stale node record | Delete the node record during startup. [04](04-k3s-cluster.md) |
| Mac node `NotReady` / duplicate Mac node | Missing `node-name` | Delete the dead record. [05](05-mac-node-lima.md) |
| Pods on the Mac cannot resolve names | `flannel-iface: eth0` | `lima0` |
| kube-vip installer hangs | It landed on the Mac while its network was broken | Cordon the Mac, delete the pod, uncordon |
| MetalLB controller CrashLoopBackOff | Wrong version | v0.15.3 |
| `kubectl apply` of the MetalLB config: webhook error | Controller not ready | Wait, apply again |
| MetalLB "Suspect … has failed"; Pi-hole IPv6 address keeps moving | Unexplained. Firewall gap or Mac VM | [10](10-firewall.md), [05](05-mac-node-lima.md) |
| Cluster DNS stops when one node is down | CoreDNS back to one replica | Scale to three. [04](04-k3s-cluster.md) Step 8 |
| `fd00:1234:5678:4300::a` answers nothing from any pod; IPv6 endpoint slice for `kube-dns` is `<unset>` | CoreDNS pod older than the dual-stack conversion, so IPv4-only | `rollout restart deployment coredns`. [04](04-k3s-cluster.md) Step 8 |
| `fd00:1234:5678:4300::a` unreachable **from a node or a host-network pod** only: "Network is unreachable" | No route to the IPv6 service range on the host. Normal here | IPv4-only DNS block for that pod. [04](04-k3s-cluster.md) Step 8 |
| SSH to a Pi froze after `nmcli con up` | DHCP gave it a new address | `ssh pi@fd00:1234:5678:50::7` from another Pi, then pin the address |
| `limactl start`: sudoers out of sync | Sudoers generated too early | Regenerate. [05](05-mac-node-lima.md) |

## Router and access points

| Symptom | Cause | Fix |
| --- | --- | --- |
| Clients get no `fd00:` address | `br0` IPv6 off, or the OUTPUT rule missing | `service restart_dnsmasq; service restart_firewall`, then `verify` |
| XT8 answers nothing over IPv6 | ip6tables OUTPUT policy DROP | `service restart_firewall` |
| A7 shows no IPv6 on `br-lan` | Device-level `ipv6` not set, or only `reload` was used | Run `a7-ap-setup.sh` |
| IPv6 ping to the AX21 times out | Expected | Nothing |
| Router web UI frozen | Too many simultaneous requests | Wait; one page at a time |
| Random Wi-Fi drops about hourly | Roaming assistant at -55 dBm | -70 dBm |
| Router reboots every few days | AiProtection engine crash | Turn AiProtection off |
| amtm / Entware downloads hang | Unresolved; Skynet suspected | Disable Skynet briefly and retry |
| `/opt/var/log/messages` is tens of MB; `logrotate.log` says "error creating stub state file /opt/var/lib/logrotate.status" | Scribe's logrotate has no state folder | On the XT8: `mkdir -p /opt/var/lib; /opt/sbin/logrotate /opt/etc/logrotate.conf`. [02](02-router-xt8.md), Add-ons |
| `messages` is 0 bytes right after a rotation | Nothing has been logged yet | `logger test; sleep 2; ls -la /opt/var/log/messages*`. Only if the old file grew instead: `killall -HUP syslog-ng` |
| System Log → IPv6 says "IPv6 Not enabled" | Expected; IPv6 is set up by script, not the UI | `ip -6 neigh show dev br0` on the XT8. [02](02-router-xt8.md), "Seeing IPv6 on the router" |
| No `RTR-ADVERT` lines in the log | A `quiet-ra` line is back in `/jffs/scripts/dnsmasq.postconf` | Comment it out, `service restart_dnsmasq` |
| `DHCPSOLICIT(br0)` repeating with no reply | One device wants DHCPv6; the router only does SLAAC | Nothing |
| `cru l` on the node shows no reboot job | `services-start` did not run at boot, or AiMesh sync reset it | `sh network/xt8/node/xt8-node-setup.sh 192.168.50.117` from the Mac. [02](02-router-xt8.md), "The AiMesh node" |
| "not giving name … because the name exists in …/.hostnames" | A device asked for an address other than the one YazDHCP has reserved for its name | Make the reservation match, or wait for the lease to renew. Seen for the bedroom Apple TV on 15 and 16 September only |
| `Home-IoT` on the A7 shows grey bars and `---` | No client is connected to it | Nothing. A BSSID and a **Disable** button mean it is broadcasting |
| Device joins the A7's `Home-IoT` but gets no address | Tagged VLAN 501 is not reaching the A7 | `brctl show` on the XT8 (`.501` members under `br1`), the A7 uplink port, any switch between. [03](03-access-points.md) |
| A LAN port on the XT8 keeps going up and down between 100 and 1000 Mbps | Marginal cable or device on that port | Swap the cable. `eth1` did this on 22 and 23 September and 2 October |
| `usb 3-1: device descriptor read/64, error -110` in the router log | The USB drive is timing out | Back it up; replace it if it repeats. Skynet, Scribe and the logs live on it |

## Working with these guides

| Symptom | Cause | Fix |
| --- | --- | --- |
| A pasted multi-line command "is missing something" and sits at a `>` prompt | The closing `EOF` line was indented, so the shell never saw it | Every command block in this repo starts at the left margin. Press Ctrl+C and paste again from the file |
| A helm upgrade removed settings | A partial values file was applied | Always apply the whole file from this repo |
| A long one-line command pasted into the Homebridge UI terminal ran as garbage | It was pasted as several lines | Paste it as one line. The A10 test is written that way |
