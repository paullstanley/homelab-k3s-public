# Pi-hole on k3s: three replicas behind one address

You end up with three Pi-hole pods, one on each of three nodes, answering DNS on a single floating IPv4 address and a single floating IPv6 address. Losing any one node does not stop DNS for the house. Upstream queries leave the house encrypted (DNS-over-HTTPS), and the web UI is served over HTTPS under a name, without a port.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | k3s v1.34 (dual-stack, embedded etcd), Helm chart `mojo2600/pihole` 2.38.0 (Pi-hole v6), MetalLB v0.15.3 in layer 2 mode, the Traefik bundled with k3s, `crazymax/cloudflared` 2025.9.1 as the DNS-over-HTTPS sidecar. Three Raspberry Pi nodes (arm64) carry the pods |
| **Also works for** | Any dual-stack Kubernetes cluster with MetalLB and Traefik. Not tested by the author on anything other than k3s. An IPv4-only cluster needs `dualStack.enabled: false` and the IPv6 values removed; that variant is not tested by the author |
| **Time** | 30 minutes, most of it waiting for pods to download blocklists |
| **You need first** | [HA k3s cluster](../kubernetes/k3s-ha-cluster.md) (dual-stack), [Load balancers](../kubernetes/load-balancers.md) (MetalLB with an IPv4 and an IPv6 pool, k3s ServiceLB disabled, Traefik on its own address), [DNS design](../network/dns-design.md) |

## How it works

- **Nothing is kept on disk.** Every pod rebuilds itself from [`files/pihole/values.yaml`](../../files/pihole/values.yaml) when it starts: blocklists, allowlist, local names. Nothing has to be synchronised between pods, and the values file is the backup.
- **One address, three pods.** MetalLB (a load balancer for bare-metal clusters) announces `192.168.50.11` and `fd00:1234:5678:50::11` from one node at a time. The DNS and web Services share that one address through MetalLB's shared-IP annotation.
- **`externalTrafficPolicy: Local`.** The Pi-hole Services keep each client's real source address. The price is that DNS sent to the floating address is answered only by the pod on the node that currently announces it. The other two pods are standbys. If the announcing node dies or has no healthy pod, MetalLB moves the address to another node.
- **Upstream is DNS-over-HTTPS.** Each pod has a second container, `cloudflared`, listening on `127.0.0.1#5053`. Pi-hole forwards to it, and it sends the queries to `https://1.1.1.1/dns-query` and `https://1.0.0.1/dns-query` on port 443. The ISP cannot read them, and because the traffic is HTTPS rather than DNS, a router rule that redirects all port 53 traffic to Pi-hole does not need an exception for Pi-hole itself.
- **The web UI goes through Traefik.** Each pod keeps its own login sessions in memory. With three pods, a browser must keep reaching the same pod, so the UI is published through Traefik (the ingress controller, on `192.168.50.12`) with a sticky cookie.

## Before you start

| Check | Why |
| --- | --- |
| The cluster is dual-stack | With `dualStack.enabled: true` the chart creates separate IPv6 Services (`pihole-dns-tcp-ipv6`, `pihole-dns-udp-ipv6`, `pihole-web-ipv6`). On an IPv4-only cluster the API server rejects them and the whole install fails |
| MetalLB is installed with both pools, and k3s ServiceLB is disabled | See [Load balancers](../kubernetes/load-balancers.md). With ServiceLB running, the UI ends up on a node's own address instead of `.11` |
| The nodes do **not** use Pi-hole for their own DNS | A node that resolves through Pi-hole cannot pull the Pi-hole image when Pi-hole is down. Nodes use public resolvers (`1.1.1.1`, `9.9.9.9`). See [Raspberry Pi preparation](../hardware/raspberry-pi.md) and [DNS design](../network/dns-design.md) |
| You have chosen which nodes carry Pi-hole | Here: the three Raspberry Pis, not the Mac VM. They get the label `pihole-host=true` |
| You have a **new** admin password | It goes in a Kubernetes Secret, never in the values file. If a password was ever committed to a repository or pasted anywhere, do not reuse it |
| Every device you name has a fixed or reserved address | A name is only as good as the address behind it |

Edit [`files/pihole/values.yaml`](../../files/pihole/values.yaml) for your addresses, domain, device names and blocklists before installing. The structure of the name lists is described under [Local names](#local-names-in-the-values-file).

## Steps

### Step 1. Label the nodes

**Run on: server-1**

```bash
sudo kubectl label node server-1 pihole-host=true --overwrite
sudo kubectl label node server-2 pihole-host=true --overwrite
sudo kubectl label node server-3 pihole-host=true --overwrite
sudo kubectl get nodes -L pihole-host
```

The last command lists the nodes with a `PIHOLE-HOST` column. The three chosen nodes show `true`.

> **Pitfall:** label all nodes before installing. Without the label the pods stay `Pending`. If the nodes are labelled one by one while pods are already waiting, two pods can be placed on the first node that qualifies (see [Pitfalls](#pitfalls)).

### Step 2. Create the admin password Secret

The values file refers to a Secret named `pihole-admin` with the key `password` (`admin.existingSecret`, `admin.passwordKey`). Create it before the first install.

**Run on: server-1**

```bash
sudo kubectl create namespace pihole
sudo kubectl -n pihole create secret generic pihole-admin --from-literal=password='<PIHOLE_ADMIN_PASSWORD>'
```

To change the password later:

```bash
sudo kubectl -n pihole delete secret pihole-admin
sudo kubectl -n pihole create secret generic pihole-admin --from-literal=password='<NEW_PASSWORD>'
sudo kubectl -n pihole rollout restart deployment pihole
```

> **Pitfall:** if you are moving from a values file that had `adminPassword:` inline, create the Secret first. Otherwise the new pods wait for a Secret that does not exist (`CreateContainerConfigError`, "secret not found").

### Step 3. Apply the HTTPS redirect rule

A Traefik Middleware (a rule Traefik applies to requests) sends `http://` requests to `https://`. An Ingress can only refer to a Middleware as `<namespace>-<name>@kubernetescrd`, so there is one copy per namespace. The file creates `redirect-https` in the `pihole` and `homebridge` namespaces; both namespaces must exist, or delete the part you do not use.

**Run on: server-1**, from the root of this repo

```bash
sudo kubectl create namespace homebridge
sudo kubectl apply -f files/traefik/middleware-redirect-https.yaml
```

"AlreadyExists" on the namespace line is fine.

### Step 4. Install

**Run on: server-1**, from the root of this repo

```bash
helm repo add mojo2600 https://mojo2600.github.io/pihole-kubernetes/
helm repo update
helm upgrade --install pihole mojo2600/pihole -n pihole --version 2.38.0 -f files/pihole/values.yaml
sudo kubectl -n pihole rollout status deployment pihole
sudo kubectl -n pihole get pods -o wide
```

If `helm` cannot reach the cluster, run `export KUBECONFIG=/etc/rancher/k3s/k3s.yaml` once in the session and run helm with `sudo -E`.

You should see three pods at `2/2 Running`, one on each labelled node. **Each pod takes several minutes.** It waits 60 seconds on purpose (`misc_delay_startup: "60"`) and then downloads every blocklist.

### Step 5. Point clients at it

Hand out `192.168.50.11` as the DNS server in your router's DHCP settings. How to do that, and how to force devices with hard-coded DNS through Pi-hole, is in [DNS design](../network/dns-design.md).

## What the important settings do

| Setting | Value | Why |
| --- | --- | --- |
| `replicaCount` | `3` | One per chosen node |
| `nodeSelector` | `pihole-host: "true"` | Keeps Pi-hole on the nodes you chose (here: off the Mac VM) |
| `topologySpreadConstraints` | `maxSkew: 1`, `topologyKey: kubernetes.io/hostname`, `whenUnsatisfiable: DoNotSchedule`, selector `app: pihole`, `release: pihole` | Never two pods on one node |
| `topologySpreadConstraints[].matchLabelKeys` | `[pod-template-hash]` | Counts only pods of the same rollout. Without it an upgrade can leave two pods on one node. See [Pitfalls](#pitfalls) |
| `podDisruptionBudget` | `enabled: true`, `minAvailable: 1` | A node drain can never take the last pod |
| `image.pullPolicy`, `doh.pullPolicy` | `IfNotPresent` | A node that already has the image can start Pi-hole without reaching the registry, and so without needing DNS to do it. This avoids a deadlock after a power cut |
| `image.tag` | `latest` | See [Upgrades](#upgrades-and-image-versions) |
| `dualStack.enabled` | `true` | Creates the IPv6 Services |
| `serviceDns`, `serviceWeb` | `type: LoadBalancer`, `loadBalancerIP: 192.168.50.11`, `loadBalancerIPv6: "fd00:1234:5678:50::11"`, annotation `metallb.universe.tf/allow-shared-ip: pihole-svc` | DNS and web share one address per family. The web Service stays a LoadBalancer so `http://192.168.50.11/admin` still works if Traefik is down |
| `serviceWeb` annotations | `traefik.ingress.kubernetes.io/service.sticky.cookie: "true"`, `...sticky.cookie.name: pihole_pod` | Fixes the login loop |
| `serviceDhcp.enabled` | `false` | The chart creates a DHCP LoadBalancer by default (and an IPv6 one with dual-stack). They would take extra MetalLB addresses |
| `ingress` | `enabled: true`, `ingressClassName: traefik`, host `pihole.home.example.com`, path `/`, annotation `traefik.ingress.kubernetes.io/router.middlewares: pihole-redirect-https@kubernetescrd` | HTTPS without a port; `http://` redirected |
| `admin` | `existingSecret: "pihole-admin"`, `passwordKey: "password"` | Password from the Secret |
| `doh` | `enabled: true`, `tag: "2025.9.1"`, `TUNNEL_DNS_UPSTREAM: "https://1.1.1.1/dns-query,https://1.0.0.1/dns-query"` | The sidecar. The chart points Pi-hole at `127.0.0.1#5053` automatically. The tag is pinned on purpose, see below |
| `FTLCONF_dns_listeningMode` | `all` | In Kubernetes, queries arrive from LAN and node addresses, not from the pod's own subnet. `LOCAL` drops them |
| `FTLCONF_dns_reply_host_force4` / `_IPv4`, `_force6` / `_IPv6` | `true` and the two floating addresses | Pi-hole answers for its own name (`pi.hole`, the pod host name) with the floating addresses, not with pod addresses |
| `FTLCONF_dns_revServers` | `true,192.168.50.0/24,192.168.50.1,home.example.com;true,fd00:1234:5678:50::/64,192.168.50.1,home.example.com` | Reverse lookups for devices not listed in the file go to the router. Array entries are separated by `;` |
| `FTLCONF_dns_domainNeeded` | `true` | Names without a dot are not forwarded upstream |
| `FTLCONF_dns_specialDomains_mozillaCanary`, `_iCloudPrivateRelay`, `_designatedResolver` | `true` | Stops browsers and Apple devices switching to their own encrypted DNS. These are the defaults, kept explicit |
| `ftl` block | `misc_delay_startup: "60"`, `dns_ignoreLocalhost: "true"`, `dns_piholePTR: "HOSTNAME"`, `dns_showDNSSEC: "true"`, `resolver_refreshNames: "ALL"`, `database_network_parseARPcache: "true"` | The chart prefixes each key with `FTLCONF_` |
| `podDnsConfig` | `enabled: true`, `policy: "None"`, name servers `127.0.0.1`, `1.1.1.1` | The pod resolves through itself, with an outside fallback while it is starting |
| `dnsmasq.customDnsEntries` | `address=/<name>/<address>` lines | Service names |
| `dnsmasq.additionalHostsEntries` | one line per device | Device names |
| `adlists`, `whitelist`, `blacklist`, `regex` | lists | Blocklists and exceptions, loaded at every pod start |

## Local names in the values file

There are two lists under `dnsmasq:`.

**`customDnsEntries`** holds service names: names for things reached through a shared address, or that are not a device's own name. Every web app behind Traefik points at Traefik's address. Add an IPv6 line when the target has a fixed IPv6 address.

```yaml
dnsmasq:
  customDnsEntries:
    - address=/pihole.home.example.com/192.168.50.12
    - address=/hb.home.example.com/192.168.50.12
    - address=/k3s.home.example.com/192.168.50.10
    - address=/gateway.home.example.com/192.168.50.1
    - address=/gateway.home.example.com/fd00:1234:5678:50::1
```

Note that `pihole.home.example.com` points at Traefik (`.12`) for the UI. DNS itself stays on `.11`.

**`additionalHostsEntries`** holds device names. Each line is `<address>  <short name>  <full name>`, so a device answers to both `server-1` and `server-1.home.example.com`.

```yaml
dnsmasq:
  additionalHostsEntries:
    - 192.168.50.3     ap-openwrt ap-openwrt.home.example.com
    - 192.168.50.5     server-1 server-1.home.example.com
    - fd00:1234:5678:50::3     ap-openwrt ap-openwrt.home.example.com
    - 192.168.101.20   kitchen-switch kitchen-switch.home.example.com
```

A workable way to keep this list honest:

- Group the lines with comments (network gear, cluster nodes, computers, cameras, IoT network).
- Mark each line `[static]` (address set on the device or reserved on the router) or `[dhcp]` (handed out by the router and not reserved). A `[dhcp]` line goes stale when the device gets a different address, so reserve the address on the router first.
- Build the list from the router's client list, and re-export it now and then.

To add a device name, add a line and run the upgrade command again:

**Run on: server-1**, from the root of this repo

```bash
helm upgrade --install pihole mojo2600/pihole -n pihole --version 2.38.0 -f files/pihole/values.yaml
```

Pods restart one at a time; DNS stays up.

### Blocklists and exceptions

- `adlists` entries must be raw list URLs. A `github.com/.../blob/...` address is an HTML page, not a list; use the raw URL.
- For the Hagezi lists, only the `-onlydomains` files are in Pi-hole format. The plain wildcard files use `*.domain` lines, which Pi-hole rejects.
- `regex` entries are matched against DNS names. A pattern that starts with `^https?://` never matches, because a DNS query never contains a URL scheme.
- If one site does not work while everything else does, find it in the Pi-hole query log, add it under `whitelist:` in the values file, and upgrade.

## What three copies cost

- The query log and dashboard are per pod. The web UI shows whichever pod your cookie pins you to.
- **Changes made in the web UI are lost when that pod restarts, and never reach the other two pods.** Make every change in the values file and run the upgrade command.
- Counters reset to zero whenever a pod restarts, including on every helm upgrade, because nothing is kept on disk.
- This covers losing any one node. It does not cover the whole cluster being down. A second Pi-hole outside the cluster, set as the router's second DNS server, would cover that; it is not part of this build.

## The DNS-over-HTTPS sidecar is pinned, and why

The sidecar uses cloudflared's `proxy-dns` command. Cloudflare [removed `proxy-dns` from cloudflared releases from 2 February 2026](https://developers.cloudflare.com/changelog/post/2025-11-11-cloudflared-proxy-dns/). Releases from before that date keep working. `doh.tag` is therefore pinned to `2025.9.1`, the last `crazymax/cloudflared` build before the removal (it has an arm64 build, and it was also what the `latest` tag of that image pointed at when checked).

- **Do not raise that tag.** A pod that pulls a build without `proxy-dns` shows `1/2`: the sidecar fails and Pi-hole has no upstream.
- If the image ever becomes unavailable, the replacement is `dnscrypt-proxy` as a container in the same pod, listening on port 5053, with `doh.enabled: false`. **Not verified:** this was evaluated and deliberately not built, because the pinned setup still encrypts.

Check what each pod is actually running:

**Run on: server-1**

```bash
sudo kubectl -n pihole get pods -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{range .status.containerStatuses[*]}{.image}{" "}{end}{"\n"}{end}'
```

## Upgrades and image versions

- Always apply the **whole** values file. A helm upgrade with a partial file removes the settings that are missing from it.
- `image.tag` is `latest` with `IfNotPresent`. A node keeps whatever it pulled, so the three pods can end up on different Pi-hole versions. To choose a version, set `tag:` to a dated release (the form is `"2026.07.2"`) and upgrade. Pinning is recommended so upgrades happen when you choose.
- After every upgrade, check the placement:

**Run on: server-1**

```bash
sudo kubectl -n pihole get pods -o wide
```

One pod per node. If two share a node, see the next section.

> **Not verified:** the `matchLabelKeys` placement fix is in the values file, but it had not yet been through an upgrade when this was written. Run the check above after each upgrade regardless.

## Check it

**Run on: server-1**

```bash
sudo kubectl get svc -n pihole
```

Every LoadBalancer Service lists `192.168.50.11` or `fd00:1234:5678:50::11` under `EXTERNAL-IP`. None shows `<pending>` or a node's own address.

**Run on: your computer** (on the LAN, not on a VPN)

```bash
nslookup example.com 192.168.50.11
nslookup example.com fd00:1234:5678:50::11
nslookup doubleclick.net 192.168.50.11
nslookup pihole.home.example.com 192.168.50.11
curl -sI -H 'Host: pihole.home.example.com' http://192.168.50.12/admin/ | head -3
```

| Command | Expected |
| --- | --- |
| 1 and 2 | Real addresses for `example.com` |
| 3 | `0.0.0.0` (blocked) |
| 4 | `192.168.50.12` |
| 5 | `301` with `Location: https://pihole.home.example.com/admin/` |

Then open `https://pihole.home.example.com/admin`, accept the certificate warning (Traefik's self-signed certificate), and log in. Click around: the login must **stay** logged in.

Confirm the upstream is encrypted:

**Run on: server-1**

```bash
sudo kubectl logs -n pihole deploy/pihole -c cloudflared --tail=20
```

The log shows connections to `https://1.1.1.1/dns-query` and no errors.

> **Floating addresses do not answer ping.** `ping 192.168.50.11` failing is normal for a MetalLB address: MetalLB answers ARP for the address and the cluster forwards only the Service's ports (53, 80), so ICMP echo gets no reply. Test with `nslookup` (`.11`) or `curl` (`.12`), never with ping.

## Pitfalls

### The login loop

**What happens.** With more than one pod, signing in to the web UI bounces straight back to the login page.

**Why.** Each pod keeps its own login sessions in memory. You log in on pod A; the next request lands on pod B, which has never heard of your session and answers `401` "session unknown" on `/api/auth` (visible in a browser network capture).

**What it is not.** The host firewall (it still looped with the firewall off on every node), and IPv4 against IPv6 (the capture was all IPv4).

**Fix.** Reach the UI through Traefik with a sticky cookie, so a browser keeps hitting the same pod. That is the `ingress:` block, the two `service.sticky.cookie` annotations on `serviceWeb`, and `pihole.home.example.com` pointing at `192.168.50.12` instead of `.11`.

If it ever loops through Traefik, check the cookie is being set:

**Run on: your computer**

```bash
curl -skI https://192.168.50.12/admin/ -H 'Host: pihole.home.example.com' | grep -i set-cookie
```

It should show `pihole_pod`. If it does, clear the browser's cookies for the site.

`http://192.168.50.11/admin` still works as a fallback. It has no stickiness. With one pod per node it reaches the single pod on the announcing node; with two pods on one node it alternates between them and loops. If you must use it while placement is wrong, scale to one pod for a few minutes:

**Run on: server-1**

```bash
sudo kubectl -n pihole scale deployment pihole --replicas=1
```

Scale back with `--replicas=3` afterwards.

### Two pods on one node after a helm upgrade, none on another

**What happens.** After an upgrade, two pods sit on one node and a labelled node has none.

**Why.** A rolling upgrade starts each new pod while old ones still run. The "one per node" rule counted old and new pods together, so the empty node looked occupied (by an old pod) when a new pod was placed. When the old pods went away the result was lopsided.

**Why it matters.** If the node with two pods dies, two of three Pi-holes go with it. And two pods behind one address on one node make `http://192.168.50.11/admin` loop at login.

**Fix now.** Delete one of the two pods that share a node. With no old pods around, the replacement must go to the empty node.

**Run on: server-1**

```bash
sudo kubectl -n pihole get pods -o wide
sudo kubectl -n pihole delete pod <one of the two on the same node>
```

**Permanent fix.** `matchLabelKeys: [pod-template-hash]` under `topologySpreadConstraints`. The label `pod-template-hash` is different for each rollout of a Deployment, so the rule counts only pods of the same rollout. It is in the values file (see the "not verified" note under [Upgrades](#upgrades-and-image-versions)).

### Two pods on one node at first install

**Why.** The nodes were labelled while pods were already waiting; both pending pods were placed the instant the first node qualified. Fix as above: delete one of the pair.

### The dashboard shows almost no queries and only a few clients

**What happens.** The UI shows a hundred or so queries and three clients while the house is clearly using DNS.

**Why.** The dashboard is one pod's view. Because of `externalTrafficPolicy: Local`, only the pod on the announcing node answers DNS. The sticky cookie has pinned your browser to a standby.

**See which pod is doing the work.**

**Run on: server-1**

```bash
for p in $(sudo kubectl -n pihole get pods -o name); do echo "$p: $(sudo kubectl -n pihole exec $p -c pihole -- pihole-FTL sqlite3 /etc/pihole/pihole-FTL.db 'select count(*), count(distinct client) from queries;')"; done
```

Each line is `pod: queries|distinct clients`. One pod has thousands and dozens; the others have a handful. The pod's name is shown at the top of the web UI, so you can tell which one you are looking at.

**To look at the busy pod's dashboard,** open `http://192.168.50.11/admin`. That address goes to the node that is answering DNS. Through `https://pihole.home.example.com` you get whichever pod your cookie points at; delete the `pihole_pod` cookie to be assigned again.

> **Why not `Cluster`:** `externalTrafficPolicy: Cluster` would spread queries over all three pods, but every client would appear as a cluster-internal address, which ruins the per-client statistics. `Local` is the better trade.

### Other traps

| What happens | Why | Avoid or recover |
| --- | --- | --- |
| Pods stuck `Pending` | The `pihole-host` label is not on the nodes | Label first (Step 1), then install |
| `ImagePullBackOff` | The node's own DNS points at an address that no longer serves DNS (often Pi-hole itself) | Give nodes public resolvers. [Raspberry Pi preparation](../hardware/raspberry-pi.md), [DNS design](../network/dns-design.md) |
| The UI answers on a node's address (`192.168.50.5`) instead of `.11`; `-ipv6` Services `<pending>` | k3s ServiceLB took the Services | `disable: servicelb` on every server. [Load balancers](../kubernetes/load-balancers.md) |
| helm install fails on the `-ipv6` Services | The cluster is not dual-stack | [HA k3s cluster](../kubernetes/k3s-ha-cluster.md) |
| A change made in the web UI disappeared | Pods rebuild from the values file | Make the change in the file |
| After a power cut, no DNS for several minutes | The router is up before the nodes; each pod waits 60 seconds and then downloads its blocklists | Expected. It settles by itself in about five minutes, provided the nodes have their own DNS |

## Troubleshooting

Start here when DNS is down.

**Run on: server-1**

```bash
sudo kubectl -n pihole get pods -o wide
sudo kubectl -n pihole get svc
sudo kubectl -n pihole get events --sort-by=.lastTimestamp | tail -15
sudo kubectl -n metallb-system get pods -o wide
```

| Symptom | Cause | Fix |
| --- | --- | --- |
| No pod is `2/2 Running` | Image pull failure (node DNS) or the admin Secret is missing | `sudo kubectl -n pihole describe pod <name> \| tail -20`; then node DNS or Step 2 |
| Pods are `1/2` | The sidecar or Pi-hole itself is failing | `sudo kubectl -n pihole logs <pod> -c cloudflared --tail=20` and `-c pihole --tail=40` |
| Pod `1/2` after pulling a fresh image | A cloudflared build without `proxy-dns` | Keep `doh.tag: "2025.9.1"` |
| Pods fine, Services show `.11`, no answers | MetalLB is not announcing, or announces from a node with no healthy pod | `sudo kubectl -n metallb-system logs -l component=speaker --tail=30`; restart the speakers with `sudo kubectl -n metallb-system rollout restart daemonset speaker` |
| Services show `<pending>` | MetalLB controller down or pool missing | [Load balancers](../kubernetes/load-balancers.md) |
| Everything looks fine on the cluster | The fault is between the device and `.11` | From another device: `nslookup example.com 192.168.50.11`. If that works, it is the one device. If a node firewall is on, see [Node firewall](../kubernetes/node-firewall.md) |
| Login loops on `https://pihole.home.example.com` | The sticky cookie is not reaching the browser | The `set-cookie` check above; then clear cookies |
| Login loops on `http://192.168.50.11/admin` | More than one pod on the announcing node | Fix the placement |
| All counters zero or tiny on every pod | The pods restarted recently | `AGE` column of `get pods`. Counters do not survive restarts |
| `pihole.home.example.com` does not resolve on one laptop | That laptop is on a VPN whose DNS answers instead of Pi-hole | [Client devices](client-devices.md) |
| Web UI unreachable from a VPN or another subnet | The node firewall allows only the LAN range | [Node firewall](../kubernetes/node-firewall.md) |
| Ping to `192.168.50.11` fails | Normal | Test with `nslookup` |
| Everything works but one site does not | Pi-hole blocks it | Query log, then `whitelist:` in the values file |

**Emergency bypass,** to get the house working while you fix Pi-hole: on the router, set the DHCP DNS server to a public resolver such as `9.9.9.9` and switch off any rule that redirects DNS to Pi-hole. Devices pick it up as they renew (toggle Wi-Fi to force it). Put both settings back afterwards. Router steps: [ASUS ZenWiFi XT8](../hardware/asus-zenwifi-xt8.md).

More cross-component cases: [Troubleshooting](../operations/troubleshooting.md).

## Undo

**Run on: server-1**

```bash
helm uninstall pihole -n pihole
sudo kubectl delete namespace pihole
```

Before you do, point the router's DHCP DNS server at another resolver, or every device loses DNS. Nothing else needs cleaning: Pi-hole kept nothing on disk.

## References

- [MoJo2600/pihole-kubernetes](https://github.com/MoJo2600/pihole-kubernetes): the Helm chart used here, with its values reference.
- [Pi-hole Docker configuration](https://docs.pi-hole.net/docker/configuration/): how `FTLCONF_` environment variables map to Pi-hole v6 settings.
- [MetalLB usage](https://metallb.io/usage/): requesting specific addresses, IP address sharing between Services, and what `externalTrafficPolicy` does in layer 2 mode.
- [Kubernetes: Pod topology spread constraints](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/): `maxSkew`, `whenUnsatisfiable` and `matchLabelKeys`.
- [Traefik: Kubernetes Ingress routing configuration](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/ingress/): the sticky-cookie Service annotations and the `router.middlewares` Ingress annotation.
- [Cloudflare changelog: cloudflared proxy-dns command will be removed starting February 2, 2026](https://developers.cloudflare.com/changelog/post/2025-11-11-cloudflared-proxy-dns/): why the sidecar image is pinned.
- [Pi-hole forum: Pi-hole not working after updating cloudflared](https://discourse.pi-hole.net/t/pi-hole-not-working-after-updating-cloudflared/85149): the same removal seen on a plain install, with dnscrypt-proxy and Unbound as replacements.
