# Maintenance

The routine care that keeps the build healthy: weekly reboots of the network gear, firmware and software upgrades, what to check again after each upgrade, log housekeeping, and a monthly and quarterly checklist.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | ASUS ZenWiFi XT8 main unit and AiMesh node on Asuswrt-Merlin (GNUton build 3004.388.10_2), TP-Link Archer A7 on OpenWrt, Archer AX21 stock firmware, Raspberry Pi OS on Pi 4-class boards, k3s v1.34.3+k3s1, Lima on macOS |
| **Also works for** | Other Asuswrt-Merlin routers and OpenWrt devices; other k3s versions. Not tested by the author |
| **Time** | 10 minutes to set up the reboots; 15 minutes a month after that |
| **You need first** | The devices themselves. Take backups first: [Backups and secrets](backups-and-secrets.md) |

## How it works

Three ideas run through this page.

- **Consumer network gear benefits from a scheduled restart.** Each of the three device types schedules it differently: the main router through its GUI, the AiMesh node through a cron job that has to be re-added at every boot, and OpenWrt through an ordinary crontab line that needs a guard against a reboot loop.
- **Some cluster settings are made by command, not by a file.** An upgrade can quietly put them back to the default. So every upgrade ends with the same short re-check.
- **A backup describes one moment.** After any change, the old backup restores the old state. Retake it.

## Before you start

- Pick a reboot time when nobody is using the network. The examples use Wednesday 03:30 for the access points and about 04:00 for the main router. Stagger them so the devices do not restart together.
- Check each device's time zone. The schedules run in local time.
- Take the backups in [Backups and secrets](backups-and-secrets.md) before any firmware upgrade.

## Steps

### Step 1. Weekly reboot: main router

In the router GUI: **Administration → System → Enable Reboot Scheduler**: yes, one day a week, about 04:00. Apply.

> **Why:** this was a recommendation after a period of instability on the test router. Whether it cured anything was not established; it is cheap and harmless.

> **Pitfall:** the GUI scheduler never appears in `cru l` (the router's cron list). It is stored in nvram (`reboot_schedule_enable=1` and `reboot_schedule=<seven day flags Sunday to Saturday><HHMM>`, for example `00010000330` for Wednesday 03:30) and is run by the firmware's watchdog, not by cron. An empty `cru l` says nothing about it.

Check it:

**Run on: the router**

```sh
nvram get reboot_schedule_enable
nvram get reboot_schedule
```

Pass: `1`, and an 11-digit value matching your day and time.

### Step 2. Weekly reboot: AiMesh node

The node has no web UI of its own, so the schedule is set over SSH by [xt8-node-setup.sh](../../files/xt8/node/xt8-node-setup.sh). Full explanation: [ASUS AiMesh node](../hardware/asus-aimesh-node.md).

**Run on: your computer**, from the root of this repo

```sh
sh files/xt8/node/xt8-node-setup.sh 192.168.50.117 admin <SSH_PORT>
```

The arguments are the node's address, the SSH user and the SSH port. The node accepts the main router's login. `ssh` asks for the password once. To change the schedule, set `REBOOT_AT` (cron fields: minute hour day month weekday), for example `REBOOT_AT="0 4 * * 0"` before the command.

| What the script does | Why |
| --- | --- |
| `nvram set jffs2_scripts=1` | Without it the firmware ignores `/jffs/scripts` at boot |
| `nvram set reboot_schedule_enable=0` | Turns the firmware's own scheduler off so the node is not rebooted twice |
| Adds `cru a WeeklyReboot "30 3 * * 3 /sbin/reboot"` to `/jffs/scripts/services-start` | Jobs added with `cru` are lost at reboot. `services-start` runs at every boot and adds the job back. Lines already in the file are kept |
| Runs the same `cru a` once | So the job exists now, without a reboot |

Check it:

**Run on: the AiMesh node**

```sh
cru l
```

Pass: one line ending `#WeeklyReboot#`.

> **Not verified:** the script was syntax-checked and run against stand-in commands; the job was set by hand on the test node. `services-start` re-adding the job by itself after a boot had not been observed. After the first scheduled day, confirm on the node that `uptime` shows under a week **and** `cru l` still lists `WeeklyReboot`.

### Step 3. Weekly reboot: OpenWrt access point

[a7-ap-setup.sh](../../files/archer-a7/a7-ap-setup.sh) sets this during setup. To add it to a running AP, use LuCI: **System → Scheduled Tasks**, one line:

```sh
30 3 * * 3 sleep 70 && touch /etc/banner && reboot
```

Or over SSH:

**Run on: ap-openwrt**

```sh
crontab -e
/etc/init.d/cron enable
/etc/init.d/cron restart
crontab -l
```

Paste the line in the editor, save, and the last command must print it back.

> **Why the `sleep 70 && touch /etc/banner`:** it prevents a reboot loop. This AP has no battery-backed clock. At boot it takes its time from the newest file in `/etc` until NTP answers. Without the guard, the clock after the reboot can land back before 03:30, the job fires again, and the AP reboots forever. Touching a file 70 seconds after 03:30 makes the restored time land after the scheduled minute.

> **Pitfall:** the line belongs in **System → Scheduled Tasks** (`/etc/crontabs/root`), not in **System → Startup → Local Startup** (`/etc/rc.local`). In Local Startup it would reboot the AP at every boot.

The backup script checks for this line and reports a FAIL if it is missing ([Backups and secrets](backups-and-secrets.md)).

The stock-firmware AP ([TP-Link Archer AX21](../hardware/tp-link-archer-ax21.md)) has no SSH; use its own reboot schedule setting if its firmware offers one.

### Step 4. Firmware and add-on upgrades: router and node

1. Take the three router backups first ([Backups and secrets](backups-and-secrets.md)).
2. Upgrade through the GUI (**Administration → Firmware Upgrade**), node and main unit in the order the firmware's release notes give.
3. Update the add-ons from `amtm` on the router.
4. Afterwards:

   **Run on: the router**

   ```sh
   sh /jffs/xt8-bootstrap.sh verify
   ```

   Pass: `0 failed`.

| After a router upgrade, check | Why | Fix |
| --- | --- | --- |
| Clients still get an `fd00:` address | Firmware and `amtm` actions can switch IPv6 off on `br0` | `service restart_dnsmasq; service restart_firewall`, then `verify` ([Local-only IPv6](../network/local-only-ipv6.md)) |
| The IoT access rules are present | A Wi-Fi restart wipes the `ebtables` rules; a hook restores them | `sh /jffs/scripts/kasa-guest-allow.sh`; check `/jffs/scripts/service-event-end` exists and is executable ([Kasa across networks](../apps/homebridge-kasa-across-networks.md)) |
| The node still has its reboot job | An AiMesh sync or upgrade can reset it | `cru l` on the node; run Step 2 again |
| Log rotation still works | See Step 8 | Step 8 |
| DNS settings | DHCP DNS Server 1 is `192.168.50.11`; DNS Director global redirection is back on its user-defined Pi-hole entry | [DNS design](../network/dns-design.md) |

> **Pitfall:** `amtm` or Entware downloads sometimes hang. Unresolved on the test router; the Skynet firewall add-on is suspected. Disable Skynet briefly and retry.

> **Pitfall:** a `.CFG` settings backup restores only onto the same firmware family. After a big version jump, expect to use the bootstrap script instead ([ASUS ZenWiFi XT8](../hardware/asus-zenwifi-xt8.md)).

> **Pitfall:** do not reinstall the `dnscrypt-proxy` manager add-on if Pi-hole already encrypts upstream DNS. It restarts dnsmasq constantly (hundreds of restarts in the log).

### Step 5. Firmware and package upgrades: access points

**OpenWrt AP**

1. Run the backup script.
2. Flash through LuCI: **System → Backup / Flash Firmware**. Keep settings if the release notes allow it.
3. If the AP comes back at `192.168.1.1` in routing mode, settings were not kept. Restore the backup in LuCI, or run [a7-ap-setup.sh](../../files/archer-a7/a7-ap-setup.sh) and [a7-iot-ssid.sh](../../files/archer-a7/a7-iot-ssid.sh) again ([TP-Link Archer A7 on OpenWrt](../hardware/tp-link-archer-a7-openwrt.md)).
4. Check `crontab -l` still shows the reboot line and `ip -6 addr show br-lan` shows an `fd00:` address.
5. Take a new backup.

> **Pitfall:** after restoring a backup onto a freshly flashed AP at `192.168.1.1`, the page stops answering, because the restore also brings back the `192.168.50.3` address. Move the cable to the main network and open `http://192.168.50.3`.

**Stock-firmware AP**: upgrade through its own web UI. Afterwards confirm it is still in Access Point mode and still at `192.168.50.4`.

### Step 6. Operating system and bootloader on the Raspberry Pis

Do one Pi at a time. Wait for it to be `Ready` before starting the next. Three of the four servers must stay up for a comfortable margin; two is the minimum for the control plane.

**Run on: one Pi**

```bash
sudo apt-get update && sudo apt-get upgrade -y
sudo rpi-eeprom-update
```

The second line reports whether a bootloader (EEPROM) update is available. To install it:

```bash
sudo rpi-eeprom-update -a
sudo reboot
```

**Run on: another server**, while you wait

```bash
sudo kubectl get nodes
```

Go on to the next Pi only when the first shows `Ready`.

> **Why:** an old bootloader is one cause of a Pi that "stopped booting from USB after years of working" ([Raspberry Pi](../hardware/raspberry-pi.md)).

The Mac VM: update packages inside the VM the same way (`limactl shell k3s-vm`), and update Lima itself on the Mac. Before rebooting the Mac, remember it is one of the four etcd members ([Mac Lima VM](../hardware/mac-lima-vm.md)).

### Step 7. k3s upgrades

k3s is upgraded by running the install script again with the new version and the same options. The settings live in `/etc/rancher/k3s/config.yaml` on each node, so the command is the same as at install time.

1. Take an etcd snapshot and copy it and the token off the node ([Backups and secrets](backups-and-secrets.md)).
2. Upgrade one server at a time, waiting for `Ready` between them.

   **Run on: each server in turn**

   ```bash
   curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='<FULL_VERSION_TAG>' sh -s - server
   ```

   The version must be the full tag, for example `v1.34.3+k3s1`. A short form such as `v1.34` fails to download.

3. After the last server, re-check everything in the table below.

> **Not verified:** the author has not taken this cluster through a k3s upgrade. The procedure is the documented manual upgrade (References). The checks below come from how the cluster was built.

**Run on: server-1**

```bash
sudo kubectl get nodes -o wide
sudo kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
sudo kubectl -n kube-system get endpointslices -l kubernetes.io/service-name=kube-dns
sudo kubectl get pods -n kube-system | grep svclb
sudo kubectl get svc -A | grep LoadBalancer
sudo kubectl -n pihole get pods -o wide
```

| Re-check after every k3s upgrade or reinstall | Pass | If not |
| --- | --- | --- |
| All nodes on the new version and `Ready` | `VERSION` column matches on all four | Finish the remaining node |
| CoreDNS replicas | Three pods on different nodes, at least one on a Pi | `sudo kubectl -n kube-system scale deployment coredns --replicas=3`. CoreDNS is managed by k3s, so the count is set by command and may be reset ([CoreDNS](../kubernetes/coredns.md)) |
| CoreDNS is dual-stack | Both `kube-dns` endpoint slices list endpoints | `sudo kubectl -n kube-system rollout restart deployment coredns` |
| ServiceLB still disabled | The `svclb` command prints nothing | `disable: servicelb` must be in the config on **every** server ([Load balancers](../kubernetes/load-balancers.md)) |
| Addresses unchanged | Pi-hole on `.11` (and `::11`), Traefik on `.12` | k3s may reset annotations on its bundled Traefik during an upgrade. If Traefik moved, see [Load balancers](../kubernetes/load-balancers.md) |
| Pi-hole placement | One pod per Pi, `2/2` | Delete one of a doubled-up pair ([Pi-hole](../apps/pihole.md)) |
| The API floating address | `sudo kubectl --server https://192.168.50.10:6443 get nodes` answers | kube-vip ([Load balancers](../kubernetes/load-balancers.md)) |

> **Not verified:** the CoreDNS replica count is believed to survive an upgrade but has not been seen to. The Traefik address-pinning annotation is untested on the test cluster; Traefik received `.12` by being second in line.

### Step 8. App upgrades (Helm)

Always apply the **whole** values file from the repo. A partial file removes settings.

**Run on: server-1**, from the root of this repo

```bash
helm repo update
helm upgrade --install pihole mojo2600/pihole -n pihole --version 2.38.0 -f files/pihole/values.yaml
sudo kubectl -n pihole get pods -o wide
```

| After | Check | Why |
| --- | --- | --- |
| Any Pi-hole upgrade | One pod per Pi | During a rollout, old and new pods were counted together, leaving two pods on one Pi. The values file has `matchLabelKeys: [pod-template-hash]` to prevent it. **Not verified:** that fix had not been through an upgrade when this was written |
| Any Pi-hole upgrade | Pods are `2/2` | A newer `cloudflared` image without `proxy-dns` leaves the pod `1/2`. Keep the sidecar tag pinned (`doh.tag: "2025.9.1"`) |
| Any Pi-hole restart | Statistics are zero | Expected. Nothing is kept on disk |
| Homebridge upgrade | UI loads; pod `/etc/resolv.conf` shows only `10.43.0.10` | The DNS block in the values file must survive ([Homebridge](../apps/homebridge.md)) |

Notes:

- Pi-hole's `image.tag` is `latest` with `IfNotPresent`, so each Pi keeps whatever it pulled and the three pods can end up on different versions. To choose a version, set `tag:` to a dated release and upgrade. Pinning the Pi-hole and Homebridge image tags is a worthwhile improvement.
- The Homebridge chart repository (`k8s-at-home`) is archived. `helm upgrade` still fetched it when last tried. Save a copy of the chart in case it stops; the same change can then be made on the Deployment with `kubectl patch`.
- Validate a values file before applying it: `helm template homebridge k8s-at-home/homebridge -n homebridge -f files/homebridge/values.yaml > /dev/null && echo OK`.
- Homebridge plugin updates are done in the Homebridge UI. Download a new UI backup afterwards.

### Step 9. Log rotation and router log review

Details: [Router logging](../network/router-logging.md).

**Run on: the router**

```sh
ls -la /opt/var/log/messages*
tail -5 /opt/var/log/logrotate.log
ls -ld /opt/var/lib
```

| Pass | If not |
| --- | --- |
| `messages` is small and growing, with older logs beside it as `messages-<date>` | Below |
| `logrotate.log` has no "error creating stub state file /opt/var/lib/logrotate.status" | `mkdir -p /opt/var/lib; /opt/sbin/logrotate /opt/etc/logrotate.conf` |
| `/opt/var/lib` exists | Same. If it keeps disappearing, the USB drive was reformatted or is failing |

> **Why:** Scribe's log rotation needs a state folder that nothing creates. Without it the rotation fails silently every night and the log grows without limit (tens of megabytes on the test router). The bootstrap script creates the folder and its `verify` checks it. Do not reinstall Scribe to fix this; create the folder.

To test a rotation by hand:

```sh
/opt/sbin/logrotate /opt/etc/logrotate.conf
logger "rotation test"; sleep 2; ls -la /opt/var/log/messages*
```

`messages` being 0 bytes right after a rotation only means nothing has been logged yet. Only if the old file keeps growing instead: `killall -HUP syslog-ng`. Old rotated files can be deleted or left for logrotate to age out.

**Periodic log review.** Once a month, read the router log for these:

| Line in the log | Meaning | Action |
| --- | --- | --- |
| `usb 3-1: device descriptor read/64, error -110` | The USB drive is timing out | Back it up; replace it if it repeats |
| A LAN port going up and down between 100 and 1000 Mbps | Marginal cable or device on that port | Swap the cable |
| Web UI logins from addresses you do not recognise | Someone logged in to the router | Confirm it was you (a VPN can make your own login come from another subnet); otherwise change the admin password |
| Kernel crash followed by a reboot, AiProtection in the trace | The AiProtection engine crashed | Turn AiProtection off, or at least Two-Way IPS and Infected Device Prevention |
| Roaming assistant disconnecting clients very often, or `roamast` crashing | Threshold too aggressive | Roaming assistant at -70 dBm, not -55 dBm |
| JFFS CRC errors | Flash storage errors | If they persist: back up JFFS, format it at next boot, restore |
| Hundreds of dnsmasq restarts | The dnscrypt-proxy manager is installed | Remove it |
| "own address as source" on LAN ports | Low priority; seen daily on the test router without effect | None |
| UPnP notify timeouts | Cosmetic | None |
| No `RTR-ADVERT` lines at all | A `quiet-ra` line is in `/jffs/scripts/dnsmasq.postconf` | Comment it out, `service restart_dnsmasq` |
| `DHCPSOLICIT(br0)` repeating with no reply | A device wants DHCPv6; the router only does SLAAC | None |

> **Pitfall:** compare the live `/jffs/scripts/dnsmasq.postconf` with [the repo copy](../../files/xt8/jffs-scripts/dnsmasq.postconf) now and then. On the test router the live file had grown extra lines (including `quiet-ra`) that the repo copy never contained, written by something else.

The AiMesh node has no USB drive and no Scribe. Its log lives in memory, limits its own size and is lost at every reboot. There is nothing to rotate.

### Step 10. Node housekeeping

**Run on: server-1**

```bash
sudo kubectl top nodes
sudo kubectl get pods -A | grep -v -E 'Running|Completed'
```

**Run on: each node**

```bash
df -h /
free -h
grep nameserver /etc/resolv.conf
```

| Check | Pass | If not |
| --- | --- | --- |
| Memory | Headroom on every node. 2 GB is the minimum for a k3s server; watch those nodes | Move workloads; pods showing `OOMKilled` are the sign |
| Disk | Well under 100% | `sudo k3s crictl rmi --prune` removes unused images; `sudo journalctl --vacuum-size=200M` trims the journal |
| Node's own DNS | `1.1.1.1` / `9.9.9.9`, **not** Pi-hole | A node that depends on Pi-hole for its own DNS deadlocks after a power cut ([DNS design](../network/dns-design.md)) |
| etcd disk speed | No repeated "slow fdatasync" or "apply request took too long" in `sudo journalctl -u k3s` | etcd on a spinning hard drive is too slow; move that node to an SSD |
| Fixed addresses | Every server, including the Mac VM, has a DHCP reservation or a static address | An etcd member whose address changes breaks the cluster. Reserve IoT devices driven by Homebridge too |

### Step 11. Retake backups after every change

| You changed | Retake |
| --- | --- |
| Anything in the router GUI or `/jffs` | `.CFG`, JFFS backup, `sh /jffs/xt8-bootstrap.sh backup` |
| Anything on the OpenWrt AP | `sh files/archer-a7/a7-backup.sh` |
| Homebridge plugins, accessories, config | UI backup archive |
| Cluster objects, a k3s upgrade, the join token | etcd snapshot **and** the token |
| Seerr settings | The Seerr folder archive |
| The Lima VM definition | Copy `lima.yaml` |
| Sonarr, Radarr, Jackett, Plex or qBittorrent settings | **Backup Now** in Sonarr and Radarr, and the media app backups ([Backups and secrets](backups-and-secrets.md#step-9-media-server-apps)) |

How: [Backups and secrets](backups-and-secrets.md).

### Step 12. Certificate and token rotation

> **Not verified:** none of these was run by the author. The commands are from the k3s documentation. Read the linked pages first and take an etcd snapshot before starting.

**Join token.**

**Run on: server-1**

```bash
sudo k3s token rotate --token "$(sudo cat /var/lib/rancher/k3s/server/token)" --new-token "$(openssl rand -hex 32)"
sudo cat /var/lib/rancher/k3s/server/token
```

Then put the new token into `/etc/rancher/k3s/config.yaml` on the other three servers and restart k3s on each, one at a time. Save the new token with your next snapshot; old snapshots still need the old token.

**Certificates** (including the admin certificate in the kubeconfig). k3s renews its own certificates when it restarts close to their expiry, so this is only needed after an exposure or if a restart has not happened for a long time.

**Run on: each server, one at a time**

```bash
sudo systemctl stop k3s
sudo k3s certificate rotate
sudo systemctl start k3s
```

Wait for the node to be `Ready` before the next one.

When to rotate anything else (passwords, API keys, the tunnel token): [Backups and secrets](backups-and-secrets.md).

### Step 13. Media server

Only if you run the [media stack](../media/media-stack-overview.md). It lives outside the cluster, so none of the steps above touch it.

**Run on: the Mac `media-1`**, as the user that runs the apps, from the root of this repo. Read-only; it prints no keys.

```sh
bash files/media/media-health.sh
```

**Run on: the Windows PC `torrent-pc`**, in PowerShell, as the user that runs qBittorrent. Read-only.

```powershell
powershell -ExecutionPolicy Bypass -File .\files\media\qbit-check.ps1 -VpnAdapter "<VPN_ADAPTER_NAME>" -SavePath "M:\Downloads" -MediaServer 192.168.50.2
```

| Check | Pass | If not |
| --- | --- | --- |
| `media-health.sh` | No `[FAIL]` lines. **Not yet run on a Mac by the author**; read its output critically the first time | The line names the app or folder; see [Troubleshooting, Media server](troubleshooting.md#media-server) |
| `qbit-check.ps1` | No `[FAIL]` lines; qBittorrent bound to the VPN adapter. **Parse-checked only** | [qBittorrent on Windows behind a VPN](../media/qbittorrent-windows-vpn.md#troubleshooting) |
| Free space on the media volume | Above the script's `MIN_FREE_GB` (100 GB by default); `df -h /Volumes/Media` | Remove torrents that have finished seeding (their hardlinked library copy stays), or move older items to a second volume |
| Sonarr and Radarr **System > Status**, Health | No messages | Each message links to the Servarr wiki entry; [Sonarr and Radarr](../media/sonarr-and-radarr.md#troubleshooting) |
| Indexers | No "Indexers are unavailable due to failures" | [Jackett and Prowlarr](../media/jackett-and-prowlarr.md#troubleshooting) |
| After a restart of either machine | The Mac is logged in with the volume mounted; the PC is signed in, the VPN is connected and `M:` is mapped before qBittorrent starts | [Media stack overview, Pitfalls](../media/media-stack-overview.md#pitfalls) |

Updates, one app at a time, with a backup first. Versions, download links and the traps for each are in [Software and firmware](software-and-firmware.md#plex-media-server-macos):

| App | How it updates in the build | Note |
| --- | --- | --- |
| Plex Media Server | Install the new macOS build over the old one, or accept the update Plex Web offers | Stay on 1.43.3 or later: Plex published security fixes for 1.43.2 and earlier |
| Sonarr | Built-in updater, automatic | Was on the `develop` branch in the build; prefer `main` |
| Radarr | Automatic updates off; update from System > Updates | If macOS refuses to open it afterwards, run the `codesign` / `xattr` line again |
| Jackett | Auto-update off in the build: update by hand at least monthly, because indexer definitions go stale | [Updating Jackett](../media/jackett-and-prowlarr.md#updating-jackett) |
| qBittorrent | Run the new installer from qbittorrent.org | Check the interface binding and Web UI settings afterwards |
| VPN app | The vendor's own updater | Re-run `qbit-check.ps1`. If a reinstall gives the adapter a different name, qBittorrent stays bound to the old one and transfers nothing |

## Check it

Run the full [Verification](verification.md) list after any firmware or k3s upgrade. For routine months, the checklist below is enough.

### Monthly

| # | Check | Where | Pass |
| --- | --- | --- | --- |
| 1 | `sh /jffs/xt8-bootstrap.sh verify` | The router | `0 failed` |
| 2 | Log rotation (Step 9) | The router | `messages` small, no logrotate error |
| 3 | Skim the router log (Step 9 table) | The router | Nothing new |
| 4 | `uptime` | Router, node, OpenWrt AP | Under a week on each |
| 5 | `cru l` | AiMesh node | `WeeklyReboot` listed |
| 6 | `crontab -l` | OpenWrt AP | The reboot line |
| 7 | `sudo kubectl get nodes` and `get pods -A \| grep -v -E 'Running\|Completed'` | server-1 | Four `Ready`; header only |
| 8 | `sudo kubectl top nodes`, `df -h /` | server-1; each node | Headroom |
| 9 | CoreDNS: three pods on different nodes | server-1 | Yes |
| 10 | Pi-hole: one pod per Pi, `2/2` | server-1 | Yes |
| 11 | Homebridge log has no new `ENOTFOUND`, `EAI_AGAIN`, `401` | Homebridge UI terminal | None |
| 12 | Newest backups are newer than the newest change | Your backup folder | Yes |
| 13 | Media server: `media-health.sh` and `qbit-check.ps1`, free space, Sonarr and Radarr Health (Step 13) | The Mac; the Windows PC | No `[FAIL]`; no Health messages |
| 14 | Jackett updated, if its auto-update is off | The Mac | Current release |

### Quarterly

| # | Task |
| --- | --- |
| 1 | Check for router, node and AP firmware; upgrade with Steps 4 and 5 |
| 2 | `sudo apt-get upgrade` and `sudo rpi-eeprom-update` on each Pi, one at a time (Step 6) |
| 3 | Check for a k3s release; upgrade with Step 7 and run its re-check table |
| 4 | Take a fresh full set of backups and copy them off site |
| 5 | Prove one backup: list the OpenWrt archive with `tar -tzf`, list the etcd snapshots |
| 6 | Run the whole [Verification](verification.md) list, including the client-side tests |
| 7 | Review DHCP reservations: every server and every IoT device Homebridge drives has one |
| 8 | Review the DNS Director per-device list on the router; make sure no rule points at an address that no longer answers DNS |
| 9 | Consider the failover test in [Verification](verification.md) when a few minutes of disruption is acceptable |
| 10 | Update Plex, Sonarr, Radarr, qBittorrent and the VPN app (Step 13); copy the media app backups off the Mac and the PC |

## Pitfalls

| What happens | Why | How to avoid or recover |
| --- | --- | --- |
| OpenWrt AP reboots in a loop at 03:30 | No battery clock; time restored to before the scheduled minute | Use the `sleep 70 && touch /etc/banner` form |
| AiMesh node stops rebooting weekly | `cru` jobs are lost at boot; `services-start` did not run, or an AiMesh sync reset it | Run the node setup script again |
| Node reboots twice | Both the firmware scheduler and the cron job are on | The script sets `reboot_schedule_enable=0` on the node |
| Cluster DNS fails when one node is down, months after it worked | CoreDNS went back to one replica at an upgrade | Scale to three after every upgrade |
| Pi-hole address moves to a node address, IPv6 Services `<pending>` | ServiceLB came back on one server | `disable: servicelb` on every server |
| Control plane stops during a rolling reboot | Two servers were down at once, or the Mac was asleep | One at a time; check `limactl list` first |
| Settings vanish after a Helm upgrade | A partial values file was applied | Always apply the whole file |
| A setting changed in the Pi-hole UI disappears | Pods rebuild from the values file | Change the file |
| Router log fills the USB drive | Missing logrotate state folder | Step 9 |
| A restore brings back old Wi-Fi keys | The backup predates the change | Step 11 |

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `cru l` on the node shows no reboot job | `services-start` did not run at boot, or AiMesh sync reset it | `sh files/xt8/node/xt8-node-setup.sh 192.168.50.117 admin <SSH_PORT>` |
| `crontab -l` on the OpenWrt AP is empty | The line was never entered, or was put in Local Startup | Step 3 |
| k3s install or upgrade: download failed | Short version such as `v1.34` | Full tag, `v1.34.3+k3s1` |
| A Pi does not come back after `rpi-eeprom-update -a` and reboot | Boot order or slow USB drive | [Raspberry Pi](../hardware/raspberry-pi.md) |
| `verify` fails a DNS-over-TLS or "upstream is only" check | The WAN page and the `WAN_DNS`, `WAN_DNS2`, `WAN_DOT` values at the top of the script disagree | Make them agree ([DNS design](../network/dns-design.md) Step 4) |
| `amtm` downloads hang | Unresolved; Skynet suspected | Disable Skynet briefly and retry |

Anything else: [Troubleshooting](troubleshooting.md).

## References

- [k3s: Manual upgrades](https://docs.k3s.io/upgrades/manual): upgrading with the install script, servers first and one at a time.
- [k3s: etcd-snapshot](https://docs.k3s.io/cli/etcd-snapshot): the snapshot to take before an upgrade, and the default schedule.
- [k3s: token](https://docs.k3s.io/cli/token): `k3s token rotate`.
- [k3s: certificate](https://docs.k3s.io/cli/certificate): checking expiry and `k3s certificate rotate`.
- [k3s: Networking services](https://docs.k3s.io/networking/networking-services): the bundled CoreDNS, Traefik and ServiceLB that an upgrade redeploys.
- [Asuswrt-Merlin wiki: Scheduled tasks (cron jobs)](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Scheduled-tasks-(cron-jobs)): the `cru` command and why jobs must be re-added at boot.
- [Asuswrt-Merlin wiki: User scripts](https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts): `services-start` and the other `/jffs/scripts` hooks.
