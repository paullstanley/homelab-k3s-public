# 15. Open items

Things that are not finished, not verified, or that I could not confirm from what you sent. Ordered by how much they matter.

## Do soon

| Item | Detail |
| --- | --- |
| k3sprimary's own DNS still includes Pi-hole | `resolv.conf` shows `1.1.1.1` and `fd00:1234:5678:50::11`. Fix in [04](04-k3s-cluster.md) Step 2 |
| k3sprimary runs etcd on a spinning hard drive | WD `WD20JDRW` 2 TB over USB. The other two Pis have NVMe SSDs. Move k3sprimary to an SSD when you can. [04](04-k3s-cluster.md) |
| funkyfresh and k3snode2 have 2 GB of RAM | Minimum for a k3s server. Watch `sudo kubectl top nodes` |
| Bootloader updates waiting on k3sprimary and funkyfresh | `sudo rpi-eeprom-update -a`, one Pi at a time. [04](04-k3s-cluster.md) |
| Apply the new `pihole/values.yaml` | Brings the placement fix and the pinned sidecar. Do [07](07-pihole.md) Step 2 (the Secret) first |
| Rotate the exposed passwords and tokens | [13](13-backups-and-secrets.md), "Rotate these". The Pi-hole password was in the repository while it was public |
| Move the live Pi-hole password into the Secret | The live `~/helm/pihole/values.yaml` still has `adminPassword:` inline. Do [07](07-pihole.md) Step 2 before applying this repo's file |
| DNS Director "User Defined 3" still points at 192.168.50.5 | That address no longer answers DNS. Any device on that rule has no DNS. [02](02-router-xt8.md) |
| Router DHCP DNS Server 1 | It was changed during troubleshooting. Set it back to 192.168.50.11 |
| Reserve 192.168.50.146 for the Mac VM | MAC `52:55:55:15:F1:69`. It is an etcd member on a DHCP address |
| Reserve every Kasa device's address | [01](01-inventory.md). All are "Automatic IP" in the client list |
| Take the backups | [13](13-backups-and-secrets.md). None of them is known to exist yet |
| Add funkyfresh, k3snode2 and the Mac VM to DNS Director | So their own DNS does not depend on Pi-hole. [02](02-router-xt8.md) |

## Not verified

| Item | Detail |
| --- | --- |
| Pi-hole login | Working from the phone and, after the placement and firewall fixes, from the work Mac. Which of those two fixes cured the Mac was not separated |
| `matchLabelKeys` placement fix | In the values file; not yet exercised by an upgrade |
| Axis camera settings | The last `libx264` config was given; result not reported |
| Failover | No node has been rebooted to test it. [12](12-verification.md) |
| Host firewall | Active on the three Pis, patched by hand to allow 192.168.0.0/16. Mac VM not checked. The IPv6 gap in [10](10-firewall.md) is still open |
| A second IPv6 range on the LAN | `fd00:aaaa:bbbb:cccc::/64` on every Pi, not from the XT8. Probably a Thread border router. Source not confirmed |
| Swap on funkyfresh | `zram0` is active. k3s tolerates it; noted because the other Pis have none |
| Mac VM details | The readings and the real `lima.yaml` were not sent |
| MetalLB "Suspect k3snode2 has failed", IPv6 address moving 34 times | Cause unknown |
| `xt8-bootstrap.sh` | Never run on the real router. Tested against stand-in commands only |
| Lima VM creation steps and `k3s/lima/k3s-mac.yaml` | Reconstructed, not copied from the Mac. Replace the file with `~/.lima/k3s-mac/lima.yaml` |
| Mac VM autostart | `limactl autostart enable --condition=boot k3s-mac` not run yet |
| Seerr helm repo address | Not recorded. [09](09-seerr-and-cloudflare.md) Step 1 |
| Homebridge `values.yaml` without the `npm install` lines | I recommended removing them; I do not know whether the live file has them. Plugins already installed are unaffected either way |
| Traefik pinned to 192.168.50.12 | It got .12 by being second in line. The pinning annotation in [06](06-load-balancers.md) is untested here |
| Token rotation, certificate rotation, `--cluster-reset` | Commands from the k3s documentation, not run here |
| September router recommendations | Roaming assistant -70 dBm, AiProtection off, weekly reboot: unknown whether applied |
| Leak and isolation tests from a personal device | [12](12-verification.md), tests 2, 3, 5, 7, 8, 10, 12 |

## Things I could not see

| Item | Detail |
| --- | --- |
| Portainer and ArgoCD | The September runbook listed them on 192.168.50.12 and .13. On 4 October the only LoadBalancer Services were Pi-hole and Traefik. I do not know whether they are still installed. The `portainer/` folder and `Ingresses/traefik/argocd.yaml` are unchanged templates |
| Resideo fix | You fixed it yourself; what changed is not recorded. [08](08-homebridge.md) Step 6 |
| The exact Wyze camera stream URL | [08](08-homebridge.md) Step 7 |
| DNS Director's per-device list | Last read 24 September; changed since |
| IPv6 DNS setting on dc01 and ca01 | Never recorded |
| AX21 settings | Not re-checked |
| AiMesh node address | 192.168.50.117 in September; not in the 4 October client list |
| Whether `pretty-pan` (192.168.50.8) still does anything | It left the cluster but is still on the network |
| The `Local-Only-IPv6-Guide.md` the September runbook refers to | Not in this repo and not sent. The runbook listed nine places where it was already wrong; the correct values are all in [02](02-router-xt8.md), [03](03-access-points.md), [04](04-k3s-cluster.md) and [07](07-pihole.md) |

## Older router items, still open

| Item | State |
| --- | --- |
| amtm / Entware downloads hang | Unresolved; Skynet suspected |
| JFFS errors (CRC error, 24 to 27 September) | Stopped. If they return: back up JFFS, format it at next boot, restore |
| "own address as source" on `eth4`/`eth5` | Low priority |
| UPnP notify timeouts to two Windows machines | Cosmetic |
| Sonarr/Radarr could not reach the torrent client on dc01 | Suspects were AiProtection and the torrent VPN's LAN exception. Outcome not recorded |
| Homebridge backup lives only on k3sprimary | Download it. [13](13-backups-and-secrets.md) |

## Optional improvements

- Wildcard certificate for `*.home.example.com` (cert-manager, Cloudflare DNS challenge), to remove the browser warning.
- cloudflared inside the cluster, two replicas.
- Pin the Pi-hole and Homebridge image tags instead of `latest`.
- A second Pi-hole outside the cluster as the router's DNS Server 2, to cover the whole cluster being down.
