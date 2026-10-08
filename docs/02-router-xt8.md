# 02. The XT8 router

ASUS ZenWiFi XT8 (product ID RT-AX95Q), two units in AiMesh: "Laundry Room" (router, 192.168.50.1) and "Master Bedroom" (node, wired backhaul). Firmware is GNUton's Asuswrt-Merlin.ng fork, 3004.388.10_2. Add-ons: Skynet, YazDHCP, Scribe.

The router is rebuilt in three parts: GUI settings by hand (or from the `.CFG` backup), then `xt8-bootstrap.sh` for everything scriptable, then the per-device lists.

**If you have the `.CFG` and JFFS backups and the firmware is the same family, restore those and skip to "Check it".**

## Part 1. GUI settings

Set these by hand after a factory reset. The bootstrap script sets the rows marked (script) for you; they are listed so you can check them.

| Page | Setting | Value |
| --- | --- | --- |
| LAN → LAN IP | IP address | 192.168.50.1 / 255.255.255.0 |
| LAN → DHCP Server | Pool | 192.168.50.20 to 192.168.50.254 |
| LAN → DHCP Server | Domain name (script) | `home.example.com` |
| LAN → DHCP Server | DNS Server 1 (script) | 192.168.50.11 |
| LAN → DHCP Server | DNS Server 2 (script) | blank |
| LAN → DHCP Server | Advertise router's IP in addition to user-specified DNS (script) | No |
| LAN → DHCP Server | Manual assignments | Restored in Part 3. Must include 192.168.50.146 for MAC `52:55:55:15:F1:69` (the Mac VM) and every Kasa device in [01](01-inventory.md) |
| LAN → DNS Director | Enable (script) | On |
| LAN → DNS Director | Global Redirection (script) | User Defined 1 |
| LAN → DNS Director | User Defined 1 / 2 / 3 (script) | 192.168.50.11 / 1.1.1.1 / 192.168.50.11 |
| LAN → DNS Director | Per-device list | Restored in Part 3 |
| WAN → Internet Connection | Connect to DNS Server automatically (script) | No |
| WAN → Internet Connection | DNS Server 1 (script) | 9.9.9.9, DNSSEC on |
| WAN → DDNS | Host name | `myhome.asuscomm.com`, Let's Encrypt certificate |
| WAN → Virtual Server / Port Forwarding | Enable | Yes |
| WAN → Virtual Server / Port Forwarding | Plex | External TCP 32400 → 192.168.50.2 port 32400. Static rule, not UPnP |
| IPv6 | Connection type (script) | **Disable**. Local IPv6 comes from the scripts |
| Administration → System | Enable JFFS custom scripts and configs (script) | Yes |
| Administration → System | Enable SSH | LAN only, port 666 |
| Administration → System | Scheduled reboot | Main router: weekly, about 4 am (recommended in September; confirm it is set). The node has its own, set by script: see "The AiMesh node" |
| USB drive | Mount point | `/tmp/mnt/gateway` (Skynet lives in `/tmp/mnt/gateway/skynet`) |
| AiMesh | Node | Re-add the second XT8, wired backhaul. Then run the node script: see "The AiMesh node" |
| Firewall → General | SPI firewall, DoS protection | On. Respond to WAN ping: off |
| VPN | IPSec server | On (remote access to the LAN) |
| QoS | | Off. Turning any QoS mode on disables hardware NAT acceleration |
| Guest Network | IoT network | See below |

### Wireless

| Setting | Value | Why |
| --- | --- | --- |
| SSIDs | `Home` (2.4 GHz, ch 1, 20 MHz), `Home5g` (5 GHz-1, ch 36), `Home6g` (5 GHz-2, ch 177, 160 MHz) | Keys are in the password manager |
| Professional → Roaming assistant | -70 dBm on all bands (2.4 GHz may be -72 to -75) | It was -55/-55/-50 and was kicking devices off Wi-Fi about 25 times a day |
| Professional → Airtime Fairness | Disabled | |
| Professional → AP Isolation | Off | On would break HomeKit discovery |
| Professional → IGMP Snooping | Enabled | |
| AiProtection | Off, or at least Two-Way IPS and Infected Device Prevention off | The Trend Micro engine crashed the kernel on 22 September and rebooted the router |

The September review recommended the roaming, AiProtection and scheduled-reboot changes. I do not know which of them you applied, so check each on the live router and record it here.

### Guest / IoT network

This is the network the Kasa and Wyze devices live on.

| Setting | Value |
| --- | --- |
| Page | Guest Network, first 2.4 GHz slot |
| Network name | `Home-IoT` |
| Access Intranet | **Disabled** |
| Resulting subnet | 192.168.101.0/24, router at 192.168.101.1 |
| Resulting bridge | `br1`, containing the guest Wi-Fi interface `wl0.1` and `eth1-6.501` |

Check it over SSH on the router:

```sh
ip -4 -o addr show | grep 192.168.101
brctl show
```

The first command must print a bridge with `192.168.101.1/24`. The second must list `wl0.1` under that bridge, and `eth1.501` to `eth6.501`. Those `.501` members are the guest network leaving every LAN port as tagged VLAN 501. Confirmed on 3 October. The Archer A7 picks that VLAN up to broadcast `Home-IoT` as well ([03](03-access-points.md)). If the guest Wi-Fi interface has another name, change `GUEST_WL` at the top of `xt8-bootstrap.sh` before running it.

### Add-ons

Reinstall Skynet, YazDHCP and Scribe through `amtm`, with Skynet's data on the USB drive.

**After installing Scribe, its log rotation needs one folder that nothing creates.** The bootstrap script now makes it (`/opt/var/lib`) and `verify` checks it. By hand:

```sh
mkdir -p /opt/var/lib
/opt/sbin/logrotate /opt/etc/logrotate.conf
logger "rotation test"; sleep 2; ls -la /opt/var/log/messages*
```

`messages` must be small and growing, with the old log beside it as `messages-<date>`. Until 7 October the folder was missing: `/opt/var/log/logrotate.log` showed "error creating stub state file /opt/var/lib/logrotate.status" every night at 00:05 and `messages` had reached 25.6 MB. **Do not reinstall dnscrypt-proxy.** Its manager caused about 550 dnsmasq restarts in one day and was removed on 1 October.

## Part 2. The bootstrap script

**Paste on: your Mac**, in the root of this repo.

```sh
scp -O -P 666 network/xt8/xt8-bootstrap.sh homeuser@192.168.50.1:/jffs/
ssh -p 666 homeuser@192.168.50.1
```

`-O` is required because the router has no SFTP server.

**Paste on: the router.**

```sh
sh /jffs/xt8-bootstrap.sh install
```

What `install` does:

1. Refuses to run unless the router's LAN address is 192.168.50.1.
2. Copies every file it is about to change into `/jffs/homenet-backups/`.
3. Writes the five files in [`network/xt8/jffs-scripts/`](../network/xt8/jffs-scripts/) to `/jffs/scripts/`, and creates Scribe's logrotate folder if Scribe is installed.
4. Applies the nvram settings marked (script) above and prints each as `ok` or `CHANGED`.
5. Restarts dnsmasq and the firewall.
6. Runs `verify` and prints PASS or FAIL per check.

In the shared hook files the script only owns the text between its two marker lines, so Skynet keeps its own line.

| Command | Use |
| --- | --- |
| `sh /jffs/xt8-bootstrap.sh verify` | Health check at any time. Changes nothing |
| `sh /jffs/xt8-bootstrap.sh scripts-only` | Reinstall the scripts without touching nvram |
| `sh /jffs/xt8-bootstrap.sh backup` | Save scripts, configs, add-ons and the per-device lists to the USB drive |
| `sh /jffs/xt8-bootstrap.sh restore-lists <file>` | Load the per-device lists back |
| `sh /jffs/xt8-bootstrap.sh uninstall` | Remove what it installed. IPv6 on `br0` goes off |

To change an address later, edit the SPEC block at the top of the script and run `install` again.

**This script has been syntax-checked and run against stand-in commands here, not on your router.** The rules it installs are the ones you typed by hand and confirmed in September. Do the first real run when you have time to watch it.

### Changed in this version: DNS Director "User Defined 3"

It was 192.168.50.5. That address only answered DNS because the k3s built-in load balancer published Pi-hole on every node. That load balancer was disabled on 3 October, so **192.168.50.5 no longer answers DNS**, and any device with a "User Defined 3" rule has had no working DNS since. The script now sets User Defined 3 to 192.168.50.11. Until you run it, fix this in the GUI: LAN → DNS Director → User Defined 3 → 192.168.50.11.

## Part 3. Per-device lists

After a reset the DNS Director client list and DHCP reservations are empty. With a backup:

```sh
sh /jffs/xt8-bootstrap.sh restore-lists /tmp/mnt/gateway/homenet-backup/nvram-lists-<timestamp>.txt
reboot
```

Without one, re-enter them in the GUI. DNS Director exceptions as last read on 24 September (you changed some afterwards, so the live router is the authority):

| Rule | Devices |
| --- | --- |
| User Defined 2 (1.1.1.1) | k3sprimary, DC-01 (`02:00:00:00:00:03`), MBP-Server-LAN, `02:00:00:00:00:04`, Owners-Work-Macbook, `02:00:00:00:00:05` |
| User Defined 3 | Three devices (not recorded which) |

### The k3s nodes and DNS Director

Each k3s node uses 1.1.1.1 and 9.9.9.9 for its own lookups, so a node never needs Pi-hole in order to start Pi-hole ([04](04-k3s-cluster.md)). DNS Director redirects port 53 from every device to Pi-hole unless the device has its own rule. Only k3sprimary is on the list above. That means funkyfresh, k3snode2 and the Mac VM are probably still being redirected to Pi-hole whatever their own settings say.

Add all three to DNS Director as **User Defined 2** (or **No Redirection**):

| Device | MAC |
| --- | --- |
| funkyfresh | `02:00:00:00:00:06` |
| k3snode2 | `02:00:00:00:00:07` |
| lima-k3s-mac | `52:55:55:15:F1:69` |

I have not confirmed the redirect on your router. The check, on funkyfresh, while watching the Pi-hole query log: `nslookup example.com 1.1.1.1`. If the query shows up in Pi-hole, the node is being redirected.

## Check it

```sh
sh /jffs/xt8-bootstrap.sh verify
```

### If verify reports a FAIL

| FAIL | First thing to do |
| --- | --- |
| LAN address | Fix LAN → LAN IP in the GUI |
| Any nvram check | Run `install` again, then reboot |
| `br0 has ...::1/64`, any `dnsmasq:` check | `service restart_dnsmasq`, wait 5 s, verify again. If still failing, `cat /jffs/scripts/dnsmasq.postconf` and confirm the marked block is there and the file is executable |
| `upstream is 9.9.9.9 only` | `cat /tmp/resolv.dnsmasq`. A `127.x` entry means dnscrypt-proxy is back |
| Any `ip6tables` or `iptables` check | `service restart_firewall`, wait 10 s, verify again |
| Guest bridge | The guest network does not exist yet or uses another subnet |
| `ebtables` rule count | `sh /jffs/scripts/kasa-guest-allow.sh`. If it stays wrong, check `GUEST_WL` against `brctl show` |
| Pi-hole answers on IPv4 | Pi-hole is down or not built yet ([07](07-pihole.md)) |
| Scribe: logrotate state folder | `mkdir -p /opt/var/lib`. If it keeps disappearing, the USB drive was reformatted or is failing |

## What each installed piece does

### `dnsmasq.postconf`: local-only IPv6

| Line | Why |
| --- | --- |
| `disable_ipv6 = 0` on `br0` | With IPv6 = Disable in the UI the firmware turns IPv6 off on `br0`. This turns it back on for the LAN only |
| `accept_ra = 0`, `autoconf = 0` | The router never configures itself from another device's advertisements |
| `ip -6 addr add ...::1/64` | The router's own address; dnsmasq builds the advertised prefix from it |
| `enable-ra` | dnsmasq sends router advertisements |
| `ra-param=br0,0,0` | Router lifetime 0: clients get addresses but **no IPv6 default route**, so internet traffic stays on IPv4 |
| `dhcp-range=::,constructor:br0,ra-stateless,64,12h` | SLAAC addresses. `ra-names` was deliberately left out |
| `option6:dns-server` | Pi-hole is the only IPv6 DNS server advertised |
| no `quiet-ra` | Deliberate. dnsmasq then logs every advertisement it sends; see below |

#### Seeing IPv6 on the router

**System Log → IPv6 says "IPv6 Not enabled" and always will.** That page only fills in when IPv6 is enabled in the UI, which must stay on Disable. The same information over SSH on the router:

```sh
ip -6 addr show dev br0
ip -6 neigh show dev br0
ip -6 route
```

The first is the router's own addresses, the second is every client's IPv6 address with its MAC, and the third must have no `default` line.

**Advertisement logging.** With no `quiet-ra` line, `/opt/var/log/messages` gets these:

| Line | Meaning |
| --- | --- |
| `RTR-ADVERT(br0) fd00:1234:5678:50::` | The router announced the prefix. A burst after each dnsmasq restart, then one every few minutes |
| `RTR-SOLICIT(br0)` | A client asked for an advertisement, usually on joining or waking |

Watch them live with `tail -f /opt/var/log/messages | grep -e RTR- -e SLAAC`.

Until 7 October the live `/jffs/scripts/dnsmasq.postconf` had a line `pc_append "quiet-ra" "$CONFIG"` (line 25) that hid these. It was commented out that day; the file before the change is `/jffs/scripts/dnsmasq.postconf.bak`. That line was never part of this repo's block, so a rebuild from the bootstrap script gives the logging by default. To silence it again, add the line back **below** the `# <<< homenet END` marker, then `service restart_dnsmasq`. The lines name the interface, not the client; for "which device has which address" use `ip -6 neigh`.

`DHCPSOLICIT(br0)` lines with no reply are one device asking for a DHCPv6 address. The router only does SLAAC, so nothing answers. Harmless.

### `firewall-start`: IPv6 filter and the Homebridge path

| Rule | Why |
| --- | --- |
| `INPUT -i br0` port 53 REJECT | The router refuses DNS over IPv6, so it cannot become a way around Pi-hole |
| `INPUT -i br0` udp 547 and ICMPv6 ACCEPT | Stateless DHCPv6 and neighbor discovery |
| `FORWARD -i br0 ! -o br0 DROP` | LAN IPv6 is never routed anywhere else |
| `OUTPUT -o br0 ACCEPT` | **The one that caused trouble.** The firmware sets the IPv6 OUTPUT policy to DROP when IPv6 is disabled. Without this rule the router cannot send advertisements, and clients never get the prefix |
| `FORWARD br0 → guest` for .5/.6/.7 | Lets the k3s nodes open connections to devices on 192.168.101.0/24 |
| `FORWARD guest → br0` ESTABLISHED,RELATED | Lets only the replies back. Guest devices still cannot start a connection to the main LAN |
| Every rule is delete-then-insert | Repeated firewall restarts never stack duplicates |

### `kasa-guest-allow.sh` and `service-event-end`: the guest isolation

**This is the part that cost the most time.** ASUS guest isolation is not in `iptables`. It is in `ebtables -t broute`, as DROP rules for ICMP and TCP from `wl0.1` to 192.168.50.0/24. Those dropped the Kasa switches' replies even though the `iptables` rules allowed them. The script inserts six ACCEPT rules (ICMP and TCP, for .5, .6 and .7) above those DROPs.

Check on the router:

```sh
ebtables -t broute -L BROUTING | grep -n 192.168.50
```

Healthy output is six `-j ACCEPT` lines followed by the two `192.168.50.0/24 ... -j DROP` lines.

A Wi-Fi restart rebuilds the `ebtables` rules and removes ours. `service-event-end` re-runs the script ten seconds after any `wireless`, `net_and_phy` or `allnet` restart.

## The AiMesh node

The second XT8 ("Master Bedroom", hostname `ZenWiFi_XT8-0000`) was at 192.168.50.117 on 6 October. It runs the same firmware and accepts the main router's SSH login on the same port. It has no USB drive, no Entware and no Scribe; its log lives in memory, limits its own size and is lost at every reboot.

### Weekly reboot

The node reboots every Wednesday at 03:30 from a cron job. **Paste on: your Mac**, in the root of this repo.

```sh
sh network/xt8/node/xt8-node-setup.sh 192.168.50.117
```

The arguments are the node's address, then optionally the SSH user (default `homeuser`) and port (default `666`). `ssh` asks for the password once. The password is not an argument on purpose: arguments end up in shell history. For an unattended run, see the `SSHPASS` note at the top of the script. A different time: `REBOOT_AT="0 4 * * 0" sh network/xt8/node/xt8-node-setup.sh 192.168.50.117`.

What it does on the node:

| Step | Why |
| --- | --- |
| Refuses if the device's LAN address is 192.168.50.1 | So it can never put the job on the main router by mistake |
| `nvram set jffs2_scripts=1` | Without it the firmware ignores `/jffs/scripts` at boot. The node has no web UI to tick the box in |
| `nvram set reboot_schedule_enable=0` | Turns the firmware's own scheduler off so the node is not rebooted twice |
| Adds `cru a WeeklyReboot "30 3 * * 3 /sbin/reboot"` to `/jffs/scripts/services-start` | `cru` jobs are lost at reboot; this file runs at every boot and adds the job back. amtm's existing line in that file is kept |
| Runs the same `cru a` once | So the job exists now, without a reboot |

The node's `services-start` as it stood on 6 October is in [`network/xt8/node/services-start`](../network/xt8/node/services-start).

Check it, on the node:

```sh
cru l
nvram get jffs2_scripts
uptime
```

One line ending `#WeeklyReboot#`, then `1`. After a Wednesday, `uptime` must show under a week and `cru l` must still list the job; that second part proves `services-start` ran by itself at boot, which had not been observed when this was written.

Things learned doing it by hand:

- **The firmware's own scheduler never appears in `cru l`.** `nvram set reboot_schedule=00010000330` (seven day flags Sunday to Saturday, then HHMM) with `reboot_schedule_enable=1` is the GUI setting, and it is run by the watchdog, not cron. An empty `cru l` says nothing about it. The cron job was chosen because it can be seen.
- **`grep: /jffs/addons/custom_settings.txt: No such file or directory`** when running `services-start` by hand comes from amtm's line. Harmless.
- **AiMesh sync might overwrite node settings.** Not seen so far. If the job is gone after the main router restarts, run the script again and note it in [15](15-open-items.md).
- **Do not install Scribe on the node.** It would need a second USB drive and Entware, for a log that is mostly Wi-Fi association chatter the main router already records.

### Moving wireless devices between the two units

The script that kicks a wireless device off one unit so it reconnects to the other is **not in this repo yet**: it was written in a session I do not have. It belongs in `xt8-bootstrap.sh`. See [15](15-open-items.md).

## Things that will bite you again

- **The IPv6 page must stay on Disable.** Every other mode either needs an ISP prefix or makes the router advertise itself as DNS. The price is that System Log → IPv6 stays blank; use the SSH commands under "Seeing IPv6 on the router".
- **amtm or firmware actions can switch `br0` IPv6 off.** `service restart_dnsmasq` brings it back.
- **The Pi-hole address does not answer ping.** Test with `nslookup example.com 192.168.50.11`.
- **One page at a time in the web UI.** Several simultaneous requests froze it.
- **BusyBox has no working `ip -6 neigh flush ... nud failed`.** Clear failed neighbor entries with:

```sh
ip -6 neigh show nud failed | while read a b c d; do ip -6 neigh del "$a" dev "$c"; done
```

- **Kasa devices on the AiMesh node.** The `ebtables` rules are installed on the main router only. On 4 October all twelve Kasa devices answered Homebridge, including the ones the client list shows as connected through the node, so this works today. If one stops answering after it roams, look here first.

## Removing dnscrypt-proxy (done 1 October, kept for reference)

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

Check it is still gone:

```sh
grep -rn -i dnscrypt /jffs/scripts /jffs/configs
cat /tmp/resolv.dnsmasq
```

The only matches allowed are three lines inside `/jffs/scripts/firewall` (that file is Skynet's). `resolv.dnsmasq` must contain only `server=9.9.9.9`.
