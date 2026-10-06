# 04. The k3s cluster

Four servers on embedded etcd, dual-stack (IPv4 and local IPv6), k3s v1.34.3+k3s1.

| Node | Address | IPv6 | Hardware | Interface |
| --- | --- | --- | --- | --- |
| k3sprimary | 192.168.50.5 | `fd00:1234:5678:50::5` | Raspberry Pi, SSD | `eth0` |
| funkyfresh | 192.168.50.6 | `fd00:1234:5678:50::6` | Raspberry Pi | `eth0` |
| k3snode2 | 192.168.50.7 | `fd00:1234:5678:50::7` | Raspberry Pi | `eth0` |
| lima-k3s-mac | 192.168.50.146 | `fd00:1234:5678:50:5055:55ff:fe15:f169` | Lima VM on the M1 MacBook Pro | `lima0` |

In k3s a **server** is control plane, etcd member and worker at once. `kubectl get nodes` shows servers as `control-plane,etcd`. All four of yours are servers.

**Quorum.** Four etcd members need three running. The cluster survives losing any one node. With the Mac VM off, losing one more Pi stops the control plane until one comes back (running pods keep running; nothing new can be scheduled).

**One rule for every step:** on the nodes, put `sudo` in front of every `kubectl` command. Without it you get "permission denied" on `/etc/rancher/k3s/k3s.yaml`.

This page is the **fresh build**. How the live cluster was converted in place, and what broke, is at the end.

## Step 1. Prepare each Raspberry Pi

**Do on: each Pi.**

Flash Raspberry Pi OS Lite 64-bit with Raspberry Pi Imager. In the Imager settings set the hostname (`k3sprimary`, `funkyfresh`, `k3snode2`), the user, the time zone (America/New_York) and enable SSH.

### Boot from the SSD, not an SD card

All three Pis are Raspberry Pi 4 Model B Rev 1.5 and boot straight from a USB drive with no SD card. How to get there depends on the Pi model, because the boot order is stored in different places.

| Model | USB boot | What you have to do |
| --- | --- | --- |
| Pi 4 B, Pi 400 | Yes, from the bootloader chip on the board | Boards made since late 2020 already try USB when no SD card is present. Rev 1.5 boards (yours) all do. Older bootloaders need the update below |
| Pi 5 | Yes, USB and NVMe (through the PCIe connector) | Same tools as the Pi 4. NVMe needs it in the boot order |
| Pi 3 B+ , Pi 3 A+ | Yes, always on | Nothing. Remove the SD card |
| Pi 3 B, Pi 2 B v1.2 | Yes, after a one-time permanent setting | Boot once from an SD card with `program_usb_boot_mode=1` in `config.txt`. It cannot be undone |
| Pi 2 B v1.1 and older, Pi Zero | No | Keep an SD card holding only `bootcode.bin`; the system can live on USB |

**Pi 4, the normal path (your Pis):**

1. On your Mac, open Raspberry Pi Imager, choose Raspberry Pi OS Lite (64-bit), and choose the **USB drive itself** as the storage. Set hostname, user, time zone and SSH in the Imager settings.
2. Plug the drive into a **blue USB 3 port** on the Pi. Leave the SD slot empty. Power on.

If it boots, you are done. If it sits at the rainbow or bootloader screen, the boot order needs setting. Boot once from an SD card with Raspberry Pi OS and run:

```bash
sudo apt-get update && sudo apt-get install -y rpi-eeprom
sudo rpi-eeprom-update -a
sudo raspi-config
```

In `raspi-config`: **Advanced Options → Boot Order → USB Boot**. Reboot, shut down, remove the SD card, power on with only the USB drive.

To see or set the order directly:

```bash
rpi-eeprom-config | grep BOOT_ORDER
sudo -E rpi-eeprom-config --edit
```

`BOOT_ORDER` is read **right to left**, one digit per attempt: `1` SD card, `4` USB drive, `6` NVMe (Pi 5), `2` network, `f` start over. `BOOT_ORDER=0xf41` means SD first, then USB, then repeat; with no SD card it goes straight to USB. `0xf14` tries USB first.

**Things that go wrong with USB drives on a Pi:**

| Symptom | Cause | Fix |
| --- | --- | --- |
| Boots sometimes, or the drive drops out under load | The drive draws more than the Pi's USB ports supply, especially a spinning hard drive | Use the official 5.1 V 3 A power supply, or a powered enclosure or hub |
| Very slow, or I/O errors and resets in `dmesg` | The USB adapter's fast mode (UAS) misbehaves with the Pi | Find the adapter's ID with `lsusb` (for example `152d:0578`), add `usb-storage.quirks=152d:0578:u` to the start of the single line in `/boot/firmware/cmdline.txt`, reboot |
| Does not boot from a hard drive but does from an SSD | The drive spins up slower than the bootloader waits | In `rpi-eeprom-config --edit` add `USB_MSD_PWR_OFF_TIME=0` and raise `USB_MSD_DISCOVER_TIMEOUT=20000` |
| Stopped booting after years of working | Old bootloader | `sudo rpi-eeprom-update -a`, reboot |

Check what each Pi has (k3sprimary and funkyfresh showed "update available" on 4 October):

```bash
sudo rpi-eeprom-update
lsblk -d -o NAME,SIZE,MODEL,TRAN
```

To install a bootloader update: `sudo rpi-eeprom-update -a`, then reboot **one Pi at a time**, waiting for it to be `Ready` again before the next.

These steps are from the Raspberry Pi documentation ([boot modes and bootloader configuration](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html)). They were not re-run for this guide; your three Pis already boot from USB.

### Is the disk good enough for etcd?

etcd needs a real disk. Check where the system lives:

```bash
findmnt -no SOURCE -T /var/lib/rancher 2>/dev/null || findmnt -no SOURCE /
```

`/dev/sda…` or `/dev/nvme…` is a USB or NVMe drive: carry on. `/dev/mmcblk…` is an SD card: do not run etcd on it.

`/dev/sda` only says "USB drive", not what kind. `lsblk -d -o NAME,SIZE,MODEL` shows the model. **k3sprimary's drive is a WD `WD20JDRW`, which is a 2 TB spinning hard drive**, while the other two Pis have NVMe SSDs. etcd writes to disk constantly and is sensitive to slow writes; a hard drive is the likeliest reason CoreDNS, metrics-server and Traefik had restarted hundreds of times on k3sprimary before the HA work. It runs, but k3sprimary is the node that most deserves an SSD.

**Memory.** k3sprimary has 8 GB. funkyfresh and k3snode2 have 2 GB each, which is the minimum k3s lists for a server, and each of them now runs the control plane, etcd and a Pi-hole pod. Watch them with `sudo kubectl top nodes`. If one starts swapping or killing pods, the cheapest fix is to stop the Mac VM being the fourth server and/or move one 2 GB Pi back to being an agent.

Update, then turn on the memory cgroups Kubernetes needs:

```bash
sudo apt-get update && sudo apt-get upgrade -y
sudo sed -i '1 s/$/ cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory/' /boot/firmware/cmdline.txt
cat /boot/firmware/cmdline.txt
```

The file must still be **one line**, now ending in the three cgroup settings. Run the `sed` line once only.

Turn swap off:

```bash
sudo swapoff -a
sudo sed -i 's/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=0/' /etc/dphys-swapfile 2>/dev/null || true
sudo reboot
```

## Step 2. Pin each Pi's address and DNS

**Do on: each Pi.** The node must have its IPv4 and IPv6 addresses **before** k3s starts, and it must use DNS servers outside the cluster.

Find the connection name:

```bash
nmcli -t -f NAME,DEVICE con show --active
```

On k3sprimary and k3snode2 it is `Wired connection 1`. On funkyfresh it is `netplan-eth0`. Use the name printed next to `eth0` in the commands below.

**k3sprimary:**

```bash
sudo nmcli con mod "Wired connection 1" ipv4.method manual ipv4.addresses 192.168.50.5/24 ipv4.gateway 192.168.50.1 ipv4.dns "1.1.1.1 9.9.9.9" ipv4.ignore-auto-dns yes ipv6.method auto ipv6.addresses "fd00:1234:5678:50::5/64" ipv6.ignore-auto-dns yes
sudo nmcli con up "Wired connection 1"
```

**funkyfresh:**

```bash
sudo nmcli con mod "netplan-eth0" ipv4.method manual ipv4.addresses 192.168.50.6/24 ipv4.gateway 192.168.50.1 ipv4.dns "1.1.1.1 9.9.9.9" ipv4.ignore-auto-dns yes ipv6.method auto ipv6.addresses "fd00:1234:5678:50::6/64" ipv6.ignore-auto-dns yes
sudo nmcli con up "netplan-eth0"
```

**k3snode2:**

```bash
sudo nmcli con mod "Wired connection 1" ipv4.method manual ipv4.addresses 192.168.50.7/24 ipv4.gateway 192.168.50.1 ipv4.dns "1.1.1.1 9.9.9.9" ipv4.ignore-auto-dns yes ipv6.method auto ipv6.addresses "fd00:1234:5678:50::7/64" ipv6.ignore-auto-dns yes
sudo nmcli con up "Wired connection 1"
```

Your SSH session may drop for a moment on the `con up` line. Then check:

```bash
ip -br addr show eth0
cat /etc/resolv.conf
```

You should see the node's `192.168.50.x` address, its `fd00:…::x` address, and `nameserver 1.1.1.1` and `9.9.9.9`.

**If `resolv.conf` lists `fd00:1234:5678:50::11`, the node is still taking Pi-hole from the router's IPv6 advertisement.** k3sprimary showed exactly that on 4 October (`1.1.1.1` and Pi-hole's IPv6 address, no `9.9.9.9`). The `ipv6.ignore-auto-dns yes` part of the command above is what stops it. On k3sprimary:

```bash
sudo nmcli con mod "Wired connection 1" ipv4.dns "1.1.1.1 9.9.9.9" ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes
sudo nmcli con up "Wired connection 1"
grep nameserver /etc/resolv.conf
```

> **Trouble we hit: a node pointing at Pi-hole for its own DNS.** All three Pis used 192.168.50.5 as DNS. When Pi-hole moved to 192.168.50.11, .5 stopped answering, the Pis could not resolve the image registry, and new Pi-hole pods sat in `ImagePullBackOff`. A node must never depend on Pi-hole to start Pi-hole. That is why the DNS here is 1.1.1.1 and 9.9.9.9. Also add the nodes to DNS Director on the router ([02](02-router-xt8.md)).

> **Trouble we hit: `nmcli con up` moved a Pi.** k3snode2 was on DHCP. Re-applying its connection gave it 192.168.50.34 and SSH to .7 froze. It was still reachable over IPv6 from another Pi: `ssh pi@fd00:1234:5678:50::7`. Setting `ipv4.method manual` with the address, as above, is the fix. The router's client list may keep showing a stale `.34` entry.

## Step 3. First server: k3sprimary

**Paste on: k3sprimary.**

```bash
sudo mkdir -p /etc/rancher/k3s
sudo nano /etc/rancher/k3s/config.yaml
```

Paste the contents of [`k3s/config/k3sprimary.yaml`](../k3s/config/k3sprimary.yaml), save (Ctrl+O, Enter, Ctrl+X), then install:

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='v1.34.3+k3s1' sh -s - server
sudo kubectl get nodes
```

> **Trouble we hit:** `INSTALL_K3S_VERSION='v1.34'` fails to download. The value must be the full tag, `v1.34.3+k3s1`.

You should see k3sprimary `Ready` with roles `control-plane,etcd`. Print the join token and put it in your password manager, not in this repo:

```bash
sudo cat /var/lib/rancher/k3s/server/token
```

## Step 4. Second and third server: funkyfresh, k3snode2

**Paste on: funkyfresh.**

```bash
sudo mkdir -p /etc/rancher/k3s
sudo nano /etc/rancher/k3s/config.yaml
```

Paste [`k3s/config/funkyfresh.yaml`](../k3s/config/funkyfresh.yaml), replace `<K3S_TOKEN>` with the token, save, then:

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='v1.34.3+k3s1' sh -s - server
```

**Paste on: k3sprimary.** Wait until funkyfresh shows `Ready` and `control-plane,etcd` (up to two minutes) before starting the next node.

```bash
sudo kubectl get nodes
```

Repeat on **k3snode2** with [`k3s/config/k3snode2.yaml`](../k3s/config/k3snode2.yaml). Join servers one at a time.

Every server's file must carry the same `cluster-cidr`, `service-cidr`, `flannel-ipv6-masq` and `disable: servicelb` lines. `node-ip` must hold **both** addresses with a comma between them.

## Step 5. The Mac VM

See [05](05-mac-node-lima.md). Do it after Step 6 of [06](06-load-balancers.md) if you want the Mac to join through the floating address, which is what its config file does.

## Step 6. Labels

**Paste on: k3sprimary.** One command per node, so all three are labelled before anything is scheduled.

```bash
sudo kubectl label node k3sprimary kube-vip-host=true pihole-host=true
sudo kubectl label node funkyfresh kube-vip-host=true pihole-host=true
sudo kubectl label node k3snode2 kube-vip-host=true pihole-host=true
sudo kubectl get nodes -L kube-vip-host,pihole-host
```

The Mac VM gets neither label.

## Step 7. Snapshot

```bash
sudo k3s etcd-snapshot save --name fresh-build
```

Snapshots land in `/var/lib/rancher/k3s/server/db/snapshots/` on the node where you ran it.

## Step 8. CoreDNS: three replicas

k3s installs cluster DNS (CoreDNS, the `kube-dns` Service on `10.43.0.10` and `fd00:1234:5678:4300::a`) as **one** pod. If that pod's node is down, nothing in the cluster resolves names. Scale it to three so it does not depend on one machine.

**Paste on: k3sprimary.**

```bash
sudo kubectl -n kube-system scale deployment coredns --replicas=3
sudo kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
sudo kubectl -n kube-system get pod -l k8s-app=kube-dns -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.status.podIPs}{"\n"}{end}'
sudo kubectl -n kube-system get endpointslices -l kubernetes.io/service-name=kube-dns
```

Pass: three pods `Running` on different nodes, at least one on a Pi; every pod has **two** addresses (a `10.42.x.x` and an `fd00:1234:5678:42xx::` one); both endpoint slices (IPv4 and IPv6) list endpoints.

On 6 October 2026 they landed on lima-k3s-mac, k3sprimary and k3snode2.

Notes:

- CoreDNS is managed by k3s, not by a file in this repo, so this is a command and not a manifest. The replica count has survived so far, but **check it after every k3s upgrade or reinstall** and run the scale command again if it is back to one.
- CoreDNS forwards outside names to the node's own `/etc/resolv.conf` (1.1.1.1 and 9.9.9.9, Step 2), not to Pi-hole.
- Its log is full of `[WARNING] No files matching import glob pattern: /etc/coredns/custom/*.override`. That is normal: no custom config is installed.

### A CoreDNS pod older than the dual-stack conversion has no IPv6 address

Found on 6 October. The single CoreDNS pod was 245 days old, older than the September dual-stack conversion, so it had only `10.42.0.234`. The IPv6 endpoint slice for `kube-dns` was empty and `fd00:1234:5678:4300::a` answered nothing. Pods are only given addresses when they are created, so the cure is to recreate it:

```bash
sudo kubectl -n kube-system rollout restart deployment coredns
sudo kubectl -n kube-system rollout status deployment coredns
```

Cluster DNS drops for a few seconds. On a cluster built fresh from these files this does not arise. After any single-stack to dual-stack conversion, list every pod's addresses and restart the ones with only one:

```bash
sudo kubectl get pods -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,IPS:.status.podIPs
```

### Host-network pods cannot reach IPv6 service addresses

A pod with `hostNetwork: true` uses its node's routing table. The nodes have routes for the IPv6 **pod** ranges (`fd00:1234:5678:4200::/56`, through `flannel-v6.1` and `cni0`) but none for the IPv6 **service** range (`fd00:1234:5678:4300::/112`), and no IPv6 default route, because IPv6 here is local-only.

```bash
ip -6 route get fd00:1234:5678:4300::a
ip -6 route show default
```

The first answers "Network is unreachable"; the second prints nothing. That is the expected state, not a fault. The forwarding rules for the service address are present (`sudo ip6tables-save | grep -i '4300::a'`), but the kernel refuses the packet before they are consulted.

What this means in practice:

- Ordinary pods are fine; they have a default route through the node.
- A host-network pod that is given the cluster's DNS addresses gets one it cannot reach. **Homebridge is the only host-network app here**, and its values file works around it by using the IPv4 DNS address only ([08](08-homebridge.md) Step 1). Any future host-network app needs the same `dnsPolicy` / `dnsConfig` block.
- A cluster-wide alternative is a route for the service range on every node, `sudo ip -6 route add fd00:1234:5678:4300::/112 dev cni0`, made permanent in each node's network config. **Not applied and not tested here**; listed in [15](15-open-items.md).

## Check it

```bash
sudo kubectl get nodes -o wide
sudo kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.spec.podCIDRs}{"\n"}{end}'
```

Every node `Ready`, roles `control-plane,etcd`, on its 192.168.50.x address, and two pod ranges each: one `10.42.x.0/24` and one inside `fd00:1234:5678:42xx::/64`.

## How the live cluster got here, and what broke

The live cluster was not built fresh. It started as one server on SQLite with agents, was converted to dual-stack in September, and to etcd HA on 3 October. If you ever have to repeat an in-place conversion, these are the traps.

| What happened | Cause | Fix |
| --- | --- | --- |
| Agent would not start: "cluster-cidr … and node-ip … must share the same IP version" | A dual-stack cluster needs an IPv4 **and** an IPv6 `node-ip` on every node | `node-ip: <v4>,<v6>` |
| Agent looped on 401 "unable to verify node identity: nodes … not found" | Stale certificates from an earlier join attempt under another name or address | Run `k3s-agent-uninstall.sh` on the node and join again |
| Single-stack to dual-stack: k3s crashed with a flannel "no IPv6" lease error | The old node record had no IPv6 address | Stop k3s, put the dual-stack config in place, start k3s, and `kubectl delete node <name>` during startup so it re-registers |
| SQLite to etcd on k3sprimary would have been skipped | A leftover `server/db/etcd` folder existed next to the live `state.db`; k3s starts from it and skips migration | Stop k3s, back up `server/db`, move the `etcd` folder away, add `cluster-init: true`, start k3s. Look for "Migrating content from sqlite to etcd" in the log |
| k3snode2 would not start as a server: "… newer than datastore and could cause a cluster outage" | The Pi had once been a server and still had `/var/lib/rancher/k3s/server` | `sudo mv /var/lib/rancher/k3s/server /root/k3s-server-old`, then install again |
| Pi-hole jumped from .11 to .5 after a k3s restart | The built-in k3s load balancer (servicelb) and MetalLB were both running; the restart let servicelb win | `disable: servicelb` on **every** server ([06](06-load-balancers.md)) |
| Homebridge plugins logged `getaddrinfo ENOTFOUND` / `EAI_AGAIN` from 3 October, found 6 October | Two things. The CoreDNS pod predated dual-stack and had no IPv6 address; and a host-network pod cannot reach the IPv6 service address at all | Restart CoreDNS, scale it to three (Step 8); IPv4-only DNS block in `Homebridge/values.yaml` ([08](08-homebridge.md) Step 1) |
| My `findmnt -no SOURCE /var/lib/rancher` printed nothing | The path is not a mount point; it needs `-T` | `findmnt -no SOURCE -T /var/lib/rancher` |

Turning an agent into a server in place:

```bash
sudo systemctl disable --now k3s-agent
sudo mkdir -p /root/k3s-agent-old
sudo mv /etc/systemd/system/k3s-agent.service /etc/systemd/system/k3s-agent.service.env /root/k3s-agent-old/
sudo systemctl daemon-reload
sudo ls /var/lib/rancher/k3s/server && sudo mv /var/lib/rancher/k3s/server /root/k3s-server-old
sudo nano /etc/rancher/k3s/config.yaml
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='v1.34.3+k3s1' sh -s - server
```

Backups made during the conversion, still on k3sprimary: `/root/k3s-db-backup` (the SQLite database), `/root/k3s-token-backup`, `/root/k3s-old-etcd`, and the etcd snapshots `post-migration` and `post-ha`.

## Recovery

| If this goes wrong | Do this |
| --- | --- |
| One server will not rejoin | On k3sprimary `sudo kubectl delete node <name>`. On the node run `k3s-uninstall.sh`, then repeat Step 4 |
| Quorum lost (two or more servers gone) | On one surviving server: `sudo systemctl stop k3s`, then `sudo k3s server --cluster-reset`. Add `--cluster-reset-restore-path=<snapshot file>` to restore a snapshot. Then start k3s and rejoin the others after moving their `/var/lib/rancher/k3s/server/db` aside |
| Need to see why k3s will not start | `sudo journalctl -u k3s --no-pager -n 40` |

The `--cluster-reset` procedure has not been run on this cluster. Read the [k3s backup and restore page](https://docs.k3s.io/datastore/backup-restore) before relying on it.

## Rotating the join token

The token was pasted into a chat on 3 October, so treat it as exposed. On k3sprimary:

```bash
sudo k3s token rotate --token "$(sudo cat /var/lib/rancher/k3s/server/token)" --new-token "$(openssl rand -hex 32)"
sudo cat /var/lib/rancher/k3s/server/token
```

Then put the new token into `/etc/rancher/k3s/config.yaml` on the other three servers and restart k3s on each, one at a time. This has not been run here; the command is from the [k3s token documentation](https://docs.k3s.io/cli/token).
