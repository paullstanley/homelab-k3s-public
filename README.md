# Home network and k3s cluster: rebuild reference

> **Public copy.** The domain, names, MAC addresses, serial numbers, IPv6 ranges and Wi-Fi names in this repository are made-up stand-ins. Passwords and tokens are placeholders. Substitute your own values.

Everything needed to put the house network and the k3s cluster back the way they were on 4 October 2026: guides, Helm values, manifests and scripts. Passwords, tokens and data backups are **not** here; [docs/13](docs/13-backups-and-secrets.md) lists what they are and where they go.

Two rules that hold everywhere in this repo:

- Every command block says which machine to paste it on, and starts at the left margin so it pastes cleanly.
- Config files are complete. Apply the whole file; never merge fragments by hand.

This is the **private** copy. To produce the shareable one with personal details replaced, see "Private and public copies" in [docs/13](docs/13-backups-and-secrets.md).

## The setup in one table

| Address | What |
| --- | --- |
| 192.168.50.1 | ASUS ZenWiFi XT8 router (AiMesh, second unit wired) |
| 192.168.50.3, .4 | Access points: Archer A7 (OpenWrt), Archer AX21 |
| 192.168.50.5, .6, .7 | Raspberry Pi k3s servers: k3sprimary, funkyfresh, k3snode2 |
| 192.168.50.146 | Fourth k3s server: Lima VM on the M1 MacBook Pro |
| 192.168.50.10 | Kubernetes API (kube-vip) |
| 192.168.50.11 | Pi-hole, three pods, DNS for the house (MetalLB) |
| 192.168.50.12 | Traefik: Pi-hole UI, Homebridge, Seerr (MetalLB) |
| 192.168.101.0/24 | Isolated guest/IoT network: Kasa and Wyze devices |

Full list of addresses, names and every device: [docs/01](docs/01-inventory.md).

## Rebuild order

Each step depends on the ones above it. If only one thing broke, go straight to its guide.

| # | What | Guide | Files |
| --- | --- | --- | --- |
| 1 | XT8: GUI settings, guest/IoT network, bootstrap script, device lists | [02](docs/02-router-xt8.md) | `network/xt8/` |
| 2 | Access points | [03](docs/03-access-points.md) | `network/archer-a7/` |
| 3 | Raspberry Pis: OS, fixed addresses, k3s servers | [04](docs/04-k3s-cluster.md) | `k3s/config/` |
| 4 | MetalLB, Traefik address, kube-vip | [06](docs/06-load-balancers.md) | `metallb/`, `traefik/`, `k3s/kube-vip/` |
| 5 | Pi-hole | [07](docs/07-pihole.md) | `pihole/values.yaml` |
| 6 | Mac VM as fourth server | [05](docs/05-mac-node-lima.md) | `k3s/lima/`, `k3s/config/lima-k3s-mac.yaml` |
| 7 | Homebridge, Kasa switches, cameras | [08](docs/08-homebridge.md) | `Homebridge/` |
| 8 | Seerr and the Cloudflare tunnel | [09](docs/09-seerr-and-cloudflare.md) | `Seerr/values.yaml` |
| 9 | Node firewall (optional, currently off) | [10](docs/10-firewall.md) | `firewall/k3s-firewall.sh` |
| 10 | Client devices, work Mac hosts file | [11](docs/11-clients.md) | `clients/` |
| 11 | Verify everything | [12](docs/12-verification.md) | |

Between steps 1 and 5 Pi-hole does not exist, so the house has no DNS. While you work, set your own computer's DNS to 9.9.9.9 by hand and add it to DNS Director on the router as **No Redirection**; undo both afterwards.

When something is wrong: [docs/14](docs/14-troubleshooting.md). What is unfinished or unverified: [docs/15](docs/15-open-items.md).

## The parts that caused the most trouble

| Problem | Where it is written up |
| --- | --- |
| Homebridge could not reach Kasa switches on the isolated network (ASUS guest isolation lives in `ebtables`) | [08](docs/08-homebridge.md) Step 5, [02](docs/02-router-xt8.md) |
| The k3s built-in load balancer taking addresses from MetalLB | [06](docs/06-load-balancers.md) |
| Nodes depending on Pi-hole for their own DNS | [04](docs/04-k3s-cluster.md) Step 2 |
| Mac VM joining on the wrong interface and under the wrong name | [05](docs/05-mac-node-lima.md) |
| Leftover `server` folders stopping the etcd conversion | [04](docs/04-k3s-cluster.md), last section |
| Pi-hole login loop with three pods | [07](docs/07-pihole.md) |
| Cloudflare 502 after Traefik moved | [09](docs/09-seerr-and-cloudflare.md) |
| Home names not resolving on the work Mac | [11](docs/11-clients.md) |
| Routers not sending IPv6 advertisements | [02](docs/02-router-xt8.md) |

## What is in each folder

| Folder | Status | Contents |
| --- | --- | --- |
| `docs/` | Current | The guides |
| `network/xt8/` | Current | `xt8-bootstrap.sh` and reference copies of the JFFS scripts it installs |
| `network/archer-a7/` | Current | `a7-ap-setup.sh` |
| `k3s/config/` | Current | `/etc/rancher/k3s/config.yaml` for each of the four servers |
| `k3s/kube-vip/` | Current | The kube-vip HelmChart |
| `k3s/lima/` | Reconstructed | Lima VM definition; replace with the real one |
| `metallb/` | Current | Address pools |
| `traefik/` | Current | HTTPS redirect rules |
| `pihole/` | Current | Complete values file, all device names |
| `Homebridge/` | Current | Values file and plugin config examples |
| `Seerr/` | Current | Values file |
| `firewall/` | Current, switched off | `k3s-firewall.sh` |
| `cloudflare/` | Current | Tunnel settings |
| `clients/` | Current | Work Mac hosts lines |
| `scripts/` | Current | `export-live-config.sh`, `make-public.py` |
| `Overseer/` | Retired | Replaced by Seerr. Kept for reference |
| `portainer/`, `flame/`, `homarr/`, `code-server/`, `letsencrypt/`, `Ingresses/` | Templates | Generic examples with placeholder hosts, not part of the running setup. Untouched |

## Changes made to this repo on 4 October 2026

| File | Change |
| --- | --- |
| `README.md` | Replaced. The old one described a generic two-Pi install on 192.168.0.x with agents; the Pi preparation steps that still apply moved to [docs/04](docs/04-k3s-cluster.md) |
| `pihole/values.yaml` | Three replicas, Traefik ingress with sticky cookie, every device name, pull policy, placement fix for upgrades, encryption sidecar pinned to 2025.9.1. **Admin password removed** and moved to a Secret |
| `firewall/k3s-firewall.sh` | Allowed range widened to 192.168.0.0/16 for VPN access |
| `Seerr/values.yaml` | Service on port 80, time zone fixed, unused blocks removed |
| `Homebridge/values.yaml` | Real host name, HTTPS redirect, pull policy, plugin installs removed from the startup script |
| `metallb/config.yaml` | Real pools: 192.168.50.11 to .15 and the Pi-hole IPv6 address |
| `metallb/values.yaml` | **Deleted.** It was a copy of the MetalLB config under a misleading name, with the old .10 to .15 pool |
| `Ingresses/ traefik/argocd` | Renamed to `Ingresses/traefik/argocd.yaml` (the folder name started with a space). Contents unchanged; note its `traefik.containo.us` API version is the old one |
| `Ingresses/nginx/example-web app.yaml` | Renamed to `example-web-app.yaml` |
| `.DS_Store` files | Removed; `.gitignore` added |
| Everything else listed as Current above | New |
