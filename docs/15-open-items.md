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
| Reserve every Kasa device's address | [01](01-inventory.md). All are "Automatic IP" in the client list. Still open on 6 October; the 1 to 5 October log shows what an address change costs |
| Rotate what was pasted into a chat on 6 October | The whole Homebridge `config.json`. [13](13-backups-and-secrets.md), "Rotate these" |
| Re-read the Homebridge log for DNS errors | The fix went in at 09:13 on 6 October and was clean at the last look. Check again after a day: [08](08-homebridge.md), "Check it" |
| Check CoreDNS is still three replicas after the next k3s upgrade | [04](04-k3s-cluster.md) Step 8. Set by command, not by a file |
| Take the backups | [13](13-backups-and-secrets.md). None of them is known to exist yet |
| Add funkyfresh, k3snode2 and the Mac VM to DNS Director | So their own DNS does not depend on Pi-hole. [02](02-router-xt8.md) |

## Added 7 October

| Item | Detail |
| --- | --- |
| **Script that moves wireless devices between the two XT8 units is not in the repo** | It was written in a session I do not have. It belongs in `network/xt8/xt8-bootstrap.sh`; paste it and it gets added, with a line in [02](02-router-xt8.md) |
| Live `dnsmasq.postconf` is longer than the repo's copy | It had `pc_append "quiet-ra"` at line 25, which the repo's 19-line block never contained. Something else wrote the rest. `cat /jffs/scripts/dnsmasq.postconf` on the router and compare |
| DNS-over-TLS on the router | On 7 October the WAN page listed 1.1.1.1 and 1.0.0.1 (`cloudflare-dns.com`) as DNS-over-TLS servers, and the log shows `stubby` starting. [02](02-router-xt8.md) and `xt8-bootstrap.sh` say plain 9.9.9.9. If DoT is on, `verify` will FAIL "upstream is 9.9.9.9 only". Decide which it is and make the script match |
| Node reboot: prove it survives a boot | After a Wednesday, on the node: `uptime` under a week and `cru l` still lists `WeeklyReboot`. Set by hand on 6 October; `services-start` running by itself at boot has not been seen |
| A7 weekly reboot | The cron line was given on 6 October; not confirmed entered. It belongs in **System → Scheduled Tasks**, not Local Startup. `crontab -l` on the A7, or the reboot check in `a7-backup.sh` |
| A7 `Home-IoT` phone test | SSID confirmed broadcasting on 3 October. A client getting 192.168.101.x through the A7 was not reported |
| `a7-iot-ssid.sh`, `a7-backup.sh`, `xt8-node-setup.sh`, the reboot lines in `a7-ap-setup.sh`, the logrotate lines in `xt8-bootstrap.sh` | New. Syntax-checked; the node and backup scripts were also run against stand-in commands. None has run on the real devices |
| **Take the first A7 backup** | None has ever been taken. `sh network/archer-a7/a7-backup.sh` from the Mac; all six checks should pass, and the reboot check will FAIL until the cron line is in. [13](13-backups-and-secrets.md) |
| XT8 `eth1` renegotiating between 100 and 1000 Mbps | 22 and 23 September, 2 October. Swap the cable unless you were replugging it |
| USB drive read timeouts | `usb 3-1 ... error -110` on 20 September and 4 October. Back the drive up |
| Web logins to the router from 192.168.0.1 | 19 and 25 September, 4 and 5 October. Probably you during the rebuild; confirm |
| Roaming assistant crashes | `roamast` crashed about 5,700 times between 1 October 20:00 and 4 October 23:30, none since. Closed unless it returns |
| Rotated log | `/opt/var/log/messages-202610072036` (26.8 MB) is left on the USB drive. Delete it or let logrotate age it out |

## Not verified

| Item | Detail |
| --- | --- |
| Pi-hole login | Working from the phone and, after the placement and firewall fixes, from the work Mac. Which of those two fixes cured the Mac was not separated |
| `matchLabelKeys` placement fix | In the values file; not yet exercised by an upgrade |
| Axis camera settings | The `libx264` 720p config is in the live file (6 October) and the snapshot errors stopped on 4 October. Picture quality still not reported |
| Resideo after the DNS fix | Recovered by itself at 09:13 on 6 October. Token renewals happen through the day, so one clean day is the real test. [08](08-homebridge.md) Step 6 |
| Resideo "Config validation failed" on the plugin settings page | The config works. Which rule it fails was not found (hover over the underlined `credentials` to read it) |
| Re-linking Resideo by blanking the two tokens | Suggested, not tried. [08](08-homebridge.md) Step 6 |
| IPv6 route to the service range on the nodes | `sudo ip -6 route add fd00:1234:5678:4300::/112 dev cni0` would let host-network pods use the IPv6 cluster DNS address. Not applied, not tested, not needed while Homebridge has its DNS block. [04](04-k3s-cluster.md) Step 8 |
| Other pods older than the dual-stack conversion | Only CoreDNS was checked and restarted. The listing command is in [04](04-k3s-cluster.md) Step 8 |
| CoreDNS replica count across a k3s upgrade | Believed to persist; not yet seen to |
| MB ceiling fan, 192.168.101.201 | Timed out far more than any other Kasa device from 1 to 5 October. Weak Wi-Fi suspected, not confirmed |
| Seven failed Homebridge UI logins, 3 and 4 October | Assumed to be you |
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
| Homebridge live `values.yaml` against this repo's | Seen on 6 October. The `npm install` lines are comments in both. The live file still sets `PUID`, `PGID` and `HOMEBRIDGE_CONFIG_UI` and has fewer comments; otherwise the same, DNS block included. Applying this repo's file has not been done since |
| Traefik pinned to 192.168.50.12 | It got .12 by being second in line. The pinning annotation in [06](06-load-balancers.md) is untested here |
| Token rotation, certificate rotation, `--cluster-reset` | Commands from the k3s documentation, not run here |
| September router recommendations | Roaming assistant -70 dBm, AiProtection off, weekly reboot of the **main** router: unknown whether applied. The log to 7 October still shows the roaming assistant disconnecting weak clients about 250 times in three weeks. The node's weekly reboot is done |
| Leak and isolation tests from a personal device | [12](12-verification.md), tests 2, 3, 5, 7, 8, 10, 12 |

## Things I could not see

| Item | Detail |
| --- | --- |
| Portainer and ArgoCD | The September runbook listed them on 192.168.50.12 and .13. On 4 October the only LoadBalancer Services were Pi-hole and Traefik. I do not know whether they are still installed. The `portainer/` folder and `Ingresses/traefik/argocd.yaml` are unchanged templates |
| Resideo fix | You fixed it yourself; what changed is not recorded. [08](08-homebridge.md) Step 6 |
| ~~The exact Wyze camera stream URL~~ | Seen on 6 October; the example file matches. [08](08-homebridge.md) Step 7 |
| DNS Director's per-device list | Last read 24 September; changed since |
| IPv6 DNS setting on dc01 and ca01 | Never recorded |
| AX21 settings | Not re-checked |
| AiMesh node address | Resolved: 192.168.50.117, confirmed over SSH on 6 October |
| Whether `pretty-pan` (192.168.50.8) still does anything | It left the cluster but is still on the network |
| The `Local-Only-IPv6-Guide.md` the September runbook refers to | Not in this repo and not sent. The runbook listed nine places where it was already wrong; the correct values are all in [02](02-router-xt8.md), [03](03-access-points.md), [04](04-k3s-cluster.md) and [07](07-pihole.md) |

## Older router items, still open

| Item | State |
| --- | --- |
| amtm / Entware downloads hang | Unresolved; Skynet suspected |
| JFFS errors (CRC error, 24 to 27 September) | Stopped; none in the log to 7 October. If they return: back up JFFS, format it at next boot, restore |
| "own address as source" on `eth4`/`eth5`/`eth6` | Low priority. Still 20 to 60 a day on 7 October |
| UPnP notify timeouts to two Windows machines | Cosmetic |
| Sonarr/Radarr could not reach the torrent client on dc01 | Suspects were AiProtection and the torrent VPN's LAN exception. Outcome not recorded |
| Homebridge backup lives only on k3sprimary | Download it. [13](13-backups-and-secrets.md) |

## Optional improvements

- Wildcard certificate for `*.home.example.com` (cert-manager, Cloudflare DNS challenge), to remove the browser warning.
- cloudflared inside the cluster, two replicas.
- Pin the Pi-hole and Homebridge image tags instead of `latest`.
- Drop the `apt-get` line from the Homebridge startup script if the image's own ffmpeg turns out to be enough. It needs working DNS and slows every start.
- Save a copy of the `k8s-at-home/homebridge` chart into this repo; the chart repository is archived.
- A second Pi-hole outside the cluster as the router's DNS Server 2, to cover the whole cluster being down.
