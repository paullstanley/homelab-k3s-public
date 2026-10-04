# 13. Backups and secrets

This repo holds the **configuration**. It does not hold data or secrets. A full recovery needs this repo, the backups below, and the password manager.

## Take these backups now

### XT8

1. Web UI: **Administration → Restore/Save/Upload Setting → Save setting**. The `.CFG` file restores every GUI setting, onto the same firmware family only.
2. Same page: **Backup JFFS partition**.
3. **Paste on: the router.**

```sh
sh /jffs/xt8-bootstrap.sh backup
```

It saves `/jffs/scripts`, `/jffs/configs`, `/jffs/addons` and the per-device lists (DNS Director clients, DHCP reservations, client names) to the USB drive and prints the `scp` line to copy them to your Mac.

### Archer A7

**Paste on: your Mac.**

```sh
ssh root@192.168.50.3 'sysupgrade -b /tmp/a7-backup.tar.gz'
scp -O root@192.168.50.3:/tmp/a7-backup.tar.gz ~/Documents/network-rebuild/
```

This is the only copy of the A7's Wi-Fi settings.

### Homebridge

Homebridge UI → **Settings → Backup → Download Backup Archive**. This holds `config.json`, the plugin list and the HomeKit pairing. **It contains passwords** (cameras, TP-Link, Wyze, Resideo). It lives on k3sprimary's disk only; if that disk dies without this archive, every accessory must be re-paired.

### Cluster

**Paste on: k3sprimary.**

```bash
sudo k3s etcd-snapshot save --name manual-$(date +%Y%m%d)
sudo ls -la /var/lib/rancher/k3s/server/db/snapshots/
```

Copy the newest snapshot file and `/var/lib/rancher/k3s/server/token` off the Pi. A snapshot can only be restored with the token it was made under.

k3s also takes its own snapshots on a schedule (by default twice a day, keeping five) on each server.

To capture the live configuration for comparison with this repo:

```bash
bash scripts/export-live-config.sh
```

It writes to `live-export/`, which git ignores, with tokens and passwords replaced by placeholders.

### Seerr

Seerr's data is one folder on k3sprimary. Find and copy it:

```bash
sudo kubectl -n seerr get pvc
sudo ls /var/lib/rancher/k3s/storage/ | grep seerr
sudo tar -czf /tmp/seerr-config.tar.gz -C /var/lib/rancher/k3s/storage "$(sudo ls /var/lib/rancher/k3s/storage/ | grep seerr | head -1)"
```

### Mac VM

```bash
cp ~/.lima/k3s-mac/lima.yaml k3s/lima/k3s-mac.yaml
```

Nothing else in the VM needs saving; it is a cluster member and rebuilds from [05](05-mac-node-lima.md).

### Where the backups go

| Backup | Contains secrets | Keep |
| --- | --- | --- |
| XT8 `.CFG`, JFFS backup, `nvram-lists-*.txt` | Yes (Wi-Fi keys, admin password) | Off the network: laptop and a cloud drive. **Not in this repo** |
| `a7-backup.tar.gz` | Yes (Wi-Fi keys) | Same |
| Homebridge backup archive | Yes | Same |
| etcd snapshot and k3s token | Yes | Same |
| Seerr folder | Yes (API keys) | Same |
| This repo | No | GitHub, private |

`.gitignore` already refuses the usual file names for all of these.

## Secrets: what exists and where it is used

Every one of these appears in this repo only as a `<PLACEHOLDER>`.

| Secret | Placeholder | Used in |
| --- | --- | --- |
| k3s join token | `<K3S_TOKEN>` | `/etc/rancher/k3s/config.yaml` on funkyfresh, k3snode2, the Mac VM |
| Pi-hole admin password | `<PIHOLE_ADMIN_PASSWORD>` | Kubernetes Secret `pihole-admin` in namespace `pihole` |
| TP-Link / Kasa account | `<KASA_ACCOUNT_EMAIL>`, `<KASA_ACCOUNT_PASSWORD>` | Homebridge Kasa plugin |
| Axis camera login | `<AXIS_USER>`, `<AXIS_PASSWORD>` | Homebridge camera plugin |
| Wyze camera RTSP login | `<WYZE_RTSP_USER>`, `<WYZE_RTSP_PASSWORD>` | Homebridge camera plugin |
| Wyze account, API key, key ID | not in any file here | Homebridge Wyze plugin |
| Resideo consumer key and secret | not in any file here | Homebridge Resideo plugin |
| Cloudflare tunnel token | not in any file here | `cloudflared service install <TOKEN>` on k3sprimary |
| Cloudflare account login | | dashboard |
| XT8 admin password, Wi-Fi keys, IoT Wi-Fi key | | router GUI |
| A7 root password, AX21 admin password | | each AP |
| Plex, Sonarr, Radarr API keys | | Seerr setup |
| kubeconfig (`/etc/rancher/k3s/k3s.yaml`) | | cluster admin; never copy into the repo |

## Private and public copies

There are two copies of this repository.

| Copy | Contains | Where it lives |
| --- | --- | --- |
| **Private** (this one) | Real domain, names, MAC addresses, serials, device list. Passwords and tokens are still placeholders | A **private** GitHub repository |
| **Public** | The same files with the personal details replaced by stand-ins | A separate repository, safe to share |

The public copy is generated, never edited by hand. **Paste on: your Mac**, in the root of the private repo:

```bash
python3 scripts/make-public.py ../homelab-k3s-public
```

It rewrites the target folder, replaces everything in its table, and then scans the result; if anything personal is left it says which file and stops with an error. The script itself is not copied, because its table holds the real values.

Rules for the public copy:

- **It must be its own repository with its own history.** Never make the private repository public: its history contains a real password.
- Run the script again after every change to the private repo, and read the diff before pushing.
- If you add a new personal word (a new family member's device, a second domain), add it to `REPLACE` or `NAMES` at the top of the script first.
- Private IPv4 addresses (192.168.x.x) are left as they are. They are the same in millions of homes and identify nothing.
- The device list is kept, with names and MACs replaced. If you would rather not publish what devices you own at all, delete the "Every device on the network" table from the public `docs/01-inventory.md` and the host lines from the public `pihole/values.yaml` before pushing.

## Rotate these

**The `pihole/values.yaml` that was in this repository contained the Pi-hole admin password in plain text.** GitHub showed the repository as public on 4 October. Assume the password was read.

The September runbook also recorded that one password was shared by Pi-hole, Wyze, Kasa and the cameras, and that a Wyze API key and the cluster's admin kubeconfig key had been pasted into a chat. The k3s join token was pasted into a chat on 3 October.

| What | How |
| --- | --- |
| Pi-hole admin password | [07](07-pihole.md), Step 2 |
| Anything else that used the same password: Wyze account, TP-Link/Kasa account, camera logins | Each service's own settings; then update the Homebridge plugin configs |
| Wyze API key | Wyze developer console: delete the key, create a new one, update the plugin |
| k3s join token | [04](04-k3s-cluster.md), "Rotating the join token" |
| Cluster admin certificate (kubeconfig) | `sudo k3s certificate rotate` on each server, one at a time, restarting k3s after each. Not run here; read the k3s certificate documentation first |

The git history confirms how long: `adminPassword:` with a real value is in `pihole/values.yaml` from the **first commit, 18 April 2025**, onwards. Whatever passwords that file held over that period should all be treated as read.

Making the repository private does not undo the exposure, and the old password is still in the repository's **git history**. After rotating, that no longer matters. If you want it gone anyway, the simplest way is a new repository created from these files with no history.
