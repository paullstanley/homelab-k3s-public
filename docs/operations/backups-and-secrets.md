# Backups and secrets

What to back up for each part of the build, how to take each backup, where to keep it, which secrets exist, and what must never go into Git. A full recovery needs three things: the configuration files in this repo, the backups below, and your password manager.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | ASUS ZenWiFi XT8 on Asuswrt-Merlin, TP-Link Archer A7 on OpenWrt, Homebridge (UI backup), k3s v1.34.3+k3s1 with embedded etcd, Pi-hole and Seerr on k3s, a Lima VM on a Mac. The media server step follows the media pages: Plex, Sonarr, Radarr and Jackett on a Mac, qBittorrent on Windows |
| **Also works for** | Other Asuswrt-Merlin routers and other OpenWrt devices (the backup mechanisms are the same; not tested by the author) |
| **Time** | 30 minutes for a first full set; 2 minutes per device afterwards |
| **You need first** | The devices you want to back up. Each section stands alone |

## How it works

The repo holds **configuration**: scripts, Helm values, manifests. It holds no data and no secrets; every secret in it is a placeholder in angle brackets such as `<K3S_TOKEN>`.

Three kinds of thing live outside the repo:

- **Device backups**: files a device exports that restore it in one step. They contain passwords.
- **Application data**: the Homebridge pairing, the etcd database, the Seerr folder, the media apps' settings and databases.
- **Secrets**: passwords, tokens and keys. They live in a password manager and are typed in at install time.

A `.gitignore` file stops the usual backup and secret file names from being committed by accident. It is a backstop, not the protection: the protection is never copying those files into the repo folder.

## Before you start

- Decide where backups live. They need to be **off the network they protect**: a laptop plus an encrypted cloud drive or archive. Not the router's USB drive alone, not a cluster node alone.
- Have a password manager entry for each secret in the table under "Secrets".
- Pick a working folder on your computer outside the repo, for example `~/Documents/network-backups/`.

> **Not verified:** the router bootstrap script's `backup` mode and `a7-backup.sh` were syntax-checked and run against stand-in commands only. They had not been run on the real devices when this was written. Read the output the first time you use them.

## Steps

### Step 1. Router (ASUS XT8, Asuswrt-Merlin)

Take all three. Details of the router setup: [ASUS ZenWiFi XT8](../hardware/asus-zenwifi-xt8.md).

1. In the web UI: **Administration → Restore/Save/Upload Setting → Save setting**. This downloads a `.CFG` file. It restores every GUI setting, but only onto the same firmware family.
2. On the same page: **Backup JFFS partition**. JFFS is the router's small persistent storage, where the custom scripts live.
3. Run the bootstrap script's backup command.

   **Run on: the router**

   ```sh
   sh /jffs/xt8-bootstrap.sh backup
   ```

   It saves `/jffs/scripts`, `/jffs/configs`, `/jffs/addons` and the per-device lists (DNS Director clients, DHCP reservations, client names, as `nvram-lists-*.txt`) to the folder `homenet-backup` on the USB drive, and prints the `scp` line that copies the folder to your computer. Run that line on your computer, with your SSH user and port:

   **Run on: your computer**

   ```sh
   scp -O -P <SSH_PORT> -r admin@192.168.50.1:/tmp/mnt/<USB_LABEL>/homenet-backup ~/Documents/network-backups/
   ```

> **Pitfall:** with no USB drive the script writes to `/tmp/homenet-backup`. `/tmp` is memory and is lost at reboot. Copy it off at once.

> **Pitfall:** the USB drive also holds the add-ons and the log. If the router log shows `usb 3-1: device descriptor read/64, error -110`, the drive is timing out. Back it up and replace it if the message repeats.

The AiMesh node needs no backup. Its only local setting is the weekly reboot, which [xt8-node-setup.sh](../../files/xt8/node/xt8-node-setup.sh) puts back ([ASUS AiMesh node](../hardware/asus-aimesh-node.md)).

### Step 2. OpenWrt access point (Archer A7)

One script, run by hand after every change to the AP: [a7-backup.sh](../../files/archer-a7/a7-backup.sh).

**Run on: your computer**, from the root of this repo

```sh
sh files/archer-a7/a7-backup.sh 192.168.50.3 root ~/Documents/network-backups/a7
```

All three arguments are optional: the AP's address (default `192.168.50.3`), the SSH user (default `root`), and the folder to save into (the script has its own default; pass yours). `ssh` asks for the AP's password once. The password is not an argument on purpose, because arguments end up in shell history.

| What it does | Why |
| --- | --- |
| Runs `sysupgrade -b -` on the AP and saves the output on your computer as `a7-backup-<date>-<time>.tar.gz` | This is OpenWrt's own backup format, the one LuCI (the OpenWrt web UI) restores. Nothing is left on the AP |
| Opens the archive and checks for the network and wireless configs, the IoT SSID and bridge, and the weekly reboot line | A backup that silently lacks the IoT network or the reboot is caught today, not on the day you need it |
| Keeps the newest 10 files (`KEEP=20 sh files/archer-a7/a7-backup.sh` to change) | Older ones are a way back if a change goes wrong |
| Sets the file to owner-read only | **It contains the Wi-Fi passwords** |

All six checks should pass. The reboot check fails until the weekly reboot line is in the AP's crontab ([Maintenance](maintenance.md)).

When to run it:

- Once now.
- After any change in LuCI or over SSH on the AP, before logging out.
- Before a firmware upgrade.

To prove a backup is readable without touching the AP:

**Run on: your computer**

```sh
tar -tzf ~/Documents/network-backups/a7/a7-backup-<date>-<time>.tar.gz | head -30
```

Restore: LuCI → **System → Backup / Flash Firmware → Restore backup** ([TP-Link Archer A7 on OpenWrt](../hardware/tp-link-archer-a7-openwrt.md)).

> **Why it is not automated:** the AP changes a few times a year, an unattended job would need a stored key with root on the AP, and a check you watch pass is worth more than a scheduled job nobody reads. If you do want it scheduled, the same script runs from `launchd` or cron with an SSH key.

This archive is the only copy of the AP's Wi-Fi settings, including any MAC deny lists.

The stock-firmware AP ([TP-Link Archer AX21](../hardware/tp-link-archer-ax21.md)) has no SSH. Use its own web UI backup page if you want a file, or keep its few settings written down.

### Step 3. Homebridge

Homebridge UI → **Settings → Backup → Download Backup Archive**.

The archive holds `config.json`, the plugin list and the HomeKit pairing. **It contains passwords** (cameras, device vendor accounts, API keys). The live data sits on one node's disk only (`server-1`). If that disk dies without this archive, every accessory must be paired again.

Details: [Homebridge](../apps/homebridge.md).

### Step 4. Cluster (etcd snapshot and token)

**Run on: server-1**

```bash
sudo k3s etcd-snapshot save --name manual-$(date +%Y%m%d)
sudo ls -la /var/lib/rancher/k3s/server/db/snapshots/
```

The first command writes a snapshot of the cluster database. The second lists the snapshots.

Copy two things off the node: the newest snapshot file, and `/var/lib/rancher/k3s/server/token`. **A snapshot can only be restored with the token it was made under.**

k3s also takes its own snapshots on a schedule on each server: by default at 00:00 and 12:00, keeping five. Those protect against a bad change, not against losing the disks, so still copy one off.

Restore is described in [k3s HA cluster](../kubernetes/k3s-ha-cluster.md).

> **Not verified:** a snapshot restore (`k3s server --cluster-reset --cluster-reset-restore-path=<snapshot file>`) has not been run by the author. Read the k3s backup and restore page (References) before relying on it.

### Step 5. Capture the live cluster configuration

A snapshot restores the cluster; it does not tell you whether the live cluster still matches the files in this repo. For that, export the live settings as text and compare.

The helper script [`files/scripts/export-live-config.sh`](../../files/scripts/export-live-config.sh) does this in one go (`bash files/scripts/export-live-config.sh` on server-1, from the root of this repo) and replaces tokens and passwords with placeholders before writing anything. The commands below are the core of it, if you would rather run them by hand. Both only read, and change nothing on the cluster.

**Run on: server-1**

```bash
OUT=~/live-export/$(date +%Y%m%d-%H%M%S); mkdir -p "$OUT"
sudo kubectl get nodes -o wide --show-labels > "$OUT/nodes.txt"
sudo kubectl get svc -A -o wide > "$OUT/services.txt"
sudo kubectl get ingress -A > "$OUT/ingresses.txt"
sudo kubectl get pods -A -o wide > "$OUT/pods.txt"
sudo helm list -A --kubeconfig /etc/rancher/k3s/k3s.yaml > "$OUT/helm-releases.txt"
sudo kubectl get ipaddresspools,l2advertisements -n metallb-system -o yaml > "$OUT/metallb-live.yaml"
sudo kubectl -n kube-system get helmchart kube-vip -o yaml > "$OUT/kube-vip-helmchart.yaml"
sudo kubectl get middlewares.traefik.io -A -o yaml > "$OUT/traefik-middlewares.yaml"
nmcli -t -f NAME,DEVICE con show --active > "$OUT/nmcli-active.txt"
ip -br addr > "$OUT/ip-addr.txt"
cat /etc/resolv.conf > "$OUT/resolv.conf.txt"
sudo ufw status verbose > "$OUT/ufw-status.txt"
systemctl is-active cloudflared > "$OUT/cloudflared-state.txt"
```

For the Helm values of one release (they can contain passwords, so the `sed` replaces the value on any line whose key contains `password`, `passwd`, `token`, `secret`, `apikey`, `api_key` or `psk`):

```bash
sudo helm get values pihole -n pihole -o yaml --kubeconfig /etc/rancher/k3s/k3s.yaml | sed -E 's/^([[:space:]]*[A-Za-z0-9_.-]*(password|passwd|token|secret|api_?key|psk)[A-Za-z0-9_.-]*:[[:space:]]*).+/\1<REDACTED>/I' > "$OUT/helm-values-pihole-pihole.yaml"
```

For the k3s config of the node (the `sed` replaces the join token):

```bash
sudo cat /etc/rancher/k3s/config.yaml | sed -E 's/^([[:space:]]*token:[[:space:]]*).*/\1<K3S_TOKEN>/' > "$OUT/k3s-config-$(hostname).yaml"
```

Then compare with the repo, for example:

```bash
diff <(grep -v '^#' files/pihole/values.yaml) "$OUT/helm-values-pihole-pihole.yaml" | less
```

> **Pitfall:** pattern-based redaction misses secrets under unusual key names. Read every exported file before it goes anywhere near a repository. If you keep the export inside the repo folder, name it `live-export/`; `.gitignore` excludes that folder.

### Step 6. Pi-hole

Pi-hole in this build keeps nothing on disk. Its whole configuration is [values.yaml](../../files/pihole/values.yaml), and its statistics reset whenever a pod restarts. So:

- There is nothing to back up beyond the values file, which is already in the repo.
- A change made in the Pi-hole web UI is lost when that pod restarts and never reaches the other pods. Make changes in the values file.
- The admin password lives in the Kubernetes Secret `pihole-admin` (namespace `pihole`). It is included in an etcd snapshot. Keep the password itself in the password manager.

Details: [Pi-hole](../apps/pihole.md).

### Step 7. Seerr

Seerr's data is one folder on `server-1`. Find it and pack it.

**Run on: server-1**

```bash
sudo kubectl -n seerr get pvc
sudo ls /var/lib/rancher/k3s/storage/ | grep seerr
sudo tar -czf /tmp/seerr-config.tar.gz -C /var/lib/rancher/k3s/storage "$(sudo ls /var/lib/rancher/k3s/storage/ | grep seerr | head -1)"
```

The first two commands show the volume claim and its folder. The third writes `/tmp/seerr-config.tar.gz`. Copy it off the node; it contains API keys.

The Cloudflare tunnel has no local data worth saving. Its token is shown again in the Cloudflare dashboard ([Seerr behind a Cloudflare tunnel](../apps/seerr-cloudflare-tunnel.md)).

### Step 8. The Mac VM

**Run on: the Mac**, from the root of this repo

```bash
cp ~/.lima/k3s-vm/lima.yaml files/k3s/lima/k3s-vm.yaml
```

This keeps the real VM definition. Read the file before committing it. Nothing else in the VM needs saving: it is a cluster member and is rebuilt from [Mac Lima VM](../hardware/mac-lima-vm.md).

> **Not verified:** the `k3s-vm.yaml` in this repo was reconstructed, not copied from a running VM. Replace it with your own `lima.yaml` once your VM works.

### Step 9. Media server apps

Only if you run the [media stack](../apps/media-stack-overview.md). The media files themselves are not covered here: they are large, and can be downloaded again. What is worth keeping is each app's settings and database. Every one of these backups **contains secrets** (API keys, the Plex token, the qBittorrent Web UI login, indexer logins).

| App | What to keep | Where | How |
| --- | --- | --- | --- |
| Sonarr, Radarr | Their own backup zips (made every 7 days, kept 28 days by default) | `~/.config/Sonarr/Backups`, `~/Library/Application Support/Radarr/Backups` | System > **Backup** > **Backup Now** before a change, then copy the folders off the Mac ([Sonarr and Radarr](../apps/sonarr-and-radarr.md#backups)) |
| Plex Media Server | The data folder (without `Cache`) and the preferences plist, which holds the server's identity and token | `~/Library/Application Support/Plex Media Server/`, `~/Library/Preferences/com.plexapp.plexmediaserver.plist` | Quit Plex, then `tar` the folder and copy the plist ([Plex Media Server](../apps/plex-media-server.md#backup-and-move)). The folder can be tens of gigabytes |
| Jackett | The config folder: API key, admin password, indexer logins | `~/.config/Jackett` (some installs: `~/Library/Application Support/Jackett`) | Copy it with the rest of the Mac ([Jackett and Prowlarr](../apps/jackett-and-prowlarr.md#updating-jackett)) |
| Prowlarr (if used instead) | Its built-in backup zips, like Sonarr and Radarr | Its appdata folder, `Backups` | System > Backup. **Not verified by the author**: Prowlarr was not installed in the build |
| qBittorrent (Windows) | Settings, and the state of every torrent | `%APPDATA%\qBittorrent\qBittorrent.ini` and `%LOCALAPPDATA%\qBittorrent\BT_backup` | Quit qBittorrent (**File > Exit**), then copy both ([qBittorrent on Windows behind a VPN](../apps/qbittorrent-windows-vpn.md#backups)) |
| The VPN app | Nothing local worth saving | | Keep the account login in the password manager |

**Run on: the Mac**, after quitting Plex. This collects the Mac side into one archive in your home folder; copy it off the Mac.

```sh
tar -czf ~/media-apps-backup-$(date +%Y%m%d).tar.gz --exclude 'Plex Media Server/Cache' -C ~ \
  ".config/Sonarr/Backups" \
  "Library/Application Support/Radarr/Backups" \
  ".config/Jackett" \
  "Library/Application Support/Plex Media Server" \
  "Library/Preferences/com.plexapp.plexmediaserver.plist"
```

> **Not verified:** this combined command was not run by the author. The per-app commands on the linked pages are the reference; the Plex data folder can make this archive very large, so leave it out and back Plex up on its own if space is short. If Jackett keeps its settings under `Library/Application Support/Jackett` on your Mac, change that line.

### Step 10. Put the backups somewhere safe

| Backup | Contains secrets | Keep it |
| --- | --- | --- |
| Router `.CFG`, JFFS backup, `homenet-backup` folder with `nvram-lists-*.txt` | Yes (Wi-Fi keys, admin password) | Off the network: a laptop and an encrypted cloud drive. **Not in a Git repo** |
| `a7-backup-*.tar.gz` | Yes (Wi-Fi keys) | Same. The newest file also in the password manager or an encrypted archive |
| Homebridge backup archive | Yes | Same |
| etcd snapshot and k3s token | Yes | Same |
| Seerr folder archive | Yes (API keys) | Same |
| Media apps: Sonarr and Radarr backup zips, Plex data folder and plist, Jackett folder, `qBittorrent.ini` and `BT_backup` | Yes (API keys, Plex token, Web UI login, indexer logins) | Same. The Plex folder is large; an external disk that is not the media volume is fine if it is encrypted |
| Exported live configuration | Possibly | Same, or delete after comparing |
| This repo | No | A Git host |

## Check it

| Check | Run on | Command | Pass |
| --- | --- | --- | --- |
| OpenWrt archive is readable | Your computer | `tar -tzf <file> \| head -30` | Lists `etc/config/network`, `etc/config/wireless` and others |
| Snapshot exists | server-1 | `sudo ls -la /var/lib/rancher/k3s/server/db/snapshots/` | A `manual-<date>` file with today's date |
| Token is saved with the snapshot | Your computer | Look in the backup folder | The token file sits beside the snapshot it belongs to |
| Nothing secret is staged | Your computer, in the repo | `git status --short` and `git check-ignore -v <file>` | No backup or token file listed as new; `check-ignore` names the matching pattern |
| No real secret in tracked files | Your computer, in the repo | `git grep -n -i -E 'password\|token\|secret\|psk' -- . \| grep -v '<'` | Only lines that are comments, key names or placeholders |

## Secrets: what exists and where it is used

Every one of these appears in the repo only as a `<PLACEHOLDER>` or not at all.

| Secret | Placeholder | Used in |
| --- | --- | --- |
| k3s join token | `<K3S_TOKEN>` | `/etc/rancher/k3s/config.yaml` on `server-2`, `server-3` and `server-4` ([config files](../../files/k3s/config/)) |
| Pi-hole admin password | `<PIHOLE_ADMIN_PASSWORD>` | Kubernetes Secret `pihole-admin` in namespace `pihole` |
| TP-Link / Kasa account | `<KASA_ACCOUNT_EMAIL>`, `<KASA_ACCOUNT_PASSWORD>` | Homebridge Kasa plugin |
| Axis camera login | `<AXIS_USER>`, `<AXIS_PASSWORD>` | Homebridge camera plugin (`source` lines) |
| Wyze camera RTSP login | `<WYZE_RTSP_USER>`, `<WYZE_RTSP_PASSWORD>` | Homebridge camera plugin (`source` lines) |
| Wyze account, API key and key ID | not in any file | Homebridge Wyze plugin |
| Resideo consumer key and secret, access and refresh tokens | not in any file | Homebridge Resideo plugin |
| Cloudflare tunnel token | not in any file | `cloudflared service install <TOKEN>` on `server-1` |
| Cloudflare account login | | Cloudflare dashboard |
| Router admin password, Wi-Fi keys (`<WIFI_PASSWORD>`), IoT Wi-Fi key | | Router GUI; also inside the `.CFG` and the OpenWrt backup |
| OpenWrt AP root password, stock AP admin password | | Each AP |
| Sonarr API key | `<SONARR_API_KEY>` | Seerr; Prowlarr if used; read from `~/.config/Sonarr/config.xml` by [`media-health.sh`](../../files/media/media-health.sh), never printed |
| Radarr API key | `<RADARR_API_KEY>` | Seerr; Prowlarr if used; Radarr's `config.xml` |
| Jackett API key and admin password | `<JACKETT_API_KEY>`, `<JACKETT_ADMIN_PASSWORD>` | The Torznab indexer entries in Sonarr and Radarr; `ServerConfig.json` |
| Plex token | `<PLEX_TOKEN>` | The Plex Connect entries in Sonarr and Radarr, Seerr; stored in the Plex preferences plist as `PlexOnlineToken` |
| qBittorrent Web UI user and password | `<QBIT_PASSWORD>` | The download client in Sonarr and Radarr; a hash of it in `qBittorrent.ini` |
| VPN account login | | The VPN app on the torrent PC |
| Indexer site logins | | Jackett or Prowlarr |
| kubeconfig (`/etc/rancher/k3s/k3s.yaml`) | | Cluster admin access. Never copy it into the repo |

Give each service its own password. One password shared by the cameras, the device accounts and Pi-hole means one leak exposes all of them.

## What must never be committed

The repo's `.gitignore` contains these patterns:

| Pattern | Stops |
| --- | --- |
| `*.secret`, `*.secrets`, `secrets/` | Anything you name as a secret |
| `*-token.txt`, `k3s-token*` | The k3s token and other tokens saved to a file |
| `*.CFG`, `*.cfg.bak` | Router settings backups |
| `a7-backup*.tar.gz` | OpenWrt AP backups |
| `jffs-*.tar*` | Router JFFS backups |
| `nvram-lists-*.txt` | The router's per-device lists (names, MAC addresses, reservations) |
| `*-deployed.yaml` | Copies of values files with real values filled in |
| `kubeconfig*`, `k3s.yaml` | Cluster admin credentials |
| `live-export/` | Exported live configuration |
| `.DS_Store`, `__MACOSX/` | macOS clutter |

Also never commit, even though no pattern catches them:

- A Helm values file with a real password in it. Put passwords in a Kubernetes Secret and reference the Secret, as [values.yaml](../../files/pihole/values.yaml) does for Pi-hole.
- A Homebridge `config.json` or backup archive.
- An etcd snapshot.
- Any media app config or backup: Sonarr's and Radarr's `config.xml` (holds the API key), Jackett's `ServerConfig.json`, Plex's `Preferences.xml` (the Linux form of its settings) or `com.plexapp.plexmediaserver.plist` (macOS), qBittorrent's `qBittorrent.ini`, and the Sonarr or Radarr backup zips.
- Screenshots or pasted terminal output that show a token.

> **Pitfall:** `.gitignore` does nothing for a file that is already tracked. If one slipped in, remove it with `git rm --cached <file>`, commit, and then treat its contents as exposed (next section), because it is still in the history.

## If a secret was exposed

Rotate it. Making a repository private afterwards, or deleting the message, does not undo the exposure.

These all count as exposed:

- A secret committed to a repository that was public at any time, even briefly. Check the history, not only the current files: `git log -p -S'adminPassword' -- files/pihole/values.yaml` shows every commit that touched that key.
- **A `config.json`, a kubeconfig, a token or a values file pasted into a chat, a forum post or an issue.** The whole Homebridge `config.json` holds every plugin's credentials at once.
- A backup archive sent or stored unencrypted somewhere others can read.

| What | How to rotate |
| --- | --- |
| Pi-hole admin password | Recreate the `pihole-admin` Secret with a new value and restart the pods ([Pi-hole](../apps/pihole.md)) |
| Camera logins (Axis, Wyze RTSP) | Each camera's own settings; then the `source` lines in the camera plugin config ([Homebridge cameras](../apps/homebridge-cameras.md)) |
| TP-Link / Kasa account, Wyze account, and anything else that shared a password | Each service's own settings; then update the Homebridge plugin configs |
| Wyze API key | Wyze developer console: delete the key, create a new one, update the plugin |
| Resideo consumer secret and tokens | Resideo developer site: regenerate the app's secret. Put the new key and secret in the plugin and link the account again ([Homebridge](../apps/homebridge.md)) |
| k3s join token | `k3s token rotate`, then the new token on every other server ([k3s HA cluster](../kubernetes/k3s-ha-cluster.md)). **Not verified** by the author |
| Cluster admin certificate (kubeconfig) | `sudo k3s certificate rotate` on each server, one at a time, with k3s stopped before and started after. **Not verified** by the author; read the k3s certificate documentation first |
| Cloudflare tunnel token | Cloudflare dashboard: delete the tunnel or refresh its token, then reinstall the `cloudflared` service with the new token |
| Sonarr, Radarr or Jackett API key | Regenerate it in the app (Settings > General in Sonarr and Radarr; the dashboard in Jackett), then update every app that uses it: Seerr, the Torznab entries, Prowlarr. **Not verified** by the author |
| Plex token | Sign the server out and in again, or remove the device under your Plex account's authorised devices; then **Authenticate with Plex.tv** again in Sonarr and Radarr. **Not verified** by the author |
| qBittorrent Web UI password | **Tools > Options > Web UI**; then the download client in Sonarr and Radarr |
| Wi-Fi keys, router and AP admin passwords | Each device's GUI; then take new backups, because the old ones hold the old keys |

After rotating, the old value in a repository's history no longer matters. If you want it gone anyway, the simplest way is a new repository created from the current files with no history.

## Publishing a homelab repo safely

A homelab repo is useful to others, and it describes your home in detail. Before making one public:

1. **Use a separate repository with its own history.** Never switch a private repository to public if a secret or personal detail was ever committed to it: the history goes public with it.
2. Generate the public copy from the private one with a script or a find-and-replace table, rather than editing by hand, and scan the result for anything the table should have caught. Run it again after every change and read the diff before pushing.
3. Replace these:

   | Scrub | Replace with |
   | --- | --- |
   | Your real domain | `example.com` names |
   | People's names, including in device and host names | Neutral names (`server-1`, `ap-openwrt`) |
   | MAC addresses | Obviously made-up ones, or remove them |
   | Serial numbers | Remove |
   | Your local IPv6 (ULA) prefix | A documentation-style prefix such as `fd00:1234:5678:50::/64`. A real ULA prefix is random and therefore identifies your network |
   | Wi-Fi names (SSIDs) | Generic names. SSIDs are mapped to physical locations by public databases |
   | Public IP addresses, tunnel IDs, account emails | Placeholders |

4. Private IPv4 addresses (`192.168.x.x`) can stay. They are the same in millions of homes and identify nothing.
5. Decide whether to publish your device list at all. A list of what you own, with DNS host entries for each, is optional; delete it from the public copy if you prefer.
6. When you add a new personal word (a new device name, a second domain), add it to the replacement table first.
7. Keep the replacement table itself out of the public copy. It holds the real values.

## Pitfalls

| What happens | Why | How to avoid or recover |
| --- | --- | --- |
| The `.CFG` will not restore | It only restores onto the same firmware family | Keep the JFFS backup and the bootstrap script as the second way back |
| A snapshot cannot be restored | The token it was made under is gone | Always copy the token with the snapshot |
| Homebridge accessories all need re-pairing | The pairing lived only on one node's disk | Download the UI backup after every plugin or accessory change |
| A password appears in `helm get values` output | It was set inline in the values file | Move it to a Secret before applying the repo's values file |
| The AP backup lacks the IoT network | It was taken before that change | Run the backup script after every change; it checks for this |
| Old backups hold old Wi-Fi keys | Backups are point-in-time | After rotating, take new backups and delete or re-encrypt old ones |
| The only copy of a backup is on the device it backs up | Router USB drive, node `/tmp` | Copy off the device the same day |

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `a7-backup.sh` reports a FAIL on the reboot check | The weekly reboot line is not in the AP's crontab | Add it under **System → Scheduled Tasks** ([Maintenance](maintenance.md)), then run the backup again |
| `a7-backup.sh`: "A7_IP must be an IPv4 address" | A host name or IPv6 address was passed | Pass the IPv4 address |
| Bootstrap `backup` says no USB drive found | The drive is not mounted | Copy `/tmp/homenet-backup` now; then check the drive |
| `scp` to or from the router fails with a protocol error | The router's SSH server has no SFTP | Use `scp -O` (legacy protocol), as in the command above |
| `git status` shows a backup file as untracked | Its name does not match a pattern | Move it out of the repo folder; add a pattern if it will recur |

## References

- [k3s: etcd-snapshot](https://docs.k3s.io/cli/etcd-snapshot): on-demand and scheduled snapshots, defaults, and why a restore needs the original token.
- [k3s: Backup and restore](https://docs.k3s.io/datastore/backup-restore): what to back up for each k3s datastore type.
- [k3s: token](https://docs.k3s.io/cli/token): what the server token protects and how `k3s token rotate` works.
- [k3s: certificate](https://docs.k3s.io/cli/certificate): checking and rotating k3s certificates.
- [Homebridge wiki: Backup and Restore](https://github.com/homebridge/homebridge/wiki/Backup-and-Restore): the UI backup archive and manual alternatives.
- [Git: gitignore](https://git-scm.com/docs/gitignore): pattern syntax, and why ignoring does not affect files already tracked.
- [GitHub Docs: Removing sensitive data from a repository](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository): rewriting history, and why rotating the secret comes first.
- [Asuswrt-Merlin wiki: User scripts](https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts): what lives in `/jffs/scripts`, which the JFFS backup protects.
