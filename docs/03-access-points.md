# 03. Access points

Two extra access points extend the XT8 mesh. Neither routes, hands out addresses, or runs a firewall. Both use the XT8 as gateway and Pi-hole as DNS.

## Archer A7 v5, OpenWrt 25.12.5, 192.168.50.3 (`livingRoomAP`)

### With a backup (five minutes)

In LuCI: **System → Backup / Flash Firmware → Restore backup**, choose `a7-backup.tar.gz`. That restores everything including Wi-Fi. Done.

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

**Step 5.** Configure Wi-Fi in LuCI at `http://192.168.50.3` → **Network → Wireless**. The script does not do Wi-Fi.

| Setting | Value |
| --- | --- |
| Both radios | Enabled, attached to network `lan` |
| Security | WPA2/WPA3-Personal, same key as the XT8 if you want roaming on one name |
| 2.4 GHz channel | 6 or 11 (the XT8 uses 1) |
| 5 GHz channel | 149 or 157 (the XT8 uses 36) |
| `multicast_to_unicast_all` | `1` on both radios |
| WPS | Off |
| 802.11k/v and `static-neighbor-reports` | Keep; they teach the A7 the ASUS and TP-Link radios for roaming. These only come back from the backup |

### What the script sets

| Setting | Value | Why |
| --- | --- | --- |
| `network.lan` IPv4 | static 192.168.50.3/24, gateway 192.168.50.1, DNS 192.168.50.11 | Management address |
| `network.globals.ula_prefix` | deleted | OpenWrt's own prefix would give clients a second IPv6 range |
| `network.@device[N].ipv6` for `br-lan` | `1` | **Required.** Without the device-level setting the bridge stays IPv6-off |
| `network.lan.ip6addr` | `fd00:1234:5678:50::3/64` | Static management address, no IPv6 gateway |
| `dhcp.lan.ignore`, `ra`, `dhcpv6`, `ndp` | `1`, `disabled` ×3 | The A7 never hands out addresses or advertisements |
| `odhcpd`, `dnsmasq`, `firewall` | disabled and stopped | A bridged AP needs none of them |
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

The first A7 guide (September) moved the WAN port into the LAN VLAN on **Network → Switch** and used the WAN port as the uplink, with the firewall's `wan` zone deleted by hand. The current method is simpler: leave the switch alone, cable a LAN port, and let the script disable DHCP, advertisements and the firewall. That guide also described OpenWrt 25.12.1; the A7 now runs 25.12.5. Use this page.

A factory reset or a firmware flash without "keep settings" puts the A7 back into routing mode at 192.168.1.1. Run the script again.

## Archer AX21 v5, stock firmware, 192.168.50.4 (`officeAP`)

Nothing to script and nothing to restore.

| Setting | Value |
| --- | --- |
| Operation Mode | Access Point |
| LAN IP | Static 192.168.50.4, gateway 192.168.50.1, DNS 192.168.50.11 |
| Wi-Fi | Names and keys from the password manager |

In Access Point mode the stock firmware has no IPv6 settings and no SSH. The AX21 has no IPv6 address of its own and a ping to it over IPv6 times out. That is expected. Its Wi-Fi clients still get IPv6 from the XT8 because it bridges.

The XT8 client list shows `officeAP` as "Automatic IP" at .4. If it ever comes up on another address, either set the static address above or reserve .4 on the XT8 for MAC `02:00:00:00:00:01`.

The AX21's DNS and EasyMesh settings were not re-checked in September or October.

## Roaming between the three kinds of access point

The A7 and AX21 are not part of AiMesh. A phone moving between ASUS coverage and TP-Link coverage does a normal reconnect, not a seamless handoff. The `Home6g` band exists on the XT8 units only.
