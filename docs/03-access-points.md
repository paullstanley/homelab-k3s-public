# 03. Access points

Two extra access points extend the XT8 mesh. Neither routes, hands out addresses, or runs a firewall. Both use the XT8 as gateway and Pi-hole as DNS.

## Archer A7 v5, OpenWrt 25.12.5, 192.168.50.3 (`livingRoomAP`)

### With a backup (five minutes)

In LuCI: **System → Backup / Flash Firmware → Restore backup**, choose the newest `a7-backup-<date>.tar.gz` from `~/Documents/network-rebuild/a7/`. That restores everything: Wi-Fi, the MAC deny lists, the IoT network and the weekly reboot. Done.

On a freshly flashed A7 (192.168.1.1) the restore also brings back the 192.168.50.3 address, so the page stops answering after the reboot. Move the cable to the main network and open `http://192.168.50.3`.

### Without a backup

**Step 1.** Flash OpenWrt and connect a computer straight to one of the A7's LAN ports. A fresh A7 is at 192.168.1.1.

**Step 2.** In LuCI (`http://192.168.1.1`): **System → Administration → Router Password**. Set one. A fresh unit has none.

**Step 3. Paste on: your Mac**, in the root of this repo.

```sh
scp -O network/archer-a7/a7-ap-setup.sh root@192.168.1.1:/tmp/
ssh root@192.168.1.1 'sh /tmp/a7-ap-setup.sh'
```

Your SSH session drops when the address changes to 192.168.50.3. That is expected.

**Step 4.** Cable one of the A7's **LAN** ports (not the WAN port) to the main network.

**Step 5.** Configure the main Wi-Fi in LuCI at `http://192.168.50.3` → **Network → Wireless**. The script does not do Wi-Fi.

| Setting | Value |
| --- | --- |
| Both radios | Enabled, attached to network `lan`. SSIDs `Home` (2.4 GHz) and `Home5g` (5 GHz) |
| Security | WPA2/WPA3-Personal (`sae-mixed`), same key as the XT8 if you want roaming on one name |
| 2.4 GHz channel | 11, 20 MHz (live on 3 October). The XT8 uses 1 |
| 5 GHz channel | 149, 80 MHz in the config on 3 October; LuCI showed 153 as the control channel. The XT8 uses 36 |
| MAC filter | Both SSIDs have a deny list (9 addresses on 5 GHz, 11 on 2.4 GHz). Only in the backup |
| `multicast_to_unicast_all` | `1` on both radios |
| WPS | Off |
| 802.11k/v and `static-neighbor-reports` | Keep; they teach the A7 the ASUS and TP-Link radios for roaming. These only come back from the backup |

**Step 6.** Add the IoT network: the next section. The weekly reboot is already set by the script in Step 3.

### The IoT network on the A7 (`Home-IoT`, added 3 October)

The A7 broadcasts the XT8's guest/IoT network on 2.4 GHz as a second SSID, so IoT devices near it have a closer access point. The A7 does no routing, DHCP or firewalling for it: the XT8 stays the gateway and DHCP server for 192.168.101.0/24, and the address reservations made there keep working.

How it reaches the A7: the XT8 sends the guest network out of every LAN port as tagged VLAN 501 ([02](02-router-xt8.md), "Guest / IoT network"). The A7 takes that VLAN off its uplink and bridges it to the new SSID. Any switch between the two must pass tagged frames.

**Paste on: your Mac**, in the root of this repo. Put the guest network's password and the A7 switch port that is cabled towards the XT8 into the second line.

```sh
scp -O network/archer-a7/a7-iot-ssid.sh root@192.168.50.3:/tmp/
ssh root@192.168.50.3 'IOT_KEY="<GUEST_WIFI_PASSWORD>" UPLINK_PORT=1 sh /tmp/a7-iot-ssid.sh'
```

`UPLINK_PORT`: WAN port = 1, LAN1 = 2, LAN2 = 3, LAN3 = 4, LAN4 = 5. **On the live A7 the uplink is the WAN port, so `UPLINK_PORT=1`.** Read from the Switch page on 8 October: VLAN 501 is tagged on CPU and WAN, off on LAN 1 to 4. That only works because the live A7 still has the WAN port in VLAN 1 (see "Where the older A7 guide is out of date"). After a rebuild with `a7-ap-setup.sh` alone the uplink is a LAN port, and `UPLINK_PORT` is that port's number instead.

The script has been syntax-checked only. On 3 October the same settings were entered by hand in LuCI, which is what the table describes.

| Where in LuCI | Setting | Value |
| --- | --- | --- |
| Network → Switch | New VLAN, ID | `501` |
| Network → Switch | CPU (eth0) and the uplink port (WAN) | tagged; LAN 1 to 4 off. VLAN 1 and 2 rows untouched |
| Network → Interfaces → Devices | New bridge device | `br-iot`, port `eth0.501` |
| Network → Interfaces | New interface | `iot`, protocol **Unmanaged**, device `br-iot`. No address, no DHCP, no firewall zone |
| Network → Wireless, `radio1` → Add | ESSID | `Home-IoT`, exactly the XT8 guest name so devices roam with no reconfiguration |
| | Network | `iot` only |
| | Encryption | WPA2-PSK (CCMP), same password as the XT8 guest network. Not the WPA2/WPA3 mixed mode: cheap IoT radios handle plain WPA2 best |
| | 802.11w Management Frame Protection | Disabled |
| | Advanced → Isolate Clients | Ticked |

| Boundary | Enforced by |
| --- | --- |
| IoT devices from the main LAN | VLAN 501 on the wire, plus the XT8's guest rules (Access Intranet off) |
| IoT devices from each other on the A7 | Isolate Clients |
| IoT devices from the A7's own admin page | The `iot` interface being Unmanaged |

Check it:

- **Network → Wireless** lists `Home-IoT` under `radio1` with a BSSID (`02:00:00:00:00:01`) and a **Disable** button.
- **Grey signal bars and `---` next to it mean no client is connected, not that it is off.** That box shows the clients' signal, and with none there is nothing to show.
- A phone joined to `Home-IoT` near the A7 gets 192.168.101.x with gateway 192.168.101.1, reaches the internet, and cannot open `http://192.168.50.3`. **This test was not reported back**; see [15](15-open-items.md).
- Phone connects but gets no address: the tagged VLAN is not arriving. Check `brctl show` on the XT8 for the `.501` members, the uplink port, and any switch in between.

On 8 October **Network → Interfaces** showed `iot` as Unmanaged on `br-iot`, carrier present, up for 17 hours, with no address, which is correct.

Take an A7 backup afterwards: `sh network/archer-a7/a7-backup.sh` ([13](13-backups-and-secrets.md)).

### Weekly reboot

`a7-ap-setup.sh` now sets this. To add it to a running A7 without re-running the script, use **System → Scheduled Tasks** in LuCI (or `crontab -e` over SSH), one line:

```
30 3 * * 3 sleep 70 && touch /etc/banner && reboot
```

Wednesday 03:30 local time; the A7's time zone is America/New_York. Over SSH, follow with `/etc/init.d/cron enable; /etc/init.d/cron restart`, and check with `crontab -l`.

The `sleep 70 && touch /etc/banner` part prevents a reboot loop. The A7 has no battery clock; at boot it takes its time from the newest file in `/etc` until NTP answers. Touching a file 70 seconds after 03:30 makes the restored time land after the scheduled minute.

The line was given on 6 October. Whether it was entered on the live A7 is not confirmed. **It does not go in System → Startup → Local Startup** (`/etc/rc.local`); that page was still at its default on 8 October, which is right. It goes in **System → Scheduled Tasks**. `a7-backup.sh` reports FAIL on its reboot check until the line exists.

### What the script sets

| Setting | Value | Why |
| --- | --- | --- |
| `network.lan` IPv4 | static 192.168.50.3/24, gateway 192.168.50.1, DNS 192.168.50.11 | Management address |
| `network.globals.ula_prefix` | deleted | OpenWrt's own prefix would give clients a second IPv6 range |
| `network.@device[N].ipv6` for `br-lan` | `1` | **Required.** Without the device-level setting the bridge stays IPv6-off |
| `network.lan.ip6addr` | `fd00:1234:5678:50::3/64` | Static management address, no IPv6 gateway |
| `dhcp.lan.ignore`, `ra`, `dhcpv6`, `ndp` | `1`, `disabled` ×3 | The A7 never hands out addresses or advertisements |
| `odhcpd`, `dnsmasq`, `firewall` | disabled and stopped | A bridged AP needs none of them |
| `/etc/crontabs/root` | `30 3 * * 3 sleep 70 && touch /etc/banner && reboot`, cron enabled | Weekly reboot, Wednesday 03:30. See "Weekly reboot" |
| `uneighbord` | removed | It only talks to other OpenWrt APs and logged an error every 30 s |
| Apply | `/etc/init.d/network restart` | **`network reload` was not enough** to bring IPv6 up on the bridge |

### Check it

**Paste on: the A7** (`ssh root@192.168.50.3`).

```sh
ip -6 addr show br-lan
ip -6 route | grep default
ping -6 -c3 fd00:1234:5678:50::1
nslookup openwrt.org fd00:1234:5678:50::11
```

Expect `fd00:1234:5678:50::3/64` listed exactly once, no default route, ping replies from the XT8, and a DNS answer. If the address appears twice:

```sh
uci -q delete network.lan.ip6addr; uci set network.lan.ip6addr='fd00:1234:5678:50::3/64'; uci commit network; /etc/init.d/network restart
```

### Where the older A7 guide is out of date

The first A7 guide (September) moved the WAN port into the LAN VLAN on **Network → Switch** and used the WAN port as the uplink, with the firewall's `wan` zone deleted by hand. The current method is simpler: leave the switch alone, cable a LAN port, and let the script disable DHCP, advertisements and the firewall. **The live A7 still has the September switch change**: on 3 October VLAN 1 held the WAN port and all four LAN ports untagged, so any port works as the uplink today. A rebuild from the script gives LAN ports only. Either is fine; just know which you have before choosing `UPLINK_PORT` for the IoT script. That guide also described OpenWrt 25.12.1; the A7 now runs 25.12.5. Use this page.

A factory reset or a firmware flash without "keep settings" puts the A7 back into routing mode at 192.168.1.1. Run the script again.

## Archer AX21 v5, stock firmware, 192.168.50.4 (`officeAP`)

Nothing to script and nothing to restore.

| Setting | Value |
| --- | --- |
| Operation Mode | Access Point |
| LAN IP | Static 192.168.50.4, gateway 192.168.50.1, DNS 192.168.50.11 |
| Wi-Fi | Names and keys from the password manager |

In Access Point mode the stock firmware has no IPv6 settings and no SSH. The AX21 has no IPv6 address of its own and a ping to it over IPv6 times out. That is expected. Its Wi-Fi clients still get IPv6 from the XT8 because it bridges.

The XT8 client list shows `officeAP` as "Automatic IP" at .4. If it ever comes up on another address, either set the static address above or reserve .4 on the XT8 for MAC `02:00:00:00:00:02`.

The AX21's DNS and EasyMesh settings were not re-checked in September or October.

## Roaming between the three kinds of access point

The A7 and AX21 are not part of AiMesh. IoT devices move between the XT8's `Home-IoT` and the A7's by themselves, because the name and password match. A phone moving between ASUS coverage and TP-Link coverage does a normal reconnect, not a seamless handoff. The `Home6g` band exists on the XT8 units only.
