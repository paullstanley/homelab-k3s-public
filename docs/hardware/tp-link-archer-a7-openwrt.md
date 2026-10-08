# TP-Link Archer A7 v5 on OpenWrt as a bridged access point

You end up with an Archer A7 that only does Wi-Fi: it bridges wireless clients onto your existing LAN and leaves routing, DHCP, DNS and firewalling to your main router. This is often called a "dumb" access point. It also reboots itself once a week and can be rebuilt in five minutes from one backup file.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | TP-Link Archer A7 v5, OpenWrt 25.12.5 (an earlier build of the same setup ran on 25.12.1). This model uses the older `swconfig` switch driver, not DSA |
| **Also works for** | Other OpenWrt 25.12.x devices with a `swconfig` switch should behave the same, with different switch port numbers. Not tested by the author. Devices that use DSA have no **Network → Switch** page, so the switch parts do not apply |
| **Time** | 5 minutes from a backup; 30 to 45 minutes from scratch |
| **You need first** | A main router that is the gateway and DHCP server for the LAN. Optional: [Local-only IPv6](../network/local-only-ipv6.md) (the script gives the AP a static IPv6 address in that prefix), [Isolated IoT network](../network/isolated-iot-network.md) (a second SSID) |

## How it works

OpenWrt ships as a router: it has a WAN side, a LAN side, a DHCP server, a DNS forwarder and a firewall between the two. A bridged access point needs none of that. The setup script:

- gives the LAN bridge (`br-lan`) a fixed address on your existing network, with your router as gateway;
- switches off the three services that would compete with your router: `dnsmasq` (DHCP and DNS), `odhcpd` (IPv6 addresses and router advertisements) and `firewall`;
- gives the AP one static local IPv6 address, and makes sure it never advertises a prefix of its own;
- schedules a weekly reboot.

Wi-Fi clients are then just bridged to the cable. They get their address, DNS server and IPv6 prefix from the main router, exactly as wired devices do.

Everything is stored by UCI (OpenWrt's configuration system, the files in `/etc/config/`), so it survives reboots. There is no startup script.

The script does **not** configure Wi-Fi. SSIDs, keys, roaming options and MAC filter lists are set by hand in LuCI (OpenWrt's web interface) or restored from a backup.

## Before you start

Decide or gather these:

| Item | Example | Notes |
| --- | --- | --- |
| The AP's address | `192.168.50.3` | Outside your router's DHCP pool |
| Gateway | `192.168.50.1` | Your router |
| DNS server for the AP itself | `192.168.50.11` | The example is a Pi-hole. Use your router's address if you have no separate DNS server |
| The AP's IPv6 address | `fd00:1234:5678:50::3/64` | Only meaningful if your LAN has that prefix. See [Local-only IPv6](../network/local-only-ipv6.md) |
| Reboot time | Wednesday 03:30 | Cron format `30 3 * * 3` |
| Which port is the uplink | a LAN port | See [The switch page and the uplink port](#the-switch-page-and-the-uplink-port) |

The four address values have defaults at the top of [`files/archer-a7/a7-ap-setup.sh`](../../files/archer-a7/a7-ap-setup.sh) (`A7_IP`, `A7_IP6`, `GATEWAY`, `PIHOLE4`). If yours differ, either edit them there or set them as environment variables in front of the command, for example `A7_IP=192.168.1.3 GATEWAY=192.168.1.1 PIHOLE4=192.168.1.11 A7_IP6=fd00:aaaa:bbbb:1::3/64 sh /tmp/a7-ap-setup.sh`. The reboot time is overridden the same way with `REBOOT_AT`.

If the device already runs OpenWrt and you have a backup of it, use the restore path in Step 1 and skip the rest.

## Steps

### Step 1. Restore from a backup, if you have one

This is the five-minute path.

1. In LuCI open **System → Backup / Flash Firmware → Restore backup**.
2. Choose the newest `a7-backup-<date>-<time>.tar.gz` (made by the [backup script](#back-up-the-settings)).
3. Upload it. The device restores and reboots.

That brings back everything: the address, Wi-Fi names and keys, MAC filter lists, roaming settings, the IoT network and the weekly reboot.

> **Pitfall:** A freshly flashed A7 answers on `192.168.1.1`. The restore also brings back the `192.168.50.3` address, so the page stops answering after the reboot. Move the cable to the main network and open `http://192.168.50.3`.

If you have no backup, continue.

### Step 2. Flash OpenWrt

Flashing is specific to the hardware revision and changes between releases, so it is not repeated here. Open the [OpenWrt Firmware Selector](https://firmware-selector.openwrt.org/), search for "Archer A7 v5", and follow the installation instructions on the device's page in the OpenWrt Table of Hardware (the selector links to it).

When it is done, connect a computer straight to one of the A7's LAN ports. A fresh OpenWrt install is at `192.168.1.1`.

### Step 3. Set a root password

In LuCI at `http://192.168.1.1`: **System → Administration → Router Password**. Set one. A fresh unit has none, and SSH login as `root` needs it.

### Step 4. Run the setup script

Copy the script to the AP and run it. `scp -O` uses the old copy protocol, which is needed because OpenWrt's default SSH server has no SFTP.

**Run on: your computer**, from the root of this repo.

```sh
scp -O files/archer-a7/a7-ap-setup.sh root@192.168.1.1:/tmp/
ssh root@192.168.1.1 'sh /tmp/a7-ap-setup.sh'
```

Your SSH session drops when the address changes to `192.168.50.3`. That is expected. It also means the "verify" lines the script prints at the end may not reach you; run the checks in [Check it](#check-it) afterwards.

To pick a different reboot time (cron format: minute, hour, day of month, month, day of week), for example Sunday 04:00:

```sh
ssh root@192.168.1.1 'REBOOT_AT="0 4 * * 0" sh /tmp/a7-ap-setup.sh'
```

The script is safe to run again on a configured AP (use `192.168.50.3` in both commands). It replaces its own settings instead of adding duplicates.

The script first saves a settings backup to `/tmp/a7-before-<date>-<time>.tar.gz` on the AP. `/tmp` is RAM and is lost at reboot. To keep it:

**Run on: your computer.**

```sh
scp -O 'root@192.168.50.3:/tmp/a7-before-*.tar.gz' .
```

### Step 5. Cable it to the main network

Connect one of the A7's **LAN** ports (not the WAN port) to your main network. Then open `http://192.168.50.3`.

> **Why:** With the stock switch layout the WAN port is in a separate VLAN that is not bridged to the LAN. See [The switch page and the uplink port](#the-switch-page-and-the-uplink-port).

### Step 6. Configure the Wi-Fi

In LuCI: **Network → Wireless**. Edit each radio's network.

| Setting | Value | Why |
| --- | --- | --- |
| Both radios | Enabled, attached to network `lan` | Clients are bridged to the cable |
| SSIDs | `Home` on 2.4 GHz, `Home5g` on 5 GHz | The same names as the main router, if you want devices to move between them on one name |
| Security | WPA2/WPA3-Personal mixed mode (`sae-mixed`), key `<WIFI_PASSWORD>` | The same key as the main router for roaming on one name |
| 2.4 GHz channel | 11, 20 MHz width | The example main router uses channel 1. Pick a non-overlapping channel (1, 6 or 11) that your router is not on |
| 5 GHz channel | 149, 80 MHz width | The example main router uses 36. With 149 at 80 MHz, LuCI showed 153 as the control channel on the tested unit |
| WPS | Off | |
| `multicast_to_unicast_all` | `1` on both radios | Converts multicast frames to unicast per client, which is more reliable for discovery traffic over Wi-Fi |
| 802.11k and 802.11v, with static neighbor reports | On, if you set them up | They tell clients about the other access points' radios so they roam sooner. The neighbor list is entered by hand per radio |
| MAC filter | Optional deny list per SSID | Keeps named devices off this AP |

`multicast_to_unicast_all` has no checkbox on every LuCI build. Over SSH it is set per SSID. List the SSID sections first, then set the option on each one that serves the main LAN.

**Run on: the access point** (`ssh root@192.168.50.3`).

```sh
uci show wireless | grep '=wifi-iface'
uci set wireless.default_radio0.multicast_to_unicast_all='1'
uci set wireless.default_radio1.multicast_to_unicast_all='1'
uci commit wireless
wifi reload
```

`default_radio0` and `default_radio1` are the section names on a default install; use the names the first command printed.

> **Pitfall:** The MAC filter lists, the 802.11k/v options and the static neighbor reports exist only in the device's own configuration. Nothing in this repo recreates them. The settings backup is their only copy, which is one more reason to take one (see [Back up the settings](#back-up-the-settings)).

### Step 7. Take a backup

Run the backup script in [Back up the settings](#back-up-the-settings) now, and again after every later change.

## What the setup script sets

[`files/archer-a7/a7-ap-setup.sh`](../../files/archer-a7/a7-ap-setup.sh), in order:

| Setting | Value | Why |
| --- | --- | --- |
| `sysupgrade -b /tmp/a7-before-<timestamp>.tar.gz` | A settings backup, taken first | A way back. It lives in RAM: copy it off before a reboot |
| `network.lan.proto`, `ipaddr`, `netmask`, `gateway`, `dns` | `static`, `192.168.50.3`, `255.255.255.0`, `192.168.50.1`, `192.168.50.11` | The management address. The gateway and DNS entries only serve the AP itself (time sync, package downloads) |
| `network.globals.ula_prefix` | deleted | OpenWrt generates its own random local IPv6 prefix at first boot. Left in place, clients would be offered a second IPv6 range |
| `network.lan.ipv6` | `1` | IPv6 on for the interface |
| `network.@device[N].ipv6` for the device named `br-lan` | `1` | **Required.** Without this device-level flag the bridge itself stays IPv6-off, whatever the interface says. The script searches for the `br-lan` device section and stops with an error if there is none |
| `network.lan.ip6assign` | deleted | The AP must not carve out and hand on a prefix |
| `network.lan.ip6addr` | deleted, then set to `fd00:1234:5678:50::3/64` | One static management address. Deleted first so that re-runs never add it twice. No IPv6 gateway is set |
| `network.lan.delegate` | `0` | No prefix delegation on this interface |
| `dhcp.lan.ignore` | `1` | No DHCPv4 server on the LAN |
| `dhcp.lan.ra`, `dhcpv6`, `ndp` | `disabled` for all three | No router advertisements, no DHCPv6, no neighbor-discovery proxy. The AP never hands out addresses |
| `odhcpd`, `dnsmasq`, `firewall` | each `disable`d (will not start at boot) and `stop`ped | A bridged AP needs none of them. Any one left running can answer clients before the real router does |
| `/etc/crontabs/root` | `30 3 * * 3 sleep 70 && touch /etc/banner && reboot`, then `cron` enabled and restarted | Weekly reboot. Any older line containing `touch /etc/banner && reboot` is replaced, so re-runs leave exactly one. See [Weekly reboot](#weekly-reboot) |
| `apk del uneighbord` | package removed | It only exchanges neighbor information with other OpenWrt access points. With a single OpenWrt AP it did nothing useful and logged an error every 30 seconds |
| `/etc/init.d/network restart` | full restart | **`network reload` was not enough** to bring IPv6 up on the bridge. Only a restart did |

It ends by printing the IPv4 and IPv6 addresses on `br-lan`, the reboot line from `crontab -l`, any IPv6 default routes (expect none), any `odhcpd` or `dnsmasq` processes (expect none), and whether a DNS lookup through `192.168.50.11` works.

> **Not verified:** The addressing, IPv6 and service parts of this script were run on the tested device. The weekly-reboot lines were added later and were syntax-checked only; they had not been run on a real device when this was written.

## The switch page and the uplink port

The Archer A7 v5 has one internal switch chip. OpenWrt shows it at **Network → Switch**. Each row is a VLAN (a numbered virtual network inside the switch); each column is a port:

| Column on the Switch page | Switch port number |
| --- | --- |
| CPU (eth0) | 0 |
| WAN | 1 |
| LAN 1 | 2 |
| LAN 2 | 3 |
| LAN 3 | 4 |
| LAN 4 | 5 |

A port can be **off**, **untagged** (ordinary traffic) or **tagged** (traffic carries a VLAN number) in each row.

There are two workable layouts. Know which one you have, because the port you cable to the main network is the "uplink port", and the IoT script needs its number.

| Layout | Switch page | Uplink | Used by |
| --- | --- | --- | --- |
| **Stock switch, LAN-port uplink** (recommended) | Untouched. VLAN 1 holds LAN 1 to 4; VLAN 2 holds the WAN port | Any LAN port. `UPLINK_PORT` is 2, 3, 4 or 5 | What you get from `a7-ap-setup.sh` alone. Simpler: leave the switch alone and let the script disable DHCP, advertisements and the firewall |
| **WAN port merged into the LAN VLAN** | VLAN 1 holds the WAN port and all four LAN ports untagged; the firewall's `wan` zone was deleted by hand | Any port, including WAN. With the cable in the WAN port, `UPLINK_PORT=1` | An older method. Gives you a fifth usable port. The device this page was tested on is still in this layout, with the WAN port as uplink |

Either is fine. The trap is mixing them up:

> **Pitfall:** `UPLINK_PORT` for [`a7-iot-ssid.sh`](../../files/archer-a7/a7-iot-ssid.sh) must be the port that is actually cabled towards the router. `UPLINK_PORT=1` (WAN) is only right if the WAN port has been merged into VLAN 1. After a rebuild with `a7-ap-setup.sh` alone the uplink is a LAN port, and the value is that port's number instead. Read the Switch page before you choose.

> **Pitfall:** The **Port status** row on the Switch page can read "no link" on every port while the page shows REFRESHING. That is a display artefact, not a fault. Wait for the refresh, or trust the fact that you reached the page over one of those ports.

Changes on this page are made row by row; **Add VLAN** creates a row and the first text box of the row is its VLAN ID. Click **Save** on each page you change, then **Save & Apply** once. If LuCI cannot reach the device within 90 seconds of applying, it rolls the change back automatically, which protects you from locking yourself out with a wrong switch setting.

## Weekly reboot

The setup script installs this. To add it to a running AP without re-running the script, open **System → Scheduled Tasks** in LuCI and enter one line:

```
30 3 * * 3 sleep 70 && touch /etc/banner && reboot
```

Or over SSH, edit the same file with `crontab -e`, then make sure cron runs.

**Run on: the access point.**

```sh
/etc/init.d/cron enable
/etc/init.d/cron restart
crontab -l
```

`crontab -l` must print the line once. `30 3 * * 3` is Wednesday 03:30 in the device's local time, so set the time zone under **System → System** first.

> **Why `sleep 70 && touch /etc/banner`:** It prevents a reboot loop. The A7 has no battery-backed clock (no RTC). At boot, OpenWrt sets the time from the newest file in `/etc` and keeps that until NTP answers. If the device rebooted at 03:30:00 exactly, the newest file could still be older than 03:30, the clock would come back up before the scheduled minute, and cron would fire the reboot again. Waiting 70 seconds and then touching a file in `/etc` makes the restored time land after the scheduled minute.

> **Pitfall:** The line belongs in **System → Scheduled Tasks** (`/etc/crontabs/root`). It does **not** go in **System → Startup → Local Startup** (`/etc/rc.local`). That file runs once at every boot; a reboot command there reboots the device forever. Leave Local Startup at its default.

> **Not verified:** The cron line follows OpenWrt's documented pattern, but the author had not confirmed a completed weekly reboot on the device when this was written. After the first scheduled time, check `uptime` on the AP: it must show less than a week.

## Back up the settings

[`files/archer-a7/a7-backup.sh`](../../files/archer-a7/a7-backup.sh) pulls a settings backup off the AP onto your computer and checks it.

**Run on: your computer**, from the root of this repo.

```sh
sh files/archer-a7/a7-backup.sh
sh files/archer-a7/a7-backup.sh 192.168.50.3 root ~/homelab-backups/archer-a7
```

The two lines do the same thing; the second spells out the defaults.

| Argument | Default | Meaning |
| --- | --- | --- |
| `A7_IP` | `192.168.50.3` | The AP's IPv4 address. Anything but digits and dots is refused |
| `USER` | `root` | SSH user |
| `DEST` | `~/homelab-backups/archer-a7` | Folder to save into. Created if missing |
| `KEEP` (environment variable) | `10` | How many backups to keep. `KEEP=20 sh files/archer-a7/a7-backup.sh` |

`ssh` asks for the AP's password once. The password is deliberately not an argument, because arguments end up in shell history. `-h` or `--help` as the first argument prints the usage text.

| What it does | Why |
| --- | --- |
| Runs `sysupgrade -b -` on the AP and saves the output locally as `a7-backup-<date>-<time>.tar.gz` | OpenWrt's own backup format, the one LuCI restores. Writing to standard output leaves nothing on the AP |
| Checks: the archive opens; it has `etc/config/network` and `etc/config/wireless`; the wireless config has an SSID on network `iot`; the network config has the bridge `br-iot`; `etc/crontabs/root` has the reboot line. Prints PASS or FAIL for each | A backup that silently lacks the IoT network or the reboot is caught on the day you take it, not on the day you need it |
| Deletes the file and stops if the archive is unreadable or SSH failed | Never leaves a broken backup that looks like a good one |
| Sets the file to owner-read-only (`chmod 600`) | **It contains the Wi-Fi passwords** |
| Keeps the newest `KEEP` files and deletes older ones | Older ones are a way back if a change goes wrong |

If you have not added the IoT SSID, the two IoT checks report FAIL. That is correct for your setup; the file is still kept and still restores. The reboot check reports FAIL until the cron line exists.

When to run it:

- once, as soon as the AP works;
- after any change in LuCI or over SSH, before logging out;
- before a firmware upgrade.

To prove a backup is usable without touching the AP, list its contents.

**Run on: your computer.**

```sh
tar -tzf ~/homelab-backups/archer-a7/a7-backup-<date>-<time>.tar.gz | head -30
```

Restore: [Step 1](#step-1-restore-from-a-backup-if-you-have-one).

> **Pitfall:** Never commit a backup to Git, public or private. It holds the Wi-Fi keys and the device's password hash. Keep the working copy in the destination folder and a second copy somewhere off that computer, such as a password manager or an encrypted archive. Add `a7-backup*.tar.gz` to `.gitignore` as a backstop. See [Backups and secrets](../operations/backups-and-secrets.md).

> **Why it is not automated:** The AP changes a few times a year. An unattended job would need a stored SSH key with root on the AP, and a check you watch pass is worth more than a scheduled job nobody reads. If that changes for you, the same script can run from a scheduler on an always-on machine with an SSH key.

> **Not verified:** The backup script was syntax-checked and run against stand-in commands. It had not been run against a real device when this was written.

## If you also have an isolated IoT network

The AP can broadcast your router's isolated guest/IoT network as a second 2.4 GHz SSID, so IoT devices near it have a closer access point. In short: the router sends that network down the cable as a tagged VLAN (501 on the tested ASUS firmware); the AP takes the VLAN off its uplink port, bridges it to a new SSID with client isolation, and takes no address on it. The router stays the gateway and DHCP server for that network.

The whole procedure, by LuCI and by script ([`files/archer-a7/a7-iot-ssid.sh`](../../files/archer-a7/a7-iot-ssid.sh)), is on [Isolated IoT network](../network/isolated-iot-network.md). Run it after the setup on this page, and take a new backup afterwards.

## If you also have other access points

An OpenWrt AP is not part of a vendor mesh such as ASUS AiMesh. A phone moving between the mesh's coverage and this AP's coverage does a normal reconnect, not a seamless handoff, even with the same SSID and key. 802.11k/v neighbor reports shorten the gap but do not remove it. The A7 has no 6 GHz radio, so a 6 GHz SSID exists on the main router only.

## Check it

**Run on: the access point** (`ssh root@192.168.50.3`).

```sh
ip -4 addr show br-lan | grep inet
ip -6 addr show br-lan
ip -6 route | grep default
ps | grep -E 'odhcpd|dnsmasq' | grep -v grep
crontab -l | grep reboot
nslookup openwrt.org 192.168.50.11
```

Expected:

| Command | Result |
| --- | --- |
| `ip -4 addr` | `192.168.50.3/24` |
| `ip -6 addr` | A link-local `fe80::` address and `fd00:1234:5678:50::3/64`, listed **exactly once** |
| `ip -6 route \| grep default` | Nothing. The AP has no IPv6 default route |
| `ps \| grep` | Nothing. Neither service runs |
| `crontab -l` | One line ending `sleep 70 && touch /etc/banner && reboot` |
| `nslookup` | An answer |

If your LAN has local IPv6 ([Local-only IPv6](../network/local-only-ipv6.md)), also:

```sh
ping -6 -c3 fd00:1234:5678:50::1
nslookup openwrt.org fd00:1234:5678:50::11
```

Expect ping replies from the router and a DNS answer.

From a Wi-Fi client joined to this AP: it gets an address from the main router's pool, with the main router as gateway, and reaches the internet.

## Pitfalls

| What happens | Why | Avoid or recover |
| --- | --- | --- |
| No IPv6 address on `br-lan` although `network.lan.ipv6` is `1` | The device-level `ipv6` flag on the `br-lan` device section is not set | The script sets it. By hand: find the section with `uci show network \| grep br-lan`, set `.ipv6='1'`, commit, `network restart` |
| IPv6 settings saved, nothing changes | `/etc/init.d/network reload` does not bring IPv6 up on the bridge | `/etc/init.d/network restart` |
| Clients have two local IPv6 ranges | OpenWrt's own `ula_prefix` is still set and something is advertising it | Delete `network.globals.ula_prefix`; keep `dhcp.lan.ra` disabled and `odhcpd` off |
| The AP's IPv6 address appears twice | `ip6addr` was added as a list entry more than once | Delete then set it (command below) |
| Clients get `192.168.1.x` addresses, or two DHCP servers answer | `dnsmasq` is still running on the AP | `/etc/init.d/dnsmasq disable; /etc/init.d/dnsmasq stop` |
| Nothing works with the cable in the WAN port | Stock switch layout: the WAN port is not in the LAN VLAN | Use a LAN port, or deliberately merge the WAN port (see the switch section) |
| Reboot loop | A reboot line in `/etc/rc.local`, or a cron reboot without the `sleep 70 && touch` guard | Remove it. If the device will not stay up long enough, boot into failsafe mode (see the OpenWrt documentation for your device) and edit the file |
| A log error every 30 seconds from `uneighbord` | It looks for other OpenWrt APs and finds none | `apk del uneighbord` (the script does this) |
| The page stops answering after a restore on a fresh device | The restored address is `192.168.50.3`, the fresh one was `192.168.1.1` | Move the cable to the main network, open the restored address |
| The AP is back at `192.168.1.1` and routing | A factory reset, or a firmware flash without "Keep settings", returns OpenWrt to router mode with DHCP on | Do not plug it into the main LAN in that state. Connect a computer directly, then restore the backup or run the script again |
| Wi-Fi settings gone after a rebuild | The script does not do Wi-Fi; MAC filters and roaming options exist only in the backup | Restore the backup, or re-enter Step 6 |

To fix a duplicated IPv6 address:

**Run on: the access point.**

```sh
uci -q delete network.lan.ip6addr; uci set network.lan.ip6addr='fd00:1234:5678:50::3/64'; uci commit network; /etc/init.d/network restart
```

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `ERROR: no 'br-lan' device section in /etc/config/network` | The network config has no bridge device named `br-lan` (not a default layout) | Check `uci show network`. On a default A7 install the section exists |
| SSH session hangs at "Restarting network" | The address changed under you | Expected. Reconnect to `192.168.50.3` |
| `scp` fails with "sftp-server: not found" | Newer `scp` uses SFTP, which OpenWrt's SSH server lacks | Add `-O` |
| `DNS via Pi-hole: FAILED` at the end of the script | The DNS server at `PIHOLE4` is unreachable or not built yet | Set `PIHOLE4` to a DNS server that exists, for example the router, and run again |
| AP shows no IPv6 on `br-lan` | Device-level `ipv6` not set, or only `reload` was used | Run `a7-ap-setup.sh` again |
| IPv6 ping to the router fails from the AP | The LAN has no such prefix, or the router does not answer on it | [Local-only IPv6](../network/local-only-ipv6.md) |
| Backup script: "could not connect or sysupgrade failed. Nothing saved." | Wrong address, wrong password, or the AP is down | `ssh root@192.168.50.3` by hand first |
| Backup script: FAIL on the two IoT lines | No IoT SSID or bridge on the AP | Expected if you did not add one. Otherwise [Isolated IoT network](../network/isolated-iot-network.md) |
| Backup script: FAIL on the reboot line | No cron line | [Weekly reboot](#weekly-reboot) |
| Switch page shows "no link" everywhere | Display artefact while the page refreshes | Nothing |
| Phones do not roam between this AP and the main router | Different vendors; no shared mesh | Normal. Match SSID and key; optionally set 802.11k/v with neighbor reports |

More symptoms across the whole build: [Troubleshooting](../operations/troubleshooting.md).

## Undo

- **Back to the state before the script:** restore the `/tmp/a7-before-*.tar.gz` file it made (if you copied it off before a reboot) through **System → Backup / Flash Firmware → Restore backup**.
- **Back to a router:** **System → Backup / Flash Firmware → Perform reset**. The device returns to `192.168.1.1` with DHCP on and the firewall running. Unplug it from the main LAN first.
- **Remove only the weekly reboot:** delete the line in **System → Scheduled Tasks**.

## Firmware and updates

The exact factory and sysupgrade image names for the Archer A7 v5, how to check them against `sha256sums`, Attended Sysupgrade versus `sysupgrade -v`, and the move from `opkg` to `apk` in 25.12: [Software and firmware](../operations/software-and-firmware.md#openwrt-on-the-archer-a7-v5). Flashing from TP-Link stock firmware is in [From nothing to a full deployment](../start-here/build-from-nothing.md#step-41-flash-openwrt-onto-the-archer-a7-v5).

## References

- [OpenWrt Firmware Selector](https://firmware-selector.openwrt.org/): finds the right firmware image for the Archer A7 v5 and links to the device's page with flashing instructions.
- [openwrt/openwrt on GitHub](https://github.com/openwrt/openwrt): the OpenWrt source. The board file `target/linux/ath79/generic/base-files/etc/board.d/02_network` is where the A7 v5 switch port numbers (CPU 0, WAN 1, LAN 2 to 5) are defined.
- [openwrt/odhcpd on GitHub](https://github.com/openwrt/odhcpd): README for OpenWrt's DHCPv6 and router-advertisement daemon, including the `ra`, `dhcpv6` and `ndp` options this page disables.
- [RFC 4193: Unique Local IPv6 Unicast Addresses](https://www.rfc-editor.org/rfc/rfc4193): what a ULA prefix is, which explains both the static address and why OpenWrt's own `ula_prefix` is removed.
- [OpenWrt Table of Hardware: TP-Link Archer A7 v5](https://openwrt.org/toh/tp-link/archer_a7_v5): the device page, with flashing instructions. Not opened while writing this page: openwrt.org blocks automated checks, so confirm the link in a browser.
- [OpenWrt wiki: VLAN configuration with the switch (swconfig)](https://openwrt.org/docs/guide-user/network/vlan/switch): background for the Switch page. Not opened while writing, for the same reason.
