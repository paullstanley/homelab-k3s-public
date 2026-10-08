# Isolated IoT network

You end up with a second Wi-Fi network for smart plugs, bulbs and other devices you do not trust. They reach the internet but cannot open connections to your computers. Optionally, a second access point of another brand broadcasts the same network, and one home-automation server on the main LAN is allowed to reach in and control the devices.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | ASUS ZenWiFi XT8 on GNUton Asuswrt-Merlin 3004.388.10_2 (router); TP-Link Archer A7 v5 on OpenWrt 25.12.5 with a `swconfig` switch (extra access point) |
| **Also works for** | Other ASUS routers on the 3004.388 firmware family should behave the same; check with `brctl show`. Not tested by the author. Newer ASUS firmware (3.0.0.6, "Guest Network Pro") is believed to differ; see the note in Part 1. Other OpenWrt devices with a `swconfig` switch need different port numbers |
| **Time** | 10 minutes for the guest network; 30 minutes for the extra access point; 30 minutes for controlled access |
| **You need first** | Part 1: an ASUS router. Part 2: [Archer A7 on OpenWrt](../hardware/tp-link-archer-a7-openwrt.md) already set up as a bridged access point. Part 3: SSH and JFFS custom scripts on the router, see [ASUS ZenWiFi XT8](../hardware/asus-zenwifi-xt8.md) |

The three parts build on each other, but each is useful alone. Stop after Part 1 if all you want is an isolated network.

## How it works

**Part 1: the guest network.** An ASUS guest network with "Access Intranet" off is more than a second SSID. The router creates a separate bridge (`br1`) with its own subnet (`192.168.101.0/24`), its own DHCP range, and rules that stop guest devices from reaching the main LAN (`br0`, `192.168.50.0/24`).

**Part 2: a second access point.** On Merlin 3004.388 the router also sends the guest network out of **every LAN port** as tagged VLAN 501. A VLAN tag is a number added to each Ethernet frame so that two networks can share one cable without mixing. Ordinary devices ignore tagged frames. An access point that understands VLANs can pick VLAN 501 off its uplink cable and connect it to a second SSID. That access point does no routing, DHCP or firewalling for the IoT network: the router remains the gateway and DHCP server, and address reservations made on the router keep working.

**Part 3: controlled access.** Isolation has two layers on ASUS firmware, and you have to open both:

| Layer | Tool | What it does by default |
| --- | --- | --- |
| Routing between the two subnets | `iptables`, FORWARD chain | No forwarding between `br0` and `br1` |
| Frames arriving from the guest Wi-Fi | `ebtables`, table `broute`, chain `BROUTING` | DROP rules for ICMP and TCP from the guest Wi-Fi interface to `192.168.50.0/24` |

`ebtables` filters at the Ethernet-frame level, before `iptables` ever sees the packet. So `iptables` rules alone look right and still do not work: the request reaches the IoT device, and the device's reply is caught by the `ebtables` rule on its way back.

## Before you start

- Choose the SSID and password for the IoT network. The examples use `Home-IoT` and `<GUEST_WIFI_PASSWORD>`.
- IoT devices are almost all 2.4 GHz only. Use a 2.4 GHz guest slot.
- For Part 2, find out which switch port of the access point is cabled towards the router. See [The switch page and the uplink port](../hardware/tp-link-archer-a7-openwrt.md#the-switch-page-and-the-uplink-port).
- For Part 2, every switch between the router and the access point must pass tagged frames. Unmanaged switches usually do, but it is not guaranteed; managed switches must have VLAN 501 allowed (tagged) on both ports.
- For Part 3, list the main-LAN addresses that are allowed to reach in. The example is the three cluster nodes that may run Homebridge: `192.168.50.5`, `.6`, `.7`.
- Take a backup of each device before changing it: [Backups and secrets](../operations/backups-and-secrets.md).

## Part 1. The guest network on the router

### Step 1. Create the guest network

In the router's web UI, open **Guest Network** and enable the **first 2.4 GHz slot**.

| Setting | Value |
| --- | --- |
| Network name (SSID) | `Home-IoT` |
| Authentication | WPA2-Personal, key `<GUEST_WIFI_PASSWORD>` |
| Access Intranet | **Disabled** |

On the tested firmware this produces:

| Result | Value |
| --- | --- |
| Subnet | `192.168.101.0/24`, router at `192.168.101.1` |
| Bridge | `br1` |
| Members of `br1` | The guest Wi-Fi interface `wl0.1`, and `eth1.501` to `eth6.501` |

`wl0.1` means "first virtual network on the first radio". The `.501` members are the guest network leaving every LAN port as tagged VLAN 501.

### Step 2. Confirm what the firmware built

Log in to the router. Add `-p <SSH_PORT>` if you changed the SSH port from 22.

**Run on: your computer.**

```sh
ssh admin@192.168.50.1
```

**Run on: the router.**

```sh
ip -4 -o addr show | grep 192.168.101
brctl show
ifconfig br1
```

The first command must print a bridge with `192.168.101.1/24`. `brctl show` lists each bridge and its member interfaces. `ifconfig br1` shows the bridge's address and whether it is up.

| What you see | Meaning | What to do |
| --- | --- | --- |
| `br1` with `192.168.101.1`, members `wl0.1` and `eth1.501` ... `eth6.501` | The layout this page describes. The guest network leaves every LAN port as VLAN 501 | Continue. Part 2 works as written |
| `br1` with `wl0.1` only, no `ethN.501` members | The guest network exists on Wi-Fi only; it is not sent down the cables | Part 1 and Part 3 work. Part 2 cannot work on this firmware |
| A guest bridge with `.`*NNN* members where *NNN* is not 501 | Your firmware uses another VLAN ID | Use that number wherever this page says 501 (`IOT_VLAN=NNN` for the script) |
| The guest Wi-Fi interface has another name (for example `wl1.1`) | A different guest slot or radio order | Use that name wherever this page says `wl0.1` (`GUEST_WL` for the router scripts) |
| Nothing with `192.168.101` | Access Intranet is still on (the guest SSID is then just bridged into `br0`), or the firmware uses another subnet | Re-check Step 1; look at every bridge in `brctl show` and `ip -4 -o addr show` |

> **Not verified:** VLAN 501, subnet `192.168.101.0/24` and bridge `br1` were confirmed on GNUton Asuswrt-Merlin 3004.388.10_2, where `brctl show` listed `eth1.501` to `eth6.501` and `wl0.1` under `br1`. Newer ASUS firmware families (3.0.0.6, with "Guest Network Pro" or a VLAN page) are believed to use different VLAN IDs and subnets. The author has not tested them. Always read your own values with `brctl show` before relying on any number on this page.

## Part 2. Extending the network to an OpenWrt access point

The access point broadcasts `Home-IoT` on 2.4 GHz as a second SSID, so IoT devices near it have a closer access point.

Do it either in LuCI (Steps 3 to 7) or with the script (Step 8). Both produce the same configuration.

> **Not verified:** The LuCI steps were carried out on the tested device, and the SSID was confirmed broadcasting. The script was syntax-checked only and had not been run on a real device when this was written. A client receiving a `192.168.101.x` address through the access point was not confirmed either; do the phone test in [Check it](#check-it).

Switch port numbers on the Archer A7 v5, as shown on **Network → Switch**:

| Column | CPU (eth0) | WAN | LAN 1 | LAN 2 | LAN 3 | LAN 4 |
| --- | --- | --- | --- | --- | --- | --- |
| Switch port number | 0 | 1 | 2 | 3 | 4 | 5 |

### Step 3. LuCI: add VLAN 501 on the switch

Open `http://192.168.50.3` → **Network → Switch**.

1. Click **Add VLAN**. A new row appears.
2. In the first text box of the new row (the VLAN ID) enter `501`.
3. In that row set **CPU (eth0)** to **tagged**.
4. Set the **uplink port** (the one cabled towards the router) to **tagged**.
5. Set every other port in that row to **off**.
6. Leave the existing VLAN 1 and VLAN 2 rows untouched. The uplink port stays an untagged member of VLAN 1, which is how the main LAN keeps working over the same cable.
7. Click **Save** (not Save & Apply yet).

> **Pitfall:** The **Port status** row can read "no link" on every port while the page shows REFRESHING. That is a display artefact. Do not use it to decide which port is the uplink; trace the cable.

### Step 4. LuCI: add the bridge device

**Network → Interfaces → Devices** tab → **Add device configuration**.

| Field | Value |
| --- | --- |
| Device type | Bridge device |
| Device name | `br-iot` |
| Bridge ports | `eth0.501` (type it in if it is not offered yet) |

Click **Save**.

### Step 5. LuCI: add the interface

**Network → Interfaces** → **Add new interface**.

| Field | Value |
| --- | --- |
| Name | `iot` |
| Protocol | **Unmanaged** |
| Device | `br-iot` |

No address, no DHCP server, no firewall zone. Click **Save**.

> **Why Unmanaged:** The access point gets no address on the IoT network at all. IoT devices therefore cannot reach its admin page or its SSH port, and it cannot become a second DHCP server by accident.

### Step 6. LuCI: add the SSID

**Network → Wireless**. Find the 2.4 GHz radio (`radio1` on the Archer A7 v5; check the band shown beside it) and click **Add**.

| Tab | Field | Value | Why |
| --- | --- | --- | --- |
| General Setup | Mode | Access Point | |
| General Setup | ESSID | `Home-IoT` | Exactly the router's guest name, so devices roam with no reconfiguration |
| General Setup | Network | `iot` **only** | Untick `lan`. Ticking both would bridge the two networks together |
| Wireless Security | Encryption | WPA2-PSK (CCMP) | Not the WPA2/WPA3 mixed mode: cheap IoT radios handle plain WPA2 best |
| Wireless Security | Key | `<GUEST_WIFI_PASSWORD>` | The same password as the router's guest network |
| Wireless Security | 802.11w Management Frame Protection | Disabled | Many IoT devices do not support it and fail to join |
| Advanced Settings | Isolate Clients | Ticked | IoT devices on this access point cannot talk to each other |

Click **Save**.

### Step 7. LuCI: apply

Click **Save & Apply** once, for all four pages together. Wi-Fi drops for a few seconds.

LuCI then checks that it can still reach the device. **If it cannot within 90 seconds, it rolls the whole change back automatically.** That is your protection against a wrong port choice in Step 3. If it rolls back, re-read which port is the uplink.

### Step 8. The script alternative

[`files/archer-a7/a7-iot-ssid.sh`](../../files/archer-a7/a7-iot-ssid.sh) makes the same changes. It takes its inputs as environment variables:

| Variable | Required | Default | Meaning |
| --- | --- | --- | --- |
| `IOT_KEY` | yes | | The guest network's Wi-Fi password |
| `UPLINK_PORT` | yes | | Switch port number cabled towards the router: WAN = 1, LAN1 = 2, LAN2 = 3, LAN3 = 4, LAN4 = 5 |
| `IOT_SSID` | no | `Home-IoT` | Must match the router's guest network name exactly |
| `IOT_VLAN` | no | `501` | The number after the dot in the router's `brctl show` output |
| `RADIO` | no | `radio1` | The 2.4 GHz radio. The script refuses to run if this radio's band is not `2g` |

**Run on: your computer**, from the root of this repo. The example is for an uplink on LAN port 1 (`UPLINK_PORT=2`).

```sh
scp -O files/archer-a7/a7-iot-ssid.sh root@192.168.50.3:/tmp/
ssh root@192.168.50.3 'IOT_KEY="<GUEST_WIFI_PASSWORD>" UPLINK_PORT=2 sh /tmp/a7-iot-ssid.sh'
```

> **Pitfall:** `UPLINK_PORT` depends on how the access point's switch is laid out. After a plain `a7-ap-setup.sh` build the uplink is a LAN port (2 to 5). `UPLINK_PORT=1` (the WAN port) is only right if the WAN port was merged into the LAN VLAN on the Switch page, which is how the tested device was set up. Both layouts are explained on [Archer A7 on OpenWrt](../hardware/tp-link-archer-a7-openwrt.md#the-switch-page-and-the-uplink-port). A wrong value does not break the main LAN; the IoT SSID just hands out no addresses.

What the script does, in order:

| Action | Detail |
| --- | --- |
| Checks its inputs | Stops if `IOT_KEY` or `UPLINK_PORT` is missing, if the port is not 1 to 5, or if `RADIO` is not 2.4 GHz |
| Backs up | `sysupgrade -b /tmp/a7-before-iot-<timestamp>.tar.gz`. In RAM: lost at reboot |
| Removes an earlier attempt | Any `switch_vlan` with VLAN ID 501, any device named `br-iot`, the `iot` interface, any SSID on network `iot`. So it is safe to run again, and safe to run over the LuCI steps |
| Adds the VLAN | `switch_vlan` on `switch0`, `vlan` = slot 3 of the switch table by default (`VLAN_SLOT`), `vid='501'`, `ports='0t <UPLINK_PORT>t'`: tagged on the CPU and the uplink only |
| Adds the bridge | Device `br-iot`, type `bridge`, port `eth0.501` |
| Adds the interface | `network.iot`, `proto='none'` (LuCI's "Unmanaged"), device `br-iot` |
| Adds the SSID | `wireless.iot_radio1`: `mode='ap'`, `network='iot'`, `ssid`, `encryption='psk2+ccmp'`, `key`, `ieee80211w='0'`, `isolate='1'` |
| Applies | `uci commit`, `/etc/init.d/network restart`, waits 15 seconds |
| Prints checks | Bridge members (expect `eth0.501` and a `phy1-ap` interface), addresses on `br-iot` (expect none), the SSID from `iwinfo` |

> **Pitfall:** The script uses slot 3 of the switch's VLAN table unless told otherwise. A stock Archer A7 uses slots 1 and 2. If you have already created other VLANs by hand, check `uci show network | grep switch_vlan` first and pass a free slot, for example `VLAN_SLOT=4`, in front of the command, or do the change in LuCI instead.

Unlike LuCI, the script has no automatic rollback.

### Step 9. Take a backup of the access point

**Run on: your computer**, from the root of this repo.

```sh
sh files/archer-a7/a7-backup.sh
```

All six checks should pass, including "wireless has an SSID on network iot" and "network has the IoT bridge br-iot". Details: [Back up the settings](../hardware/tp-link-archer-a7-openwrt.md#back-up-the-settings).

### What isolates what

| Boundary | Enforced by |
| --- | --- |
| IoT devices from the main LAN | VLAN 501 on the wire, plus the router's guest rules (Access Intranet off) |
| IoT devices from each other on the extra access point | Isolate Clients |
| IoT devices from the extra access point's own admin page | The `iot` interface being Unmanaged (no address) |

### Roaming

The extra access point is not part of the router's mesh. IoT devices still move between the router's `Home-IoT` and the access point's by themselves, **because the name and the password match**. To the device it is one network with two transmitters. Each move is a normal reconnect, which IoT devices tolerate.

## Part 3. Controlled access from the main LAN into the IoT network

Some home-automation software talks to devices directly over the local network rather than through a cloud service. If that software runs on the main LAN and the devices are on the IoT network, the isolation blocks it. This part opens a narrow, one-way path: named main-LAN hosts may open connections to IoT devices; IoT devices still cannot open connections to anything on the main LAN.

Devices that are driven through their maker's cloud need none of this.

### Step 10. Give each IoT device a fixed address

Software that reaches a device by address loses it when the address changes. On the router: **LAN → DHCP Server → Manually Assigned IP**, add each device's MAC address with its `192.168.101.x` address. With the YazDHCP add-on it is the same list. Do this for every device the server controls directly.

> **Pitfall:** Devices left on automatic addresses work until a lease changes, and then fail one at a time with connection timeouts that look like Wi-Fi problems.

### Step 11. Install the three router rules

| # | Rule | Effect |
| --- | --- | --- |
| 1 | `iptables` FORWARD: from `br0`, source the allowed hosts, to the guest bridge, destination `192.168.101.0/24`, ACCEPT | The server may open connections to IoT devices |
| 2 | `iptables` FORWARD: from the guest bridge to `br0`, destination the allowed hosts, state ESTABLISHED or RELATED, ACCEPT | Only replies come back. An IoT device cannot start a connection |
| 3 | `ebtables -t broute` BROUTING: IPv4 arriving on `wl0.1`, destination each allowed host, protocol ICMP and TCP, ACCEPT, inserted **ahead of** ASUS's DROP rules | The replies survive the guest-isolation layer |

**Rule 3 is the one that is easy to miss.** ASUS guest isolation is not in `iptables`. It is in `ebtables -t broute`, as DROP rules for ICMP and TCP from the guest Wi-Fi interface to `192.168.50.0/24`. Those rules discarded the IoT devices' replies even though rules 1 and 2 allowed them. With only rules 1 and 2, a ping from the server to an IoT device simply times out.

The rules live in three files under `/jffs/scripts/`. Reference copies: [`files/xt8/jffs-scripts/`](../../files/xt8/jffs-scripts/).

| File | Runs when | Does |
| --- | --- | --- |
| [`homenet.conf`](../../files/xt8/jffs-scripts/homenet.conf) | read by the others | The values: `GUEST_PREFIX="192.168.101."`, `GUEST_NET="192.168.101.0/24"`, `GUEST_WL="wl0.1"`, `HB_HOSTS="192.168.50.5,192.168.50.6,192.168.50.7"` |
| [`firewall-start`](../../files/xt8/jffs-scripts/firewall-start) | after every firewall restart | Rules 1 and 2, then calls the next file |
| [`kasa-guest-allow.sh`](../../files/xt8/jffs-scripts/kasa-guest-allow.sh) | called by `firewall-start` and `service-event-end` | Rule 3 |
| [`service-event-end`](../../files/xt8/jffs-scripts/service-event-end) | after any router service event | Puts rule 3 back after a Wi-Fi restart |

**Option A: the bootstrap script.** [`files/xt8/xt8-bootstrap.sh`](../../files/xt8/xt8-bootstrap.sh) installs all of them. Set `GUEST_PREFIX`, `GUEST_NET`, `GUEST_WL` and `HB_HOSTS` at the top to your values and follow [ASUS ZenWiFi XT8](../hardware/asus-zenwifi-xt8.md).

> **Not verified:** The bootstrap script was syntax-checked and run against stand-in commands, not on a real router. The rules themselves were entered by hand on a real router and confirmed working: twelve IoT devices answered the server through them.

**Option B: by hand.** The hook files are shared with other add-ons (Skynet keeps a line in `firewall-start`). Add to an existing file; do not overwrite it.

Create `/jffs/scripts/kasa-guest-allow.sh`. It inserts one ACCEPT rule per allowed host and protocol, deleting any old copy first so that repeated runs never stack duplicates.

**Run on: the router**, in an editor such as `vi /jffs/scripts/kasa-guest-allow.sh`.

```sh
#!/bin/sh
# ASUS guest isolation lives in "ebtables -t broute": it drops icmp/tcp from the
# guest Wi-Fi to 192.168.50.0/24, which kills the REPLIES from IoT devices.
# These ACCEPT rules sit above those DROPs, for the allowed hosts only.
GUEST_WL="wl0.1"
HB_HOSTS="192.168.50.5,192.168.50.6,192.168.50.7"
for IP in $(echo "$HB_HOSTS" | tr ',' ' '); do
  for PR in icmp tcp; do
    ebtables -t broute -D BROUTING -p IPv4 -i "$GUEST_WL" --ip-dst "$IP" --ip-proto "$PR" -j ACCEPT 2>/dev/null
    ebtables -t broute -I BROUTING -p IPv4 -i "$GUEST_WL" --ip-dst "$IP" --ip-proto "$PR" -j ACCEPT
  done
done
```

Add this to `/jffs/scripts/firewall-start` (first line `#!/bin/sh` if the file is new). It finds the guest bridge by its address rather than assuming `br1`, and logs a message instead of failing if the guest network does not exist.

```sh
GUEST_PREFIX="192.168.101."
GUEST_NET="192.168.101.0/24"
HB_HOSTS="192.168.50.5,192.168.50.6,192.168.50.7"
GBR=$(ip -4 -o addr show | awk -v p="$GUEST_PREFIX" 'index($4,p)==1 {print $2; exit}')
if [ -n "$GBR" ]; then
  iptables -D FORWARD -i br0 -s $HB_HOSTS -o $GBR -d $GUEST_NET -j ACCEPT 2>/dev/null
  iptables -I FORWARD -i br0 -s $HB_HOSTS -o $GBR -d $GUEST_NET -j ACCEPT
  iptables -D FORWARD -i $GBR -o br0 -d $HB_HOSTS -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
  iptables -I FORWARD -i $GBR -o br0 -d $HB_HOSTS -m state --state ESTABLISHED,RELATED -j ACCEPT
else
  logger -t firewall-start "guest bridge (${GUEST_PREFIX}x) not found; IoT access rules skipped"
fi
sh /jffs/scripts/kasa-guest-allow.sh
```

Add this to `/jffs/scripts/service-event-end` (first line `#!/bin/sh` if the file is new). The firmware calls this script with the event type as `$1` and the service name as `$2`.

```sh
case "$2" in wireless|net_and_phy|allnet) sleep 10; sh /jffs/scripts/kasa-guest-allow.sh ;; esac
```

Make them executable and apply.

**Run on: the router.**

```sh
chmod a+rx /jffs/scripts/kasa-guest-allow.sh /jffs/scripts/firewall-start /jffs/scripts/service-event-end
service restart_firewall
```

> **Pitfall:** A Wi-Fi restart on the router rebuilds the `ebtables` rules and **removes rule 3**. Changing almost any wireless setting causes one. `service-event-end` re-runs `kasa-guest-allow.sh` ten seconds after any `wireless`, `net_and_phy` or `allnet` service event. Without that hook, access works until the next Wi-Fi change and then stops with no error anywhere.

> **Not verified:** The ebtables manual says that in the `broute` table DROP means "route this frame instead of bridging it" and ACCEPT means "bridge it as normal". So ASUS's DROP rules probably do not discard the reply outright; they take it off the bridge, after which the `iptables` rule for the guest bridge no longer matches it. The author did not trace this. The observed behaviour is what matters: replies vanish until the ACCEPT rules are in place above the DROP rules.

### Step 12. If the server also has a host firewall

A firewall on the server itself must allow traffic from `192.168.101.0/24` in, or the replies are refused at the last hop. See [Node firewall](../kubernetes/node-firewall.md).

### Step 13. Point the software at the devices by address

Device discovery is a broadcast, and broadcasts do not cross from one network to the other. Every device has to be listed by address in the controlling software. For Homebridge and TP-Link Kasa devices, the plugin configuration, the account settings and a symptom table are on [Homebridge: Kasa across networks](../apps/homebridge-kasa-across-networks.md).

## If you also have an AiMesh node

The `ebtables` rules are installed on the main router only. On the tested network, IoT devices that the client list showed as connected through the AiMesh node still answered the server, so this works as it stands.

> **Not verified:** Why it works through the node was not investigated, and it may not hold on other firmware. If one device stops answering after it moves rooms (that is, after it roams to the node), look here first: check the rules on the main router, then try the device close to the main router.

Nothing in this page is installed on the node.

## Check it

### Part 1

- A phone joined to `Home-IoT` near the router gets a `192.168.101.x` address with gateway `192.168.101.1` and reaches the internet.
- From that phone, `http://192.168.50.1` and any other main-LAN address fail to open.

> **Not verified:** The isolation test from a guest device is the intended acceptance test; the author has no record of running it.

### Part 2

In LuCI on the access point:

- **Network → Wireless** lists `Home-IoT` under the 2.4 GHz radio with a BSSID (the SSID's own MAC address, for example `02:00:00:00:00:04`) and a **Disable** button. That means it is broadcasting.
- **Grey signal bars and `---` next to it mean no client is connected, not that it is off.** That box shows the connected clients' signal, and with none there is nothing to show.
- **Network → Interfaces** shows `iot` with Protocol: Unmanaged, on `br-iot`, carrier present (shown as up, with an uptime), and **no IPv4 address**. That is the correct, healthy state. On the tested device it stayed that way for many hours.

Over SSH:

**Run on: the access point.**

```sh
ls /sys/class/net/br-iot/brif
ip -4 addr show br-iot | grep inet
iwinfo | grep -B1 -A2 "Home-IoT"
```

Expect `eth0.501` and a `phy1-ap` interface; then nothing; then the SSID block.

The real test: a phone joined to `Home-IoT` **near the access point** (far from the router, or with the router's guest network briefly disabled) gets `192.168.101.x` with gateway `192.168.101.1`, reaches the internet, and **cannot** open `http://192.168.50.3`.

### Part 3

**Run on: the router.**

```sh
ebtables -t broute -L BROUTING | grep -n 192.168.50
iptables -S FORWARD | grep 192.168.101
```

Healthy output of the first command is the ACCEPT lines (two per allowed host, so six for three hosts) **followed by** ASUS's two `192.168.50.0/24 ... -j DROP` lines. Order matters: an ACCEPT below the DROPs does nothing. The second command prints the two FORWARD rules.

**Run on: server-1** (or whichever host you allowed), with one of your IoT devices' addresses.

```sh
ping -c 3 192.168.101.201
nc -vz -w 3 192.168.101.201 9999
```

Expect replies, then "succeeded". Port 9999 is what TP-Link Kasa devices listen on; use the port your devices use.

Then restart Wi-Fi on the router (change and re-apply any wireless setting, or `service restart_wireless`), wait 20 seconds, and run the `ebtables` check again. The ACCEPT lines must be back.

## Pitfalls

| What happens | Why | Avoid or recover |
| --- | --- | --- |
| `iptables` rules are in place, ping from the server still times out | The `ebtables` broute DROP rules catch the replies | Rule 3 |
| Access worked, then stopped after a Wi-Fi change | The Wi-Fi restart wiped the `ebtables` rules | `sh /jffs/scripts/kasa-guest-allow.sh`; make sure `/jffs/scripts/service-event-end` exists and is executable |
| The ACCEPT rules are present but below the DROP rules | They were appended (`-A`) instead of inserted (`-I`) | Use `-I` |
| The rules never match | The guest Wi-Fi interface is not `wl0.1` on your router | Read it from `brctl show`; change `GUEST_WL` |
| A phone joins the extra access point's `Home-IoT` but gets no address | The tagged VLAN is not arriving | See Troubleshooting |
| The IoT SSID "looks off": grey bars and `---` | No clients connected | Nothing. A BSSID and a Disable button mean it is on |
| IoT devices will not join the extra access point | WPA2/WPA3 mixed mode, or 802.11w on | WPA2-PSK (CCMP), 802.11w disabled |
| IoT and main LAN are bridged together | The SSID was attached to both `lan` and `iot` | `iot` only |
| IoT devices can open the access point's admin page | The `iot` interface was given an address | Protocol Unmanaged |
| LuCI rolls the change back after 90 seconds | The device became unreachable, usually a wrong switch row | Leave VLAN 1 and 2 alone; only add the 501 row |
| A device loses its address reservation "randomly" | It was never reserved | Step 10 |
| Controlled access breaks when the server moves to another host | Only the listed addresses are allowed | List every host that may run it (`HB_HOSTS`) |
| The guest network vanishes from the extra access point after a firmware change on the router | The firmware's VLAN ID or behaviour changed | `brctl show` on the router; adjust `IOT_VLAN` |
| The router UI freezes during setup | Several pages loading at once | One page at a time |

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| No bridge with `192.168.101.1` on the router | The guest network does not exist yet, Access Intranet is on, or the firmware uses another subnet | Part 1 |
| Device joins the extra access point's `Home-IoT` but gets no address | Tagged VLAN 501 is not reaching the access point | In order: `brctl show` on the router for the `.501` members under `br1`; the access point's uplink port in the VLAN 501 row; any switch in between |
| Same, and the router shows no `.501` members | This firmware does not put the guest network on the LAN ports | Part 2 cannot work; keep the guest network on the router's own radios |
| `ERROR: radio1 is not the 2.4 GHz radio` from the script | Different radio order on your device | Find the 2.4 GHz radio with `uci show wireless \| grep band`; pass `RADIO=radio0` |
| `ERROR: set UPLINK_PORT` or `set IOT_KEY` | A required variable is missing | Step 8 |
| `br-iot` has no `phy1-ap` member | The SSID failed to start | `logread \| grep hostapd`; check the key is 8 to 63 characters |
| Ping from the server fails for **every** IoT device | The router rules are gone | `sh /jffs/scripts/kasa-guest-allow.sh` on the router, then the Part 3 checks |
| Ping fails for **one** device | That device is off the network or changed address | The maker's app; the router's client list; fix the reservation |
| "Timeout ... connecting to the device: 192.168.101.x:9999" in the server's log, ping fails | Rule 3 missing or wiped | Same as two rows up |
| Ping works from the server, the application still times out, and a host firewall was recently enabled | The host firewall refuses the replies | Step 12 |
| Stopped right after a router Wi-Fi change | The hook did not restore the `ebtables` rules | Check `/jffs/scripts/service-event-end` exists, is executable, and JFFS custom scripts are enabled |
| The `ebtables` rule count is wrong after running the script | `GUEST_WL` does not match the real interface | Compare with `brctl show` |
| `firewall-start` logged "guest bridge ... not found" | The guest network was off when the firewall started | Enable it, then `service restart_firewall` |
| One device stopped after moving rooms | It may have roamed to the AiMesh node | See the AiMesh section |
| A guest device can reach the main LAN | Access Intranet is on, or a FORWARD rule is too broad | Re-check Step 1; rule 2 must have `--state ESTABLISHED,RELATED` |

More symptoms across the whole build: [Troubleshooting](../operations/troubleshooting.md).

## Undo

**Part 3.** Remove the lines you added from `firewall-start` and `service-event-end`, delete `kasa-guest-allow.sh`, then `service restart_firewall` and restart Wi-Fi so the firmware rebuilds its own `ebtables` rules. With the bootstrap script: `sh /jffs/xt8-bootstrap.sh uninstall` (this also removes its other blocks, including local IPv6). To remove the rules without restarting anything, repeat each insert command with `-D` in place of `-I`.

**Part 2.** In LuCI delete, in this order: the `Home-IoT` SSID (**Network → Wireless → Remove**), the `iot` interface, the `br-iot` device, the VLAN 501 row on the Switch page. Then **Save & Apply**. Or restore the `/tmp/a7-before-iot-*.tar.gz` backup the script made, if the access point has not rebooted since, or your last good backup.

**Part 1.** Disable the guest network on the router's **Guest Network** page. Devices on it lose their connection.

## References

- [ASUS FAQ: How to configure the guest network to deny wireless devices access to the internal network](https://www.asus.com/support/faq/1009857): what the Access Intranet setting does, on both older and newer ASUS firmware.
- [ASUS FAQ: How to set up Guest Network on ASUS Router](https://www.asus.com/us/support/FAQ/1042732): creating a guest network in the web UI and the app, and its documented limits.
- [Asuswrt-Merlin wiki: User scripts](https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts): when `firewall-start` and `service-event-end` run and what arguments they receive.
- [Asuswrt-Merlin wiki: Iptables tips](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Iptables-tips): examples of adding `iptables` rules from the firewall scripts.
- [ebtables-legacy(8) manual page](https://manpages.debian.org/bookworm/ebtables/ebtables-legacy.8.en.html): the `broute` table and `BROUTING` chain, and the special meaning of DROP and ACCEPT there.
- [gnuton/asuswrt-merlin.ng](https://github.com/gnuton/asuswrt-merlin.ng): the Asuswrt-Merlin fork for the ZenWiFi XT8 that this page was done on.
- [openwrt/openwrt on GitHub](https://github.com/openwrt/openwrt): the OpenWrt source; the board file `target/linux/ath79/generic/base-files/etc/board.d/02_network` defines the Archer A7 v5 switch port numbers used for `UPLINK_PORT`.
- [OpenWrt Firmware Selector](https://firmware-selector.openwrt.org/): finds the firmware and device page for the access point.
