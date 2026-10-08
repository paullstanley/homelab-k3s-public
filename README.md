# Self-hosted homelab guide: home network, k3s and a media server

A set of step-by-step guides for building and looking after a home network with an isolated IoT network, local-only IPv6, and a small highly available k3s (Kubernetes) cluster that runs Pi-hole, Homebridge and Seerr, plus an optional media server (Plex, Sonarr, Radarr and a VPN'd downloader) beside it. Every guide comes from a real build, and records what went wrong as well as what worked.

The guides are **modular**. Each page stands on its own: if you only own one of these devices, or only want Pi-hole on k3s, go straight to that page. Each one lists what it needs first.

**New here?** Read [Overview](docs/start-here/overview.md) for how the pieces fit, then [Conventions](docs/start-here/conventions.md) for the example names and addresses used everywhere. To build everything from scratch, follow [From nothing to a full deployment](docs/start-here/build-from-nothing.md).

**Something is broken?** Go to [Troubleshooting](docs/operations/troubleshooting.md). It is organised by symptom.

## Find your page

### By hardware

| You have | Guide |
| --- | --- |
| ASUS ZenWiFi XT8 (or another ASUS router on Asuswrt-Merlin) | [ASUS ZenWiFi XT8 router](docs/hardware/asus-zenwifi-xt8.md) |
| A second XT8 as an AiMesh node | [AiMesh node](docs/hardware/asus-aimesh-node.md) |
| TP-Link Archer A7 v5 (or another OpenWrt device used as an access point) | [Archer A7 on OpenWrt](docs/hardware/tp-link-archer-a7-openwrt.md) |
| TP-Link Archer AX21 on stock firmware | [Archer AX21 as an access point](docs/hardware/tp-link-archer-ax21.md) |
| Raspberry Pi 4 or 5 | [Preparing a Raspberry Pi for k3s](docs/hardware/raspberry-pi.md) |
| An Apple-silicon Mac you want in the cluster | [Mac as a k3s server in a Lima VM](docs/hardware/mac-lima-vm.md) |

### By what you want to do

| You want | Guide |
| --- | --- |
| Ad-blocking DNS for the whole house that survives a node failing | [Pi-hole on k3s](docs/apps/pihole.md), [DNS design](docs/network/dns-design.md) |
| A k3s cluster with no single point of failure | [HA k3s cluster](docs/kubernetes/k3s-ha-cluster.md), [Load balancers](docs/kubernetes/load-balancers.md), [CoreDNS](docs/kubernetes/coredns.md) |
| A firewall on the nodes that does not break k3s | [Node firewall](docs/kubernetes/node-firewall.md) |
| Order instead of whatever DHCP handed out: address blocks, which devices need reservations, host names, which devices to exempt from roaming | [Address plan](docs/network/address-plan.md) |
| Smart devices kept away from your computers, but still controllable | [Isolated IoT network](docs/network/isolated-iot-network.md) |
| The same IoT network on a second, non-ASUS access point | [Isolated IoT network](docs/network/isolated-iot-network.md) |
| IPv6 on the LAN although your ISP offers none | [Local-only IPv6](docs/network/local-only-ipv6.md) |
| HomeKit for devices that do not support it | [Homebridge on k3s](docs/apps/homebridge.md) |
| Homebridge reaching Kasa devices on the IoT network | [Kasa across networks](docs/apps/homebridge-kasa-across-networks.md) |
| Axis or Wyze cameras in the Home app | [Cameras](docs/apps/homebridge-cameras.md) |
| A request app reachable from outside without opening a port | [Seerr behind a Cloudflare tunnel](docs/apps/seerr-cloudflare-tunnel.md) |
| A media library that fills itself: requests become downloads that land in Plex, named and sorted | [Media stack overview](docs/media/media-stack-overview.md), then [Plex Media Server](docs/media/plex-media-server.md), [Sonarr and Radarr](docs/media/sonarr-and-radarr.md), [Jackett and Prowlarr](docs/media/jackett-and-prowlarr.md) |
| Indexers that fail with "Challenge detected but FlareSolverr is not configured" working again (Cloudflare browser checks only, not captchas) | [FlareSolverr for Jackett and Prowlarr](docs/media/flaresolverr.md) |
| A download client on its own PC, with torrent traffic forced through a VPN | [qBittorrent on Windows behind a VPN](docs/media/qbittorrent-windows-vpn.md) |
| Home names working on a laptop with a corporate VPN | [Client devices](docs/apps/client-devices.md) |
| To understand what your router log is telling you | [Router logging](docs/network/router-logging.md) |
| To build the whole thing from scratch, in order, including flashing the firmware | [From nothing to a full deployment](docs/start-here/build-from-nothing.md) |

### Running it

| Task | Guide |
| --- | --- |
| Prove a build or a change works | [Verification](docs/operations/verification.md) |
| Back everything up, and keep secrets out of Git | [Backups and secrets](docs/operations/backups-and-secrets.md) |
| Reboots, upgrades, periodic checks | [Maintenance](docs/operations/maintenance.md) |
| Where each firmware and software package comes from, and how to update it | [Software and firmware](docs/operations/software-and-firmware.md) |
| Review the router and access point settings, and export them without leaking secrets | [Security review](docs/operations/security-review.md) |
| Fix a problem | [Troubleshooting](docs/operations/troubleshooting.md) |
| Every external document these guides cite | [References](docs/references.md) |

## Build order for the whole thing

The short version is below. The full version, with downloads, flashing, first boot, Helm and a checkpoint per phase, is [From nothing to a full deployment](docs/start-here/build-from-nothing.md). Each step depends on the ones above it. Skip what you do not have.

| # | Step | Guide |
| --- | --- | --- |
| 1 | Router: settings, IoT network, scripts | [XT8 router](docs/hardware/asus-zenwifi-xt8.md), [Isolated IoT network](docs/network/isolated-iot-network.md), [Local-only IPv6](docs/network/local-only-ipv6.md) |
| 2 | Mesh node and extra access points | [AiMesh node](docs/hardware/asus-aimesh-node.md), [Archer A7](docs/hardware/tp-link-archer-a7-openwrt.md), [Archer AX21](docs/hardware/tp-link-archer-ax21.md) |
| 3 | Prepare the cluster machines | [Raspberry Pi](docs/hardware/raspberry-pi.md) |
| 4 | Cluster | [HA k3s cluster](docs/kubernetes/k3s-ha-cluster.md) |
| 5 | Addresses for services | [Load balancers](docs/kubernetes/load-balancers.md), [CoreDNS](docs/kubernetes/coredns.md) |
| 6 | DNS for the house | [Pi-hole](docs/apps/pihole.md), then point the router at it: [DNS design](docs/network/dns-design.md) |
| 7 | Optional fourth server | [Mac in a Lima VM](docs/hardware/mac-lima-vm.md) |
| 8 | Apps | [Homebridge](docs/apps/homebridge.md), [Kasa](docs/apps/homebridge-kasa-across-networks.md), [Cameras](docs/apps/homebridge-cameras.md), [Seerr](docs/apps/seerr-cloudflare-tunnel.md) |
| 9 | Optional media server (a Mac and a Windows PC outside the cluster) | [Media stack overview](docs/media/media-stack-overview.md), [Plex](docs/media/plex-media-server.md), [qBittorrent behind a VPN](docs/media/qbittorrent-windows-vpn.md), [Jackett and Prowlarr](docs/media/jackett-and-prowlarr.md), optionally [FlareSolverr](docs/media/flaresolverr.md), [Sonarr and Radarr](docs/media/sonarr-and-radarr.md) |
| 10 | Optional hardening | [Node firewall](docs/kubernetes/node-firewall.md) |
| 11 | Tidy up addresses and names | [Address plan](docs/network/address-plan.md) |
| 12 | Prove it, back it up | [Verification](docs/operations/verification.md), [Backups and secrets](docs/operations/backups-and-secrets.md) |

Between steps 1 and 6 there is no Pi-hole yet, so nothing on the network should be told to use it. [DNS design](docs/network/dns-design.md) explains how to get through that window.

## How the pages are written

Every guide has the same parts, in the same order:

| Section | What it gives you |
| --- | --- |
| Summary table | The exact hardware and versions it was done on, what it should also work for, and what you need first |
| How it works | A short plain-language model, so the steps and the traps make sense |
| Steps | Numbered. Every command block says which machine to run it on |
| Check it | Commands with the result you should see |
| Pitfalls | Each trap: what happens, why, and how to avoid or recover from it |
| Troubleshooting | Symptom, cause, fix |
| Undo | How to back the change out |
| References | The official documentation behind the page |

Two labels matter:

- **"Applies to"** means the author did it on that exact hardware and version.
- **"Not verified"** means the step, script or claim was not run or confirmed by the author. Treat it as a starting point and test it yourself. Several scripts in `files/` were only syntax-checked or run against stand-in commands; each page says which.

## What is in this repository

| Folder | Contents |
| --- | --- |
| [`docs/`](docs/) | The guides: `start-here`, `hardware`, `network`, `kubernetes`, `apps` (apps on the cluster and client devices), `media` (the optional media server: Plex, Sonarr, Radarr, Jackett or Prowlarr, FlareSolverr, qBittorrent), `operations` |
| [`files/`](files/) | Working configuration files and scripts the guides use: router scripts, access point scripts, k3s configs, Helm values, MetalLB, Traefik, the node firewall, the media stack health checks in [`files/media/`](files/media/), and the FlareSolverr manifest for the cluster in [`files/flaresolverr/`](files/flaresolverr/) |
| [`extras/`](extras/) | Older generic templates (Portainer, Flame, Homarr, code-server, cert-manager issuers, example Ingresses). Not part of the build described here and not maintained |

The same guides are also published on this repository's **Wiki** tab, with a sidebar. The wiki is generated from `docs/` by [`files/scripts/build-wiki.py`](files/scripts/build-wiki.py); edit the files in `docs/`, never the wiki pages.

Run commands that mention a path such as `files/pihole/values.yaml` from the root of a clone of this repository:

```sh
git clone https://github.com/<YOUR_ACCOUNT>/self-hosted-homelab-guide.git
cd self-hosted-homelab-guide
```

## Before you copy anything

- **All names, addresses, MAC addresses, the domain and the IPv6 prefix are examples.** [Conventions](docs/start-here/conventions.md) lists them and how to swap in yours.
- **Passwords and tokens are placeholders** in angle brackets, such as `<K3S_TOKEN>`. Never commit the real ones; [Backups and secrets](docs/operations/backups-and-secrets.md) says where they belong.
- **Read a script before you run it**, especially the ones that change a router. Take the backup the page tells you to take first.
- This is one household's build, shared as-is with no warranty. Firmware and software move on; check the versions in each page's summary table against yours.

## Contributing

Corrections, additions for other hardware, and reports of steps that no longer work are welcome as issues or pull requests. Please keep the page structure above, say exactly what hardware and versions you tested on, and never include real passwords, tokens, public IP addresses or hardware MAC addresses.

## License

[MIT](LICENSE). Use it, change it, share it.
