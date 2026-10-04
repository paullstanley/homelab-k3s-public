# 09. Seerr and the Cloudflare tunnel

Seerr is the only app reachable from the internet. No port is forwarded for it: a Cloudflare tunnel carries the traffic.

```
browser → https://request.example.com → Cloudflare → tunnel → cloudflared on k3sprimary
        → http://192.168.50.12 (Traefik) → Seerr pod (port 5055)
```

## Step 1. Install Seerr

**Paste on: k3sprimary**, in the root of this repo.

```bash
helm upgrade --install seerr harish2k01/seerr -n seerr --create-namespace -f Seerr/values.yaml
sudo kubectl -n seerr get pods,svc,ingress
```

If helm says the `harish2k01` repo is not found, list what the live cluster used and add that repo first:

```bash
helm repo list
helm list -n seerr
```

The repo address is not recorded in this repo. Run those two lines **now**, while the cluster is healthy, and write the address here: `helm repo add harish2k01 <FILL IN>`.

You should see the pod `Running`, a Service of type `ClusterIP` on port 80, and an Ingress for `request.example.com`.

Test from k3sprimary without Cloudflare:

```bash
curl -sI -H 'Host: request.example.com' http://192.168.50.12/ | head -3
```

A `307` (redirect to the login or setup page) or `200` means Traefik reaches Seerr.

Seerr's own data (users, requests, the Plex/Sonarr/Radarr connections) is on a `local-path` volume on k3sprimary. After a rebuild with no copy of that volume, Seerr starts at its setup wizard: sign in with Plex, then re-enter Sonarr (`192.168.50.2`) and Radarr (`192.168.50.2`) with their API keys.

## Step 2. cloudflared on k3sprimary

cloudflared runs **on the k3sprimary host as a system service**, not in the cluster. The tunnel is managed from the Cloudflare dashboard.

After a rebuild of k3sprimary:

1. Cloudflare dashboard → **Zero Trust** → **Networks** → **Tunnels** → your tunnel → **Configure**.
2. Choose the Debian / arm64 connector instructions. It shows an install command and a `cloudflared service install <TOKEN>` line.
3. Paste both on k3sprimary. The token is a secret; it goes in the password manager, not here.

Check on k3sprimary:

```bash
systemctl status cloudflared --no-pager | head -5
```

The tunnel should show **Healthy** in the dashboard.

## Step 3. The published route

In the tunnel's **Published application routes** (formerly "Public Hostnames"):

| Field | Value |
| --- | --- |
| Subdomain | `request` |
| Domain | `example.com` |
| Service type | `HTTP` |
| URL | `192.168.50.12` |

Cloudflare creates the `request` DNS record for you when the route is saved.

> **Trouble we hit: 502 Bad Gateway after the HA work.** The route's URL was `localhost:80`. That worked while the k3s built-in load balancer published Traefik on every node's own address. Once that was disabled, Traefik lived only on 192.168.50.12 and nothing listened on k3sprimary's port 80. Changing the URL to `192.168.50.12` fixed it. An existing route **can** be edited: open the tunnel, the routes tab, the three-dot menu on the route, Edit.

> **Trouble we hit: Seerr chart schema error.** A half-edited `httpRoute:` block in the values file made helm fail with "values don't meet the specifications of the schema". The block is removed from `Seerr/values.yaml`.

> **Also fixed:** `TZ: America/New York` (with a space) is not a valid time zone. It is `America/New_York`.

Seerr has no redirect middleware on purpose. Cloudflare talks plain HTTP to Traefik; a redirect to https there would loop.

## Should Seerr be highly available?

No. It keeps its database in one file on one volume and is not built to run as several copies. If k3sprimary is down, requests wait until it is back. The same goes for Homebridge.

## Optional later

- Run cloudflared inside the cluster as two replicas, so the tunnel survives k3sprimary going down. Seerr itself would still be on k3sprimary.
- cert-manager with a Let's Encrypt wildcard certificate for `*.home.example.com` through Cloudflare DNS, to get rid of the browser warning on the home names. The `letsencrypt/` folder holds older issuer templates that use the HTTP challenge, which cannot work for names that only exist inside the house; a DNS challenge is needed.
