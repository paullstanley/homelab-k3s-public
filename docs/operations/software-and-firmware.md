# Software and firmware: where to get it and how to update it

One place for every piece of firmware and software in this build: where it comes from, the exact file for this hardware, how it goes on the first time, how it is updated, how to see which version you run, and the traps. It ends with the order and the rhythm in which to update everything.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | ASUS ZenWiFi XT8 (RT-AX95Q v1) router and AiMesh node on GNUton 3004.388.x with amtm and Entware; TP-Link Archer A7 v5 on OpenWrt 25.12.x; TP-Link Archer AX21 v5 stock; Raspberry Pi 4 on Raspberry Pi OS Lite 64-bit; k3s v1.34 with MetalLB 0.15, kube-vip, Pi-hole (mojo2600 chart), Homebridge, Seerr, cloudflared; Lima on macOS |
| **Also works for** | Other models from the same projects, with a different file name. Not tested by the author |
| **Time** | Reading: 20 minutes. Each update: see the cadence table |
| **You need first** | Backups of whatever you are about to update: [Backups and secrets](backups-and-secrets.md). The routine around upgrades (reboots, re-checks): [Maintenance](maintenance.md) |

## How it works

Every item below has an upstream "home": a GitHub repository, a vendor download page or a package repository. Versions move on, so this page names the version **seen on the download pages in October 2026** and tells you how to check for a newer one. It never assumes that what was current then is current when you read it.

Three rules cover most of the trouble:

- **Get the file for your exact model and hardware version.** A firmware for a neighbouring model, region or hardware revision is the most common cause of a failed or bricked upgrade.
- **Know which update path keeps your settings.** Some updates keep everything (OpenWrt sysupgrade with "keep settings", Helm with the whole values file), some keep settings but not add-on packages (plain OpenWrt sysupgrade), and some wipe a partition you rely on (an ASUS firmware update may erase JFFS).
- **Move one step at a time.** One device, one minor version, one chart at a time, with a check in between. k3s in particular must never skip a minor version.

Where a step was done on the author's hardware, it says so. Everything else on this page is from the projects' own documentation, release pages and forums, and is marked "Not verified".

## Before you start

- Take the backups first: router `.CFG` and JFFS, OpenWrt backup, etcd snapshot and token, Homebridge backup ([Backups and secrets](backups-and-secrets.md)).
- Read the release notes of the version you are moving to, and of every version you skip.
- Pick a quiet time. Router and access point updates drop Wi-Fi; k3s updates restart pods.

## Steps

### Step 1. Find out what you run now

**Run on: the router** (and on the AiMesh node, at `192.168.50.117`)

```sh
nvram get productid
nvram get buildno; nvram get extendno
```

`productid` must print `RT-AX95Q`. The firmware version is also on the web UI header and on **Administration > Firmware Upgrade**.

> **Not verified:** `buildno` and `extendno` are the keys commonly used for the version over SSH; no documentation for them was found.

**Run on: the OpenWrt access point**

```sh
cat /etc/openwrt_release
ubus call system board
```

**Run on: each Pi**

```sh
cat /etc/os-release
uname -r
vcgencmd bootloader_version
sudo rpi-eeprom-update
```

**Run on: server-1**

```sh
sudo kubectl get nodes -o wide
helm version
sudo -E helm list -A
sudo kubectl -n metallb-system get deploy controller -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
sudo kubectl -n kube-system get ds -o wide | grep kube-vip
sudo kubectl -n kube-system get deploy traefik -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
sudo kubectl -n pihole get pods -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{range .status.containerStatuses[*]}{.image}{" "}{end}{"\n"}{end}'
cloudflared --version
```

`sudo -E helm` needs `export KUBECONFIG=/etc/rancher/k3s/k3s.yaml` first ([From nothing](../start-here/build-from-nothing.md#phase-7-kubectl-and-helm)).

**Run on: the Mac**

```sh
limactl --version
limactl list
```

Write the results down. That list is what the cadence table at the end works from.

### Step 2. Look up what is current

Use the **Where** line of each item below. For GitHub projects the releases page is authoritative, but a cached list page can lag behind; the tag page or the project's own channel (for k3s) is more reliable.

### Step 3. Update in the recommended order

See [Recommended update order and cadence](#recommended-update-order-and-cadence). Do one item, check it, then the next.

## GNUton Asuswrt-Merlin for the XT8 (RT-AX95Q)

| | |
| --- | --- |
| **Where** | [gnuton/asuswrt-merlin.ng](https://github.com/gnuton/asuswrt-merlin.ng), which lists "ZenWiFi XT8 / RT-AX95Q v1". Files on its [Releases](https://github.com/gnuton/asuswrt-merlin.ng/releases) page. Documentation is the upstream [Asuswrt-Merlin wiki](https://github.com/RMerl/asuswrt-merlin.ng/wiki). The XT8 is built only by GNUton, not by the upstream Asuswrt-Merlin project |
| **Download** | `RT-AX95Q_3004_388.11_1-gnuton1_puresqubi.w` and `RT-AX95Q_3004_388.11_1-gnuton1_puresqubi.w.md5` (release 3004.388.11_1-gnuton1, 10 June 2026, the newest stable seen in October 2026). The earlier build this wiki was written on is `RT-AX95Q_3004_388.10_2-gnuton1_puresqubi.w` |
| **First install** | Flash through the stock web UI like an ASUS firmware, then factory reset: [From nothing, Phase 1](../start-here/build-from-nothing.md#phase-1-main-router-firmware) |
| **Update** | Back up JFFS first (**Administration > Restore/Save/Upload Setting > Backup JFFS partition**): the Merlin wiki warns that firmware updates may erase JFFS. Check the `.md5`. Reboot the router to free memory. **Administration > Firmware Upgrade**, upload the `.w` |
| **Check version** | Web UI header; [Step 1](#step-1-find-out-what-you-run-now) |
| **Back to stock** | Upload the ASUS image the same way, then reset. ASUS stock for the XT8 seen in October 2026: 3.0.0.4.388_24854 (2026/08/04), with **separate builds for HW 1.0 and V2**, SHA-256 values on the [ASUS support page](https://www.asus.com/networking-iot-servers/whole-home-mesh-wifi-system/zenwifi-wifi-systems/asus-zenwifi-ax-xt8/helpdesk_bios/) |

What changed upstream between the versions this wiki was written on and the newest, because GNUton tracks upstream Merlin:

| Upstream version | Change that matters here |
| --- | --- |
| 388.10 | **DNS Director "Router" mode always redirects to the router's own IP** (use a Custom entry to point elsewhere); Router mode fixed for IPv6; **UPnP disabled by default**; Tools > Other Settings moved to Administration > Tweaks |
| 388.10_2 | OpenVPN 2.6.15; an httpd crash with the mobile app API fixed |
| 388.11 | **AiCloud removed** (with AsusWebStorage and Dropbox USB sync); Traffic Monitor redesigned; IPv6 blocking of DNS-over-TLS servers fixed |
| 388.12, 388.12_2 (upstream only; no GNUton build for the XT8 seen in October 2026) | Large OpenVPN server changes (static keys and server compression removed), dnsmasq 2.93, IPsec and httpd security fixes |

Pitfalls:

- **Hardware version.** GNUton lists only RT-AX95Q **v1**. No GNUton statement about V2 was found. ASUS's own V2 firmware is a different build.
- **Wrong model.** Do not take `RT-AXE95Q_*` (ZenWiFi ET8) or any other near-name. A user who flashed an RT-AX95E image got version mismatches across the mesh.
- **Checksum format.** GNUton ships `.md5`, not `.sha256`. There is no `.zip` for this model; the `.zip` and `.tar.gz` on a release are GitHub's source archives.
- **Settings backups do not cross versions.** Do not restore a `.CFG` saved on another firmware version.
- **Reset after big jumps.** Users who skipped the recommended reset reported odd behaviour; a reset after the first flash from stock is advised.
- **Clear the browser cache** after the first login on a new version, or parts of the UI look broken.
- **WireGuard disables hardware NAT acceleration** (Merlin 388.1 changelog). Expect lower routing throughput with the WireGuard server or client on.
- **The built-in update check finds nothing.** "Scheduled check for new firmware availability" asks ASUS's server, which does not offer GNUton builds. Watch the GNUton releases page, or use MerlinAU (below).
- **Read the forum thread first.** The SNBForums release thread for each GNUton build collects XT8 reports. For 388.11_1 they included clean upgrades of 3-node meshes, one node that fell back from 5 GHz to 2.4 GHz wireless backhaul a day later (that user had skipped the reset), and one node that went solid blue and dropped clients until it was reset with its button and re-added to AiMesh.

## The AiMesh node

| | |
| --- | --- |
| **Where** | Same firmware as the router. Rules in the [Asuswrt-Merlin wiki: AiMesh](https://github.com/RMerl/asuswrt-merlin.ng/wiki/AiMesh) |
| **Download** | The same `.w` file as the router |
| **First install** | Factory reset the node, add it under AiMesh, then update it as below |
| **Update** | On the **main router**: **Administration > Firmware Upgrade**, click the **Upload** link next to the node, choose the `.w`. Update the node before or after the router, but do not leave them on builds from very different dates |
| **Check version** | The AiMesh page and the Firmware Upgrade page on the main router; or [Step 1](#step-1-find-out-what-you-run-now) over SSH on the node |

- **A node may run Merlin or GNUton only if the main router does.** Mixed meshes (Merlin router, stock node) are allowed.
- The Merlin wiki **recommends stock firmware on nodes**, because Merlin gives a node little. This build runs GNUton on the node anyway, for its JFFS scripts ([AiMesh node](../hardware/asus-aimesh-node.md)).
- **Merlin and GNUton nodes never update themselves.** Only stock nodes take the global live update.
- **MerlinAU** (an amtm script that automates firmware updates) updates only the unit it runs on. To automate a node, install it on the node too.
- Re-adding a node to AiMesh requires a factory reset of the node.
- After a node update, check that its weekly reboot job came back: `cru l` on the node ([AiMesh node](../hardware/asus-aimesh-node.md#check-it)).

> **Not verified:** the Upload procedure is from the Merlin wiki. Whether the main router ever pushes GNUton to a node by itself was not found documented.

## amtm, Entware and the router add-ons

| Item | Current home (October 2026) | Archived old home | Version seen |
| --- | --- | --- | --- |
| amtm (terminal menu) | Built into the firmware; [decoderman/amtm](https://github.com/decoderman/amtm), [diversion.ch](https://diversion.ch/amtm.html) | | 7.0 (23 Aug 2026) on diversion.ch; the GitHub README image still showed 6.7.2 |
| Entware (package manager) | Installed by amtm (`ep`); [Merlin wiki: Entware](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Entware) | | |
| Skynet | [Adamm00/IPSet_ASUS](https://github.com/Adamm00/IPSet_ASUS) | | |
| scribe | [AMTM-OSR/scribe](https://github.com/AMTM-OSR/scribe) | [cynicastic/scribe](https://github.com/cynicastic/scribe), archived 6 Jul 2025, with a pointer to the new home | 3.2.12 |
| YazDHCP | [AMTM-OSR/YazDHCP](https://github.com/AMTM-OSR/YazDHCP) | [jackyaz/YazDHCP](https://github.com/jackyaz/YazDHCP), archived 22 Mar 2026, no pointer | 1.2.6 |
| uiScribe | [AMTM-OSR/uiScribe](https://github.com/AMTM-OSR/uiScribe) | [jackyaz/uiScribe](https://github.com/jackyaz/uiScribe), archived 22 Mar 2026 | 1.4.14 |
| scMerlin | [AMTM-OSR/scMerlin](https://github.com/AMTM-OSR/scMerlin) | [jackyaz/scMerlin](https://github.com/jackyaz/scMerlin), archived 22 Mar 2026 | 2.5.49 |

The [AMTM-OSR](https://github.com/AMTM-OSR) organisation ("Orphaned Script Revival") took over these scripts when their authors stopped; amtm 6.0 (May 2025) moved them there.

**First install.** Enable SSH and **Administration > System > Enable JFFS custom scripts and configs**, plug in a USB drive of at least 2 GB, run `amtm`, format the drive ext4 with `fd`, install Entware with `ep`, add swap, then install the scripts from the menu. Skynet before scribe. Steps: [From nothing, Phase 2](../start-here/build-from-nothing.md#step-22-prepare-the-usb-drive).

Each project also documents a one-line manual install. For example, from their READMEs:

**Run on: the router**

```sh
/usr/sbin/curl -s "https://raw.githubusercontent.com/Adamm00/IPSet_ASUS/master/firewall.sh" -o "/jffs/scripts/firewall" && chmod 755 /jffs/scripts/firewall && sh /jffs/scripts/firewall install
```

```sh
/usr/sbin/curl -fsL --retry 3 "https://raw.githubusercontent.com/AMTM-OSR/YazDHCP/master/YazDHCP.sh" -o "/jffs/scripts/YazDHCP" && chmod 0755 /jffs/scripts/YazDHCP && /jffs/scripts/YazDHCP install
```

Prefer amtm; it knows the current URLs.

**Update.**

| Item | How |
| --- | --- |
| amtm and the scripts it manages | `amtm`, then `u` to check for and apply updates. amtm 7.0 adds an `au` menu for scheduled automatic updates of scripts that support it |
| Skynet | `firewall update` (exits if nothing changed), `firewall update check` (check only), `firewall update -f` (force) |
| YazDHCP | Through amtm `u`. `/jffs/scripts/YazDHCP stable` switches back to the production branch |
| scribe, uiScribe, scMerlin | Through amtm `u`, or from each script's own menu (`scribe`, `uiScribe`, `scmerlin`) |
| Entware packages | `opkg update && opkg upgrade` |

> **Not verified:** the menu keys inside each script, and amtm keys other than `fd`, `ep`, `u` and `au`.

**Check version.** amtm shows its own version in its header and lists installed scripts with versions; each script's menu shows its version.

**Pitfalls.**

- An install made before 2025 may still point at an archived repository and stop receiving updates. Update through amtm; if a script still reports the old home, reinstall it from the AMTM-OSR repository. How amtm migrates existing installs was not found documented.
- The uiScribe README still names `cynicastic/scribe` as its requirement. Use `AMTM-OSR/scribe`.
- If Skynet is installed after scribe, re-run scribe's install and force it.
- YazDHCP does not import reservations from `/jffs/configs/dnsmasq*.conf.add`; remove those after migrating, because duplicates can break dnsmasq restarts. Its page takes 8 to 10 seconds to load, and you must click Apply. Guest-network reservations are not backed up or restored by it. Use its `dp` option to keep backups on the USB drive.
- Entware and Optware (ASUS Download Master) cannot coexist.
- amtm and Entware downloads sometimes hang; Skynet is suspected. Disable it briefly and retry.
- "Router date keeper" and "shell history" are built-in amtm features, not separate scripts. Something called "ntpBootWatchdog" is not an amtm feature; if you find it on a router, find out where it came from before relying on it.

## OpenWrt on the Archer A7 v5

| | |
| --- | --- |
| **Where** | [downloads.openwrt.org/releases](https://downloads.openwrt.org/releases/), target `ath79/generic`, profile `tplink_archer-a7-v5` ("TP-Link Archer A7, variant v5"). The [Firmware Selector](https://firmware-selector.openwrt.org/) finds the same files in a browser |
| **Download** | For 25.12.5 (30 June 2026, the newest 25.12 release seen in October 2026), in [`releases/25.12.5/targets/ath79/generic/`](https://downloads.openwrt.org/releases/25.12.5/targets/ath79/generic/): **factory** `openwrt-25.12.5-ath79-generic-tplink_archer-a7-v5-squashfs-factory.bin` (first flash from TP-Link firmware); **sysupgrade** `openwrt-25.12.5-ath79-generic-tplink_archer-a7-v5-squashfs-sysupgrade.bin` (upgrading OpenWrt); initramfs `...-initramfs-kernel.bin` (recovery and testing only); and `sha256sums` |
| **First install** | The factory image through the TP-Link web UI: [From nothing, Phase 4](../start-here/build-from-nothing.md#step-41-flash-openwrt-onto-the-archer-a7-v5) |
| **Update** | Attended Sysupgrade, or the sysupgrade image (below) |
| **Check version** | LuCI **Status > Overview**; `cat /etc/openwrt_release` |

Ways to upgrade, from most to least convenient:

| Method | Keeps settings | Keeps extra packages | How |
| --- | --- | --- | --- |
| **Attended Sysupgrade (ASU)** | Yes | **Yes**: the server builds an image with your installed packages | LuCI **System > Attended Sysupgrade** (installed by default in 25.12; on the tested device it is configured to use `sysupgrade.openwrt.org` and to check at login), or the Firmware Selector |
| `owut` (command line ASU client) | Yes | Yes | `owut check`, then `owut upgrade`. For a new release series: `owut upgrade --verbose --version-to 25.12`. Included only "on devices with larger flash"; whether the A7 image has it was not verified |
| LuCI flash | Yes, with **Keep settings** ticked | **No** | **System > Backup / Flash Firmware**, upload the sysupgrade image |
| Command line | Yes | **No** | Copy the image to `/tmp` and run `sysupgrade -v /tmp/<sysupgrade.bin>` |
| Clean start | No | No | Back up, `sysupgrade -n /tmp/<sysupgrade.bin>`, then restore from your backup or re-run the setup scripts |

**Run on: your computer**, then **the access point**

```sh
grep 'tplink_archer-a7-v5-squashfs-sysupgrade.bin' sha256sums | sha256sum -c -
scp -O openwrt-25.12.5-ath79-generic-tplink_archer-a7-v5-squashfs-sysupgrade.bin root@192.168.50.3:/tmp/
ssh root@192.168.50.3 'sysupgrade -v /tmp/openwrt-25.12.5-ath79-generic-tplink_archer-a7-v5-squashfs-sysupgrade.bin'
```

The first line checks the download against OpenWrt's checksum list (on macOS: `shasum -a 256 -c`). `scp -O` is needed because OpenWrt's SSH server has no SFTP. Take the AP backup first ([Archer A7](../hardware/tp-link-archer-a7-openwrt.md#back-up-the-settings)).

**Packages: `apk`, not `opkg`.** OpenWrt 25.12 replaced `opkg` with `apk` (Alpine Package Keeper), because OpenWrt's `opkg` fork was no longer maintained. Command-line arguments differ and a few package names changed. The setup script in this repo already uses `apk del uneighbord`. Older guides that say `opkg install` need translating; OpenWrt publishes an opkg-to-apk cheatsheet on its wiki. Common forms (not verified on the A7):

```sh
apk update
apk add <PACKAGE>
apk del <PACKAGE>
apk list --installed
```

Pitfalls:

- **25.12.5 is a security release** (an odhcpd stack overflow, uhttpd request smuggling, LuCI privilege escalation and XSS fixes). The OpenWrt forum post calls the upgrade "strongly recommended".
- A plain sysupgrade removes packages you added. Note them first (`apk list --installed`) or use Attended Sysupgrade.
- An upgrade **without keep settings** brings the AP back as a router at `192.168.1.1` with DHCP on. Keep it off the main LAN until it is restored ([Archer A7](../hardware/tp-link-archer-a7-openwrt.md#pitfalls)).
- 24.10 to 25.12 is a supported upgrade on most devices; 23.05 to 25.12 is not. 24.10 reaches end of life in September 2026.
- Known 25.12 issue: **802.11r fast transition with WPA3 causes client problems.** Leave 802.11r off on this AP.
- Never flash a factory image onto OpenWrt, or a sysupgrade image onto stock firmware.

## TP-Link Archer AX21 v5 stock firmware

| | |
| --- | --- |
| **Where** | [TP-Link Archer AX21 v5 downloads](https://www.tp-link.com/us/support/download/archer-ax21/v5/) (US). The hardware selector offers V5.60, V5.46 and older versions; the label on the device decides |
| **Download** | US V5.6x, newest seen in October 2026: Archer AX21(US)_V5.60_1.1.2 Build 20250814, file `Archer AX21_V5.6_250814.zip`. Unzip it and use the `.bin` inside |
| **First install / Update** | Web UI **Advanced > System > Firmware Upgrade**, upload the `.bin`, wait about 3 minutes. Or the online update (the update icon in the web UI, or the Tether app), which needs the AP to have a gateway and working DNS |
| **Check version** | The Firmware Upgrade page. The build number is the date (YYYYMMDD) |

- **1.1.2 (Build 20250814) cannot be rolled back.**
- Back up first: **Advanced > System > Backup & Restore** saves `config.bin`.
- Only the firmware for your purchase region and exact hardware version. Use a cable, and do not cut power.
- If the progress bar sticks, wait 5 minutes, then try another browser. TP-Link has a recovery procedure for failed updates ([FAQ 2571](https://www.tp-link.com/us/support/faq/2571/)).
- After the update, confirm it is still in Access Point mode at `192.168.50.4`.

> **Not verified:** TP-Link's pages do not mention updating in AP mode. In AP mode the AX21 takes its management address from the main router; a manual `.bin` upload needs no internet.

## Raspberry Pi Imager

| | |
| --- | --- |
| **Where** | [raspberrypi.com/software](https://www.raspberrypi.com/software/); source and releases at [raspberrypi/rpi-imager](https://github.com/raspberrypi/rpi-imager/releases) |
| **Download** | The "latest" installer for your computer: `imager_latest.exe` (Windows), `imager_latest.dmg` (macOS), `imager_latest_amd64.AppImage` (Linux x86_64). Newest release seen in October 2026: v2.0.11.1 |
| **First install** | Run the installer. On Raspberry Pi OS: `sudo apt update && sudo apt install rpi-imager`. Linux AppImage: make it executable and run it with `sudo` |
| **Update** | Download the installer again; on Raspberry Pi OS it updates with `apt` |
| **Check version** | `rpi-imager --version` |

- Keep **Exclude system drives** ticked.
- A brand-new NVMe drive may not show a partition until erased (Imager's Erase option).
- The command-line mode (`rpi-imager --cli <image> <device>`) writes an image but does not apply the customisation screens.
- **Misc utility images > Bootloader > SD Card Boot** writes a card that resets the Pi's bootloader (EEPROM); boot from it and wait for a steady green LED and a green screen.

## Raspberry Pi OS

| | |
| --- | --- |
| **Where** | [Raspberry Pi operating system images](https://www.raspberrypi.com/software/operating-systems/), or from inside Imager |
| **Download** | **Raspberry Pi OS Lite (64-bit)**. Seen in October 2026: release of 6 October 2026, Debian 13 "trixie", kernel 6.18. A "Legacy" Lite (64-bit) on Debian 12 "bookworm", kernel 6.12, is also offered |
| **First install** | With Imager: [From nothing, Phase 5](../start-here/build-from-nothing.md#phase-5-raspberry-pis) |
| **Update** | `sudo apt update && sudo apt full-upgrade`. The documentation says `full-upgrade`, not `upgrade`. `sudo apt clean` if space is short |
| **Check version** | `cat /etc/os-release`, `uname -r` |

- **One Pi at a time** in a running cluster, waiting for `Ready` between them ([Maintenance](maintenance.md#step-6-operating-system-and-bootloader-on-the-raspberry-pis)).
- **A new Debian major version (bookworm to trixie):** the Raspberry Pi documentation strongly recommends a clean install onto new media, not an in-place upgrade. For a cluster node that means: drain and remove the node, reinstall, prepare it again ([Raspberry Pi](../hardware/raspberry-pi.md)) and rejoin it. The cluster here runs both versions side by side.
- `rpi-update` installs pre-release firmware for testers. Do not use it on a server.
- The kernel command line is `/boot/firmware/cmdline.txt` on bookworm and trixie (older k3s docs say `/boot/cmdline.txt`), and must stay one line.
- k3s notes that Debian-based systems may hit a known iptables bug. k3s ships its own iptables; `prefer-bundled-bin: true` in the k3s config makes it use that. **Not verified** whether current Raspberry Pi OS is affected.

## Raspberry Pi bootloader (EEPROM) and boot order

| | |
| --- | --- |
| **Where** | The `rpi-eeprom` package; documented in [Raspberry Pi hardware documentation](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html) |
| **Update** | `sudo rpi-eeprom-update` (check), `sudo rpi-eeprom-update -a && sudo reboot` (install), `sudo rpi-eeprom-update -r` (cancel a pending update) |
| **Automatic updates** | `apt` installs new bootloader images but does not flash them; the `rpi-eeprom-update` service applies them at boot. `sudo systemctl mask rpi-eeprom-update` stops that |
| **Release stream** | `FIRMWARE_RELEASE_STATUS` in `/etc/default/rpi-eeprom-update` (`default` or `latest`), or `raspi-config` **Advanced Options > Bootloader Version** |
| **Boot order** | `rpi-eeprom-config` shows it; `sudo rpi-eeprom-config --edit` changes it; or `raspi-config` **Advanced Options > Boot Order**. Digits right to left: `1` SD, `4` USB, `6` NVMe (Pi 5 family), `2` network, `f` restart. Default `0xf41` |
| **Check version** | `vcgencmd bootloader_version` |

- Reflashing the bootloader resets its configuration, including `BOOT_ORDER`.
- `FREEZE_VERSION` in the config blocks automatic updates.
- An inserted SD card is tried first unless `BOOT_ORDER` says otherwise.
- Pi 5 with a non-HAT+ NVMe adapter: `PCIE_PROBE=1`. Gen 3 PCIe is not certified.

## k3s

| | |
| --- | --- |
| **Where** | [docs.k3s.io](https://docs.k3s.io/), releases on [k3s-io/k3s](https://github.com/k3s-io/k3s/releases), release channels at `https://update.k3s.io/v1-release/channels/<channel>` |
| **Download** | Nothing to download by hand: the install script fetches the release. Seen in October 2026: channel `stable` = **v1.36.5+k3s1** (30 Sep 2026); channel `v1.34` = **v1.34.12+k3s1** (30 Sep 2026). This wiki's cluster was built on v1.34.3+k3s1 |
| **First install** | `curl -sfL https://get.k3s.io \| INSTALL_K3S_VERSION='<FULL_TAG>' sh -s - server`, with the settings in `/etc/rancher/k3s/config.yaml` ([HA k3s cluster](../kubernetes/k3s-ha-cluster.md)) |
| **Update** | The same command with the new tag, one server at a time ([Maintenance, Step 7](maintenance.md#step-7-k3s-upgrades)) |
| **Check version** | `k3s --version`; `sudo kubectl get nodes` (VERSION column) |

Pinning a version:

| Variable | Effect |
| --- | --- |
| `INSTALL_K3S_VERSION=v1.34.12+k3s1` | That exact release. Must be the full tag; `v1.34` fails to download |
| `INSTALL_K3S_CHANNEL=v1.34` | The newest patch of that minor version |
| neither | The `stable` channel, which **changes minor version without warning** |

**Upgrade path, one minor version at a time.** From v1.34.3:

1. v1.34.3 → the newest v1.34 patch (v1.34.12 in October 2026).
2. → the newest v1.35 patch (look it up: `https://update.k3s.io/v1-release/channels/v1.35`).
3. → the newest v1.36 patch.

Before each step: take an etcd snapshot, read the release notes of the new minor version, upgrade servers one at a time, and run the re-checks in [Maintenance](maintenance.md#step-7-k3s-upgrades). The script neither drains nor cordons nodes; drain by hand if you want pods moved first.

**The system-upgrade-controller channel trap.** k3s can upgrade itself with the [system-upgrade-controller](https://docs.k3s.io/upgrades/automated) and `Plan` objects. A plan with `channel: https://update.k3s.io/v1-release/channels/stable` would now jump straight to v1.36 and **skip v1.35**, which Kubernetes does not support. Use a minor channel URL (`.../channels/v1.35`) or an explicit `version:` in the plan, and move it on by hand one minor at a time. The controller refuses downgrades, and a refused downgrade leaves nodes cordoned.

**etcd snapshots.**

| Default | Value |
| --- | --- |
| Schedule | 00:00 and 12:00 (`0 */12 * * *`) |
| Kept | 5 per server |
| Folder | `/var/lib/rancher/k3s/server/db/snapshots` |

**Run on: server-1**

```sh
sudo k3s etcd-snapshot save --name before-upgrade
sudo k3s etcd-snapshot ls
```

A snapshot restores only with the token that was in use when it was taken. The restore procedure is in the [k3s etcd-snapshot documentation](https://docs.k3s.io/cli/etcd-snapshot) and [Backups and secrets](backups-and-secrets.md#step-4-cluster-etcd-snapshot-and-token).

Pitfalls:

- **Traefik chart v40 arrives with k3s v1.34.9.** The ingress-nginx migration provider was renamed from `kubernetesIngressNginx` to `kubernetesIngressNGINX`; update any `HelmChartConfig` that sets it.
- Since v1.34.1 the packaged manifests no longer tolerate the old `node-role.kubernetes.io/master` taint.
- Server flags that must match on every server (`cluster-cidr`, `service-cidr`, `disable`, and others) stay in `config.yaml`, so a re-run of the installer keeps them. Settings given only on the old command line are lost.
- Dual-stack cannot be added to an existing cluster.
- Four etcd members tolerate one failure, the same as three.
- **Not verified:** the author has not taken this cluster through a k3s upgrade.

## kubectl and Helm

| | |
| --- | --- |
| **Where** | `kubectl` is part of k3s (`sudo kubectl` on a server). Helm: [helm.sh](https://helm.sh/docs/intro/install/), releases on [helm/helm](https://github.com/helm/helm/releases) |
| **Download** | Helm 4 is the current major version (the documentation is versioned 4.3.0 in October 2026; Helm 3 still receives releases) |
| **First install** | On a server: the `get-helm-4` script ([From nothing, Phase 7](../start-here/build-from-nothing.md#phase-7-kubectl-and-helm)). On a Mac: `brew install helm` (community-maintained formula). Debian also has a community apt repository, documented on the Helm install page |
| **Update** | Run the install script again, or `brew upgrade helm` |
| **Check version** | `helm version`; `kubectl version` |

- `kubectl` on a laptop must be within one minor version of the cluster. After a k3s upgrade, update the laptop's `kubectl` too.
- Helm 4 `upgrade` documents `--install`, `--reuse-values`, `--reset-then-reuse-values` and `--rollback-on-failure`; `--atomic` is not listed. This wiki always passes the whole values file with `-f` instead of reusing values.
- Some chart READMEs still say "Helm 3.x required" (kube-vip's, for example).

## MetalLB

| | |
| --- | --- |
| **Where** | [metallb.io](https://metallb.io/), releases on [metallb/metallb](https://github.com/metallb/metallb/releases) |
| **Download** | This build uses the **v0.15.3** native manifest: `https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml`. Newest seen in October 2026: chart 0.16.1 (May 2026) |
| **First install** | `kubectl apply` of the manifest, then the pools ([Load balancers](../kubernetes/load-balancers.md#step-2-install-metallb)) |
| **Update** | Within 0.15: apply the newer native manifest of the same layout. Read the [release notes](https://metallb.io/release-notes/) first |
| **Check version** | The controller image tag ([Step 1](#step-1-find-out-what-you-run-now)) |

- **0.16 changes the defaults.** FRR-K8s becomes the default BGP backend in the Helm chart (FRR mode is deprecated), the installation page now recommends the FRR-K8s manifest with native as the alternative, and metrics endpoints are HTTPS-only. A layer-2-only cluster like this one gains nothing from FRR. Either stay on 0.15.3, or move to 0.16 with the **native** manifest, or with the Helm chart and `speaker.frr.enabled=false` and `frrk8s.enabled=false`.
- Do not mix install methods: a manifest install and a Helm install of MetalLB are different objects.
- k3s ServiceLB must stay disabled on every server.
- Older charts use the annotation prefix `metallb.universe.tf/`; current MetalLB documents `metallb.io/`.

> **Not verified:** a move from 0.15.3 to 0.16 was not done on this cluster.

## kube-vip

| | |
| --- | --- |
| **Where** | [kube-vip.io](https://kube-vip.io/docs/usage/k3s/), releases on [kube-vip/kube-vip](https://github.com/kube-vip/kube-vip/releases), chart in [kube-vip/helm-charts](https://github.com/kube-vip/helm-charts) (repo `https://kube-vip.github.io/helm-charts`) |
| **Download** | Nothing by hand: k3s's Helm controller fetches the chart named in [`files/k3s/kube-vip/helmchart.yaml`](../../files/k3s/kube-vip/helmchart.yaml). Seen in October 2026: kube-vip v1.2.4 (16 Sep); chart 0.11.1 with appVersion v1.2.3 |
| **Update** | The HelmChart in this repo names no chart version, so k3s takes the newest chart when it (re)installs it. To control updates, add `version: <CHART_VERSION>` under `spec:` and re-apply the file; raise it when you choose |
| **Check version** | `sudo kubectl -n kube-system get ds -o wide \| grep kube-vip` (image tag) |

- `--tls-san` on the servers must contain the floating address (`192.168.50.10`), or clients reject the API certificate.
- Keep `svc_enable: "false"` while MetalLB handles Services; the two must not both announce Service addresses.
- The kube-vip pod needs the API to start, so the first servers join through a real node address, not the floating one.
- **Not verified:** pinning `spec.version` in this HelmChart was not done on this cluster.

## Pi-hole (mojo2600 chart)

| | |
| --- | --- |
| **Where** | Chart [MoJo2600/pihole-kubernetes](https://github.com/MoJo2600/pihole-kubernetes) (repo `https://mojo2600.github.io/pihole-kubernetes/`); image [pi-hole/docker-pi-hole](https://github.com/pi-hole/docker-pi-hole/releases) |
| **Download** | Chart **2.38.0** (July 2026; appVersion 2026.07.2), which this build uses. Image newest seen in October 2026: `pihole/pihole:2026.07.2` |
| **First install** | [Pi-hole](../apps/pihole.md#step-4-install) |
| **Update** | `helm repo update`, then `helm upgrade --install pihole mojo2600/pihole -n pihole --version <CHART> -f files/pihole/values.yaml`. The image: set `image.tag` in the values file to a dated release and upgrade |
| **Check version** | `helm list -n pihole`; the web UI footer; the pod image list in [Step 1](#step-1-find-out-what-you-run-now) |

- **`pihole -up` does not work in a container.** Pi-hole is upgraded by a new image.
- Image tags are dated (`2026.07.2`), not semantic versions. `latest` with `IfNotPresent` lets each node keep a different version; pin a dated tag.
- Always read the Pi-hole release notes; always apply the whole values file.
- The chart's README asks for maintainers. Watch its activity.
- The DNS-over-HTTPS sidecar is a separate problem: next section.

## The cloudflared DNS-over-HTTPS sidecar

| | |
| --- | --- |
| **What runs** | `crazymax/cloudflared` tag `2025.9.1`, running `cloudflared proxy-dns` beside each Pi-hole ([Pi-hole](../apps/pihole.md#the-dns-over-https-sidecar-is-pinned-and-why)) |
| **Status in October 2026** | Cloudflare deprecated `proxy-dns` on 11 Nov 2025 and **removed it from every cloudflared release from 2 Feb 2026**. Older releases keep working and are supported for one year from their release date. The `crazymax/cloudflared` image was **archived on 21 Dec 2025** and calls itself abandoned |
| **Update** | None possible: a newer `cloudflare/cloudflared` image has no `proxy-dns`, and the pod would show `1/2` |

What this means: the pinned sidecar still encrypts DNS, but gets no more fixes and falls out of Cloudflare's support window. Plan a replacement. The options documented by Pi-hole and Cloudflare:

| Option | Notes |
| --- | --- |
| dnscrypt-proxy as the sidecar, listening on `127.0.0.1#5053` (DoH) | Pi-hole has a guide for it. Set `doh.enabled: false` and add it as an extra container. **Not verified** in this build |
| unbound as the sidecar (a recursive resolver, no third-party upstream) | Pi-hole has a guide for it. Not encrypted to the authoritative servers. **Not verified** in this build |
| Pi-hole upstream = the router, with the router doing DNS-over-TLS | No sidecar. Moves the encryption to the router ([DNS design](../network/dns-design.md#step-4-choose-the-routers-own-upstream)). **Not verified** in this build |
| Cloudflare WARP Connector | Cloudflare's own suggestion for servers and routers. Not evaluated |

## Homebridge

| | |
| --- | --- |
| **Where** | Image [homebridge/docker-homebridge](https://github.com/homebridge/docker-homebridge), published as `ghcr.io/homebridge/homebridge` (formerly `oznu/homebridge`). UI: [homebridge-config-ui-x](https://github.com/homebridge/homebridge-config-ui-x). Chart: `k8s-at-home/homebridge` from the [archived k8s-at-home charts](https://github.com/k8s-at-home/charts) |
| **Download** | Image tags: `latest` / `ubuntu` (stable, Ubuntu 24.04), dated tags such as `2026-09-25` (newest stable seen in October 2026), `beta`, `alpha`, `legacy` (Homebridge 1.x). Chart 5.3.2, last released 2022 |
| **First install** | [Homebridge](../apps/homebridge.md#step-1-install) |
| **Update** | **Update the image, not from inside the UI.** Set `image.tag` to a dated tag in [`files/homebridge/values.yaml`](../../files/homebridge/values.yaml) and `helm upgrade` with the whole file. Plugins are updated from the UI's Plugins page; they live in the `/homebridge` volume |
| **Check version** | The UI dashboard shows Homebridge, UI and Node.js versions |

- Since the 2025-06-25 image, updates of Homebridge core, the UI and Node.js made inside the container are overwritten when the container is recreated.
- The chart's default image is the old `ghcr.io/oznu/homebridge`. The values file in this repo overrides it; keep that override.
- The chart repository was archived on 22 Aug 2022. `helm pull k8s-at-home/homebridge` once and keep the copy.
- The Homebridge documentation discourages automatic updaters such as Watchtower.
- Take a UI backup before and after.

## Seerr

| | |
| --- | --- |
| **Where** | [seerr-team/seerr](https://github.com/seerr-team/seerr), docs at [docs.seerr.dev](https://docs.seerr.dev/getting-started/kubernetes/). Image `ghcr.io/seerr-team/seerr` |
| **Download** | Newest release seen in October 2026: v3.5.0 (28 Sep 2026). Official chart `oci://ghcr.io/seerr-team/seerr/seerr-chart` (3.9.1 with appVersion v3.4.1 on the development branch README) |
| **First install** | This build uses a community chart: [Seerr](../apps/seerr-cloudflare-tunnel.md#step-1-install-seerr) |
| **Update** | Pin `image.tag` to a release in [`files/seerr/values.yaml`](../../files/seerr/values.yaml) and `helm upgrade`. Back up the config volume first ([Backups and secrets](backups-and-secrets.md#step-7-seerr)) |
| **Check version** | `helm list -n seerr`; the image tag |

- Seerr runs as UID 1000 (`node`). After a migration, the config folder must be owned by `1000:1000`.
- One replica only. Chart 2.7.0 of the official chart moved to a StatefulSet and removed `replicaCount`; chart 3.0.0 renamed the old `jellyseerr` chart to `seerr`.
- The Seerr team does not support third-party charts, and calls the Kubernetes method one for advanced users.
- **Not verified:** moving this build from the community chart to the official one. Value names differ; compare them before switching.

## cloudflared for the tunnel

| | |
| --- | --- |
| **Where** | Package repository [pkg.cloudflare.com](https://pkg.cloudflare.com/index.html), releases on [cloudflare/cloudflared](https://github.com/cloudflare/cloudflared/releases) |
| **Download** | Newest seen in October 2026: 2026.9.1 (11 Sep 2026). On a Pi, the `arm64` Debian package from the repository |
| **First install** | From the Cloudflare dashboard's connector instructions, then `sudo cloudflared service install <TUNNEL_TOKEN>` ([Seerr](../apps/seerr-cloudflare-tunnel.md#step-2-install-cloudflared-on-the-node)). The repository setup, from Cloudflare's package page, is below |
| **Update** | `sudo apt-get update && sudo apt-get install --only-upgrade cloudflared`, then `sudo systemctl restart cloudflared` |
| **Check version** | `cloudflared --version` |

**Run on: server-1**

```sh
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt-get update && sudo apt-get install cloudflared
```

- Cloudflare supports releases within one year of the newest one. With the apt repository, the Pi's ordinary updates keep it current.
- A package install is updated only with the package manager; `cloudflared update` is for binary installs.
- Restart the service after an upgrade.
- The `proxy-dns` removal does not affect tunnels.

## Lima and socket_vmnet on the Mac

| | |
| --- | --- |
| **Where** | [lima-vm.io](https://lima-vm.io/docs/installation/), releases on [lima-vm/lima](https://github.com/lima-vm/lima/releases); [lima-vm/socket_vmnet](https://github.com/lima-vm/socket_vmnet/releases) |
| **Download** | Newest seen in October 2026: Lima v2.2.0 (21 Jul 2026); socket_vmnet v1.2.2 |
| **First install** | `brew install lima`; socket_vmnet into `/opt/socket_vmnet` ([Mac in a Lima VM](../hardware/mac-lima-vm.md#step-1-install-lima-and-the-bridged-network-helper)) |
| **Update** | `brew upgrade lima`. socket_vmnet: extract the new release over `/opt/socket_vmnet` with `sudo tar Cxzvf / <socket_vmnet-release>.tar.gz opt/socket_vmnet`. Then regenerate the sudoers file (`limactl sudoers`) and install it again |
| **Check version** | `limactl --version` |

- **Lima's documentation calls the Homebrew socket_vmnet "not secure and not recommended"**, because any admin user could replace the binary Lima runs as root. This build copies the Homebrew binary to `/opt/socket_vmnet` with root ownership; the documented alternative is the binary release extracted to `/` (lands in `/opt/socket_vmnet`) or a source build with `sudo make PREFIX=/opt/socket_vmnet install.bin`.
- `limactl start` refuses with a sudoers "out of sync" error when the sudoers file is older than `networks.yaml` or the installed paths. Regenerate it after every Lima or socket_vmnet update. **Not verified** that every update requires this; doing it costs nothing.
- `limactl start-at-login` starts the VM when the user **logs in**, not at boot. A headless Mac needs automatic login for the node to come back after a power cut.
- Updating packages inside the VM is ordinary Ubuntu `apt`; the VM is an etcd member, so treat its reboot like a Pi's.

## Traefik (bundled with k3s)

| | |
| --- | --- |
| **Where** | Deployed by k3s as a HelmChart in `kube-system`; [k3s networking services](https://docs.k3s.io/networking/networking-services), [k3s Helm](https://docs.k3s.io/add-ons/helm) |
| **Version** | Set by k3s: v3.7.13 in k3s v1.34.12. Earlier v1.34 patches carried Traefik 3.5.1 (v1.34.2) to 3.7.8 (v1.34.10) |
| **Update** | With k3s. There is no separate upgrade |
| **Customise** | Never edit the packaged `traefik.yaml` in `/var/lib/rancher/k3s/server/manifests/`; k3s rewrites it at startup. Put chart values in a `HelmChartConfig` instead (below) |
| **Check version** | The Traefik image tag ([Step 1](#step-1-find-out-what-you-run-now)) |

**Run on: server-1** (as root), creating `/var/lib/rancher/k3s/server/manifests/traefik-config.yaml`:

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    service:
      annotations:
        metallb.io/loadBalancerIPs: "192.168.50.12"
```

The name and namespace must match k3s's HelmChart exactly. This is the permanent way to keep Traefik on its address across k3s upgrades; [Load balancers](../kubernetes/load-balancers.md#step-3-give-traefik-a-fixed-address) uses an annotation applied by command instead.

> **Not verified:** this HelmChartConfig was not used on the author's cluster. The `service.annotations` key is the Traefik chart's; check it against the chart version your k3s bundles.

- Read the Traefik chart's major-version notes whenever a k3s release bumps the chart (v40 arrived with k3s v1.34.9).
- Disabling Traefik (`disable: [traefik]`) must be done on every server.

## Recommended update order and cadence

Update from the edge of the network inwards, and the cluster from the bottom up. Each row assumes the rows above it are healthy.

| # | Item | Cadence | Before | After |
| --- | --- | --- | --- | --- |
| 1 | OpenWrt AP | Each 25.12.x service release; security releases promptly | AP backup | [A7 checks](../hardware/tp-link-archer-a7-openwrt.md#check-it); extra packages present |
| 2 | Stock AP | When TP-Link publishes a release | `config.bin` | Still AP mode at `.4` |
| 3 | Router add-ons (amtm `u`) | Monthly | JFFS backup | Log rotation; Skynet line in `firewall-start` |
| 4 | AiMesh node firmware | With the router, same version | Router backups | `cru l` on the node |
| 5 | Main router firmware | Each GNUton stable release, after reading its forum thread | `.CFG`, JFFS, bootstrap backup | `verify`; [Maintenance, Step 4](maintenance.md#step-4-firmware-and-add-on-upgrades-router-and-node) |
| 6 | Raspberry Pi OS and bootloader | Monthly, one Pi at a time | etcd snapshot | Node `Ready` |
| 7 | Lima and the VM | Monthly | etcd snapshot | `server-4` `Ready` on `lima0` |
| 8 | k3s patch release (same minor) | Monthly to quarterly | etcd snapshot and token | [Maintenance, Step 7](maintenance.md#step-7-k3s-upgrades) re-checks |
| 9 | k3s minor version | Once or twice a year, one minor at a time; never let a minor version fall out of support | Read release notes; snapshot | Same re-checks; Traefik chart notes |
| 10 | kubectl and Helm on admin machines | After each k3s minor | | `helm list -A` |
| 11 | MetalLB | When a release fixes something you need; 0.16 only deliberately | Read release notes | `.11` and `.12` answer |
| 12 | kube-vip | With the k3s minor, if pinned | | `.10` answers |
| 13 | Pi-hole chart and image | Monthly, pinned dated tag | Note the values | One pod per Pi, `2/2`; [Pi-hole checks](../apps/pihole.md#check-it) |
| 14 | DoH sidecar | Replace once (see above) | | `2/2` and encrypted upstream |
| 15 | Homebridge image, then plugins | Monthly | UI backup | Accessories respond; pod DNS block |
| 16 | Seerr | Monthly | Config volume backup | Public name loads |
| 17 | cloudflared | With the Pi's `apt` updates | | Tunnel healthy |

After any of these, retake the backups ([Backups and secrets](backups-and-secrets.md)).

## Check it

After an update round, run [Step 1](#step-1-find-out-what-you-run-now) again and compare with your list: every item on the version you intended, every node on the same k3s version. Then run [Verification](verification.md).

## Pitfalls

| What happens | Why | Avoid or recover |
| --- | --- | --- |
| Router or AP will not take the file | Wrong model, region or hardware version | Check `productid` and the label; use the exact file named above |
| JFFS scripts gone after a router update | Firmware updates may erase JFFS | Restore the JFFS backup or run the bootstrap script again |
| Add-on packages missing after an OpenWrt upgrade | Plain sysupgrade keeps settings, not packages | Attended Sysupgrade, or reinstall with `apk` |
| An add-on stops updating | Its repository was archived | Update or reinstall from the AMTM-OSR home |
| A k3s upgrade jumps two minor versions | Installer or upgrade plan followed `stable` | Pin `INSTALL_K3S_VERSION`, or a minor channel |
| Pi-hole pod `1/2` after an upgrade | Sidecar moved to a cloudflared without `proxy-dns` | Keep `doh.tag: "2025.9.1"` until it is replaced |
| Three Pi-hole pods on three versions | `latest` with `IfNotPresent` | Pin a dated tag |
| Homebridge reverts to an older version after a restart | Core or Node.js was updated inside the container | Update the image tag instead |
| MetalLB 0.16 deploys FRR you did not ask for | FRR-K8s is the 0.16 chart default | Native manifest, or `speaker.frr.enabled=false` and `frrk8s.enabled=false` |
| kube-vip changes version on its own | The HelmChart has no `version:` | Pin it |
| Lima refuses to start after an update | Stale sudoers file | `limactl sudoers` and install it again |
| Traefik settings reset after a k3s upgrade | The packaged manifest was edited, or the address was set by command | Use a `HelmChartConfig` |

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| The router's update check says there is no new firmware | ASUS's server does not know GNUton builds | Check the GNUton releases page |
| A node shows an older firmware than the router | Merlin nodes are not updated automatically | **Upload** link next to the node |
| `apk: not found` or `opkg: not found` on OpenWrt | A guide for the other release series | 25.12 uses `apk`; 24.10 and older use `opkg` |
| `sha256sum -c` prints `FAILED` | Incomplete or wrong download | Download again; check the file name matches the line in `sha256sums` |
| `INSTALL_K3S_VERSION` download fails | Short tag | Use the full tag, `v1.34.12+k3s1` |
| `helm upgrade` cannot find a chart | Repository not added or moved | `helm repo list`; add it again |
| `rpi-eeprom-update` says an update is pending but nothing changes | It is applied at the next boot | Reboot, then `vcgencmd bootloader_version` |
| Anything else | | [Troubleshooting](troubleshooting.md) |

## References

- [gnuton/asuswrt-merlin.ng releases](https://github.com/gnuton/asuswrt-merlin.ng/releases): GNUton firmware for the RT-AX95Q and its changelogs.
- [Asuswrt-Merlin changelog](https://www.asuswrt-merlin.net/changelog): the upstream changes GNUton builds inherit.
- [Asuswrt-Merlin wiki: AiMesh](https://github.com/RMerl/asuswrt-merlin.ng/wiki/AiMesh): firmware rules and manual updates for nodes.
- [amtm](https://diversion.ch/amtm.html): the current amtm version and its update features.
- [AMTM-OSR on GitHub](https://github.com/AMTM-OSR): the new home of scribe, YazDHCP, uiScribe and scMerlin.
- [OpenWrt 25.12.5 service release](https://forum.openwrt.org/t/openwrt-25-12-5-service-release/251479): what the release fixes and why to upgrade.
- [OpenWrt 25.12 released with apk replacing opkg](https://linuxiac.com/openwrt-25-12-released-with-apk-package-manager-replacing-opkg/): the package manager change and upgrade paths.
- [TP-Link: How to update the firmware](https://www.tp-link.com/us/support/faq/2796/): manual firmware upgrade on TP-Link routers.
- [Raspberry Pi documentation: updating the bootloader](https://raw.githubusercontent.com/raspberrypi/documentation/master/documentation/asciidoc/computers/raspberry-pi/boot-eeprom.adoc): `rpi-eeprom-update` and release streams.
- [K3s: Manual upgrades](https://docs.k3s.io/upgrades/manual): re-running the installer, version pinning and the no-skipping rule.
- [K3s: Automated upgrades](https://docs.k3s.io/upgrades/automated): the system-upgrade-controller and `Plan` objects.
- [K3s: etcd-snapshot](https://docs.k3s.io/cli/etcd-snapshot): snapshot defaults and restore.
- [MetalLB release notes](https://metallb.io/release-notes/): the 0.16 FRR-K8s default and other breaking changes.
- [Cloudflare: cloudflared proxy-dns deprecation](https://developers.cloudflare.com/changelog/post/2025-11-11-cloudflared-proxy-dns/): the removal date and the support window.
- [Pi-hole: upgrading the Docker image](https://docs.pi-hole.net/docker/upgrading/): why `pihole -up` is disabled in containers.
- [Lima: VMNet networks](https://lima-vm.io/docs/config/network/vmnet/): installing socket_vmnet securely and the sudoers file.
