# 01. Inventory: addresses, names, devices

State as of Sunday 4 October 2026. The device list comes from the XT8 client list exported that day.

## Networks

| Item | Value |
| --- | --- |
| Main LAN | 192.168.50.0/24, bridge `br0` on the XT8 |
| Guest / IoT LAN | 192.168.101.0/24, bridge `br1` on the XT8, Wi-Fi name `Home-IoT`, 2.4 GHz, intranet access off |
| DHCP pool (main) | 192.168.50.20 to .254. Addresses .2 to .19 are for fixed devices |
| Local domain | `home.example.com` |
| Public domain | `example.com` (Cloudflare) |
| DDNS name | `myhome.asuscomm.com` |
| IPv6 | Local-only. No ISP IPv6, no IPv6 default route |
| IPv6 /48 | `fd00:1234:5678::/48` |
| LAN IPv6 /64 | `fd00:1234:5678:50::/64` |
| k3s pod ranges | `10.42.0.0/16` and `fd00:1234:5678:4200::/56` |
| k3s service ranges | `10.43.0.0/16` and `fd00:1234:5678:4300::/112` |
| Main Wi-Fi names | `Home` (2.4 GHz, ch 1), `Home5g` (5 GHz-1, ch 36), `Home6g` (5 GHz-2, ch 177) |

## Fixed addresses

| Address | IPv6 | What | Notes |
| --- | --- | --- | --- |
| 192.168.50.1 | `fd00:1234:5678:50::1` | XT8 router "Laundry Room" | GNUton-Merlin 3004.388.10_2. SSH port 666, LAN only |
| 192.168.50.117 | | XT8 AiMesh node "Master Bedroom" | Wired backhaul. Address as of late September; not in the 4 Oct client list |
| 192.168.50.2 | `::2` | 2019 MacBook Pro server (`mbp-server-lan`) | Plex, Sonarr (`shows`), Radarr (`movies`). Wired interface `en8` |
| 192.168.50.3 | `::3` | Archer A7 v5, OpenWrt, `livingRoomAP` | Bridged access point |
| 192.168.50.4 | none | Archer AX21, stock firmware, `officeAP` | Access point mode |
| 192.168.50.5 | `::5` | `k3sprimary` (Raspberry Pi, SSD on `/dev/sda2`) | k3s server. Homebridge, Seerr and cloudflared run here |
| 192.168.50.6 | `::6` | `funkyfresh` (Raspberry Pi) | k3s server. Also answers to the old name `k3snode1` |
| 192.168.50.7 | `::7` | `k3snode2` (Raspberry Pi) | k3s server |
| 192.168.50.8 | | `pretty-pan` (Raspberry Pi) | No longer in the cluster |
| 192.168.50.10 | | **kube-vip** floating address | Kubernetes API only (`k3s.home.example.com`) |
| 192.168.50.11 | `::11` | **MetalLB**: Pi-hole | DNS for the whole house. Does not answer ping |
| 192.168.50.12 | | **MetalLB**: Traefik | Every web app: Pi-hole UI, Homebridge, Seerr |
| 192.168.50.13 to .15 | | MetalLB, free | |
| 192.168.50.16 | `::16` | `dc01` (Windows) | Also runs the torrent client |
| 192.168.50.17 | `::17` | `ca01` (Windows) | |
| 192.168.50.146 | `fd00:1234:5678:50:5055:55ff:fe15:f169` | `lima-k3s-mac` (Lima VM on the M1 MacBook Pro) | k3s server. From DHCP: **reserve it** for MAC `52:55:55:15:F1:69` |

## Cluster hardware

Read from each Pi on 4 October 2026.

| | k3sprimary | funkyfresh | k3snode2 |
| --- | --- | --- | --- |
| Model | Raspberry Pi 4 Model B Rev 1.5 | Raspberry Pi 4 Model B Rev 1.5 | Raspberry Pi 4 Model B Rev 1.5 |
| RAM | 8 GB | 2 GB | 2 GB |
| Revision code | `d03115` | `b03115` | `b03115` |
| Serial | `<PI_SERIAL_1>` | `<PI_SERIAL_2>` | `<PI_SERIAL_3>` |
| Hostname on the Pi | `k3sprimary` | `funkyFresh` (capital F; the node name is `funkyfresh`) | `k3snode2` |
| Wired MAC (`eth0`) | `02:00:00:00:00:0a` | `02:00:00:00:00:08` | `02:00:00:00:00:09` |
| Wi-Fi MAC (`wlan0`, unused) | `02:00:00:00:00:0b` | `02:00:00:00:00:0c` | `02:00:00:00:00:0d` |
| Boot and data disk | WD `WD20JDRW` 2 TB, USB. **This model is a spinning hard drive, not an SSD** | Crucial P310 500 GB NVMe in a USB enclosure | 500 GB NVMe in a Realtek RTL9210 USB enclosure |
| Root filesystem | `/dev/sda2`, ext4, 2% used | `/dev/sda2`, ext4, 2% used | `/dev/sda2`, ext4, 1% used |
| SD card | none | none | none |
| OS | Debian 12 (bookworm) | Debian 13 (trixie) | Debian 12 (bookworm) |
| Kernel | 6.6.74+rpt-rpi-v8 | 6.12.47+rpt-rpi-v8 | 6.12.25+rpt-rpi-v8 |
| Network connection name | `Wired connection 1` | `netplan-eth0` | `Wired connection 1` |
| Own DNS servers | 1.1.1.1 and **Pi-hole's IPv6 address** (to fix, see [15](15-open-items.md)) | 1.1.1.1, 9.9.9.9 | 1.1.1.1, 9.9.9.9 |
| Bootloader firmware | update available | update available | up to date (8 May 2025) |
| Host firewall (`ufw`) | active | active | active |
| Extra roles | Holds 192.168.50.10 (kube-vip) at the time of reading. Homebridge, Seerr, cloudflared | Swap on compressed RAM (`zram0`) is on | |

The Mac VM (`lima-k3s-mac`): Ubuntu 26.04, kernel 7.0.0-34, bridged interface `lima0` with MAC `52:55:55:15:F1:69`.

**A second IPv6 range is on the LAN.** Every Pi also has an address in `fd00:aaaa:bbbb:cccc::/64`. The XT8 does not hand that out, so something else on the network is advertising it. The usual source is an Apple TV or HomePod acting as a Thread border router. It is harmless for normal use, but it matters for the node firewall ([10](10-firewall.md)).

## Names served by Pi-hole

All defined in `pihole/values.yaml`.

| Name | Points at | What |
| --- | --- | --- |
| `pihole.home.example.com` | 192.168.50.12 | Pi-hole web UI through Traefik (HTTPS, sticky sessions) |
| `hb.home.example.com` | 192.168.50.12 | Homebridge UI through Traefik |
| `traefik.home.example.com` | 192.168.50.12 | Traefik |
| `k3s.home.example.com` | 192.168.50.10 | Kubernetes API |
| `shows`, `movies`, `plex.home.example.com` | 192.168.50.2 | Apps on the MacBook Pro server |
| `torrent.home.example.com` | 192.168.50.16 | Torrent client on dc01 |
| every device below | its own address | Short name and `<name>.home.example.com` |

`request.example.com` (Seerr) is a public name in Cloudflare, not a Pi-hole name. See [09](09-seerr-and-cloudflare.md).

## Web addresses

| What | Address | Fallback if Traefik is down |
| --- | --- | --- |
| Pi-hole | `https://pihole.home.example.com/admin` | `http://192.168.50.11/admin` |
| Homebridge | `https://hb.home.example.com` | `http://192.168.50.5:8581` |
| Seerr | `https://request.example.com` | none (needs Traefik) |
| XT8 | `http://192.168.50.1` | |
| Archer A7 (LuCI) | `http://192.168.50.3` | |
| Archer AX21 | `http://192.168.50.4` | |

Traefik serves its own self-signed certificate for the `home.example.com` names, so browsers show a warning once.

## Every device on the network

"Name in Pi-hole" is the short hostname; add `.home.example.com` for the full name. Devices marked DHCP can change address unless you reserve them on the XT8, and then the Pi-hole name goes stale.

| Address | Name in Pi-hole | Name on the router | Maker | MAC | Address from | Connected by |
| --- | --- | --- | --- | --- | --- | --- |
| 192.168.50.2 | `mbp-server-lan` | MBP-Server-LAN | Ugreen Group Limited | `02:00:00:00:00:0E` | Static | Wired |
| 192.168.50.3 | `livingroomap` | livingRoomAP | TP-LINK TECHNOLOGIES CO.LTD. | `02:00:00:00:00:0F` | Static | Wired |
| 192.168.50.4 | `officeap` | officeAP | MSFT 5.0 | `02:00:00:00:00:04` | DHCP | Wired |
| 192.168.50.5 | `k3sprimary` | k3sprimary | Raspberry Pi Trading Ltd | `02:00:00:00:00:0A` | DHCP | Wired |
| 192.168.50.6 | `funkyfresh` | funkyFresh | Raspberry Pi Trading Ltd | `02:00:00:00:00:08` | Static | Wired |
| 192.168.50.8 | `pretty-pan` | Pretty Pan | Raspberry Pi Foundation | `02:00:00:00:00:10` | Static | Wired |
| 192.168.50.16 | `dc01` | DC-01 | Dell Inc. | `02:00:00:00:00:05` | Static | Wired |
| 192.168.50.17 | `ca01` | CA-01 | Dell Inc. | `02:00:00:00:00:11` | Static | Wired |
| 192.168.50.25 | `ownersphone` | ownersPhone | Apple iPhone | `02:00:00:00:00:12` | DHCP | 5 GHz-1 |
| 192.168.50.34 | (stale) | k3snode2, old DHCP lease; the Pi is really on .7 | Raspberry Pi Trading Ltd | `02:00:00:00:00:09` | DHCP | Wired |
| 192.168.50.47 | `mainbedroomatv` | MainBedroomATV | Apple Inc. | `02:00:00:00:00:13` | DHCP | 5 GHz-1 |
| 192.168.50.48 | `member3s-mini` | Member3s-Mini | Apple iPhone | `02:00:00:00:00:14` | DHCP | 5 GHz-1 |
| 192.168.50.52 | `ps5` | ps5 | Sony Interactive Entertainment Inc. | `02:00:00:00:00:15` | Static | Wired |
| 192.168.50.56 | `unknown-apple-56` | 02:00:00:00:00:01 | Apple Inc. | `02:00:00:00:00:01` | DHCP | Wired |
| 192.168.50.57 | `soma-connect` | soma-connect | dhcpcd-8.1.2:Linux-5.10.17+:arm | `02:00:00:00:00:16` | DHCP | 2.4 GHz |
| 192.168.50.69 | `backyard-camera` | WyzeCam | Wyze Labs Inc | `02:00:00:00:00:17` | DHCP | Wired |
| 192.168.50.71 | `upstairs-thermostat` | Upstairs-Thermostat | dhcpcd-8.1.6:Linux-2.6.31-816-g | `02:00:00:00:00:18` | DHCP | 2.4 GHz |
| 192.168.50.72 | `office-bulb` | Office-Bulb | Wyze Labs Inc | `02:00:00:00:00:19` | DHCP | 2.4 GHz |
| 192.168.50.82 | `mbp-lan-dongle` | MBP-LAN-Dongle | IEEE Registration Authority | `02:00:00:00:00:1A` | DHCP | Wired |
| 192.168.50.93 | `nintendo-switch` | Nintendo Co  Ltd | Nintendo Co.Ltd | `02:00:00:00:00:1B` | DHCP | 5 GHz-1 |
| 192.168.50.94 | `living-room-atv` | Apple | Apple Inc. | `02:00:00:00:00:1C` | Static | Wired |
| 192.168.50.103 | `roomba` | Roomba-31C7C41472024730 | AzureWave Technology Inc. | `02:00:00:00:00:1D` | DHCP | Wired |
| 192.168.50.106 | `apple-watch` | Watch | Apple Inc. | `02:00:00:00:00:1E` | DHCP | 2.4 GHz |
| 192.168.50.115 | `homepod-mini` | HomePod-Mini | Apple iPhone | `02:00:00:00:00:1F` | DHCP | 5 GHz-1 |
| 192.168.50.116 | `member2siphone2` | Member2siPhone2 | Apple iPhone | `02:00:00:00:00:20` | DHCP | 5 GHz-1 |
| 192.168.50.127 | `living-room-camera` | Axis Communications AB | Axis Communications AB | `02:00:00:00:00:21` | Static | Wired |
| 192.168.50.129 | `unknown-apple-129` | 02:00:00:00:00:02 | Apple Inc. | `02:00:00:00:00:02` | DHCP | Wired |
| 192.168.50.136 | `wiz-bulb` | wiz | WiZ IoT Company Limited | `02:00:00:00:00:22` | DHCP | Wired |
| 192.168.50.146 | `lima-k3s-mac` | lima-k3s-mac | Loading manufacturer.. | `52:55:55:15:F1:69` | DHCP | Wired |
| 192.168.50.149 | `mb-homepod-mini` | MB-Home-Pod-mini | Apple TV | `02:00:00:00:00:23` | DHCP | 5 GHz-1 |
| 192.168.50.153 | `ipad` | iPad | Apple iPhone | `02:00:00:00:00:24` | DHCP | 5 GHz-1 |
| 192.168.50.157 | `tuya-157` | wlan0 | Tuya Smart Inc. | `02:00:00:00:00:25` | DHCP | 2.4 GHz |
| 192.168.50.159 | `owners-work-macbook` | Owners-Work-Macbook | Apple Inc. | `02:00:00:00:00:26` | DHCP | 5 GHz-2 |
| 192.168.50.173 | `axisdvr` | axisDVR | Axis Communications AB | `02:00:00:00:00:27` | DHCP | Wired |
| 192.168.50.209 | `entrance-camera` | Axis Communications AB | Axis Communications AB | `02:00:00:00:00:28` | Static | Wired |
| 192.168.50.210 | `downstairs-thermostat` | downstairsThermostat | Resideo | `02:00:00:00:00:29` | DHCP | Wired |
| 192.168.50.213 | `doorbell` | doorBell | Logitech | `02:00:00:00:00:2A` | DHCP | 2.4 GHz |
| 192.168.50.214 | `smart-innovation-214` | Smart Innovation LLC | Smart Innovation LLC | `02:00:00:00:00:2B` | DHCP | Wired |
| 192.168.50.216 | `unknown-216` | 02:00:00:00:00:03 | Microsoft Corp. | `02:00:00:00:00:03` | Static | 5 GHz-1 |
| 192.168.50.247 | `homepod-mini-2` | HomePod-Mini-2 | Apple iPhone | `02:00:00:00:00:2C` | DHCP | 5 GHz-1 |
| 192.168.50.254 | `iphone-254` | iPhone | Apple Inc. | `02:00:00:00:00:2D` | DHCP | 5 GHz-1 |
| 192.168.101.5 | `foyer-lights` | Foyer-Lights | TP-LINK TECHNOLOGIES CO.LTD. | `02:00:00:00:00:2E` | DHCP | 2.4 GHz Guest Network - 1 |
| 192.168.101.6 | `entrance-lamp` | Entrance-Lamp | Wyze Labs Inc | `02:00:00:00:00:2F` | DHCP | Wired |
| 192.168.101.29 | `lr-reading-light` | LR-Reading-Light | Wyze Labs Inc | `02:00:00:00:00:30` | DHCP | Wired |
| 192.168.101.45 | `kids-bathroom` | Kids-Bathroom | TP-LINK TECHNOLOGIES CO.LTD. | `02:00:00:00:00:31` | DHCP | 2.4 GHz Guest Network - 1 |
| 192.168.101.58 | `office-leds` | Office-LEDs | Wyze Labs Inc | `02:00:00:00:00:32` | DHCP | 2.4 GHz Guest Network - 1 |
| 192.168.101.83 | `outside-front-light` | Outside-Front-Light | TP-LINK TECHNOLOGIES CO.LTD. | `02:00:00:00:00:33` | DHCP | 2.4 GHz Guest Network - 1 |
| 192.168.101.85 | `owners-lamp` | Owners-Lamp | Wyze Labs Inc | `02:00:00:00:00:34` | DHCP | 2.4 GHz Guest Network - 1 |
| 192.168.101.116 | `lr-ceiling-fan` | LR-Ceiling-Fan | TP-LINK TECHNOLOGIES CO.LTD. | `02:00:00:00:00:35` | DHCP | Wired |
| 192.168.101.118 | `hall-light` | Hall-Light | TP-Link Systems Inc | `02:00:00:00:00:36` | DHCP | 2.4 GHz Guest Network - 1 |
| 192.168.101.137 | `mbtv` | MBTV | Wyze Labs Inc | `02:00:00:00:00:37` | DHCP | 2.4 GHz Guest Network - 1 |
| 192.168.101.144 | `mb-leds` | MB-LEDs | Wyze Labs Inc | `02:00:00:00:00:38` | DHCP | 2.4 GHz Guest Network - 1 |
| 192.168.101.154 | `floor-fan` | Floor-Fan | Wyze Labs Inc | `02:00:00:00:00:39` | DHCP | 2.4 GHz Guest Network - 1 |
| 192.168.101.180 | `member2s-lamp` | Member2s-Lamp | Wyze Labs Inc | `02:00:00:00:00:3A` | DHCP | 2.4 GHz Guest Network - 1 |
| 192.168.101.183 | `edison-lights` | Edison-Lights | Wyze Labs Inc | `02:00:00:00:00:3B` | DHCP | Wired |
| 192.168.101.188 | `holiday-lights` | Holiday-Lights | Wyze Labs Inc | `02:00:00:00:00:3C` | DHCP | Wired |
| 192.168.101.189 | `stairs-light` | Stairs-Light | TP-LINK TECHNOLOGIES CO.LTD. | `02:00:00:00:00:3D` | DHCP | Wired |
| 192.168.101.194 | `front-porch` | Front-Porch | TP-Link Systems Inc | `02:00:00:00:00:3E` | DHCP | 2.4 GHz Guest Network - 1 |
| 192.168.101.195 | `kitchen-lights` | Kitchen-Lights | TP-LINK TECHNOLOGIES CO.LTD. | `02:00:00:00:00:3F` | DHCP | 2.4 GHz Guest Network - 1 |
| 192.168.101.201 | `mb-ceiling-fan` | MB-Ceiling-Fan | TP-LINK TECHNOLOGIES CO.LTD. | `02:00:00:00:00:40` | DHCP | 2.4 GHz Guest Network - 1 |
| 192.168.101.237 | `mb-overhead-lights` | MB-Overhead-Lights | TP-Link Systems Inc | `02:00:00:00:00:41` | DHCP | 2.4 GHz Guest Network - 1 |
| 192.168.101.238 | `patio-fan` | Patio-Fan | TP-Link Systems Inc | `02:00:00:00:00:42` | DHCP | Wired |
| 192.168.101.242 | `dining-room-light` | Dining-Room-Light | TP-Link Systems Inc | `02:00:00:00:00:43` | DHCP | Wired |

## Kasa devices (guest network)

These are the ones Homebridge controls directly, so each needs a DHCP reservation on the XT8 and an entry in the Homebridge Kasa plugin. Details in [08](08-homebridge.md).

| Address | Router name | Name in HomeKit | MAC |
| --- | --- | --- | --- |
| 192.168.101.5 | Foyer-Lights | Foyer Lights | `02:00:00:00:00:2E` |
| 192.168.101.45 | Kids-Bathroom | Kids bathroom | `02:00:00:00:00:31` |
| 192.168.101.83 | Outside-Front-Light | Outside front | `02:00:00:00:00:33` |
| 192.168.101.116 | LR-Ceiling-Fan | Ceiling fan | `02:00:00:00:00:35` |
| 192.168.101.118 | Hall-Light | Hall light | `02:00:00:00:00:36` |
| 192.168.101.189 | Stairs-Light | Stairs Light | `02:00:00:00:00:3D` |
| 192.168.101.194 | Front-Porch | Front porch | `02:00:00:00:00:3E` |
| 192.168.101.195 | Kitchen-Lights | Kitchen light | `02:00:00:00:00:3F` |
| 192.168.101.201 | MB-Ceiling-Fan | Master bedroom fan | `02:00:00:00:00:40` |
| 192.168.101.237 | MB-Overhead-Lights | Master bedroom overhead light | `02:00:00:00:00:41` |
| 192.168.101.238 | Patio-Fan | Patio fan | `02:00:00:00:00:42` |
| 192.168.101.242 | Dining-Room-Light | Dining Room Light | `02:00:00:00:00:43` |

## Software versions

| Thing | Version |
| --- | --- |
| k3s | v1.34.3+k3s1 on all four nodes |
| MetalLB | v0.15.3 (do not use v0.16.0 or `:main`) |
| Pi-hole chart | mojo2600/pihole 2.38.0 (Pi-hole v6) |
| Homebridge | v2.4.0, chart k8s-at-home/homebridge |
| XT8 firmware | GNUton Asuswrt-Merlin.ng 3004.388.10_2 |
| Archer A7 | OpenWrt 25.12.5 |
| Node operating systems | k3sprimary and k3snode2: Debian 12. funkyfresh: Debian 13. Mac VM: Ubuntu 26.04 |
