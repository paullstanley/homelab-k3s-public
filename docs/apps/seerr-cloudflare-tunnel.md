# Seerr behind a Cloudflare tunnel through Traefik

You end up with Seerr (a web app where people request films and series for a media server) running on k3s and reachable from the internet at `https://request.example.com`, without forwarding any port on your router. A Cloudflare tunnel carries the traffic into the house and hands it to Traefik.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | Seerr (image `ghcr.io/seerr-team/seerr`), a community Helm chart referred to as `harish2k01/seerr`, k3s v1.34 with bundled Traefik on a MetalLB address, `cloudflared` installed as a systemd service on a Raspberry Pi node (Debian, arm64), tunnel managed from the Cloudflare dashboard |
| **Also works for** | Any web app behind Traefik; any Linux host for `cloudflared`. Running `cloudflared` inside the cluster is described but **not tested by the author** |
| **Time** | 30 to 45 minutes |
| **You need first** | [HA k3s cluster](../kubernetes/k3s-ha-cluster.md), [Load balancers](../kubernetes/load-balancers.md) (Traefik on `192.168.50.12`), a domain whose DNS is on Cloudflare, a Cloudflare account with Zero Trust enabled (the free plan is enough) |

## How it works

```
browser → https://request.example.com → Cloudflare → tunnel → cloudflared on server-1
        → http://192.168.50.12 (Traefik) → Seerr Service (port 80) → Seerr pod (port 5055)
```

- `cloudflared` is a small program that makes an **outbound** connection from your network to Cloudflare and keeps it open. Cloudflare sends visitors' requests back down that connection. Nothing listens on your public address.
- Cloudflare terminates HTTPS for visitors. `cloudflared` then speaks plain HTTP to Traefik, keeping the original host name, and Traefik routes by host name to the Seerr Service.
- Seerr's Service is a `ClusterIP` (cluster-internal). It does not get its own load-balancer address; Traefik fronts it.
- Seerr keeps its database in one file on one `local-path` volume, a folder on one node's disk. It runs as one replica, pinned to that node.

## Before you start

| Decide or gather | Notes |
| --- | --- |
| Public host name | `request.example.com` |
| Which node runs Seerr | Wherever the pod first lands is where its volume is created and where it stays. Here `server-1` |
| Where `cloudflared` runs | On a node as a system service (tested), or in the cluster (not tested). See [cloudflared on a node or in the cluster](#cloudflared-on-a-node-or-in-the-cluster) |
| The chart repository address | See Step 1 |
| For Seerr's setup wizard | Media server login (Plex here), Sonarr and Radarr addresses and API keys |

Should Seerr be highly available? No. It keeps its database in one file on one volume and is not built to run as several copies. If its node is down, requests wait until it is back.

## Steps

### Step 1. Install Seerr

Review [`files/seerr/values.yaml`](../../files/seerr/values.yaml) and set your host name and time zone.

**Run on: server-1**, from the root of this repo

```bash
helm upgrade --install seerr harish2k01/seerr -n seerr --create-namespace -f files/seerr/values.yaml
sudo kubectl -n seerr get pods,svc,ingress
```

You should see the pod `Running`, a Service of type `ClusterIP` on port 80, and an Ingress for `request.example.com`.

> **Not verified:** the address of the `harish2k01` Helm repository was not recorded in this build, so no `helm repo add` line is given. If helm says the repo is not found, find the chart's repository address (for example on Artifact Hub) and run `helm repo add harish2k01 <REPO_URL>` first. On a cluster that already has Seerr installed, `helm repo list` and `helm list -n seerr` show what was used; record the address while the cluster is healthy. The Seerr project also keeps a chart in its own repository (`charts/seerr-chart`); its value names may differ from this file, and it is not tested by the author.

What the values file sets:

| Setting | Value | Why |
| --- | --- | --- |
| `replicaCount` | `1` | One database file; not built for several copies |
| `image` | `ghcr.io/seerr-team/seerr`, tag `latest`, `pullPolicy: IfNotPresent` | The pod can restart without reaching the registry. Pin a tag for predictable versions |
| `env.TZ` | `America/New_York` | Underscore, not a space. `America/New York` is not a valid time zone |
| `env.PORT` | `"5055"` | The port Seerr listens on in the pod |
| `service` | `type: ClusterIP`, `port: 80`, `targetPort: 5055`, `portName: http` | No load-balancer address of its own. Traefik reaches it on port 80 |
| `persistence.config` | `/app/config`, `ReadWriteOnce`, `1Gi`, `storageClassName: "local-path"` | Users, requests and connections to the media stack |
| `ingress` | `className: "traefik"`, host `request.example.com`, path `/` `Prefix`, `tls: []` | Traefik routes by host name. No TLS here: Cloudflare does HTTPS |
| no redirect middleware | on purpose | Cloudflare talks plain HTTP to Traefik; a redirect to https there would loop |
| no `httpRoute` block | on purpose | A half-filled one fails the chart's schema check |
| `livenessProbe`, `readinessProbe` | HTTP `GET /api/v1/settings/public` on port `http` | Health checks |

Test from the cluster side, without Cloudflare:

**Run on: server-1**

```bash
curl -sI -H 'Host: request.example.com' http://192.168.50.12/ | head -3
```

A `307` (redirect to the login or setup page) or `200` means Traefik reaches Seerr.

Then open Seerr and run its setup wizard: sign in with the media server account, then add Sonarr and Radarr with their addresses and API keys. After a rebuild with no copy of the volume, Seerr starts at this wizard again.

### Step 2. Install cloudflared on the node

The tunnel is created and managed in the Cloudflare dashboard; the node only runs the connector.

1. Cloudflare dashboard → **Zero Trust** → **Networks** → **Tunnels**. Create a tunnel (type Cloudflared), or open your existing tunnel → **Configure**.
2. Choose the connector instructions for your node's system: Debian, arm64 for a Raspberry Pi. The page shows an install command and a `cloudflared service install <TUNNEL_TOKEN>` line.
3. Paste both on the node.

**Run on: server-1**

```bash
sudo cloudflared service install <TUNNEL_TOKEN>
systemctl status cloudflared --no-pager | head -5
```

The service is `active (running)`, and the tunnel shows **Healthy** in the dashboard. Menu names in the dashboard change over time; follow the current [Cloudflare Tunnel documentation](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/) if they differ.

> **Pitfall:** the tunnel token is a secret. Anyone holding it can run a connector for your tunnel. Keep it in a password manager, never in the repo.

### Step 3. Publish the host name

In the tunnel's **Published application routes** (formerly "Public Hostnames"), add:

| Field | Value |
| --- | --- |
| Subdomain | `request` |
| Domain | `example.com` |
| Service type | `HTTP` |
| URL | `192.168.50.12` |

Cloudflare creates the `request` DNS record (a proxied CNAME to the tunnel) when the route is saved.

The URL must be **Traefik's address**, not `localhost`. See the 502 pitfall below.

## Check it

| Test | Where | Pass |
| --- | --- | --- |
| `curl -sI -H 'Host: request.example.com' http://192.168.50.12/ \| head -3` | server-1 | `307` or `200` |
| `systemctl status cloudflared --no-pager \| head -5` | server-1 | `active (running)` |
| Tunnel status | Cloudflare dashboard | Healthy |
| `https://request.example.com` | A phone on mobile data (not home Wi-Fi) | Seerr loads |

## cloudflared on a node or in the cluster

| | On a node as a systemd service (used here) | In the cluster |
| --- | --- | --- |
| Setup | One install command and a token | A Deployment with the token in a Secret |
| Survives that node going down | No. The tunnel is down until the node is back | Yes, with two replicas on different nodes |
| Depends on the cluster being healthy | No | Yes |
| Target URL | Traefik's address, `192.168.50.12` | Traefik's address, or its cluster Service name |
| Status | Tested | **Not verified by the author.** Cloudflare publishes a [Kubernetes deployment guide](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/deployment-guides/kubernetes/) |

Moving the tunnel into the cluster only helps the tunnel. Seerr itself still lives on one node, so the public site is still down when that node is down.

## Security notes

- Seerr is the only app published this way in this build. Everything else (Pi-hole UI, Homebridge UI, Traefik dashboard) is reachable only inside the house, because those names exist only in local DNS and point at a private address. Keep `home.example.com` names out of Cloudflare.
- Anything you add as a published route is on the public internet. Seerr has its own login; use strong accounts. Cloudflare Access (in the same Zero Trust dashboard) can put an extra login in front of a route; it was not used here.
- The tunnel reaches Traefik, and Traefik routes by host name. Only host names that are published as tunnel routes arrive from outside, but treat the tunnel route list as the list of what is exposed and review it.
- Secrets involved: the tunnel token, the Cloudflare account login, and the Plex/Sonarr/Radarr API keys stored in Seerr's volume. None belongs in Git. See [Backups and secrets](../operations/backups-and-secrets.md).
- Record the dashboard-only settings somewhere (tunnel name, routes, DNS records), because no file holds them. Export the zone's DNS records once for the record: dashboard → DNS → Records → Import and Export → Export. The export contains no secrets, but lists everything you publish.

## Pitfalls

### 502 Bad Gateway after Traefik's address changed

**What happens.** The public site shows a Cloudflare 502 page, though Seerr is running.

**Why.** The route's URL was `localhost:80`. That works while k3s's built-in load balancer (ServiceLB) publishes Traefik on every node's own address. Once ServiceLB is disabled in favour of MetalLB, Traefik lives only on its MetalLB address and nothing listens on the node's port 80.

**Fix.** Change the route's URL to `192.168.50.12`. An existing route can be edited: open the tunnel, the routes tab, the three-dot menu on the route, **Edit**.

The same applies if Traefik's address ever changes again (for example after a k3s upgrade resets its Service). Pinning Traefik's address is covered in [Load balancers](../kubernetes/load-balancers.md).

### Other traps

| What happens | Why | Avoid or recover |
| --- | --- | --- |
| helm: "values don't meet the specifications of the schema" | A half-edited `httpRoute:` block in the values file | Leave the block out; use the file as supplied |
| Wrong times, or the pod complains about the time zone | `TZ: America/New York` with a space | `America/New_York` |
| Redirect loop on the public name | An https-redirect middleware on the Seerr Ingress; Cloudflare already talks plain HTTP to Traefik | No redirect middleware on this Ingress |
| Pod `Pending` with "node affinity conflict" | The `local-path` volume lives on another node | Seerr can only run where its volume is |
| Setup wizard appears after a rebuild | The volume was not restored | Restore the backup below, or run the wizard again |

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Cloudflare 502 Bad Gateway | Route URL points at `localhost:80` or an old address | Route URL `192.168.50.12` |
| Cloudflare error page saying the tunnel is down (for example error 1033) | `cloudflared` is not running or cannot reach Cloudflare | `systemctl status cloudflared` on the node; is the node up? |
| `curl` test to `.12` cannot connect | Traefik is not on `192.168.50.12` | `sudo kubectl get svc -A \| grep traefik`; [Load balancers](../kubernetes/load-balancers.md) |
| `curl` test returns `404 page not found` | Traefik has no rule for that host | The Ingress is missing or has another host name. Apply the values file |
| `curl` test returns `502` | Traefik has the rule but Seerr does not answer | `sudo kubectl -n seerr get pods`; `sudo kubectl -n seerr logs deploy/seerr --tail=40` |
| Works from outside, not from inside the house | Local DNS overrides or blocks the name | `nslookup request.example.com` on a LAN device |
| helm: repo `harish2k01` not found | The repo was never added on this machine | Step 1 |

## Backup

Seerr's data is one folder on the node.

**Run on: server-1**

```bash
sudo kubectl -n seerr get pvc
sudo ls /var/lib/rancher/k3s/storage/ | grep seerr
sudo tar -czf /tmp/seerr-config.tar.gz -C /var/lib/rancher/k3s/storage "$(sudo ls /var/lib/rancher/k3s/storage/ | grep seerr | head -1)"
```

Copy `/tmp/seerr-config.tar.gz` off the node. It contains API keys; keep it off the network and out of Git. See [Backups and secrets](../operations/backups-and-secrets.md).

## Undo

1. Delete the published route in the tunnel (this removes public access at once), and delete the tunnel if nothing else uses it.
2. Remove the connector and the app.

**Run on: server-1**

```bash
sudo cloudflared service uninstall
helm uninstall seerr -n seerr
sudo kubectl delete namespace seerr
```

Deleting the namespace deletes Seerr's data. Back it up first.

## References

- [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/): overview of tunnels and the `cloudflared` connector.
- [Cloudflare Tunnel: routing to a tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/routing-to-tunnel/): publishing an application under a public host name and the DNS record behind it.
- [Cloudflare: run cloudflared as a service on Linux](https://developers.cloudflare.com/tunnel/advanced/local-management/as-a-service/linux/): `cloudflared service install` and managing the systemd service.
- [Cloudflare Tunnel: Kubernetes deployment guide](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/deployment-guides/kubernetes/): running the connector inside a cluster.
- [Seerr documentation](https://docs.seerr.dev/): installation, setup wizard and settings.
- [seerr-team/seerr](https://github.com/seerr-team/seerr): source, container image and the project's own chart directory.
- [Traefik: Kubernetes Ingress routing configuration](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/ingress/): how Traefik turns an Ingress into a route.
- [K3s: Volumes and storage](https://docs.k3s.io/add-ons/storage): the local-path provisioner and the folder backed up above.
