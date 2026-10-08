# TP-Link Archer AX21 on stock firmware as an access point

You end up with an Archer AX21 that extends your Wi-Fi and nothing else: your main router stays the gateway, DHCP server and firewall. It needs no custom firmware, no script and no backup, because there are only a handful of settings.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | TP-Link Archer AX21 v5, stock TP-Link firmware, Operation Mode set to Access Point |
| **Also works for** | Other AX21 hardware versions and other TP-Link Archer models with an Access Point mode should be the same in outline. Not tested by the author |
| **Time** | 10 minutes |
| **You need first** | A main router that is the gateway and DHCP server for the LAN. Nothing else in this wiki is required |

## How it works

In Access Point mode the AX21 stops routing. Its Ethernet ports and its radios become one bridge, so a Wi-Fi client is, as far as the network is concerned, plugged straight into your LAN. The client's address, gateway and DNS server all come from the main router.

The AX21 itself keeps one IPv4 address, used only to reach its admin page.

## Before you start

Gather:

| Item | Example |
| --- | --- |
| The AP's address | `192.168.50.4`, outside the main router's DHCP pool |
| Gateway | `192.168.50.1` |
| DNS server | `192.168.50.11` (a Pi-hole in the example; otherwise your router's address) |
| Wi-Fi names and keys | The same as the main router if you want devices to use both on one name, with `<WIFI_PASSWORD>` |

## Steps

### Step 1. Switch to Access Point mode

Connect a computer to the AX21, open its admin page (`http://tplinkwifi.net` on an unconfigured unit) and log in. Change **Operation Mode** to **Access Point** and save. The device reboots. TP-Link's own walkthrough is [Archer - Configure Access Point Mode](https://community.tp-link.com/us/home/kb/detail/390).

### Step 2. Enter the settings

| Setting | Value |
| --- | --- |
| Operation Mode | Access Point |
| LAN IP | Static `192.168.50.4`, gateway `192.168.50.1`, DNS `192.168.50.11` |
| Wi-Fi | Your SSIDs and keys |

That is the whole configuration. There is nothing to script and nothing to restore.

### Step 3. Cable it to the main network

Connect the AX21 to your LAN by Ethernet and open `http://192.168.50.4`.

### Alternative to a static LAN IP: a DHCP reservation

If you leave the AX21's LAN address on automatic, it asks the main router for one, and the router's client list shows it as an automatic (DHCP) address. That works until the address changes. Either set the static address above, or reserve the address on the main router for the AX21's MAC address (on an ASUS router: **LAN → DHCP Server → Manually Assigned IP**, for example `192.168.50.4` for `02:00:00:00:00:05`). Do one of the two, so that the admin page is always where you expect it.

## If your LAN has IPv6

In Access Point mode the stock firmware has **no IPv6 settings** and **no SSH**.

- The AX21 has no IPv6 address of its own. An IPv6 ping to it times out. **That is expected**, not a fault.
- Its Wi-Fi clients still get IPv6 addresses and IPv6 DNS from the main router, because the AX21 bridges router advertisements like any other traffic.

So on a network with [Local-only IPv6](../network/local-only-ipv6.md), the AX21 simply has no entry in the IPv6 address plan. Manage it over IPv4.

## If you also have a mesh or other access points

The AX21 is not part of a vendor mesh such as ASUS AiMesh. A device moving between the mesh's coverage and the AX21's coverage does a normal reconnect, not a seamless handoff, even when the SSID and key match. That is fine for phones and laptops; a call in progress may hiccup. The AX21 has no 6 GHz radio, so a 6 GHz SSID exists on the main router only.

Stock firmware in AP mode cannot carry a second, isolated network from a VLAN the way an OpenWrt AP can. For that see [Isolated IoT network](../network/isolated-iot-network.md) and the [Archer A7 on OpenWrt](tp-link-archer-a7-openwrt.md).

## Check it

**Run on: your computer.**

```sh
ping -c 3 192.168.50.4
```

Expect replies. Then:

- `http://192.168.50.4` shows the TP-Link login page.
- A phone joined to the AX21's Wi-Fi gets an address in the main router's pool with gateway `192.168.50.1`, and reaches the internet.
- If the LAN has local IPv6, the same phone also has an address in `fd00:1234:5678:50::/64`.

## Pitfalls

| What happens | Why | Avoid or recover |
| --- | --- | --- |
| IPv6 ping to the AX21 times out | It has no IPv6 address in AP mode | Nothing to fix |
| No SSH | Stock firmware does not offer it in AP mode | Use the web page |
| The admin page moves to another address | The LAN IP was left on automatic and the lease changed | Static LAN IP, or a DHCP reservation on the main router |
| Some settings you saw in router mode are gone | AP mode removes router features (TP-Link lists NAT, Parental Controls and QoS as unavailable) | Expected |
| No "Access Point" choice under Operation Mode | Old firmware | Update the firmware from TP-Link's support page, then try again |

> **Not verified:** The author did not re-check the AX21's own DNS setting or its EasyMesh setting after the rest of the network was changed. If you use EasyMesh with other TP-Link devices, review that page yourself; this wiki does not cover it.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Clients on the AX21 get no address | The AX21 is not cabled to the LAN, or it is still in router mode | Check the cable; check Operation Mode |
| Clients get addresses from a different range | Still in router mode, handing out its own addresses | Set Access Point mode |
| IPv6 ping to the AX21 times out | Expected | Nothing |
| Cannot find the AX21 after a change | It took a new DHCP address | Look for it in the main router's client list, then fix the address as above |
| Clients on the AX21 have no IPv6 address but clients elsewhere do | Not seen by the author; the AX21 bridges advertisements | Reconnect the client; compare with a wired device |

## Undo

Set **Operation Mode** back to router mode in the admin page, or hold the reset button to return the unit to factory settings.

## References

- [Archer - Configure Access Point Mode](https://community.tp-link.com/us/home/kb/detail/390): TP-Link's step-by-step for switching an Archer router to Access Point mode, and what is unavailable in that mode.
- [Download for Archer AX21](https://www.tp-link.com/us/support/download/archer-ax21/): TP-Link's support page with the user guide and firmware for each hardware version.
