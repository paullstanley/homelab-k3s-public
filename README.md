# Home network and k3s cluster: rebuild reference

> **Public copy.** The domain, names, MAC addresses, serial numbers, IPv6 ranges and Wi-Fi names in this repository are made-up stand-ins. Passwords and tokens are placeholders. Substitute your own values.

Everything needed to put the house network and the k3s cluster back the way they were on 8 October 2026: guides, Helm values, manifests and scripts. Passwords, tokens and data backups are **not** here; [docs/13](docs/13-backups-and-secrets.md) lists what they are and where they go.

Two rules that hold everywhere in this repo:

- Every command block says which machine to paste it on, and starts at the left margin so it pastes cleanly.
- Config files are complete. Apply the whole file; never merge fragments by hand.

This is the **private** copy. To produce the shareable one with personal details replaced, see "Private and public copies" in [docs/13](docs/13-backups-and-secrets.md).

## The setup in one table

| Address | What |
| --- | --- |
| 192.168.50.1 | ASUS ZenWiFi XT8 router (AiMesh, second unit wired, at .117) |
| 192.168.50.3, .4 | Access points: Archer A7 (OpenWrt), Archer AX21 |
| 192.168.50.5, .6, .7 | Raspberry Pi k3s servers: k3sprimary, funkyfresh, k3snode2 |
| 192.168.50.146 | Fourth k3s server: Lima VM on the M1 MacBook Pro |
| 192.168.50.10 | Kubernetes API (kube-vip) |
| 192.168.50.11 | Pi-hole, three pods, DNS for the house (MetalLB) |
| 192.168.50.12 | Traefik: Pi-hole UI, Homebridge, Seerr (MetalLB) |
| 192.168.101.0/24 | Isolated guest/IoT network: Kasa and Wyze devices. Broadcast by the XT8 and the Archer A7 |

Full list of addresses, names and every device: [docs/01](docs/01-inventory.md).

## Rebuild order

Each step depends on the ones above it. If only one thing broke, go straight to its guide.

| # | What | Guide | Files |
| --- | --- | --- | --- |
| 1 | XT8: GUI settings, guest/IoT network, bootstrap script, device lists | [02](docs/02-router-xt8.md) | `network/xt8/` |
| 2 | Access points, IoT network on the A7, weekly reboots | [03](docs/03-access-points.md), [02](docs/02-router-xt8.md) "The AiMesh node" | `network/archer-a7/`, `network/xt8/node/` |
| 3 | Raspberry Pis: OS, fixed addresses, k3s servers, CoreDNS replicas | [04](docs/04-k3s-cluster.md) | `k3s/config/` |
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
| Homebridge plugins failing DNS lookups (`getaddrinfo ENOTFOUND`): a host-network pod cannot reach the IPv6 cluster DNS address | [08](docs/08-homebridge.md) Step 1, [04](docs/04-k3s-cluster.md) Step 8, [14](docs/14-troubleshooting.md) A10 |
| Router log growing without limit (Scribe's logrotate had no state folder) | [02](docs/02-router-xt8.md), Add-ons |

## What is in each folder

| Folder | Status | Contents |
| --- | --- | --- |
| `docs/` | Current | The guides |
| `network/xt8/` | Current | `xt8-bootstrap.sh` and reference copies of the JFFS scripts it installs |
| `network/xt8/node/` | Current | `xt8-node-setup.sh` (weekly reboot of the AiMesh node, run from the Mac) and a copy of the node's `services-start` |
| `network/archer-a7/` | Current | `a7-ap-setup.sh`, `a7-iot-ssid.sh`, `a7-backup.sh` |
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

## Changes made to this repo on 7 and 8 October 2026

| File | Change |
| --- | --- |
| `network/archer-a7/a7-iot-ssid.sh` | New. Adds the isolated `Home-IoT` SSID (VLAN 501) to the A7 |
| `network/xt8/node/xt8-node-setup.sh` | New. Weekly reboot for the AiMesh node; takes the node's address, SSH user and port |
| `network/xt8/node/services-start` | New. Reference copy of the node's boot script |
| `network/archer-a7/a7-backup.sh` | New. Pulls a checked settings backup off the A7 to the Mac |
| `network/archer-a7/a7-ap-setup.sh` | Schedules the A7's weekly reboot (Wednesday 03:30) |
| `network/xt8/xt8-bootstrap.sh` | Creates Scribe's logrotate state folder and checks it in `verify` |
| [docs/02](docs/02-router-xt8.md) | The AiMesh node, weekly reboot, Scribe log rotation, seeing and logging IPv6, VLAN 501 confirmed |
| [docs/03](docs/03-access-points.md) | IoT network on the A7, weekly reboot, live Wi-Fi and switch settings as read on 3 October |
| [docs/01](docs/01-inventory.md), [13](docs/13-backups-and-secrets.md), [14](docs/14-troubleshooting.md) | Node address, new A7 backup, new troubleshooting rows |
| [docs/15](docs/15-open-items.md) | "Added 7 October": what is still missing from this repo, and findings from the router log review |
| `scripts/make-public.py` | Replaces the node's hostname |

**Not in yet:** the script that moves wireless devices between the XT8 units. See [docs/15](docs/15-open-items.md).

## Changes made to this repo on 6 October 2026

All from one piece of work: Homebridge's Wyze and Resideo plugins were failing DNS lookups a few times an hour. Cause and fix are in [08](docs/08-homebridge.md) Step 1.

| File | Change |
| --- | --- |
| `Homebridge/values.yaml` | **`dnsPolicy: None` and a `dnsConfig` block** (one name server, 10.43.0.10, `ndots: 1`). Image name changed to `ghcr.io/homebridge/homebridge` to match the live file. Warning about comment indentation in the startup script |
| `Homebridge/config-examples/kasa-python.json` | Brought in line with the live config: polling 15, wait 1000, and the other plugin options |
| `Homebridge/config-examples/camera-ffmpeg.json` | Wyze still-image line and stream limits as in the live config |
| [docs/04](docs/04-k3s-cluster.md) | New Step 8: CoreDNS scaled to three; CoreDNS pods older than dual-stack; why host-network pods cannot reach IPv6 service addresses |
| [docs/08](docs/08-homebridge.md) | The DNS block and how to check it; mDNS advertiser Ciao; Resideo 401s; camera and Wyze details confirmed; leftovers |
| [docs/12](docs/12-verification.md) | CoreDNS and Homebridge DNS checks |
| [docs/13](docs/13-backups-and-secrets.md) | What was pasted into a chat on 6 October and must be rotated |
| [docs/14](docs/14-troubleshooting.md) | New A10 (DNS inside a pod, step by step) and new rows in Part B |
| [docs/15](docs/15-open-items.md) | New open and unverified items; two old ones closed |

Changed on the live cluster the same day, by command (nothing in this repo applies them): CoreDNS restarted and scaled to three replicas; `~/helm/homebridge/values.yaml` on k3sprimary given the DNS block and applied with `helm upgrade`.

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
