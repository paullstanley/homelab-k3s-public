# Preparing a Raspberry Pi to be a k3s server

You end up with a Raspberry Pi that boots from a USB or NVMe drive, has a fixed IPv4 address and a fixed short IPv6 address, resolves names without depending on anything inside the cluster, and has the kernel settings Kubernetes needs. At that point it is ready for k3s to be installed on it.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | Raspberry Pi 4 Model B Rev 1.5 (one with 8 GB RAM, two with 2 GB), Raspberry Pi OS Lite 64-bit based on Debian 12 "bookworm" (kernels 6.6 and 6.12) and Debian 13 "trixie" (kernel 6.12), booting from USB drives with no SD card, wired Ethernet (`eth0`) |
| **Also works for** | Raspberry Pi 5 and Pi 400 (same bootloader tools; NVMe on the Pi 5). Not tested by the author. The USB-boot table below also lists older models from the Raspberry Pi documentation; none of those were tested |
| **Time** | 30 to 45 minutes per Pi |
| **You need first** | A wired network with a free fixed address per Pi. For the IPv6 parts: a local IPv6 prefix on the LAN, see [Local-only IPv6](../network/local-only-ipv6.md). Next page after this one: [Highly available k3s](../kubernetes/k3s-ha-cluster.md) |

## How it works

A k3s **server** is a control-plane node: it runs the Kubernetes API, the cluster database (etcd) and ordinary workloads all at once. Four things about the host decide whether that goes well.

- **The disk.** etcd writes to disk constantly and waits for each write to be confirmed. An SD card wears out and is too slow. A spinning hard disk works but is slow enough to cause restarts. An SSD or NVMe drive is what you want.
- **The addresses.** Other servers find an etcd member by its address. If the address changes, the member is lost. So the address is set on the Pi itself, not left to DHCP (the service that hands out addresses automatically). On a dual-stack cluster (IPv4 and IPv6 together) the node needs both addresses before k3s starts.
- **The node's own DNS.** The node must look up the image registry to start any pod, including the pod that provides DNS for your house if you run one. So the node uses outside resolvers directly and never a DNS server that runs in the cluster.
- **Kernel settings.** Kubernetes limits each container's memory through "cgroups" (control groups, the kernel's resource accounting). Raspberry Pi OS ships with the memory cgroup switched off, so it has to be turned on in the kernel command line.

## Before you start

Decide and write down, for each Pi:

| Value | Example | Notes |
| --- | --- | --- |
| Hostname | `server-1`, `server-2`, `server-3` | Becomes the Kubernetes node name. Use lower case; a hostname with a capital letter ends up as a lower-case node name, and the mismatch is confusing later |
| IPv4 address | `192.168.50.5`, `.6`, `.7` | Outside the router's DHCP pool. In the example network the pool is `.20` to `.254` and `.2` to `.19` are kept for fixed devices |
| IPv6 address | `fd00:1234:5678:50::5`, `::6`, `::7` | A short address inside your LAN's /64. Only needed for a dual-stack cluster |
| Gateway | `192.168.50.1` | Your router |
| The node's DNS servers | `1.1.1.1` and `9.9.9.9` | Any two public resolvers. Not Pi-hole, not the cluster |
| Time zone | for example `America/New_York` | Set in the Imager |

Hardware to check before you buy or reuse anything:

| Item | Guidance |
| --- | --- |
| Drive | An SSD or NVMe drive in a USB enclosure. Not an SD card. Not a spinning hard disk if you can avoid it (see [Step 3](#step-3-check-that-the-disk-is-good-enough-for-etcd)) |
| Memory | 2 GB is the minimum k3s lists for a server. It works, but such a Pi then carries the control plane, etcd and whatever pods land on it. 8 GB is comfortable |
| Power | The official 5.1 V 3 A supply (Pi 4), or a powered enclosure or hub for the drive |
| Network | Wired. Wi-Fi (`wlan0`) is not used |

## Steps

### Step 1. Install the operating system on the USB drive

**Run on: your computer.**

1. Open Raspberry Pi Imager. Choose **Raspberry Pi OS Lite (64-bit)**.
2. Choose the **USB drive itself** as the storage, not an SD card.
3. In the Imager's settings set the hostname (`server-1`), a user name and password, the time zone, and enable SSH.
4. Write the image.

Then plug the drive into a **blue USB 3 port** on the Pi, leave the SD slot empty, and power on.

If it boots, go to Step 3. If it sits at the rainbow screen or the bootloader screen, do Step 2.

### Step 2. Make the Pi boot from USB (only if it did not)

Where the boot order is stored depends on the model.

| Model | USB boot | What you have to do |
| --- | --- | --- |
| Pi 4 B, Pi 400 | Yes, from the bootloader chip (EEPROM) on the board | Boards made since late 2020 already try USB when no SD card is present. All Rev 1.5 boards do. Older bootloaders need the update below |
| Pi 5 | Yes, USB and NVMe (through the PCIe connector) | Same tools as the Pi 4. NVMe must be in the boot order |
| Pi 3 B+, Pi 3 A+ | Yes, always on | Nothing. Remove the SD card |
| Pi 3 B, Pi 2 B v1.2 | Yes, after a one-time permanent setting | Boot once from an SD card with `program_usb_boot_mode=1` in `config.txt`. It cannot be undone |
| Pi 2 B v1.1 and older, Pi Zero | No | Keep an SD card holding only `bootcode.bin`; the system can live on USB |

> **Not verified:** this step is taken from the [Raspberry Pi hardware documentation](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html). The Pis this guide was written on (Pi 4 B Rev 1.5) booted from USB with no changes, so the commands in this step were not run by the author.

For a Pi 4 or Pi 5, boot once from an SD card with Raspberry Pi OS on it.

**Run on: the Pi (booted from the SD card).**

```sh
sudo apt-get update && sudo apt-get install -y rpi-eeprom
sudo rpi-eeprom-update -a
sudo raspi-config
```

The first two lines install the bootloader tools and stage the newest bootloader. In `raspi-config` choose **Advanced Options → Boot Order → USB Boot**. Reboot, shut down, remove the SD card, and power on with only the USB drive attached.

To see or set the order directly:

**Run on: the Pi.**

```sh
rpi-eeprom-config | grep BOOT_ORDER
sudo -E rpi-eeprom-config --edit
```

`BOOT_ORDER` is read **right to left**, one digit per attempt:

| Digit | Meaning |
| --- | --- |
| `1` | SD card |
| `4` | USB drive |
| `6` | NVMe (Pi 5) |
| `2` | Network |
| `f` | Start over |

`BOOT_ORDER=0xf41` means SD card first, then USB, then repeat; with no SD card inserted it goes straight to USB. `0xf14` tries USB first.

### Step 3. Check that the disk is good enough for etcd

**Run on: the Pi.**

```sh
findmnt -no SOURCE -T /var/lib/rancher 2>/dev/null || findmnt -no SOURCE /
lsblk -d -o NAME,SIZE,MODEL,TRAN
```

The first command prints the device that will hold the k3s data. The second prints the model of each drive.

| First command prints | Meaning |
| --- | --- |
| `/dev/sda…` or `/dev/nvme…` | A USB or NVMe drive. Carry on |
| `/dev/mmcblk…` | An SD card. Do not run etcd on it |

`/dev/sda` only says "a USB drive", not what kind. Look up the model that `lsblk` prints. A drive sold as a "portable drive" can be a spinning hard disk: on one of the Pis here the model turned out to be a 2 TB hard disk (WD `WD20JDRW`), while the other two had NVMe SSDs in USB enclosures.

> **Why:** etcd is sensitive to slow writes. On the Pi with the hard disk, CoreDNS, metrics-server and Traefik had restarted hundreds of times, and a slow disk is the likeliest reason. It runs, but that is the node that most deserves an SSD. When the disk is too slow the k3s log repeats "slow fdatasync" or "apply request took too long".

> **Pitfall:** `findmnt -no SOURCE /var/lib/rancher` (without `-T`) prints nothing, because that path is not itself a mount point. The `-T` option asks "which filesystem holds this path".

### Step 4. Update, and update the bootloader

**Run on: the Pi.**

```sh
sudo apt-get update && sudo apt-get upgrade -y
sudo rpi-eeprom-update
```

The second command reports whether a newer bootloader is available. If it says "update available", install it and reboot:

```sh
sudo rpi-eeprom-update -a
sudo reboot
```

> **Pitfall:** if the Pi is already a member of a cluster, update the bootloader on **one Pi at a time**. Wait until the node shows `Ready` again in `sudo kubectl get nodes` before starting the next. Rebooting two servers of a three- or four-server cluster at once stops the control plane (see [quorum](../kubernetes/k3s-ha-cluster.md#how-it-works)).

### Step 5. Turn on the memory cgroups

**Run on: the Pi.**

```sh
sudo sed -i '1 s/$/ cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory/' /boot/firmware/cmdline.txt
cat /boot/firmware/cmdline.txt
```

The `sed` line appends three settings to the end of the kernel command line. The file must still be **one single line**, now ending in the three cgroup settings.

> **Pitfall:** run the `sed` line once only. Running it twice appends the settings twice. If the file ends up with more than one line the Pi may not boot; edit it with `sudo nano /boot/firmware/cmdline.txt` and join it back into one line.

### Step 6. Turn swap off

**Run on: the Pi.**

```sh
sudo swapoff -a
sudo sed -i 's/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=0/' /etc/dphys-swapfile 2>/dev/null || true
sudo reboot
```

`swapoff -a` stops swap now. The second line stops the swap file coming back at boot on systems that use `dphys-swapfile`; it does nothing, harmlessly, where that file does not exist. The reboot also applies Step 5.

After the reboot, check:

```sh
swapon --show
grep -o 'cgroup[^ ]*' /proc/cmdline
```

`swapon --show` printing nothing means no swap. The second command should print the three cgroup settings.

> **Not verified:** on the Debian 13 Pi, swap on compressed RAM (`zram0`) was still active after this procedure; the Debian 12 Pis had none. k3s tolerates it and the node ran normally, so it was left alone. Whether it should be turned off was not investigated.

### Step 7. Pin the Pi's addresses and its own DNS

The node must have its IPv4 and IPv6 addresses **before** k3s starts, and it must use DNS servers outside the cluster.

Raspberry Pi OS manages the network with NetworkManager; `nmcli` is its command-line tool. First find the name of the wired connection.

**Run on: the Pi.**

```sh
nmcli -t -f NAME,DEVICE con show --active
```

Use the name printed next to `eth0` in the commands below. On the Debian 12 Pis it was `Wired connection 1`. On the Debian 13 Pi it was `netplan-eth0`.

**Run on: server-1.**

```sh
sudo nmcli con mod "Wired connection 1" ipv4.method manual ipv4.addresses 192.168.50.5/24 ipv4.gateway 192.168.50.1 ipv4.dns "1.1.1.1 9.9.9.9" ipv4.ignore-auto-dns yes ipv6.method auto ipv6.addresses "fd00:1234:5678:50::5/64" ipv6.ignore-auto-dns yes
sudo nmcli con up "Wired connection 1"
```

**Run on: server-2** (shown with the other connection name).

```sh
sudo nmcli con mod "netplan-eth0" ipv4.method manual ipv4.addresses 192.168.50.6/24 ipv4.gateway 192.168.50.1 ipv4.dns "1.1.1.1 9.9.9.9" ipv4.ignore-auto-dns yes ipv6.method auto ipv6.addresses "fd00:1234:5678:50::6/64" ipv6.ignore-auto-dns yes
sudo nmcli con up "netplan-eth0"
```

**Run on: server-3.**

```sh
sudo nmcli con mod "Wired connection 1" ipv4.method manual ipv4.addresses 192.168.50.7/24 ipv4.gateway 192.168.50.1 ipv4.dns "1.1.1.1 9.9.9.9" ipv4.ignore-auto-dns yes ipv6.method auto ipv6.addresses "fd00:1234:5678:50::7/64" ipv6.ignore-auto-dns yes
sudo nmcli con up "Wired connection 1"
```

What each part does:

| Setting | Effect |
| --- | --- |
| `ipv4.method manual` with `ipv4.addresses` and `ipv4.gateway` | Fixed IPv4 address, set on the Pi itself. DHCP is no longer used |
| `ipv4.dns "1.1.1.1 9.9.9.9"` | The node's own resolvers |
| `ipv4.ignore-auto-dns yes` | Ignore DNS servers offered by DHCP |
| `ipv6.method auto` | Keep accepting the router's IPv6 advertisement, so the node still learns the prefix and gets an automatic address |
| `ipv6.addresses "fd00:…::5/64"` | Add the short fixed IPv6 address on top of the automatic one |
| `ipv6.ignore-auto-dns yes` | Ignore DNS servers offered in the router's IPv6 advertisement |

Your SSH session may drop for a moment on the `con up` line.

If you do not use IPv6 at all, leave out the three `ipv6.…` settings.

### Step 8. Check the time

**Run on: the Pi.**

```sh
timedatectl
```

Look for `System clock synchronized: yes` and the right time zone. A Pi 4 has no battery-backed clock, so it depends on network time after every boot; the cluster's certificates and etcd both assume the servers agree on the time. To change the time zone: `sudo timedatectl set-timezone America/New_York`.

> **Not verified:** the time zone was set in the Imager. The `timedatectl` check is general Linux practice added here; it is not a step the author recorded running.

## Check it

**Run on: the Pi.**

```sh
ip -br addr show eth0
grep nameserver /etc/resolv.conf
grep -o 'cgroup[^ ]*' /proc/cmdline
findmnt -no SOURCE /
nslookup ghcr.io
```

Expected:

| Command | Expected result |
| --- | --- |
| `ip -br addr show eth0` | The node's `192.168.50.x/24` address and its `fd00:1234:5678:50::x/64` address. Other IPv6 addresses on the same line are normal (see Pitfalls) |
| `grep nameserver /etc/resolv.conf` | Exactly `nameserver 1.1.1.1` and `nameserver 9.9.9.9` |
| `grep -o … /proc/cmdline` | `cgroup_enable=cpuset`, `cgroup_memory=1`, `cgroup_enable=memory` |
| `findmnt -no SOURCE /` | `/dev/sda…` or `/dev/nvme…`, not `/dev/mmcblk…` |
| `nslookup ghcr.io` | An answer. This is the lookup a node does when it pulls an image |

## Pitfalls

| What happens | Why | How to avoid or recover |
| --- | --- | --- |
| New pods sit in `ImagePullBackOff` and never start, including the DNS server pods themselves | The node's own DNS pointed at a DNS server that runs in the cluster (here: Pi-hole on a node's address). When that server moved or stopped, the nodes could not resolve the image registry, so the pod that would have fixed DNS could not be pulled. A node must never depend on Pi-hole to start Pi-hole | Node DNS is `1.1.1.1` and `9.9.9.9`, set in Step 7. This also matters after a power cut: the Pis come up before any cluster DNS exists |
| `/etc/resolv.conf` lists your in-cluster DNS address (for example `fd00:1234:5678:50::11`) next to `1.1.1.1`, and `9.9.9.9` is missing | The node is taking a DNS server from the router's IPv6 advertisement. `ipv4.ignore-auto-dns` does not cover IPv6 | `ipv6.ignore-auto-dns yes`, as in Step 7. To fix an existing node: `sudo nmcli con mod "Wired connection 1" ipv4.dns "1.1.1.1 9.9.9.9" ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes`, then `sudo nmcli con up "Wired connection 1"`, then `grep nameserver /etc/resolv.conf` |
| SSH freezes right after `nmcli con up`, and the Pi is gone from its address | The connection was still on DHCP. Re-applying it made the Pi ask for a new lease and the router gave it a different address (here `.34` instead of `.7`) | Always set `ipv4.method manual` with the address in the same `con mod` command. To recover, reach the Pi over IPv6 from another machine on the LAN: `ssh <USER>@fd00:1234:5678:50::7`. The router's client list may keep showing the stale DHCP entry for a while |
| The Pi has more IPv6 addresses than the one you set | `ipv6.method auto` also gives it an automatically generated address in the LAN prefix. Another device on the LAN (commonly an Apple TV or HomePod acting as a Thread border router) may advertise a second prefix as well, which gives every Pi an address in a range your router does not hand out | Harmless for k3s. It matters for a host firewall that lists node addresses: see [Node firewall](../kubernetes/node-firewall.md#the-ipv6-gap) |
| `cmdline.txt` has the cgroup settings twice, or the Pi does not boot after Step 5 | The `sed` line was run twice, or the file was split into two lines | Edit the file back to one line with one copy of the settings |
| A 2 GB Pi starts swapping, or pods are killed with `OOMKilled` | 2 GB is the minimum for a k3s server | Watch with `sudo kubectl top nodes`. The cheapest fixes are to run fewer servers (drop an optional fourth server) or to make one 2 GB Pi an agent (worker only) instead of a server |
| Bootloader update on several Pis at once takes the cluster down | Each update needs a reboot | One Pi at a time, wait for `Ready` |

## Troubleshooting

USB drives on a Pi:

| Symptom | Cause | Fix |
| --- | --- | --- |
| Boots sometimes, or the drive drops out under load | The drive draws more than the Pi's USB ports supply, especially a spinning hard disk | Use the official 5.1 V 3 A power supply, or a powered enclosure or hub |
| Very slow, or I/O errors and resets in `dmesg` | The USB adapter's fast mode (UAS) misbehaves with the Pi | Find the adapter's ID with `lsusb` (for example `152d:0578`), add `usb-storage.quirks=152d:0578:u` to the start of the single line in `/boot/firmware/cmdline.txt`, reboot |
| Does not boot from a hard disk but does from an SSD | The disk spins up slower than the bootloader waits | In `sudo -E rpi-eeprom-config --edit` add `USB_MSD_PWR_OFF_TIME=0` and raise `USB_MSD_DISCOVER_TIMEOUT=20000` |
| Stopped booting after years of working | Old bootloader | `sudo rpi-eeprom-update -a`, reboot |
| Sits at the rainbow or bootloader screen | Boot order does not include USB | Step 2 |

> **Not verified:** the four USB fixes above come from the Raspberry Pi documentation and were not needed on the author's hardware.

The node once it is in a cluster:

| Symptom | Cause | Fix |
| --- | --- | --- |
| Pod `ImagePullBackOff`, `ErrImagePull`, "no such host" | The node cannot resolve or reach the registry | On that node `grep nameserver /etc/resolv.conf` must show `1.1.1.1` and `9.9.9.9`, and `nslookup ghcr.io` must answer. Step 7 |
| `eth0` has no `192.168.50.x` address | The node lost or changed its address | Reach it over IPv6, then pin the address (Step 7) |
| k3s log repeats "slow fdatasync" or "apply request took too long" | The disk is too slow for etcd | Move the node to an SSD (Step 3) |
| Disk at 100% | Logs or container images filled it | `sudo k3s crictl rmi --prune` and `sudo journalctl --vacuum-size=200M` |
| `OOMKilled` pods on a 2 GB Pi | Out of memory | `sudo kubectl top nodes`; see Pitfalls |
| "permission denied" on `/etc/rancher/k3s/k3s.yaml` | `kubectl` run without `sudo` on the node | `sudo kubectl …` |

Useful first look on a node that misbehaves:

**Run on: the Pi.**

```sh
sudo systemctl status k3s --no-pager | head -12
sudo journalctl -u k3s --no-pager -n 40
ip -br addr show eth0
free -h
df -h /
```

## Undo

To put the network connection back on DHCP:

**Run on: the Pi.**

```sh
sudo nmcli con mod "Wired connection 1" ipv4.method auto ipv4.addresses "" ipv4.gateway "" ipv4.dns "" ipv4.ignore-auto-dns no ipv6.addresses "" ipv6.ignore-auto-dns no
sudo nmcli con up "Wired connection 1"
```

The Pi will get a new address from DHCP and your SSH session will drop. Do not do this to a Pi that is still an etcd member.

To remove the cgroup settings, edit `/boot/firmware/cmdline.txt` and delete the three words added in Step 5, keeping the file on one line. The Pi 3 B / Pi 2 B v1.2 USB boot setting (`program_usb_boot_mode=1`) cannot be undone.

> **Not verified:** the DHCP revert command is standard `nmcli` usage and was not run by the author.

## If you also have an Asuswrt-Merlin router with DNS Director

DNS Director forces every device's DNS queries to one server, typically Pi-hole. That would silently redirect the nodes' queries to `1.1.1.1` back into the cluster, which recreates the dependency this page removes. Give each node a per-device rule that keeps it away from Pi-hole. This build uses **Router**, which has the router's own resolver answer the node. See [ASUS ZenWiFi XT8](asus-zenwifi-xt8.md) and [DNS design](../network/dns-design.md).

## Firmware and updates

Raspberry Pi Imager, Raspberry Pi OS releases, bootloader (EEPROM) updates and the boot order are covered in [Software and firmware](../operations/software-and-firmware.md#raspberry-pi-bootloader-eeprom-and-boot-order). A first boot from an SD card followed by a move to an SSD or NVMe drive is in [From nothing to a full deployment](../start-here/build-from-nothing.md#phase-5-raspberry-pis).

## References

- [Raspberry Pi computer hardware](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html): boot EEPROM, bootloader configuration and USB mass storage boot for every model.
- [Raspberry Pi getting started](https://www.raspberrypi.com/documentation/computers/getting-started.html): Raspberry Pi Imager, OS customisation (hostname, user, SSH) and the recommended power supply per model.
- [Raspberry Pi configuration](https://www.raspberrypi.com/documentation/computers/configuration.html): `raspi-config`, networking and static addresses with `nmcli`, and the kernel command line.
- [K3s requirements](https://docs.k3s.io/installation/requirements): minimum CPU and memory for servers and agents, and the advice to use an SSD because etcd is write intensive.
- [K3s high availability embedded etcd](https://docs.k3s.io/datastore/ha-embedded): notes that embedded etcd performs poorly on slow disks such as SD cards.
- [nm-settings-nmcli reference](https://networkmanager.dev/docs/api/latest/nm-settings-nmcli.html): every connection property that `nmcli con mod` can set.
