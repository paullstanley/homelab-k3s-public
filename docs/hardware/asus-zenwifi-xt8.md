# ASUS ZenWiFi XT8 router on Asuswrt-Merlin

An ASUS ZenWiFi XT8 running GNUton's build of Asuswrt-Merlin as the main router: it hands out addresses, sends every device's DNS to Pi-hole, carries an isolated IoT network, and advertises a local-only IPv6 prefix. Most of the setup is done by one script, so a factory reset costs minutes instead of an evening.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | ASUS ZenWiFi XT8 (product ID RT-AX95Q), GNUton Asuswrt-Merlin.ng 3004.388.10_2, with the add-ons Skynet, YazDHCP and Scribe installed through amtm |
| **Also works for** | Other routers on Asuswrt-Merlin 3004.388.x or GNUton's builds of it. Not tested by the author. Interface names (`wl0.1`, `eth1` to `eth6`) differ between models |
| **Time** | About 1 hour from a factory reset; 10 minutes if you have backups |
| **You need first** | The router flashed with the firmware and reachable at its LAN address. A USB drive plugged into the router (for Entware, Skynet and Scribe). For the DNS settings to work: [Pi-hole](../apps/pihole.md) |

## How it works

The rebuild has three parts:

1. **GUI settings**, entered by hand (or restored from a saved `.CFG` file).
2. **The bootstrap script**, [`files/xt8/xt8-bootstrap.sh`](../../files/xt8/xt8-bootstrap.sh). It writes hook scripts into `/jffs/scripts/` (JFFS is the router's small persistent flash partition; Merlin runs scripts there at set moments), sets the nvram values (nvram is where the firmware stores its settings) that are safe to script, restarts the affected services, and checks the result.
3. **Per-device lists**: the DNS Director client list and the DHCP reservations, restored from a backup or typed in again.

Four ideas explain most of the settings:

- **Pi-hole is the only DNS server clients are given**, and DNS Director (Merlin's feature that redirects port 53 traffic) forces devices that ignore that. See [DNS design](../network/dns-design.md).
- **The IPv6 page stays on Disable.** Local IPv6 is switched on for the LAN bridge by script instead. See [Local-only IPv6](../network/local-only-ipv6.md).
- **The IoT network is the ASUS guest network**, with a few narrow exceptions added by script. See [Isolated IoT network](../network/isolated-iot-network.md).
- **In shared hook files the script only owns the text between its two marker lines** (`# >>> homenet BEGIN ...` and `# <<< homenet END`). Lines that other add-ons put there, such as Skynet's, are kept.

## Before you start

- **If you have the `.CFG` and JFFS backups and the firmware is the same family, restore those and go straight to [Check it](#check-it).**
- Decide the values in the SPEC block at the top of the script. The defaults match this wiki's examples:

| Variable | Default | Meaning |
| --- | --- | --- |
| `ULA_NET` | `fd00:1234:5678:50` | First four groups of the local IPv6 /64 |
| `ROUTER6` | `${ULA_NET}::1` | The router's own local IPv6 address |
| `PIHOLE6` / `PIHOLE4` | `${ULA_NET}::11` / `192.168.50.11` | Pi-hole's addresses |
| `LAN_IP` | `192.168.50.1` | The LAN address the router must already have |
| `DOMAIN` | `home.example.com` | Local domain |
| `WAN_DNS`, `WAN_DNS2` | `1.1.1.1`, `1.0.0.1` | The router's own upstream resolvers |
| `WAN_DOT` | `1` | `1` = the router is expected to use DNS-over-TLS to those servers (set in the GUI; the script only checks it). `0` = plain DNS |
| `DNSF_CUSTOM2` | `1.1.1.1` | DNS Director "User Defined 2" |
| `DNSF_CUSTOM3` | blank | DNS Director "User Defined 3", unused |
| `GUEST_PREFIX` / `GUEST_NET` | `192.168.101.` / `192.168.101.0/24` | The guest/IoT subnet |
| `GUEST_WL` | `wl0.1` | The guest Wi-Fi interface that carries the isolation rules |
| `HB_HOSTS` | `192.168.50.5,192.168.50.6,192.168.50.7` | LAN hosts allowed to open connections into the IoT network (the k3s nodes that may run Homebridge) |

- Have the Wi-Fi keys and admin password to hand. They are not in any file here.
- Know your SSH port. The examples use `22`; write your own where you see `<SSH_PORT>`.

> **Not verified:** the bootstrap script has been syntax-checked and run against stand-in commands. It has not been run on a real router by the author. The rules it installs are the same ones that were entered by hand and confirmed working on this hardware. Do the first real run when you have time to watch it, and take the backups in [Backups and secrets](../operations/backups-and-secrets.md) first.

## Steps

### Step 1. GUI settings

Set these after a factory reset. Rows marked (script) are set by the bootstrap script in Step 4; they are listed so you can check them.

| Page | Setting | Value |
| --- | --- | --- |
| LAN > LAN IP | IP address | `192.168.50.1` / `255.255.255.0` |
| LAN > DHCP Server | Pool | `192.168.50.20` to `192.168.50.254` |
| LAN > DHCP Server | Domain name (script) | `home.example.com` |
| LAN > DHCP Server | DNS Server 1 (script) | `192.168.50.11` |
| LAN > DHCP Server | DNS Server 2 (script) | blank |
| LAN > DHCP Server | Advertise router's IP in addition to user-specified DNS (script) | No |
| LAN > DHCP Server | Manual assignments | Restored in Step 5. Reserve every device that another system refers to by address |
| LAN > DNS Director | Enable (script) | On |
| LAN > DNS Director | Global Redirection (script) | User Defined 1 |
| LAN > DNS Director | User Defined 1 (script) | IPv4 `192.168.50.11`, IPv6 `fd00:1234:5678:50::11` |
| LAN > DNS Director | User Defined 2 / 3 (script) | `1.1.1.1` / blank. Neither is used by a device |
| LAN > DNS Director | Per-device list | Restored in Step 5 |
| WAN > Internet Connection | Connect to DNS Server automatically (script) | No |
| WAN > Internet Connection | DNS Server (script) | Cloudflare: `1.1.1.1` and `1.0.0.1`. DNSSEC on, validate unsigned replies on, rebind protection on |
| WAN > Internet Connection | DNS Privacy Protocol | **DNS-over-TLS (DoT)**, profile Strict, servers `1.1.1.1` and `1.0.0.1` with TLS hostname `cloudflare-dns.com`, port and fingerprint blank. Set by hand; every field is explained in [DNS design](../network/dns-design.md) Step 4 |
| WAN > Internet Connection | Prevent client auto DoH | Auto |
| WAN > DDNS | Host name | Optional. For example `myhome.asuscomm.com` with a Let's Encrypt certificate |
| WAN > Virtual Server / Port Forwarding | | Optional. Use static rules, not UPnP. Example: external TCP 32400 to a media server on port 32400 |
| IPv6 | Connection type (script) | **Disable**. Local IPv6 comes from the scripts |
| Administration > System | Enable JFFS custom scripts and configs (script) | Yes |
| Administration > System | Enable SSH | LAN only, port `<SSH_PORT>` |
| Administration > System | Scheduled reboot | Weekly, at about 4 am. Recommended |
| USB drive | Mount point | `/tmp/mnt/<label>`. In the examples the label is `gateway`, so Skynet lives in `/tmp/mnt/gateway/skynet` |
| AiMesh | Node | If you have a second unit, add it here. Then see [AiMesh node](asus-aimesh-node.md) |
| Firewall > General | SPI firewall, DoS protection | On. Respond to WAN ping: off |
| VPN | IPSec server | Optional. On if you want remote access to the LAN |
| QoS | | Off. Turning any QoS mode on disables hardware NAT acceleration |
| Guest Network | IoT network | See Step 2 |

Wireless:

| Setting | Value | Why |
| --- | --- | --- |
| SSIDs | `Home` (2.4 GHz, channel 1, 20 MHz), `Home5g` (5 GHz-1, channel 36), `Home6g` (5 GHz-2, channel 177, 160 MHz) | Passwords: `<WIFI_PASSWORD>` |
| Professional > Roaming assistant | -70 dBm on all bands (2.4 GHz may be -72 to -75) | The roaming assistant disconnects a client whose signal is weaker than this. Thresholds of -55/-55/-50 kicked devices off Wi-Fi about 25 times a day |
| Professional > Airtime Fairness | Disabled | |
| Professional > AP Isolation | Off | On would break HomeKit discovery |
| Professional > IGMP Snooping | Enabled | |
| AiProtection | Off, or at least Two-Way IPS and Infected Device Prevention off | The Trend Micro engine was seen to crash the kernel and reboot the router |

> **Pitfall:** open one page of the web UI at a time. Several simultaneous requests have frozen it. If that happens, wait.

### Step 2. Guest network for IoT devices

| Setting | Value |
| --- | --- |
| Page | Guest Network, first 2.4 GHz slot |
| Network name | `Home-IoT` |
| Access Intranet | **Disabled** |
| Resulting subnet | `192.168.101.0/24`, router at `192.168.101.1` |
| Resulting bridge | `br1`, containing the guest Wi-Fi interface `wl0.1` and `eth1.501` to `eth6.501` |

**Run on: the router**

```sh
ip -4 -o addr show | grep 192.168.101
brctl show
```

The first command must print a bridge with `192.168.101.1/24`. The second must list `wl0.1` under that bridge, and `eth1.501` to `eth6.501`. Those `.501` members are the guest network leaving every LAN port as tagged VLAN 501, which lets a wired access point broadcast the same network. Confirmed on this hardware.

If the guest Wi-Fi interface has another name, change `GUEST_WL` at the top of `xt8-bootstrap.sh` before Step 4. The full design is in [Isolated IoT network](../network/isolated-iot-network.md).

### Step 3. Add-ons

amtm is the Asuswrt-Merlin terminal menu that installs and updates add-ons. Entware (the package manager most add-ons need) and Skynet need the USB drive.

**Run on: the router**

```sh
amtm
```

Install these from the menu, with Skynet's data on the USB drive:

| Add-on | What it is |
| --- | --- |
| Skynet | Firewall add-on that blocks known-bad addresses using IP sets |
| YazDHCP | Stores DHCP reservations in files, which raises the number you can have |
| Scribe | Replaces the firmware's logger with syslog-ng and logrotate, so the log lives on the USB drive and survives reboots |

After installing Scribe, its log rotation needs one folder that nothing creates. The bootstrap script makes it and `verify` checks it. To do it by hand:

**Run on: the router**

```sh
mkdir -p /opt/var/lib
/opt/sbin/logrotate /opt/etc/logrotate.conf
logger "rotation test"; sleep 2; ls -la /opt/var/log/messages*
```

`messages` must be small and growing, with the old log beside it as `messages-<date>`. Details in [Router logging](../network/router-logging.md).

> **Pitfall:** do not install dnscrypt-proxy on the router. Its manager script was seen to cause about 550 dnsmasq restarts in one day. Pi-hole already encrypts upstream DNS ([DNS design](../network/dns-design.md)). If it is already installed, see [Undo](#removing-dnscrypt-proxy).

### Step 4. Run the bootstrap script

Copy the script to the router and log in.

**Run on: your computer**, from the root of this repo

```sh
scp -O -P 22 files/xt8/xt8-bootstrap.sh admin@192.168.50.1:/jffs/
ssh -p 22 admin@192.168.50.1
```

`-O` is required because the router has no SFTP server. Replace `22` with your `<SSH_PORT>`.

**Run on: the router**

```sh
sh /jffs/xt8-bootstrap.sh install
```

What `install` does, in order:

1. Refuses to run unless the router's LAN address is `192.168.50.1` (`LAN_IP` in the SPEC block).
2. Copies every file it is about to change into `/jffs/homenet-backups/`, with a timestamp.
3. Writes the five files described under [What each installed script does](#what-each-installed-script-does) to `/jffs/scripts/`. If it finds a hand-made version of one of the hook files without markers, it rebuilds the file and keeps lines owned by other add-ons (a command followed by a `# Tag` comment); the original is in the backup folder.
4. Creates Scribe's logrotate state folder `/opt/var/lib` if logrotate is installed and the folder is missing.
5. Applies the nvram settings marked (script) in Step 1 and prints each as `ok` or `CHANGED`. If anything changed it commits nvram and tells you to reboot once.
6. Restarts dnsmasq, waits 5 seconds, restarts the firewall, waits 10 seconds.
7. Runs `verify` and prints PASS or FAIL per check.

The nvram keys it sets:

| Key | Value | GUI setting |
| --- | --- | --- |
| `jffs2_scripts` | `1` | Administration > System > Enable JFFS custom scripts |
| `ipv6_service` | `disabled` | IPv6 > Connection type = Disable |
| `ipv6_fw_rulelist` | empty | Firewall > IPv6 Firewall: no inbound rules |
| `ipv6_dns1_x` | Pi-hole's IPv6 address | IPv6 DNS, only used if native IPv6 is ever enabled |
| `lan_domain` | `home.example.com` | LAN > DHCP Server > Domain name |
| `dhcp_dns1_x` | `192.168.50.11` | LAN > DHCP Server > DNS Server 1 |
| `dhcp_dns2_x` | empty | LAN > DHCP Server > DNS Server 2 |
| `dhcpd_dns_router` | `0` | Advertise router's IP = No |
| `dnsfilter_enable_x` | `1` | LAN > DNS Director > Enable |
| `dnsfilter_mode` | `8` | DNS Director global = User Defined 1 |
| `dnsfilter_custom1` / `2` / `3` | `192.168.50.11` / `1.1.1.1` / `192.168.50.11` | DNS Director User Defined 1 / 2 / 3 |
| `wan0_dnsenable_x`, `wan_dnsenable_x` | `0` | WAN > Connect to DNS Server automatically = No |
| `dnsfilter_custom61` | `fd00:1234:5678:50::11` | DNS Director User Defined 1, IPv6 |
| `wan0_dns1_x`, `wan_dns1_x` | `1.1.1.1` | WAN > DNS Server 1 |
| `wan0_dns2_x`, `wan_dns2_x` | `1.0.0.1` | WAN > DNS Server 2 |

All commands:

| Command | Use |
| --- | --- |
| `sh /jffs/xt8-bootstrap.sh install` | Everything above. Also the default when no command is given |
| `sh /jffs/xt8-bootstrap.sh verify` | Health check at any time. Changes nothing |
| `sh /jffs/xt8-bootstrap.sh scripts-only` | Reinstall the scripts, restart the services and verify, without touching nvram |
| `sh /jffs/xt8-bootstrap.sh backup` | Save `/jffs/scripts`, `/jffs/configs`, `/jffs/addons` and the per-device lists to the USB drive |
| `sh /jffs/xt8-bootstrap.sh restore-lists <file>` | Load the per-device lists back |
| `sh /jffs/xt8-bootstrap.sh uninstall` | Remove what it installed. IPv6 on `br0` goes off. nvram is left alone |

The script is safe to run repeatedly. To change an address later, edit the SPEC block at the top of the script and run `install` again.

### Step 5. Per-device lists

After a reset the DNS Director client list and the DHCP reservations are empty. With a backup made by the `backup` command:

**Run on: the router**

```sh
sh /jffs/xt8-bootstrap.sh restore-lists /tmp/mnt/gateway/homenet-backup/nvram-lists-<timestamp>.txt
reboot
```

It restores four nvram keys and nothing else: `dnsfilter_rulelist` (DNS Director clients), `dhcp_staticlist` (reservations), `dhcp_hostnames` and `custom_clientlist` (client names). Instead of a reboot you can run `service restart_dnsmasq; service restart_firewall`.

Without a backup, enter them again in the GUI. Typical DNS Director exceptions:

| Rule | Give it to |
| --- | --- |
| **Router** | Devices that must not depend on Pi-hole: every cluster node, and a work laptop on each of its adapters. The router's own resolver answers them. See below |
| No Redirection | Your own computer, temporarily, while rebuilding |
| User Defined 2 or 3 | Nothing in this build. If you use one, it must point at an address that really answers DNS |

#### If you also have the k3s cluster that runs Pi-hole

Each cluster node uses `1.1.1.1` and `9.9.9.9` for its own lookups so that it never needs Pi-hole in order to start Pi-hole ([DNS design](../network/dns-design.md)). DNS Director redirects port 53 from every device to Pi-hole unless the device has its own rule, whatever the device's own settings say. So add **every** node, including a VM node, to LAN > DNS Director as **Router**, by MAC address. Also give each node a DHCP reservation or a static address.

> **Not verified:** that the redirect really catches a node without an exception was not confirmed on this hardware. The check: on the node, run `nslookup example.com 1.1.1.1` while watching the Pi-hole query log. If the query shows up in Pi-hole, the node is being redirected.

### Step 6. Back up

**Run on: the router**

```sh
sh /jffs/xt8-bootstrap.sh backup
```

It writes `nvram-lists-<timestamp>.txt`, `jffs-<timestamp>.tar.gz` and a copy of the script to `/tmp/mnt/gateway/homenet-backup/`, and prints an `scp` line for copying the folder off the router. If no USB drive is mounted at `/tmp/mnt/gateway` it writes to `/tmp/homenet-backup` instead, which is RAM and is lost at reboot: copy it at once.

**Run on: your computer**

```sh
scp -O -P 22 -r admin@192.168.50.1:/tmp/mnt/gateway/homenet-backup ./xt8-backup
```

Also take the two GUI backups: Administration > Restore/Save/Upload Setting > **Save setting** (the `.CFG` file, which restores every GUI setting onto the same firmware family only) and **Backup JFFS partition**. All of these contain Wi-Fi keys and the admin password. Keep them off the network and out of Git. See [Backups and secrets](../operations/backups-and-secrets.md).

## Check it

**Run on: the router**

```sh
sh /jffs/xt8-bootstrap.sh verify
```

Expected: every line `PASS`, and a last line ending `0 failed.` It checks the LAN address, the nvram settings, the router's IPv6 address and missing default route, the dnsmasq configuration, the upstream resolver, that dnscrypt-proxy is not running, the `ip6tables`, `iptables` and `ebtables` rules, the guest bridge, that Pi-hole answers on IPv4, and (if Scribe is installed) the logrotate state folder.

Pi-hole over IPv6 is tested from a client, not from the router: the router's own `ip6tables` INPUT policy drops the reply. See [Verification](../operations/verification.md).

### If verify reports a FAIL

| FAIL | First thing to do |
| --- | --- |
| `router LAN address is ...` | Fix LAN > LAN IP in the GUI |
| Any nvram check (JFFS scripts, IPv6 type, DHCP, DNS Director) | Run `install` again, then reboot |
| `br0 has ...::1/64`, `no IPv6 default route`, any `dnsmasq:` check | `service restart_dnsmasq`, wait 5 seconds, verify again. If it still fails, `cat /jffs/scripts/dnsmasq.postconf` and confirm the marked block is there and the file is executable |
| Any `DNS-over-TLS` check | The script's `WAN_DOT=1` says the router should use DNS-over-TLS. Set WAN > DNS Privacy Protocol as in [DNS design](../network/dns-design.md) Step 4, or set `WAN_DOT=0` if you chose plain DNS. The keys were confirmed on 3004.388.10_2 ([DNS design](../network/dns-design.md) Step 4) |
| `dnsmasq: upstream is only ...` | Only with `WAN_DOT=0`. `cat /tmp/resolv.dnsmasq` must list exactly the `WAN_DNS` servers. A `127.x` entry means DNS-over-TLS is on or dnscrypt-proxy is back |
| `no dnscrypt-proxy running` | [Removing dnscrypt-proxy](#removing-dnscrypt-proxy) |
| Any `ip6tables` or `iptables` check | `service restart_firewall`, wait 10 seconds, verify again |
| `guest bridge for 192.168.101.x exists` | The guest network does not exist yet or uses another subnet (Step 2) |
| `ebtables: 6 guest->Homebridge ACCEPT rules` | `sh /jffs/scripts/kasa-guest-allow.sh`. If it stays wrong, check `GUEST_WL` against `brctl show` |
| `Pi-hole answers on IPv4` | Pi-hole is down or not built yet ([Pi-hole](../apps/pihole.md)) |
| `Scribe: logrotate state folder exists` | `mkdir -p /opt/var/lib`. If it keeps disappearing, the USB drive was reformatted or is failing |

## What each installed script does

Reference copies are in [`files/xt8/jffs-scripts/`](../../files/xt8/jffs-scripts/). Do not copy them to the router by hand; run the bootstrap script, which also keeps other add-ons' lines in the shared files. On a real router `firewall-start` also has a Skynet line outside the marked block.

| File | Runs when | What it does |
| --- | --- | --- |
| `homenet.conf` | Read by the others | The addresses from the SPEC block |
| `dnsmasq.postconf` | Every dnsmasq start | Turns local-only IPv6 on for `br0` and advertises Pi-hole as the only IPv6 DNS server |
| `firewall-start` | Every firewall restart | IPv6 filter rules, and the rules that let chosen LAN hosts reach the IoT network |
| `kasa-guest-allow.sh` | Called by the two around it | The `ebtables` rules that let IoT replies through the guest isolation |
| `service-event-end` | After any router service event | Re-runs `kasa-guest-allow.sh` after a Wi-Fi restart wipes the `ebtables` rules |

### `dnsmasq.postconf`: local-only IPv6

| Line | Why |
| --- | --- |
| `disable_ipv6 = 0` on `br0` | With IPv6 = Disable in the UI the firmware turns IPv6 off on `br0`. This turns it back on for the LAN only |
| `accept_ra = 0`, `autoconf = 0` | The router never configures itself from another device's router advertisements |
| `ip -6 addr add ...::1/64` | The router's own address. dnsmasq builds the advertised prefix from it |
| `enable-ra` | dnsmasq sends router advertisements (the messages that tell clients which IPv6 prefix to use) |
| `ra-param=br0,0,0` | Router lifetime 0: clients get addresses but **no IPv6 default route**, so internet traffic stays on IPv4 |
| `dhcp-range=::,constructor:br0,ra-stateless,64,12h` | Clients make their own addresses (SLAAC). `ra-names` was deliberately left out |
| `dhcp-option=option6:dns-server,[...::11]` | Pi-hole is the only IPv6 DNS server advertised |
| `dhcp-option=option6:domain-search,home.example.com` | The local search domain over IPv6 |
| no `quiet-ra` | Deliberate. dnsmasq then logs every advertisement it sends; see [Router logging](../network/router-logging.md) |

The whole design is in [Local-only IPv6](../network/local-only-ipv6.md).

### `firewall-start`: IPv6 filter and the path into the IoT network

| Rule | Why |
| --- | --- |
| `INPUT -i br0` udp and tcp port 53 REJECT | The router refuses DNS over IPv6, so it cannot become a way around Pi-hole |
| `INPUT -i br0` udp 547 and ICMPv6 ACCEPT | Stateless DHCPv6 and neighbor discovery |
| `FORWARD -i br0 ! -o br0 DROP` | LAN IPv6 is never routed anywhere else |
| `OUTPUT -o br0 ACCEPT` | The firmware sets the IPv6 OUTPUT policy to DROP when IPv6 is disabled. Without this rule the router cannot send advertisements or answer pings, and clients never get the prefix. This is the rule most easily missed |
| `INPUT -i lo` and `OUTPUT -o lo` ACCEPT | Loopback |
| `FORWARD br0 -> guest bridge` for `HB_HOSTS` | Lets those LAN hosts open connections to devices on `192.168.101.0/24` |
| `FORWARD guest bridge -> br0` ESTABLISHED,RELATED | Lets only the replies back. IoT devices still cannot start a connection to the LAN |
| Every rule is delete-then-insert | Repeated firewall restarts never stack duplicates |

The guest bridge name is looked up from the address prefix at run time. If it is not found, the script logs `guest bridge (192.168.101.x) not found; Homebridge->Kasa rules skipped` under the tag `firewall-start`.

### `kasa-guest-allow.sh` and `service-event-end`: the guest isolation

ASUS guest isolation is not in `iptables`. It is in `ebtables -t broute` (a filter that acts on bridged frames before routing), as DROP rules for ICMP and TCP from `wl0.1` to `192.168.50.0/24`. Those drop the **replies** from IoT devices even when `iptables` allows them. The script inserts ACCEPT rules above those DROPs: ICMP and TCP for each address in `HB_HOSTS`, so six rules with the defaults.

**Run on: the router**

```sh
ebtables -t broute -L BROUTING | grep -n 192.168.50
```

Healthy output is six `-j ACCEPT` lines followed by the two `192.168.50.0/24 ... -j DROP` lines.

A Wi-Fi restart rebuilds the `ebtables` rules and removes the ACCEPT lines. `service-event-end` re-runs the script ten seconds after any `wireless`, `net_and_phy` or `allnet` restart.

## Pitfalls

Things that will bite you again:

| What happens | Why | Avoid or recover |
| --- | --- | --- |
| Clients lose their `fd00:` address after you change the IPv6 page | Every mode other than Disable either needs an ISP prefix or makes the router advertise itself as DNS | Leave IPv6 on **Disable**. The price is that System Log > IPv6 stays blank; use the SSH commands in [Router logging](../network/router-logging.md) |
| IPv6 on `br0` goes off after an amtm or firmware action | The firmware switches it off again | `service restart_dnsmasq` brings it back |
| Ping to Pi-hole's address fails | Normal for a MetalLB address | Test with `nslookup example.com 192.168.50.11` |
| Web UI freezes | Several pages loading at once | One page at a time. Wait for it to recover |
| `ip -6 neigh flush ... nud failed` does nothing | BusyBox's `ip` has no working flush for that | Use the loop below |
| A device has no DNS at all | Its DNS Director rule points at an address that no longer serves DNS. This happened with "User Defined 3" set to a cluster node's own address, which only answered DNS while a different load balancer was in use | Keep every User Defined entry pointing at a live resolver. The script sets User Defined 3 to `192.168.50.11` |
| DHCP "DNS Server 1" left on a temporary value after troubleshooting | The emergency bypass in [DNS design](../network/dns-design.md) was not undone | `verify` catches it. Set it back to `192.168.50.11` |
| IoT devices stop answering after a Wi-Fi change | The `ebtables` ACCEPT rules were wiped and the hook did not restore them | `sh /jffs/scripts/kasa-guest-allow.sh`; check `/jffs/scripts/service-event-end` exists and is executable |
| An IoT device stops answering after it roams to the AiMesh node | The `ebtables` rules are installed on the main router only | Observed working with devices connected through the node, so look here only if one stops. See [AiMesh node](asus-aimesh-node.md) |
| Devices drop off Wi-Fi many times a day | Roaming assistant threshold too strict | -70 dBm (Step 1) |
| Router reboots by itself every few days | AiProtection engine crash | Turn AiProtection off (Step 1) |
| Throughput drops after enabling QoS | Any QoS mode disables hardware NAT acceleration | Leave QoS off |
| Hundreds of dnsmasq restarts in the log | dnscrypt-proxy's manager | [Removing dnscrypt-proxy](#removing-dnscrypt-proxy) |
| `/jffs/scripts/dnsmasq.postconf` on a long-lived router is longer than the reference copy | Other tools or earlier hand edits added lines outside the marked block, for example `pc_append "quiet-ra" "$CONFIG"` | Read the live file with `cat /jffs/scripts/dnsmasq.postconf`. The script never touches lines outside its markers |

Clearing failed IPv6 neighbor entries:

**Run on: the router**

```sh
ip -6 neigh show nud failed | while read a b c d; do ip -6 neigh del "$a" dev "$c"; done
```

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Clients get no `fd00:` address | `br0` IPv6 off, or the OUTPUT rule missing | `service restart_dnsmasq; service restart_firewall`, then `verify` |
| Router answers nothing over IPv6 | `ip6tables` OUTPUT policy DROP | `service restart_firewall` |
| `scp` fails with a subsystem or connection-closed error | The router has no SFTP server | Add `-O` |
| `install` stops with "router LAN IP is ..." | The LAN address differs from `LAN_IP` | Set LAN > LAN IP, or edit the SPEC block |
| amtm or Entware downloads hang | Unresolved. Skynet is suspected | Disable Skynet briefly and retry |
| JFFS CRC errors in the log | Flash partition trouble. Seen for a few days, then stopped by itself | If they return: back up JFFS, format it at next boot (Administration > System), restore |
| Things come back in the wrong order after a power cut | The router is up before Pi-hole | Expected. It settles in about five minutes; see [DNS design](../network/dns-design.md). Then run `verify` and confirm the `ebtables` rules came back |
| Odd lines in the router log | | [Router logging](../network/router-logging.md) |

More in [Troubleshooting](../operations/troubleshooting.md).

## Undo

**Run on: the router**

```sh
sh /jffs/xt8-bootstrap.sh uninstall
```

It removes the marked blocks from `dnsmasq.postconf`, `firewall-start` and `service-event-end`, deletes `kasa-guest-allow.sh` and `homenet.conf`, restarts dnsmasq and the firewall, removes the router's local IPv6 address and switches IPv6 off on `br0`. nvram settings are left as they are; change those in the GUI. Earlier versions of every file are in `/jffs/homenet-backups/`.

### Removing dnscrypt-proxy

Use this if the dnscrypt-proxy installer for Asuswrt-Merlin was ever run on the router.

**Run on: the router**

```sh
[ -f /jffs/dnscrypt/manager ] && sh /jffs/dnscrypt/manager stop x
killall dnscrypt-proxy 2>/dev/null
for F in /jffs/scripts/* /jffs/configs/*; do
  [ -f "$F" ] && sed -i '/Asuswrt-Merlin-Dnscrypt-Proxy-Installer/d' "$F"
done
sed -i '\~/jffs/dnscrypt/manager~d' /jffs/scripts/init-start /jffs/scripts/services-stop /jffs/scripts/dnsmasq.postconf
rm -rf /jffs/dnscrypt
service restart_dnsmasq
```

Check it is gone:

**Run on: the router**

```sh
grep -rn -i dnscrypt /jffs/scripts /jffs/configs
cat /tmp/resolv.dnsmasq
```

The only matches allowed are lines inside `/jffs/scripts/firewall` (that file is Skynet's; three lines were seen). With plain DNS, `resolv.dnsmasq` must list only your upstream servers. With DNS-over-TLS it points at the router's own forwarder instead, so rely on the `grep` and on `ps w | grep dnscrypt` showing nothing.

## Firmware and updates

Where the GNUton firmware for the RT-AX95Q comes from, the exact file name, how to flash it from stock and go back, how the AiMesh node is updated (the **Upload** link on the main router), and where amtm, Entware and each add-on now live (several moved to the AMTM-OSR organisation): [Software and firmware](../operations/software-and-firmware.md#gnuton-asuswrt-merlin-for-the-xt8-rt-ax95q). A first flash and factory reset, with Entware on a USB drive, is walked through in [From nothing to a full deployment](../start-here/build-from-nothing.md#phase-1-main-router-firmware). The upgrade routine and the re-checks afterwards are in [Maintenance](../operations/maintenance.md#step-4-firmware-and-add-on-upgrades-router-and-node).

## References

- [gnuton/asuswrt-merlin.ng](https://github.com/gnuton/asuswrt-merlin.ng): GNUton's builds of Asuswrt-Merlin for extra models, including the ZenWiFi XT8 (RT-AX95Q).
- [Asuswrt-Merlin wiki: User scripts](https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts): when `services-start`, `firewall-start` and `service-event-end` run, and how to enable JFFS scripts.
- [Asuswrt-Merlin wiki: Custom config files](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Custom-config-files): postconf scripts and the `pc_append` helper used by `dnsmasq.postconf`.
- [Asuswrt-Merlin wiki: DNS Director](https://github.com/RMerl/asuswrt-merlin.ng/wiki/DNS-Director): global redirection, per-device rules, user-defined servers.
- [Asuswrt-Merlin wiki: Entware](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Entware): the package manager the add-ons need, and its USB disk requirement.
- [amtm](https://github.com/decoderman/amtm): the terminal menu used to install the add-ons.
- [Skynet (IPSet_ASUS)](https://github.com/Adamm00/IPSet_ASUS): the firewall add-on and its USB requirement.
- [YazDHCP](https://github.com/AMTM-OSR/YazDHCP): the DHCP reservation add-on (the earlier `jackyaz/YazDHCP` repository is archived).
- [scribe](https://github.com/AMTM-OSR/scribe): the syslog-ng and logrotate installer.
- [dnsmasq manual page](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html): every dnsmasq option the postconf script appends.
