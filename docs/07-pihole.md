# 07. Pi-hole

Three Pi-hole pods, one per Raspberry Pi, behind 192.168.50.11 and `fd00:1234:5678:50::11`. Chart `mojo2600/pihole` 2.38.0 (Pi-hole v6). Upstream DNS goes out as DNS-over-HTTPS through a cloudflared sidecar to 1.1.1.1 and 1.0.0.1.

Pi-hole keeps **nothing on disk**. Every pod rebuilds itself from `pihole/values.yaml` at start: blocklists, allowlist, local names. So nothing needs syncing between pods, and the values file in this repo *is* the backup.

## Before you start

- The cluster is dual-stack ([04](04-k3s-cluster.md)). On an IPv4-only cluster the chart's `-ipv6` Services are rejected and the whole install fails.
- MetalLB is installed with both pools ([06](06-load-balancers.md)).
- The three Pis carry `pihole-host=true`.
- The nodes do **not** use Pi-hole for their own DNS.

## Step 1. Label the Pis

**Paste on: k3sprimary.** Skip if already done in [04](04-k3s-cluster.md).

```bash
sudo kubectl label node k3sprimary pihole-host=true --overwrite
sudo kubectl label node funkyfresh pihole-host=true --overwrite
sudo kubectl label node k3snode2 pihole-host=true --overwrite
sudo kubectl get nodes -L pihole-host
```

## Step 2. The admin password

The password is not in the values file. Create it as a Secret. Replace the placeholder with a **new** password (the old one was in this repo and in chat; do not reuse it).

```bash
sudo kubectl create namespace pihole
sudo kubectl -n pihole create secret generic pihole-admin --from-literal=password='<PIHOLE_ADMIN_PASSWORD>'
```

To change it later:

```bash
sudo kubectl -n pihole delete secret pihole-admin
sudo kubectl -n pihole create secret generic pihole-admin --from-literal=password='<NEW_PASSWORD>'
sudo kubectl -n pihole rollout restart deployment pihole
```

**Your live cluster still has the password inline** (`adminPassword:` in `~/helm/pihole/values.yaml`). The first time you apply this repo's file, do Step 2 first, or the pods will wait for a Secret that does not exist.

## Step 3. The HTTPS redirect rule

```bash
sudo kubectl apply -f traefik/middleware-redirect-https.yaml
```

## Step 4. Install

**Paste on: k3sprimary**, in the root of this repo.

```bash
helm repo add mojo2600 https://mojo2600.github.io/pihole-kubernetes/
helm repo update
helm upgrade --install pihole mojo2600/pihole -n pihole --version 2.38.0 -f pihole/values.yaml
sudo kubectl -n pihole rollout status deployment pihole
sudo kubectl -n pihole get pods -o wide
```

If `helm` cannot reach the cluster, put this in front of the session once: `export KUBECONFIG=/etc/rancher/k3s/k3s.yaml` and run helm with `sudo -E`.

You should see three pods at `2/2 Running`, one on each Pi. **Each pod takes several minutes**: it waits 60 seconds on purpose, then downloads all 56 blocklists.

## Check it

```bash
sudo kubectl get svc -n pihole
```

Every LoadBalancer Service lists `192.168.50.11` or `fd00:1234:5678:50::11` under EXTERNAL-IP. Then from any computer on the LAN:

```bash
nslookup example.com 192.168.50.11
nslookup example.com fd00:1234:5678:50::11
nslookup doubleclick.net 192.168.50.11
nslookup pihole.home.example.com 192.168.50.11
curl -sI -H 'Host: pihole.home.example.com' http://192.168.50.12/admin/ | head -3
```

The first two return real addresses, the third returns `0.0.0.0`, the fourth returns `192.168.50.12`, and the last prints `301` with `Location: https://pihole.home.example.com/admin/`.

Then open `https://pihole.home.example.com/admin`, accept the certificate warning, and log in.

## What the important settings do

| Setting | Value | Why |
| --- | --- | --- |
| `replicaCount` | 3 | One per Pi |
| `nodeSelector` | `pihole-host: "true"` | Keeps Pi-hole off the Mac VM |
| `topologySpreadConstraints` | one per hostname, `DoNotSchedule` | Never two pods on one Pi |
| `podDisruptionBudget` | `minAvailable: 1` | A drain can never take the last pod |
| `image.pullPolicy`, `doh.pullPolicy` | `IfNotPresent` | A Pi that already has the image can start Pi-hole without reaching the registry, and without DNS |
| `dualStack.enabled` | `true` | Creates the IPv6 Services |
| `serviceDns` / `serviceWeb` | `loadBalancerIP: 192.168.50.11`, `loadBalancerIPv6: fd00:…::11`, annotation `allow-shared-ip: pihole-svc` | DNS and web share one address |
| `serviceDhcp.enabled` | `false` | Otherwise it grabs extra MetalLB addresses |
| `ingress` | host `pihole.home.example.com`, class `traefik`, redirect middleware | HTTPS without a port, http redirected |
| `serviceWeb` sticky cookie | `pihole_pod` | **Fixes the login loop**, below |
| `FTLCONF_dns_listeningMode` | `all` | In Kubernetes, queries arrive from non-local addresses. `LOCAL` drops them |
| `FTLCONF_dns_reply_host_*` | the two floating addresses | Pi-hole reports its own name on them, not on pod addresses |
| `FTLCONF_dns_revServers` | the XT8, both ranges | Reverse lookups for devices not listed in the file |
| `doh` | cloudflared to 1.1.1.1 and 1.0.0.1 | Upstream leaves as HTTPS on port 443, so Pi-hole needs no DNS Director exception |
| `podDnsConfig` | `127.0.0.1`, `1.1.1.1` | The pod resolves through itself, with an outside fallback while starting |
| `dnsmasq.customDnsEntries` | `address=/name/ip` | Service names ([01](01-inventory.md)) |
| host lines | one per device | Every device from the router's client list, short name and full name |

## Trouble we hit

### The login loop

After going to three replicas, signing in to the web UI bounced straight back to the login page.

**Cause.** Each pod keeps its own login sessions in memory. You log in on pod A; the next request lands on pod B, which has never heard of your session and answers `401 session unknown` (this was visible in a browser HAR capture, on `/api/auth`).

**Things it was not:** the host firewall (it still looped with `ufw` off on every node), and IPv4 against IPv6 (the capture was all IPv4).

**Fix.** Reach the UI through Traefik with a sticky cookie, so a browser keeps hitting the same pod. That is the `ingress:` block plus the two `service.sticky.cookie` annotations on `serviceWeb`, with `pihole.home.example.com` pointing at 192.168.50.12 instead of .11.

The cluster side was confirmed working (301 to https, then 302 into the admin page), and the phone logged in and stayed logged in through this route. The work Mac kept looping until the pod placement and the firewall range were fixed (both below). If it ever loops through Traefik again, check the cookie is being set: `curl -skI https://192.168.50.12/admin/ -H 'Host: pihole.home.example.com' | grep -i set-cookie` should show `pihole_pod`.

`http://192.168.50.11/admin` still works as a fallback, without stickiness, so it can loop. If you must use it, scale to one pod for a few minutes: `sudo kubectl -n pihole scale deployment pihole --replicas=1`, and back to 3 afterwards.

### "HTTPS on the Pi-hole doesn't resolve"

The work MacBook's DNS goes to the VPN's proxy (`fddd:dddd::…`), which answers NXDOMAIN for home names. Nothing was wrong with Pi-hole. Fix: `/etc/hosts` on that Mac ([11](11-clients.md)).

### Two pods on one Pi after a `helm upgrade`, none on another

Found on 4 October: two pods on k3sprimary, one on k3snode2, none on funkyfresh, although all three Pis had the label.

**Cause.** A helm upgrade starts each new pod while the old ones still run. The "one per Pi" rule counted old and new pods together, so funkyfresh looked occupied (by an old pod) when a new pod was placed. When the old pods went away the result was lopsided.

**See it:**

```bash
sudo kubectl -n pihole get pods -o wide
```

**Fix it now:** delete one of the two pods that share a Pi. With no old pods around, the replacement must go to the empty Pi.

```bash
sudo kubectl -n pihole delete pod <one of the two on the same node>
```

**Permanent fix:** `matchLabelKeys: [pod-template-hash]` under `topologySpreadConstraints`, which makes the rule count only pods of the same rollout. It is in `pihole/values.yaml` now. It has not been through an upgrade here yet, so run the `get pods -o wide` line after the next upgrade anyway.

**Why it mattered:** if k3sprimary had died, two of three Pi-holes would have gone with it. And with two pods behind one address on one Pi, `http://192.168.50.11/admin` alternated between them and looped at login.

### The dashboard shows almost no queries and only a few clients

On 4 October the UI showed 124 queries and 3 clients while the house was clearly using DNS.

**Cause.** The dashboard is one pod's view. The Pi-hole Services use `externalTrafficPolicy: Local`, which keeps each client's real address but means DNS sent to 192.168.50.11 is answered **only by the pod on the Pi that currently announces that address**. The other pods are standbys and see almost nothing. The sticky cookie had pinned the browser to a standby.

**See which pod is doing the work:**

```bash
for p in $(sudo kubectl -n pihole get pods -o name); do echo "$p: $(sudo kubectl -n pihole exec $p -c pihole -- pihole-FTL sqlite3 /etc/pihole/pihole-FTL.db 'select count(*), count(distinct client) from queries;')"; done
```

Each line is `pod: queries|distinct clients`. One pod has thousands and dozens; the others have a handful. The pod's name is shown at the top of the web UI, so you can tell which one you are looking at.

**To look at the busy pod's dashboard:** open `http://192.168.50.11/admin`. That address goes to the Pi that is answering DNS, which is the busy pod. (Through `https://pihole.home.example.com` you get whichever pod your cookie points at; delete the `pihole_pod` cookie to be re-assigned.)

Counters also reset to zero whenever a pod restarts, including every helm upgrade, because nothing is kept on disk.

This is the price of `Local`. The alternative, `Cluster`, spreads queries over all three pods but makes every client appear as a cluster-internal address, which ruins the per-client statistics. `Local` is the better trade.

### Cannot reach the web UI (or SSH, or Homebridge) from the VPN

From the VPN you arrive from 192.168.0.x. The node firewall only allowed 192.168.50.0/24, so anything addressed to a Pi itself was refused. Fixed by allowing 192.168.0.0/16 ([10](10-firewall.md)). The work Mac's login loop stopped after this and the pod placement fix were both applied; they were done together, so which of the two cured the loop was not separated.

### Pods stuck `Pending`

The `pihole-host` label was not on the Pis yet. Label first, then upgrade.

### Two pods on one Pi

The Pis were labelled with one command; both new pods were placed the instant the first Pi qualified. Delete one of the pair and its replacement goes to the empty Pi:

```bash
sudo kubectl -n pihole get pods -o wide
sudo kubectl -n pihole delete pod <one of the two on the same node>
```

### `ImagePullBackOff`

The Pi's own DNS pointed at an address that no longer served DNS. See [04](04-k3s-cluster.md), Step 2.

### The UI showed on 192.168.50.5, not .11

servicelb. See [06](06-load-balancers.md).

## What three copies cost

- The query log and dashboard are per pod. The web UI shows whichever pod your cookie pins you to.
- **Changes made in the web UI are lost when that pod restarts, and never reach the other two.** Make every change in `pihole/values.yaml` and run the `helm upgrade` line again.
- This covers losing any one Pi. It does not cover the whole cluster being down.

## Adding a device name

Add a line under the host list in `pihole/values.yaml`, in the same form as the others (`- <address>  <short-name> <short-name>.home.example.com`), then:

```bash
helm upgrade --install pihole mojo2600/pihole -n pihole --version 2.38.0 -f pihole/values.yaml
```

Pods restart one at a time; DNS stays up. A name is only as good as the address behind it, so reserve the device's address on the XT8 first.

## The encryption sidecar is pinned, and why

Upstream DNS leaves the house encrypted (DNS-over-HTTPS to Cloudflare) through the `cloudflared` container in each pod, so the ISP cannot read the queries. That container uses cloudflared's `proxy-dns` feature, which **Cloudflare removed from releases after 2 February 2026**. `doh.tag` is therefore pinned to `2025.9.1`, the last `crazymax/cloudflared` build before the removal (it is also what `latest` pointed at when checked on 4 October 2026, built for arm64).

Do not raise that tag. If the image ever becomes unavailable, the replacement is dnscrypt-proxy as a container in the same pod, listening on port 5053, with `doh.enabled: false`. That was looked at on 4 October and deliberately not done, because the current setup already encrypts.

Check what a pod is actually running:

```bash
sudo kubectl -n pihole get pods -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{range .status.containerStatuses[*]}{.image}{" "}{end}{"\n"}{end}'
```

## Pinning the image

`image.tag` is `latest`. With `IfNotPresent` a Pi keeps whatever it pulled, so the three pods can end up on different versions. To choose a version, set `tag:` to a dated release and upgrade.
