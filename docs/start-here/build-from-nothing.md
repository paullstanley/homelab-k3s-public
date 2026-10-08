# From nothing to a full deployment

The whole build in order, from boxes on a table to a network with an isolated IoT network, local IPv6, a highly available k3s cluster and the apps on it. Each phase says what it achieves, what it needs, what to download first, where the detailed steps are, and how to tell that it worked before you move on. It also fills the gaps the other pages leave: flashing the router and the access point, installing Entware and the router add-ons, first boot of a Raspberry Pi, and installing Helm.

Example addresses and names are explained in [Conventions](conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | ASUS ZenWiFi XT8 (RT-AX95Q, hardware v1) on GNUton Asuswrt-Merlin 3004.388.x, TP-Link Archer A7 v5 on OpenWrt 25.12.5, TP-Link Archer AX21 v5 on stock firmware, Raspberry Pi 4 Model B on Raspberry Pi OS Lite 64-bit, k3s v1.34, an Apple-silicon Mac with Lima. Versions seen on the download pages in October 2026 are given where a download is named |
| **Also works for** | Any subset of the build. Every phase links to pages that stand on their own. Similar hardware should follow the same order; not tested by the author |
| **Time** | A long weekend from nothing. About an evening if you have the backups from [Backups and secrets](../operations/backups-and-secrets.md) |
| **You need first** | Nothing. Read [Overview](overview.md) for how the pieces fit and [Conventions](conventions.md) for the example values |

## How it works

The order is set by dependencies, and two of them catch people out:

- **DNS comes last but is configured first.** The router is told to hand out Pi-hole as the only DNS server long before Pi-hole exists. Until Pi-hole runs (Phase 9), the network has no working DNS for ordinary devices. [DNS design](../network/dns-design.md#the-no-dns-window-during-a-rebuild) explains how to work through that window; Phase 2 repeats the short version.
- **The cluster never depends on itself.** The Pis use outside DNS servers and fixed addresses, so they can start Pi-hole without Pi-hole. That is why the Pis are prepared (Phase 5) before the cluster is built, and why the router needs a per-device exception for each node.

Everything else is ordinary layering: firmware, then settings, then scripts, then backups; machines, then the cluster, then addresses for services, then apps.

Where this page gives steps of its own (flashing, Entware, first boot, Helm), they come from the vendors' and projects' documentation. The author's devices were already flashed when the rest of this wiki was written, so **those steps were not run by the author for this page** and are marked "Not verified". The steps on the linked pages carry their own labels.

## Before you start

### Decide

| Decision | Where it is explained |
| --- | --- |
| Your subnet, local domain, IPv6 prefix and host names | [Conventions](conventions.md#choosing-your-own-values) |
| Which pieces you build at all (no IPv6, no IoT network, no Mac, no cluster) | [Overview](overview.md#what-you-can-leave-out) |
| Which addresses are fixed and where the DHCP pool starts | [Address plan](../network/address-plan.md) |
| Three or four cluster servers. Four tolerate only one failure, the same as three | [HA k3s cluster](../kubernetes/k3s-ha-cluster.md) |

### Shopping and accounts

| Item | Notes |
| --- | --- |
| ASUS ZenWiFi XT8, one or two | GNUton lists only **RT-AX95Q v1**. ASUS sells a hardware version 2 with its own stock firmware; GNUton support for it was not found. Check the label before you buy a used one |
| USB drive for the router, **2 GB or more**, formatted ext4 | Entware, Skynet's swap file and Scribe's logs live on it. Skynet's documentation asks for at least 2 GB so there is room for swap. Any cheap flash drive is enough |
| TP-Link Archer A7 **v5** | The version matters for the OpenWrt image. Optional |
| TP-Link Archer AX21 v5 | Optional. Stock firmware only |
| Raspberry Pi 4 or 5, three | 2 GB is the k3s minimum for a server; 8 GB is comfortable |
| One SSD or NVMe drive per Pi | In a USB 3 enclosure (Pi 4), or on an M.2 HAT+ (Pi 5). Not an SD card and preferably not a spinning hard disk: etcd needs fast writes ([Raspberry Pi](../hardware/raspberry-pi.md#step-3-check-that-the-disk-is-good-enough-for-etcd)) |
| The official power supply for each Pi model | Under-powered USB drives drop out under load |
| One spare microSD card | For a first boot from SD if you take that route, and for the bootloader recovery image |
| Ethernet cables, and a switch if the router has too few ports | Every Pi and access point is wired |
| An Apple-silicon Mac on wired Ethernet | Optional fourth server |
| A computer with `ssh`, `scp` and a browser | Your workstation for every phase |
| A password manager | For Wi-Fi keys, the k3s token, the tunnel token and every admin password. None of them go in Git |
| A Cloudflare account and a domain whose DNS is on Cloudflare | Only for Seerr through a tunnel. The Zero Trust free plan is enough |
| A clone of this repository | `git clone https://github.com/<YOUR_ACCOUNT>/homelab-k3s-public.git`. Commands that name `files/...` run from its root |

## Steps

### Phase 0. Download everything first

Once the router is reset you may have no internet for a while, so fetch every image first. Exact files, where to find them, and how to verify them are on [Software and firmware](../operations/software-and-firmware.md).

| Download | Exact file (versions seen in October 2026) | Where |
| --- | --- | --- |
| GNUton firmware for the XT8 | `RT-AX95Q_3004_388.11_1-gnuton1_puresqubi.w` and its `.w.md5` | [GNUton releases](https://github.com/gnuton/asuswrt-merlin.ng/releases) |
| ASUS stock firmware for the XT8 (your way back) | The HW 1.0 build, 3.0.0.4.388_24854 | [ASUS XT8 support page](https://www.asus.com/networking-iot-servers/whole-home-mesh-wifi-system/zenwifi-wifi-systems/asus-zenwifi-ax-xt8/helpdesk_bios/) |
| OpenWrt factory image for the Archer A7 v5 | `openwrt-25.12.5-ath79-generic-tplink_archer-a7-v5-squashfs-factory.bin`, plus `sha256sums` | [OpenWrt 25.12.5 ath79/generic](https://downloads.openwrt.org/releases/25.12.5/targets/ath79/generic/) |
| OpenWrt sysupgrade image (for later upgrades) | `openwrt-25.12.5-ath79-generic-tplink_archer-a7-v5-squashfs-sysupgrade.bin` | Same folder |
| Archer AX21 v5 stock firmware | `Archer AX21_V5.6_250814.zip` (1.1.2 Build 20250814, US) | [TP-Link AX21 v5 downloads](https://www.tp-link.com/us/support/download/archer-ax21/v5/) |
| Raspberry Pi Imager | v2.0.11.1 or the "latest" installer | [raspberrypi.com/software](https://www.raspberrypi.com/software/) |
| Raspberry Pi OS Lite (64-bit) | Debian 13 "trixie" release, or let Imager download it | [Raspberry Pi OS](https://www.raspberrypi.com/software/operating-systems/) |
| Lima (Mac only) | Through Homebrew | [Lima installation](https://lima-vm.io/docs/installation/) |

Also copy your backups (if any) onto the workstation: the router `.CFG` and JFFS backups, the OpenWrt backup, the Homebridge backup, the etcd snapshot and token.

**Checkpoint:** every file is on your workstation, and each firmware file's checksum matches (commands in Phase 1 and Phase 4).

### Phase 1. Main router firmware

**Goal:** the XT8 runs GNUton Asuswrt-Merlin from a clean factory reset.
**Needs:** the XT8, a computer on a cable to one of its LAN ports, the `.w` and `.w.md5` files.

> **Not verified:** the flashing, reset and revert steps in this phase come from the Asuswrt-Merlin and GNUton documentation. They were not recorded on the author's hardware.

#### Step 1.1. Check the hardware version

On stock firmware with SSH enabled, or later on Merlin:

**Run on: the router**

```sh
nvram get productid
```

It must print `RT-AX95Q`. That only tells you the model; the hardware version (1.0 or V2) is on the label or the box. Do not flash an `RT-AXE95Q_*` file: that is the ZenWiFi ET8. A wrong-model image has caused version mismatches across mesh nodes.

#### Step 1.2. Verify the download

**Run on: your computer**, in the download folder.

```sh
cat RT-AX95Q_3004_388.11_1-gnuton1_puresqubi.w.md5
md5sum RT-AX95Q_3004_388.11_1-gnuton1_puresqubi.w
```

On macOS use `md5 RT-AX95Q_3004_388.11_1-gnuton1_puresqubi.w`. The two hashes must match. GNUton publishes `.md5`, not `.sha256`. The `.zip` and `.tar.gz` files on a release page are GitHub's source archives; never flash those.

#### Step 1.3. Flash

1. Reboot the router first. A router that has been up for a long time may lack the free memory to accept the image.
2. Log in to the web UI at `http://192.168.50.1` (a factory-new XT8 uses `192.168.50.1` or `router.asus.com`).
3. **Administration > Firmware Upgrade**, upload the `.w` file as a manual update, and wait. Do not power it off during the upgrade.
4. Clear the browser cache or force-refresh before you judge the new UI. A stale cache has made parts of the Network Map look broken.

#### Step 1.4. Factory reset

A reset is advised after the first flash from stock and after any big version jump. Do one now, while there is nothing to lose:

- **Administration > Restore/Save/Upload Setting > Factory default**, or
- hold the reset button for more than 5 seconds, or power on while holding WPS.

The old "30/30/30" reset does not work on these models.

> **Pitfall:** never restore a `.CFG` settings file that was saved on a different firmware version. Enter the settings again instead (Phase 2), or use the bootstrap script, which does most of them.

#### Step 1.5. If it goes wrong: recovery mode

Power on while holding the reset button, and release it when the power LED blinks. Give your computer the static address `192.168.1.100/24`, then browse to `192.168.1.1` or use the ASUS Firmware Recovery Tool to upload a firmware file. Firmware updates do not touch the bootloader, so recovery mode stays available.

#### Step 1.6. Going back to stock

Upload the ASUS stock image for your hardware version through the same Firmware Upgrade page, then factory reset. ASUS publishes SHA-256 values for its images on the support page; check them with `sha256sum` (macOS: `shasum -a 256`). ASUS strongly recommends a factory reset after installing some of its XT8 builds.

**Checkpoint:** the web UI header shows `3004.388.11_1-gnuton1` (or the version you flashed), the router is on factory defaults, and you can log in.

### Phase 2. Main router settings, add-ons and scripts

**Goal:** the router serves the LAN with your addresses, has SSH and JFFS scripts, has Entware and the add-ons on its USB drive, and runs the bootstrap script.
**Needs:** Phase 1, the USB drive, your values from [Conventions](conventions.md).

#### Step 2.1. Basic settings

Follow [ASUS ZenWiFi XT8, Step 1](../hardware/asus-zenwifi-xt8.md#step-1-gui-settings). At minimum before going on: LAN IP, DHCP pool, **Administration > System > Enable JFFS custom scripts and configs = Yes**, SSH on (LAN only), and the Wi-Fi names and keys. Reboot once after enabling JFFS scripts.

Prefer SSH keys over passwords and HTTPS for the web UI from the start: [Security review](../operations/security-review.md#step-3-router-administration).

#### Step 2.2. Prepare the USB drive

Plug the drive into the router's USB port.

**Run on: the router** (`ssh -p 22 admin@192.168.50.1`)

```sh
amtm
```

amtm, the Asuswrt-Merlin terminal menu, is built into the firmware. In its menu:

1. **`fd`**: format the disk. Choose ext4. **This erases the drive.** Entware needs ext2, ext3 or ext4.
2. Give the drive a label; it is mounted at `/tmp/mnt/<label>`. The examples in this wiki use the label `gateway`, so paths read `/tmp/mnt/gateway/...`.
3. Create a swap file from amtm's swap option. Skynet expects swap.

#### Step 2.3. Install Entware

Still in amtm, choose **`ep`** to install Entware, the package manager most add-ons need.

> **Pitfall:** Entware cannot coexist with the older Optware. If ASUS Download Master was ever installed on the drive, remove it first.

**Run on: the router**

```sh
opkg update
opkg list-installed | head
```

`opkg` answering means Entware works.

#### Step 2.4. Install the add-ons through amtm

From the amtm menu, install:

| Add-on | Needed for | Current home (October 2026) |
| --- | --- | --- |
| Skynet | Blocking known-bad addresses | `Adamm00/IPSet_ASUS` |
| YazDHCP | More DHCP reservations, kept in files | `AMTM-OSR/YazDHCP` |
| scribe | syslog-ng and logrotate, logs on the USB drive | `AMTM-OSR/scribe` |
| uiScribe (optional) | A web page for scribe's logs | `AMTM-OSR/uiScribe` |
| scMerlin (optional) | Service and script controls in the web UI | `AMTM-OSR/scMerlin` |

Install **Skynet before scribe**. If scribe was installed first, run scribe's install again and force it, so it picks up Skynet's log handlers.

Then do the one manual fix scribe needs, from [ASUS ZenWiFi XT8, Step 3](../hardware/asus-zenwifi-xt8.md#step-3-add-ons) (the logrotate state folder), and check rotation as in [Router logging](../network/router-logging.md).

> **Pitfall:** the original repositories of YazDHCP, uiScribe, scMerlin (`jackyaz/...`) and scribe (`cynicastic/scribe`) are archived. amtm installs from the new `AMTM-OSR` homes. If an old install still updates from an archived repository, see [Software and firmware](../operations/software-and-firmware.md#amtm-entware-and-the-router-add-ons).

> **Pitfall:** do not install dnscrypt-proxy on the router ([ASUS ZenWiFi XT8](../hardware/asus-zenwifi-xt8.md#removing-dnscrypt-proxy)).

#### Step 2.5. Guest network, bootstrap script, lists, backups

In this order, from the router page:

1. Guest network for IoT devices: [Step 2](../hardware/asus-zenwifi-xt8.md#step-2-guest-network-for-iot-devices), with the design in [Isolated IoT network, Part 1](../network/isolated-iot-network.md#part-1-the-guest-network-on-the-router).
2. The bootstrap script: [Step 4](../hardware/asus-zenwifi-xt8.md#step-4-run-the-bootstrap-script). It also installs the local-only IPv6 scripts ([Local-only IPv6](../network/local-only-ipv6.md#step-2-install-the-router-scripts)) and the rules for controlled access into the IoT network ([Part 3](../network/isolated-iot-network.md#part-3-controlled-access-from-the-main-lan-into-the-iot-network)).
3. Per-device lists: [Step 5](../hardware/asus-zenwifi-xt8.md#step-5-per-device-lists).
4. Backups: [Step 6](../hardware/asus-zenwifi-xt8.md#step-6-back-up).

#### Step 2.6. Get through the no-DNS window

The bootstrap script points every device at Pi-hole (`192.168.50.11`), which does not exist yet. Until Phase 9:

1. Set your own computer's DNS to `9.9.9.9` by hand.
2. Add your computer to **LAN > DNS Director** as **No Redirection**.
3. Undo both after Phase 9.

Other devices on the network have no DNS meanwhile. If the household needs the internet during the build, use the emergency bypass in [DNS design](../network/dns-design.md#emergency-bypass) and put it back afterwards.

**Checkpoint:** `sh /jffs/xt8-bootstrap.sh verify` shows every line `PASS` except `Pi-hole answers on IPv4`, which fails until Phase 9. `ip -4 -o addr show | grep 192.168.101` shows the guest bridge. Your computer has an `fd00:` IPv6 address. The backups are off the router.

### Phase 3. AiMesh node

**Goal:** the second XT8 extends Wi-Fi, including the IoT network, and reboots weekly.
**Needs:** Phase 2.

1. A node can run Merlin only if the main router runs Merlin. The Merlin wiki recommends leaving nodes on stock; this build runs GNUton on the node too, because the node script needs JFFS and `services-start`.
2. Reset the node to factory defaults (adding or re-adding a node requires it), then add it under **AiMesh** on the main router.
3. If the node is not on the same GNUton version as the router, update it from the main router: **Administration > Firmware Upgrade**, then the **Upload** link next to the node, and choose the same `.w` file. Merlin and GNUton nodes are never updated automatically. Avoid builds from very different dates on router and node.
4. Run the node script: [AiMesh node](../hardware/asus-aimesh-node.md#step-2-run-the-node-script).

> **Not verified:** steps 1 to 3 are from the Asuswrt-Merlin wiki's AiMesh page; the author's node was already on GNUton.

**Checkpoint:** the node shows as connected in the AiMesh page with the same firmware version as the router, and `cru l` on the node lists the weekly reboot ([AiMesh node, Check it](../hardware/asus-aimesh-node.md#check-it)).

### Phase 4. Access points

**Goal:** extra Wi-Fi that only bridges onto the LAN.
**Needs:** Phase 2. Skip what you do not own.

#### Step 4.1. Flash OpenWrt onto the Archer A7 v5

> **Not verified:** the flashing steps come from OpenWrt's published image names and the general "factory image from stock" method. The device page on the OpenWrt Table of Hardware, which holds model-specific notes (TFTP recovery, region-locked stock builds), could not be opened while writing. Read it in a browser before flashing.

**Run on: your computer**, in the download folder.

```sh
grep 'tplink_archer-a7-v5-squashfs-factory.bin' sha256sums | sha256sum -c -
```

On macOS use `shasum -a 256 -c` instead of `sha256sum -c`. It must print `OK`.

1. Connect your computer to a LAN port of the A7, not to your main network. The stock firmware runs its own DHCP server.
2. Log in to the TP-Link web UI and open its firmware upgrade page.
3. Upload the **factory** image (`...-squashfs-factory.bin`). Never upload a `sysupgrade` image to stock firmware.
4. Wait for the reboot. OpenWrt answers at `http://192.168.1.1` with no password.

Then continue on [Archer A7 on OpenWrt](../hardware/tp-link-archer-a7-openwrt.md#step-3-set-a-root-password) from Step 3 (root password), Step 4 (setup script) and onwards. If you want the IoT network on it too: [Isolated IoT network, Part 2](../network/isolated-iot-network.md#part-2-extending-the-network-to-an-openwrt-access-point).

Later upgrades use the **sysupgrade** image or Attended Sysupgrade, never the factory image: [Software and firmware](../operations/software-and-firmware.md#openwrt-on-the-archer-a7-v5). Going back to TP-Link firmware needs a stock image prepared as described on the OpenWrt device page; not covered here.

#### Step 4.2. Archer AX21 on stock firmware

Update it to the current stock firmware first (**Advanced > System > Firmware Upgrade**, upload the `.bin` from inside the `.zip`), then follow [Archer AX21](../hardware/tp-link-archer-ax21.md). Build 20250814 (1.1.2) cannot be rolled back.

**Checkpoint:** `ssh root@192.168.50.3` works and the [A7 checks](../hardware/tp-link-archer-a7-openwrt.md#check-it) pass; the AX21 answers at `192.168.50.4`; a phone on either AP gets a `192.168.50.x` address from the main router.

### Phase 5. Raspberry Pis

**Goal:** three Pis booting from SSD or NVMe, with fixed addresses, outside DNS and the kernel settings k3s needs.
**Needs:** Phase 2 (for the network), the SSDs.

There are two ways onto the SSD. Route A is what the author used.

#### Route A. Write the SSD directly from your computer

Put the SSD in its USB enclosure, connect it to your computer, and write it with Raspberry Pi Imager:

1. **Device**: your Pi model.
2. **OS**: Raspberry Pi OS Lite (64-bit). It is listed under the "Raspberry Pi OS (other)" group (group name not verified).
3. **Storage**: the SSD. Leave **Exclude system drives** on, so you cannot overwrite your computer's own disk.
4. **Customisation**: hostname (`server-1`), localisation (time zone), a lower-case user name and password, and **Enable SSH**. Prefer **public-key authentication** and paste your workstation's public key. Skip Wi-Fi; the Pis are wired.
5. **Write**, confirm the erase, and let it verify.

Plug the SSD into a blue USB 3 port, leave the SD slot empty, power on. A Pi 4 made since late 2020 tries USB when no SD card is present. If it does not boot, use Route B's boot-order step.

#### Route B. First boot from an SD card, then move to the SSD

> **Not verified:** this route is from the Raspberry Pi documentation; the author's Pis booted from USB without it.

1. Write Raspberry Pi OS Lite (64-bit) to the SD card with Imager, customised as in Route A. Boot the Pi from it.
2. Update the system and the bootloader.

   **Run on: the Pi**

   ```sh
   sudo apt update && sudo apt full-upgrade -y
   sudo rpi-eeprom-update
   sudo rpi-eeprom-update -a
   sudo reboot
   ```

   The second line reports whether a newer bootloader exists; the third installs it at the next boot.

3. Write the OS to the SSD. Either:
   - power off, connect the blank SSD, remove the SD card and power on while holding **Shift** to start **Network Install** (Pi 4 and later, needs a monitor, keyboard and wired Ethernet). It runs Imager on the Pi with the same customisation screens; or
   - stay booted from the SD card and use Imager's command-line mode, then finish first-boot setup at a console, because the command-line mode does not apply the customisation:

     **Run on: the Pi**

     ```sh
     sudo apt install -y rpi-imager
     lsblk
     sudo rpi-imager --cli <IMAGE_FILE>.img.xz /dev/sda
     ```

     Use the device `lsblk` shows for the SSD: `/dev/sda` for USB, `/dev/nvme0n1` for NVMe. A brand-new NVMe drive may need erasing first (Imager's Erase option) before it shows a partition.

4. Set the boot order so the SSD is tried.

   **Run on: the Pi**

   ```sh
   sudo raspi-config
   ```

   **Advanced Options > Boot Order** (shown as "Bootloader Order" on some versions), and pick the USB or NVMe option. Or edit it directly with `sudo rpi-eeprom-config --edit` and set `BOOT_ORDER`. It is read **right to left**: `1` SD, `4` USB, `6` NVMe (Pi 5), `f` start over.

   | `BOOT_ORDER` | Tries |
   | --- | --- |
   | `0xf41` | SD, then USB, repeat. The default when unset |
   | `0xf14` | USB, then SD |
   | `0xf46` | NVMe, then USB |
   | `0xf416` | NVMe, then SD, then USB (derived from the rule, not printed in the docs) |

   On a Pi 5 with a non-HAT+ NVMe adapter, also add `PCIE_PROBE=1` to the bootloader config and `dtparam=pciex1` to `/boot/firmware/config.txt`. PCIe Gen 3 (`dtparam=pciex1_gen=3`) is not certified on the Pi 5 and may be unstable.

5. Power off, remove the SD card, power on.

#### Then, on every Pi

Continue on [Raspberry Pi](../hardware/raspberry-pi.md) from [Step 3](../hardware/raspberry-pi.md#step-3-check-that-the-disk-is-good-enough-for-etcd): disk check, updates, cgroups, swap off, fixed addresses and own DNS, time.

Then give each Pi a **Router** rule in DNS Director on the main router, so its DNS is never redirected to Pi-hole ([ASUS ZenWiFi XT8](../hardware/asus-zenwifi-xt8.md#if-you-also-have-the-k3s-cluster-that-runs-pi-hole)).

**Checkpoint:** on each Pi, `findmnt -no SOURCE /` shows `/dev/sda…` or `/dev/nvme…`; `grep nameserver /etc/resolv.conf` shows only `1.1.1.1` and `9.9.9.9`; `nslookup ghcr.io` answers; the [Raspberry Pi checks](../hardware/raspberry-pi.md#check-it) pass.

### Phase 6. The k3s cluster

**Goal:** three k3s servers on embedded etcd, dual-stack.
**Needs:** Phase 5.

Follow [HA k3s cluster](../kubernetes/k3s-ha-cluster.md#step-1-first-server) Steps 1 to 5. Pin the version with `INSTALL_K3S_VERSION` (the full tag, such as `v1.34.12+k3s1`), and use the same version on every server. Before you choose a version, read [Software and firmware](../operations/software-and-firmware.md#k3s): the `stable` channel moves between minor versions.

Store the join token in your password manager the moment you print it.

**Checkpoint:** `sudo kubectl get nodes` shows three nodes `Ready` with roles `control-plane,etcd`, all on the same version, and the first etcd snapshot exists ([Step 5](../kubernetes/k3s-ha-cluster.md#step-5-take-a-snapshot)).

### Phase 7. kubectl and Helm

**Goal:** you can run `kubectl` and `helm` against the cluster.
**Needs:** Phase 6.

k3s includes `kubectl`; on a server, use `sudo kubectl`. For a laptop, see [Client devices, Step 6](../apps/client-devices.md#step-6-kubectl-from-a-laptop).

Helm is not included. The app pages run it on `server-1`. Install it there with the project's install script:

**Run on: server-1**

```sh
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
chmod 700 get_helm.sh
./get_helm.sh
helm version
```

The script downloads the newest Helm 4 release for the Pi's architecture and installs it in `/usr/local/bin`. Read it before you run it.

Helm needs to find the cluster. k3s keeps the admin kubeconfig at `/etc/rancher/k3s/k3s.yaml`, readable by root only. Either set it per session:

```sh
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
sudo -E helm list -A
```

or pass it each time: `sudo helm --kubeconfig /etc/rancher/k3s/k3s.yaml list -A`.

> **Not verified:** the Helm version the author used was not recorded. The commands in this wiki use only `helm repo add`, `helm repo update`, `helm upgrade --install` with `-n`, `-f`, `--version` and `--create-namespace`, which Helm 4 documents. Some chart READMEs still say "Helm 3 required"; that was not found to matter here.

**Checkpoint:** `helm version` prints a version, and `sudo -E helm list -A` returns a (possibly empty) list without an error.

### Phase 8. Addresses for services, and cluster DNS

**Goal:** ServiceLB off, MetalLB handing out `.11` to `.15`, Traefik on `.12`, the API on `.10` through kube-vip, three CoreDNS replicas.
**Needs:** Phase 6.

1. [Load balancers](../kubernetes/load-balancers.md#step-1-disable-servicelb-on-every-server), Steps 1 to 5.
2. [CoreDNS](../kubernetes/coredns.md), Steps 1 to 3.

**Checkpoint:** `sudo kubectl get svc -A | grep LoadBalancer` shows Traefik on `192.168.50.12`; `sudo kubectl --server https://192.168.50.10:6443 get nodes` answers; the [load balancer checks](../kubernetes/load-balancers.md#check-it) pass.

### Phase 9. Pi-hole, and DNS for the house

**Goal:** Pi-hole answers on `192.168.50.11` and `fd00:1234:5678:50::11`, and the router's settings from Phase 2 start working.
**Needs:** Phases 7 and 8.

1. [Pi-hole](../apps/pihole.md), Steps 1 to 5.
2. [DNS design](../network/dns-design.md): confirm the exceptions and the router's own upstream.
3. Undo the no-DNS-window workarounds from Step 2.6.

**Checkpoint:** `sh /jffs/xt8-bootstrap.sh verify` on the router now shows `0 failed`; `nslookup example.com 192.168.50.11` answers from a client; the [DNS checks](../network/dns-design.md#check-it) pass.

### Phase 10. Optional fourth server

[Mac in a Lima VM](../hardware/mac-lima-vm.md). It joins through the API address, so Phase 8 must be done.

**Checkpoint:** `server-4` is `Ready` and does not carry the `kube-vip-host` label.

### Phase 11. Apps

Each is independent.

| App | Page | Also needs |
| --- | --- | --- |
| Homebridge | [Homebridge](../apps/homebridge.md) | Traefik on `.12`, a DNS name for the UI |
| Kasa devices on the IoT network | [Kasa across networks](../apps/homebridge-kasa-across-networks.md) | The router rules from Phase 2 |
| Cameras | [Cameras](../apps/homebridge-cameras.md) | Homebridge |
| Seerr through a Cloudflare tunnel | [Seerr](../apps/seerr-cloudflare-tunnel.md) | The Cloudflare account and domain |
| Client machines | [Client devices](../apps/client-devices.md) | Pi-hole |

**Checkpoint:** each app's own Check it section passes.

### Phase 12. Hardening, tidying, proof and backups

1. [Node firewall](../kubernetes/node-firewall.md) (optional).
2. [Security review](../operations/security-review.md): go through the router and access point settings once.
3. [Address plan](../network/address-plan.md): reserve every fixed-role device, including every port-forward target.
4. [Verification](../operations/verification.md): the end-to-end tests.
5. [Backups and secrets](../operations/backups-and-secrets.md): take every backup and put it off the devices.
6. [Maintenance](../operations/maintenance.md): set the weekly reboots and the monthly checks.

**Checkpoint:** every verification test passes and every backup exists in two places.

## Build or rebuild just one piece

| Piece | Depends on | Start here | Re-check after |
| --- | --- | --- | --- |
| Main router (after a reset or new firmware) | Firmware file, USB drive | Phase 1, then [ASUS ZenWiFi XT8](../hardware/asus-zenwifi-xt8.md) (restore the `.CFG` only onto the same firmware version) | `verify` on the router; IoT access ([Kasa across networks](../apps/homebridge-kasa-across-networks.md#check-it)); clients get `fd00:` addresses; node and APs still connected |
| Router add-ons only | Entware on the USB drive | Phase 2, Steps 2.2 to 2.4 | Log rotation ([Router logging](../network/router-logging.md#check-it)); `firewall-start` still has Skynet's line and the marked block |
| AiMesh node | Main router on Merlin/GNUton | Phase 3 | `cru l` on the node; guest network reaches the node |
| OpenWrt access point | Main router | Restore its backup ([Step 1](../hardware/tp-link-archer-a7-openwrt.md#step-1-restore-from-a-backup-if-you-have-one)), else Phase 4.1 | [A7 checks](../hardware/tp-link-archer-a7-openwrt.md#check-it); IoT SSID if used |
| Stock access point | Main router | [Archer AX21](../hardware/tp-link-archer-ax21.md) | Still in Access Point mode at `.4` |
| One Raspberry Pi | The cluster has quorum without it | Phase 5, then rejoin as in [HA k3s cluster](../kubernetes/k3s-ha-cluster.md#step-2-second-and-third-server) (delete the old node object first) | `sudo kubectl get nodes`; Pi-hole placement one pod per Pi; DNS Director rule for its MAC |
| The whole cluster | Pis prepared; etcd snapshot and token if restoring | Phase 6, or restore ([Backups and secrets](../operations/backups-and-secrets.md#step-4-cluster-etcd-snapshot-and-token)) | Everything from Phase 8 on |
| MetalLB, kube-vip, Traefik address | Cluster | [Load balancers](../kubernetes/load-balancers.md) | `.10`, `.11`, `.12` answer |
| Pi-hole | MetalLB, Traefik | [Pi-hole](../apps/pihole.md) | Router `verify`; one pod per Pi, `2/2` |
| Homebridge | Traefik; router IoT rules for Kasa | [Homebridge](../apps/homebridge.md), restore its backup | Home app accessories respond; pod DNS block |
| Seerr and tunnel | Traefik; Cloudflare | [Seerr](../apps/seerr-cloudflare-tunnel.md) | Public name loads; no 502 |
| Mac VM | Cluster with kube-vip | [Mac in a Lima VM](../hardware/mac-lima-vm.md) | Joined on `lima0` under the right name |
| Helm on a new admin machine | Cluster | Phase 7 | `helm list -A` |

## Check it

After the last phase:

**Run on: the router**

```sh
sh /jffs/xt8-bootstrap.sh verify
```

Expected: a last line ending `0 failed.`

**Run on: server-1**

```sh
sudo kubectl get nodes -o wide
sudo kubectl get svc -A | grep LoadBalancer
sudo kubectl -n pihole get pods -o wide
```

Expected: every node `Ready` on one version; Pi-hole on `192.168.50.11` and Traefik on `192.168.50.12`; three Pi-hole pods `2/2`, one per Pi. Then run the whole of [Verification](../operations/verification.md).

## Pitfalls

| What happens | Why | Avoid or recover |
| --- | --- | --- |
| No device on the network can resolve names during the build | The router hands out Pi-hole before Pi-hole exists | Expected until Phase 9. Use the workarounds in Step 2.6 |
| Pi-hole cannot be pulled after a restart | A node used Pi-hole for its own DNS | Node DNS is `1.1.1.1` and `9.9.9.9`, and every node has a DNS Director **Router** rule (Phase 5) |
| Router settings restore makes things worse | The `.CFG` file came from another firmware version | Re-enter the settings and use the bootstrap script |
| A flashed router behaves oddly after a big jump | Old settings carried over | Factory reset after the first flash and after big version jumps |
| Mesh node falls back to a slower backhaul, or drops clients, after an upgrade | Reported by some users after a dirty upgrade | Reset the node with its button and re-add it to AiMesh |
| `INSTALL_K3S_VERSION='v1.34'` fails | The installer wants a full tag | Use `v1.34.12+k3s1` or set `INSTALL_K3S_CHANNEL=v1.34` |
| An automated k3s upgrade jumps two minor versions | A plan followed the `stable` channel | Pin a version or a minor channel ([Software and firmware](../operations/software-and-firmware.md#k3s)) |
| The A7 comes up routing at `192.168.1.1` on your LAN | A fresh OpenWrt install runs DHCP | Configure it on a direct cable first (Phase 4) |
| An Entware add-on updates from an archived repository | Installed before the move to `AMTM-OSR` | Update through amtm, or reinstall from the new home |
| A secret ends up in Git or a chat while you build | Copying config files around | Placeholders only; if it happened, rotate ([Backups and secrets](../operations/backups-and-secrets.md#if-a-secret-was-exposed)) |

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Router rejects the firmware file | Not enough free memory, or the wrong model's file | Reboot and retry; check the file is `RT-AX95Q_*` and the MD5 matches |
| Router does not come back after a flash | Interrupted or bad flash | Recovery mode (Step 1.5) |
| `amtm` or Entware downloads hang | Unresolved; Skynet is suspected | Disable Skynet briefly and retry |
| `ep` refuses to install Entware | The drive is not ext2/3/4, or Optware is present | Format with `fd`; remove Download Master |
| The A7 stock UI refuses the OpenWrt file | Wrong image type or hardware version | Use the `factory` image for `archer-a7-v5`; read the OpenWrt device page |
| A Pi sits at the rainbow or bootloader screen | Boot order does not include the SSD, or an old bootloader | Route B, steps 2 and 4 |
| `helm` says it cannot reach the cluster | No kubeconfig | `export KUBECONFIG=/etc/rancher/k3s/k3s.yaml` and `sudo -E helm ...` |
| Anything else | | [Troubleshooting](../operations/troubleshooting.md) |

## References

- [gnuton/asuswrt-merlin.ng releases](https://github.com/gnuton/asuswrt-merlin.ng/releases): GNUton firmware files for the RT-AX95Q, with `.md5` checksums.
- [Asuswrt-Merlin wiki: Installation](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Installation): flashing from stock, when to reset, recovery mode.
- [Asuswrt-Merlin wiki: Reverting](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Reverting): going back to ASUS stock firmware.
- [Asuswrt-Merlin wiki: AiMesh](https://github.com/RMerl/asuswrt-merlin.ng/wiki/AiMesh): which firmware a node may run and how Merlin nodes are updated.
- [Asuswrt-Merlin wiki: Entware](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Entware): installing Entware with amtm and the disk format it needs.
- [Asuswrt-Merlin wiki: AMTM](https://github.com/RMerl/asuswrt-merlin.ng/wiki/AMTM): what amtm is and how to start it.
- [OpenWrt sysupgrade data for the Archer A7 v5](https://sysupgrade.openwrt.org/json/v1/releases/25.12.5/targets/ath79/generic/tplink_archer-a7-v5.json): the exact factory and sysupgrade image names for 25.12.5.
- [Raspberry Pi documentation: Install an operating system](https://raw.githubusercontent.com/raspberrypi/documentation/master/documentation/asciidoc/computers/getting-started/install.adoc): Imager steps, customisation and Network Install.
- [Raspberry Pi documentation: bootloader configuration](https://raw.githubusercontent.com/raspberrypi/documentation/master/documentation/asciidoc/computers/raspberry-pi/eeprom-bootloader.adoc): `BOOT_ORDER` and `PCIE_PROBE`.
- [Helm: Installing Helm](https://helm.sh/docs/intro/install/): the install script and package options.
