# Homebridge on k3s

You end up with Homebridge (a bridge that makes non-HomeKit devices appear in Apple's Home app) running as one pod on one k3s node, with its web UI at `https://hb.home.example.com` behind Traefik. The page also covers the DNS failure that host-network pods suffer on a dual-stack cluster, and its fix.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | Homebridge v2.4.0, image `ghcr.io/homebridge/homebridge`, Helm chart `k8s-at-home/homebridge` (archived), k3s v1.34 dual-stack with local-only IPv6, Traefik bundled with k3s, on a Raspberry Pi (arm64) |
| **Also works for** | Any Kubernetes cluster with a default storage class and Traefik. The DNS section applies to **any** `hostNetwork` pod on a dual-stack cluster whose nodes have no route to the IPv6 service range. Not tested by the author beyond the setup above |
| **Time** | 20 minutes with a backup to restore; an hour or more without |
| **You need first** | [HA k3s cluster](../kubernetes/k3s-ha-cluster.md), [Load balancers](../kubernetes/load-balancers.md) (Traefik on `192.168.50.12`), a DNS name for the UI ([Pi-hole](pihole.md) or any local DNS). Useful background: [CoreDNS](../kubernetes/coredns.md) |

Related pages: [Kasa devices across networks](homebridge-kasa-across-networks.md), [Cameras](homebridge-cameras.md).

## How it works

- **Host network.** HomeKit finds bridges by mDNS (multicast announcements on the local network) and then connects to the accessory ports. Neither works from inside the cluster's pod network. So the pod uses `hostNetwork: true`: it shares the node's network, and its traffic comes from the node's address (`192.168.50.5` for `server-1`).
- **One replica, on purpose.** HomeKit pairs with one bridge identity, stored on one volume. Two copies would be two bridges fighting over the same accessories. This app is not highly available. If its node dies, restore the Homebridge backup onto another node.
- **Pinned to a node by its volume.** Everything Homebridge knows (`config.json`, plugins, the HomeKit pairing) lives on a `local-path` volume, which is a folder on one node's disk (under `/var/lib/rancher/k3s/storage` on k3s). Once the volume exists, the pod can only run on that node.
- **UI behind Traefik.** Traefik (on `192.168.50.12`) terminates HTTPS and talks plain HTTP to the UI on port 8581. `http://192.168.50.5:8581` keeps working as a fallback.
- **DNS needs help.** A host-network pod on a dual-stack cluster is handed an IPv6 DNS address that the node cannot route to. The values file replaces the pod's DNS settings. See [The DNS block](#the-dns-block-required-on-a-dual-stack-cluster).

## Before you start

| Decide or gather | Notes |
| --- | --- |
| Which node runs Homebridge | Here `server-1`. Wherever the pod lands on first install is where its volume is created and where it stays. To choose, cordon the other nodes during the first install or add a node selector to the values file (the supplied file has none) |
| The cluster DNS Service address | `sudo kubectl -n kube-system get svc kube-dns`. On k3s the default is `10.43.0.10`. It must match `dnsConfig.nameservers` in the values file |
| A name for the UI pointing at Traefik | `hb.home.example.com` → `192.168.50.12`. In Pi-hole: `address=/hb.home.example.com/192.168.50.12` |
| A Homebridge backup archive, if you have one | Restores config, plugins and pairing in one step |
| Accounts and keys for your plugins | TP-Link/Kasa account, Wyze account with API key and key ID, Resideo developer app consumer key and secret, camera logins |

> **Pitfall:** `config.json` and the backup archive contain passwords (cameras, TP-Link, Wyze, Resideo tokens). Never commit them to Git and never paste the file into a chat, forum post or issue. If you need help with a config, replace every credential with a placeholder first. If it has already been pasted somewhere, treat every credential in it as read: change each one, and give each service its own password. See [Backups and secrets](../operations/backups-and-secrets.md).

## Steps

### Step 1. Install

**Run on: server-1**, from the root of this repo

```bash
helm repo add k8s-at-home https://k8s-at-home.com/charts/
helm repo update
sudo kubectl create ns homebridge
sudo kubectl create ns pihole
sudo kubectl apply -f files/traefik/middleware-redirect-https.yaml
helm upgrade --install homebridge k8s-at-home/homebridge -n homebridge -f files/homebridge/values.yaml
sudo kubectl -n homebridge rollout status deployment homebridge
sudo kubectl -n homebridge get pods -o wide
```

What this does: adds the chart repository, creates the namespace, applies the Traefik rule that redirects `http://` to `https://`, installs the chart with [`files/homebridge/values.yaml`](../../files/homebridge/values.yaml), and waits for the pod.

- The middleware file creates `redirect-https` in both the `pihole` and `homebridge` namespaces, which is why both namespaces are created. If you do not run Pi-hole, delete that part of the file instead. "AlreadyExists" is fine.
- The pod must show the node you intended in the `NODE` column.
- If you keep a working copy of the values file on the node, keep it identical to the one in the repo. Always apply the whole file.

> **Not verified:** the k8s-at-home chart repository was archived in 2022. `helm upgrade` still fetched the chart when this was written. If it ever cannot, the same change can be made directly on the Deployment with `kubectl patch`; save a copy of the chart (`helm pull k8s-at-home/homebridge`) while it is still available.

### Step 2. Restore the backup, if you have one

Open `http://192.168.50.5:8581`, finish the first-run screen, then **Settings → Backup → Restore** and choose the backup archive. That brings back `config.json`, the plugins and the HomeKit pairing. Skip to [Check it](#check-it).

Without a backup, continue with Steps 3 to 5 and pair every bridge again in the Home app.

### Step 3. UI settings

In the Homebridge UI, **Settings**:

| Setting | Value | Why |
| --- | --- | --- |
| Enable HTTPS | **Off** | Traefik does the HTTPS and talks plain HTTP to the UI. On gives "Bad Gateway" |
| UI port | `8581` | Do not change to 80 or 443; Traefik is in front |
| Host IP | `0.0.0.0` | Traefik reaches the UI over the pod network |
| Reverse proxy hostname | `hb.home.example.com` | So the UI accepts requests arriving under that name |
| Network interfaces (mDNS) | `eth0` only | Switch off `flannel.1`, `flannel-v6.1` and `cni0`. Advertising HomeKit on the cluster's internal interfaces is useless and confused discovery (accessories stuck pairing) |
| mDNS advertiser | **Ciao** | With the Avahi advertiser the log showed "Could not (re-)create mDNS advertisement ... DBusInvokeError: Local name collision". None with Ciao |
| Homebridge port | `51192` (example) | The main bridge. Each child bridge has its own port in its `_bridge` block |
| Scheduled restart | optional, for example 05:00 daily (`0 5 * * *`) | If set, expect a clean restart in the log at that time |

The UI is then at `https://hb.home.example.com` with no port; `http://` redirects. The browser warns about Traefik's self-signed certificate; accept it.

### Step 4. Plugins

Install plugins from the **Plugins** page of the UI. They are kept on the volume. Do not install them from the startup script.

| Plugin (version used) | For | Child bridge |
| --- | --- | --- |
| `homebridge-kasa-python` (3.2.0) | TP-Link Kasa switches, dimmers, fans. [Kasa devices across networks](homebridge-kasa-across-networks.md) | Yes |
| `homebridge-wyze-smart-home` (0.5.61) | Wyze bulbs, plugs, light strips (through Wyze's cloud) | Yes |
| `homebridge-wiz-lan` (3.4.2) | WiZ bulbs | |
| `@homebridge-plugins/homebridge-camera-ffmpeg` (4.1.0) | Cameras. [Cameras](homebridge-cameras.md) | No (cameras on the main bridge here) |
| `@homebridge-plugins/homebridge-resideo` (3.2.3) | Resideo/Honeywell Home thermostat | |

A child bridge is a plugin running in its own process with its own HomeKit pairing, so a crashing plugin does not take the others down.

Plugins **not** to install:

| Plugin | Why not |
| --- | --- |
| `homebridge-camera-ffmpeg` (unscoped, 3.1.4) | Superseded by the `@homebridge-plugins/` one. Installed side by side they both register the same platform. See [Cameras](homebridge-cameras.md) |
| `homebridge-tplink-smarthome` | Unmaintained, no support for the newer Kasa protocol, and its child bridge crashed here |

### Step 5. Resideo (Honeywell Home) thermostat

1. Create a (free) Resideo developer account and an app in it. Note the app's consumer key and consumer secret.
2. In the plugin's settings page, enter the key and secret and start the login flow. The log shows "Start Resideo Login Server".
3. The redirect (callback) address registered in the developer app must match the one the plugin shows. Copy it from the plugin exactly. The plugin's [wiki](https://github.com/homebridge-plugins/homebridge-resideo/wiki) has the installation and configuration pages.
4. Sign in with the Resideo account and allow access. A working link logs "Total Locations Found: 1" and "Total Devices Found at Home: 1" (with your counts).

> **Not verified:** the exact callback address used in this build was not recorded. A reinstall of the plugin (3.2.3) was part of getting the link to work; what else changed is unknown.

**"Unauthorized Request" or 401 in the log is not always a broken link.** The plugin renews its token through the day. If a renewal hits a failed DNS lookup, the plugin stays unauthorised until the next good renewal or restart. Look for `getaddrinfo` errors around the same time first, and fix DNS (next section). In this build the 401s stopped with the DNS errors and the account did **not** need linking again; the plugin recovered by itself at the next restart.

Link again only if 401s continue with no DNS errors near them. The settings page shows "Your Resideo account has been linked" and no link button whenever tokens are present, working or not. Blanking `accessToken` and `refreshToken` (keep the consumer key and secret), saving and reopening the settings should bring the button back.

> **Not verified:** blanking the two tokens to force a new link was suggested, not tried. Homebridge keeps config backups under Settings if it needs undoing.

The settings page may also show "Config validation failed - you can still save your changes", with `credentials` underlined, on a config that loads and works. Which rule it objects to was not found. Closing without saving is fine.

## The DNS block (required on a dual-stack cluster)

[`files/homebridge/values.yaml`](../../files/homebridge/values.yaml) sets:

```yaml
dnsPolicy: None
dnsConfig:
  nameservers:
    - 10.43.0.10
  searches:
    - homebridge.svc.cluster.local
    - svc.cluster.local
    - cluster.local
    - home.example.com
  options:
    - name: ndots
      value: "1"
```

`dnsPolicy: None` tells Kubernetes to ignore its own DNS settings for the pod and use only `dnsConfig`. Do not remove the block.

### What goes wrong without it

With `hostNetwork: true` and the chart's default DNS settings, the pod's `/etc/resolv.conf` looked like this:

```
search homebridge.svc.cluster.local svc.cluster.local cluster.local home.example.com
nameserver 10.43.0.10
nameserver fd00:1234:5678:4300::a
options ndots:5
```

Both name servers are the cluster DNS Service (CoreDNS), once per address family. A host-network pod uses the **node's** routing table. On a cluster with local-only IPv6 the node has routes for the IPv6 pod ranges but none for the IPv6 service range (`fd00:1234:5678:4300::/112` here), and deliberately no IPv6 default route. So the second name server can never be reached, and every time a lookup on the first is slow or lost, the lookup fails.

What it looks like in the Homebridge log, a few times an hour:

```
[Wyze] Error getting devices: Error: getaddrinfo ENOTFOUND api.wyzecam.com
[Wyze] [Plugin] Refresh failed: Error: getaddrinfo EAI_AGAIN api.wyzecam.com
[Resideo] ... failed to pushChanges, Error Message: "getaddrinfo ENOTFOUND api.honeywellhome.com"
[Resideo] ... failed to refreshStatus, Unauthorized Request
[Resideo] ... failed to pushChanges, Error Message: "Request failed with status code 401"
[Resideo] Failed to refresh access token
```

Local devices (Kasa by address) keep working; cloud-driven devices (Wyze, the thermostat) lag or fail.

The fix gives the pod the IPv4 cluster DNS address only. `ndots: 1` instead of the default 5 stops every outside name being tried against the four search domains first.

Ordinary pods (not `hostNetwork`) are not affected. They have their own default route out through the node. Any other host-network app on such a cluster needs the same block. The cluster side (CoreDNS replicas, CoreDNS pods older than a dual-stack conversion having no IPv6 address, and an untested node-route alternative) is in [CoreDNS](../kubernetes/coredns.md).

### Check the DNS block

**Run on: the Homebridge UI terminal** (the pod's own shell; UI menu → Terminal)

```bash
cat /etc/resolv.conf
for i in $(seq 1 20); do getent hosts api.wyzecam.com >/dev/null && echo ok || echo FAIL; done | sort | uniq -c
```

Expected: one `nameserver 10.43.0.10` line, no `fd00:` line, `options ndots:1`, and `20 ok`.

**Run on: server-1**

```bash
sudo kubectl -n homebridge get pod -o jsonpath='{.items[0].spec.dnsPolicy}{"\n"}'
```

Expected: `None`.

### Tracking down a DNS fault inside the pod

Use this when a plugin logs `getaddrinfo ENOTFOUND` or `EAI_AGAIN` while the house and the cluster look healthy. The method works for any pod; Homebridge is the easy one because its UI has a terminal.

**1. Which name servers does the pod use?**

**Run on: the Homebridge UI terminal**

```bash
cat /etc/resolv.conf
```

| You see | Meaning |
| --- | --- |
| Only `nameserver 10.43.0.10`, `options ndots:1` | Correct. Go to 2 |
| `10.43.0.10` **and** `fd00:1234:5678:4300::a`, `ndots:5` | The DNS block is missing. Apply the values file |
| `1.1.1.1` / `9.9.9.9` | The pod is using the node's own DNS, not the cluster's. Look at its `dnsPolicy` |

**2. Test each name server on its own, 20 times.** This is one line; paste it as one line. It needs Node.js, which the Homebridge image has.

**Run on: the Homebridge UI terminal**

```bash
node -e 'const d=require("dns").promises;(async()=>{for(const s of process.argv.slice(1)){const r=new d.Resolver({timeout:2000,tries:1});r.setServers([s]);let ok=0,e={};for(let i=0;i<20;i++){try{await r.resolve4("api.wyzecam.com");ok++}catch(x){e[x.code]=(e[x.code]||0)+1}}console.log(s,"ok:",ok,JSON.stringify(e))}})()' 10.43.0.10 fd00:1234:5678:4300::a 1.1.1.1
```

Healthy answer:

```
10.43.0.10 ok: 20 {}
fd00:1234:5678:4300::a ok: 0 {"ECONNREFUSED":20}
1.1.1.1 ok: 20 {}
```

The middle line failing is **normal from a host-network pod** and stays that way. `ECONNREFUSED` is how Node reports "could not contact the server"; the real reason is "Network is unreachable".

| Result | Meaning | Next |
| --- | --- | --- |
| `10.43.0.10` fails, `1.1.1.1` works | CoreDNS, or the pod network to it | Step 3 |
| Both fail | The node has lost its way out, or the router is intercepting DNS | [DNS design](../network/dns-design.md) |
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
| Fewer replicas than you set, or all on one node | Replica count was reset | `sudo kubectl -n kube-system scale deployment coredns --replicas=3` |
| A pod with one address only; the IPv6 endpoint slice shows `<unset>` | The pod is older than the dual-stack conversion | `sudo kubectl -n kube-system rollout restart deployment coredns` |
| `i/o timeout` or `SERVFAIL` in the log | CoreDNS cannot reach its upstream, which is the node's own DNS | Fix the node's DNS |
| Only "No files matching import glob pattern" warnings | Normal | Nothing |

Details: [CoreDNS](../kubernetes/coredns.md).

**4. Is it the route?**

**Run on: server-1**

```bash
ip -6 route get fd00:1234:5678:4300::a
ip -6 route show default
sudo ip6tables-save | grep -i '4300::a'
ping -6 -c 3 "$(sudo kubectl -n kube-system get pod -l k8s-app=kube-dns -o jsonpath='{.items[0].status.podIPs[1].ip}')"
```

"Network is unreachable", no default route, forwarding rules present, ping answers: that is the normal state of a local-only IPv6 cluster. It proves the IPv6 pod network is fine and only the service address is unreachable from the host.

**5. Did it stop?**

**Run on: the Homebridge UI terminal**

```bash
grep -E 'ENOTFOUND|EAI_AGAIN|401|Unauthorized' /var/lib/homebridge/homebridge.log | tail -5
```

Nothing newer than the redeploy that applied the fix. Before the fix there was an error roughly every half hour, so a few quiet hours is good evidence. Token renewals happen through the day, so one clean day is the real test.

## The startup script

The values file mounts a `startup.sh` that the image runs as root every time the container starts:

```sh
apt-get update && apt-get install -y ffmpeg libpcap-dev || echo "apt-get failed; continuing without updating packages"
```

- It installs `ffmpeg`, which the camera plugin needs, and `libpcap-dev`.
- `|| echo` keeps Homebridge starting when the package servers cannot be reached. The pod then runs with whatever ffmpeg the image has.
- It needs working DNS and slows every start. If the image's own ffmpeg is enough for your cameras, the line can be dropped. **Not verified:** running without it was not tried.
- Do **not** add `npm install` lines for plugins here. A script that reinstalled `homebridge-camera-ffmpeg` on every start is what put a second, outdated camera plugin next to the current one.

> **Pitfall:** every line of the script, comments included, must stay indented under `startup.sh: |` in the values file. A `#` comment at the left margin ends the script early and helm fails with "error converting YAML to JSON: yaml: line N: did not find expected key". Check a file before applying it:

**Run on: server-1**, from the root of this repo

```bash
helm template homebridge k8s-at-home/homebridge -n homebridge -f files/homebridge/values.yaml > /dev/null && echo OK
```

## Check it

| Test | Pass |
| --- | --- |
| `https://hb.home.example.com` | Loads. `http://hb.home.example.com` redirects to it |
| Status page | Every child bridge running |
| UI terminal: `cat /etc/resolv.conf` | One name server, `10.43.0.10`; `options ndots:1`; no `fd00:` line |
| UI terminal: the `grep -E 'ENOTFOUND\|EAI_AGAIN\|401\|Unauthorized'` line above | Nothing newer than the last redeploy |
| Toggle a device in the Home app | Responds within a second or two |
| Each camera in the Home app | Live picture within a few seconds |

From the cluster side:

**Run on: server-1**

```bash
curl -sI -H 'Host: hb.home.example.com' http://192.168.50.12/ | head -3
```

A `301` redirect to `https://` means Traefik has the rule and the middleware.

## Pitfalls

| What happens | Why | Avoid or recover |
| --- | --- | --- |
| The name only answers with `:8581` | The name points at the node (`.5`), not at Traefik, or there is no Ingress | Point `hb.home.example.com` at `192.168.50.12`; apply the values file |
| "Bad Gateway" through Traefik | "Enable HTTPS" is on in the Homebridge UI; Traefik talks plain HTTP to it | Turn it off. Turning it back on later breaks it again |
| `http://` does not redirect | The Middleware is missing in the `homebridge` namespace | `sudo kubectl apply -f files/traefik/middleware-redirect-https.yaml` |
| The UI stopped working through its old address after Traefik got its own MetalLB address | It relied on Traefik answering on every node's address (k3s ServiceLB) | Use Traefik's address. [Load balancers](../kubernetes/load-balancers.md) |
| Pod `Pending` with "node affinity conflict" or a missing volume claim | The `local-path` volume lives on another node | The pod can only run where its volume is. Restore from backup to move it |
| Version changes unexpectedly, or not at all | Tag `latest` with `IfNotPresent`: the version is whatever the node last pulled | Pin a version tag to make restarts predictable. `IfNotPresent` is deliberate: the pod can restart without reaching the registry and without DNS |
| Old image name | `ghcr.io/oznu/homebridge` is the project's former image name | Use `ghcr.io/homebridge/homebridge` |
| A long one-line command pasted into the UI terminal runs as garbage | It was pasted as several lines | Paste it as one line |
| Searching the log for "oom" matches everything | "room" contains "oom" | Use `grep -w` |

### Known leftovers

- `PUID`, `PGID` and `HOMEBRIDGE_CONFIG_UI` environment variables from older setups are not in the values file; the current image ignores them. Harmless if still present.
- The log prints an AWS SDK v2 end-of-support notice at every start. It comes with the Wyze plugin and needs nothing.
- "Homebridge process ended. Code: 143" is a clean stop: a config save, a UI restart or the scheduled restart. A crash would not be 143.
- "Failed login attempt" lines from the UI are worth a look. With this setup the UI is only reachable inside the house (Traefik's LAN address, not a public tunnel).

### Reading a long log

Most of the log is Kasa polling. This hides the routine lines and counts what is left:

**Run on: the Homebridge UI terminal**

```bash
grep -viE 'Getting sys_info|Serializing device|Updated sys_info|getSysInfo HTTP|Skipping poll|Getting light info' /var/lib/homebridge/homebridge.log | sed -E 's/^\[[^]]+\] //' | sort | uniq -c | sort -rn | head -40
```

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Every accessory says "No Response" | Homebridge itself is down | `sudo kubectl -n homebridge get pods -o wide`; is the node up? Open `http://192.168.50.5:8581` |
| `getaddrinfo ENOTFOUND` / `EAI_AGAIN` for cloud APIs, a few times an hour | The host-network pod was given an IPv6 DNS address it cannot route to | The DNS block |
| Resideo "Unauthorized Request", "status code 401", "Failed to refresh access token" | A token renewal hit a failed DNS lookup | Fix DNS first; it recovers at the next restart. Link again only if it continues with no DNS errors |
| Resideo settings: "Config validation failed - you can still save your changes" | Unknown; the config loads and works | Close without saving |
| "Could not (re-)create mDNS advertisement ... Local name collision" | The Avahi advertiser | mDNS advertiser: Ciao |
| Accessories stuck pairing | mDNS advertised on cluster interfaces | Network interfaces: `eth0` only |
| Bad Gateway | Homebridge's own HTTPS is on, or the pod is down | UI setting; pod status |
| `404 page not found` from Traefik | No Ingress for that host name | Apply the values file |
| helm: "did not find expected key" on the values file | An unindented comment inside the startup script | Indent it; test with `helm template` |
| Config "verification warning" after pasting JSON | The pasted JSON was cut off | Paste the whole block |
| Two camera plugins listed | An old startup script reinstalled the unscoped plugin | Uninstall the old one in the UI |
| Kasa devices time out | Network path to the IoT network | [Kasa devices across networks](homebridge-kasa-across-networks.md) |
| UI on `:8581` unreachable from a VPN | Node firewall range | [Node firewall](../kubernetes/node-firewall.md), [Client devices](client-devices.md) |

Pod logs from the cluster side:

**Run on: server-1**

```bash
sudo kubectl -n homebridge logs deploy/homebridge --tail=40
```

## Backup and restore

Homebridge UI → **Settings → Backup → Download Backup Archive**. The archive holds `config.json`, the plugin list and the HomeKit pairing. Until you download it, the only copy is on the node's disk; if that disk dies without the archive, every accessory must be paired again. The archive contains passwords: keep it off the network and out of Git. See [Backups and secrets](../operations/backups-and-secrets.md).

To move Homebridge to another node: uninstall, delete the volume claim, install so the pod lands on the new node, and restore the archive (Step 2).

## Undo

**Run on: server-1**

```bash
helm uninstall homebridge -n homebridge
sudo kubectl delete namespace homebridge
```

Deleting the namespace deletes the volume claim and, with the default `local-path` reclaim policy, the data. Download a backup first. Remove the bridges from the Home app.

## References

- [homebridge/docker-homebridge](https://github.com/homebridge/docker-homebridge): the container image; host network requirement and the `startup.sh` custom startup script.
- [Homebridge wiki: mDNS options](https://github.com/homebridge/homebridge/wiki/mDNS-Options): the Bonjour-HAP, Ciao, Avahi and systemd-resolved advertisers.
- [k8s-at-home/charts](https://github.com/k8s-at-home/charts): the archived chart repository this install uses.
- [Kubernetes: DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/): pod DNS policies, `dnsPolicy: None` and `dnsConfig`.
- [K3s: Volumes and storage](https://docs.k3s.io/add-ons/storage): the local-path provisioner and where its data lives on a node.
- [Traefik: Kubernetes Ingress routing configuration](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/ingress/): the `router.middlewares` annotation used for the redirect.
- [homebridge-plugins/homebridge-resideo](https://github.com/homebridge-plugins/homebridge-resideo): the Resideo plugin; needs a free Resideo developer account.
- [jfarmer08/homebridge-wyze-smart-home](https://github.com/jfarmer08/homebridge-wyze-smart-home): the Wyze plugin and its required API key and key ID fields.
