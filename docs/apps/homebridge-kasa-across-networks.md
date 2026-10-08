# Kasa devices on an isolated IoT network, driven from Homebridge on the LAN

You end up with TP-Link Kasa switches, dimmers and fan controllers that live on an isolated guest/IoT network, controlled locally from Homebridge on the main LAN. The IoT devices still cannot open connections into the LAN. This takes several pieces that must all be in place at once; any one missing gives the same "timeout" symptom.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | `homebridge-kasa-python` 3.2.0 on Homebridge v2.4.0 (host-network pod on a k3s node), Kasa devices on an ASUS ZenWiFi XT8 guest network (Asuswrt-Merlin) with client isolation |
| **Also works for** | Homebridge on any host, and any router that isolates a guest network, as long as you can allow LAN-to-IoT connections and their replies. The router rules differ per vendor. Other local-control plugins that talk to devices by address follow the same pattern. Not tested by the author on other routers |
| **Time** | 30 to 60 minutes, more with many devices |
| **You need first** | [Homebridge on k3s](homebridge.md) (or any Homebridge), [Isolated IoT network](../network/isolated-iot-network.md) |

## How it works

The plugin controls Kasa devices over the local network: Homebridge opens a TCP connection to the device (port 9999 on older devices) and sends commands. Normally the plugin finds devices by sending a broadcast and listening for answers.

Two things break when the devices are on another network:

1. **Discovery.** A broadcast stays inside its own network. The plugin on `192.168.50.0/24` never hears devices on `192.168.101.0/24`. Each device must be listed by address.
2. **Reachability.** Guest isolation exists to stop the two networks talking. You must open exactly one direction: connections **from** the Homebridge host **to** the IoT network, and the replies. On ASUS routers, isolation is enforced in `ebtables` (the bridge-level firewall) as well as `iptables`, so an `iptables` rule alone looks right and still does not work.

The other direction stays blocked: an IoT device cannot open a connection to anything on the main LAN.

## Before you start

- Know which host Homebridge's traffic comes from. With `hostNetwork` it is the node's own address (`192.168.50.5` for `server-1`).
- Have the TP-Link/Kasa account email and password. Newer devices and firmware need them even for local control.
- Have the list of devices and their MAC addresses (the router's client list shows them once they join).

## Steps

All of these must be true. Work through them in order.

### Step 1. Put the device on the IoT network

In the Kasa phone app: add the device, and when it asks for Wi-Fi choose `Home-IoT` (2.4 GHz). Finish setup in the app and check it works there. If the app offers a "Third-Party Compatibility" setting, leave it on.

### Step 2. Give it a fixed address

On the router, reserve the device's address by MAC. On the XT8: **LAN → DHCP Server → Manually Assigned IP**, add the device's MAC with its `192.168.101.x` address (with the YazDHCP add-on, the same list).

> **Pitfall:** if a device changes address, Homebridge loses it. Unreserved devices produced spells of `[Errno 113] Connect call failed`, `[Errno 111]` and "No sys_info returned ... Marking offline" in the log. Reserve every device before listing it.

### Step 3. List every device under `manualDevices`

The full example is [`files/homebridge/config-examples/kasa-python.json`](../../files/homebridge/config-examples/kasa-python.json). Paste it into the plugin's JSON config (Plugins → the plugin → JSON Config), then fill in your addresses and account. Paste the whole block; a cut-off paste gives a config "verification warning".

```json
{
  "platform": "KasaPython",
  "name": "KasaPython",
  "enableCredentials": true,
  "username": "<KASA_ACCOUNT_EMAIL>",
  "password": "<KASA_ACCOUNT_PASSWORD>",
  "pollingInterval": 15,
  "discoveryPollingInterval": 300,
  "offlineInterval": 7,
  "waitTimeUpdate": 1000,
  "manualDevices": [
    { "host": "192.168.101.20" },
    { "host": "192.168.101.21" }
  ]
}
```

| Setting | Value used | What it does |
| --- | --- | --- |
| `manualDevices` | one `{ "host": "<address>" }` per device | **Required for every device.** Discovery broadcasts do not cross networks |
| `enableCredentials`, `username`, `password` | `true`, the TP-Link/Kasa account | Required for newer devices. Without valid credentials the log shows `AuthenticationError (host=192.168.101.x)` |
| `pollingInterval` | `15` (seconds) | How often each device's state is read. `5` was used earlier; `15` is the settled value |
| `waitTimeUpdate` | `1000` (milliseconds) | How long similar commands are combined before being sent to a device. `100` was used earlier |
| `discoveryPollingInterval` | `300` | How often discovery runs |
| `offlineInterval` | `7` | As in the example file |
| `enableEnergyMonitoring`, `logEnergyMonitoring` | `false` | Not used |
| `powerThreshold` | `2` | As in the example file |
| `hideHomeKitMatter` | `true` | Hides devices that already support HomeKit or Matter natively, to avoid duplicates |
| `pythonPath` | `/bin/python3` | Where Python is in the Homebridge image |
| `advancedPythonLogging` | `true` | More detail in the log; turn off once stable to shorten it |

Run the plugin as a child bridge, so a plugin problem does not take the main bridge down.

> **Pitfall:** the plugin config holds your TP-Link account password. Do not commit `config.json` or paste it anywhere.

### Step 4. The router rules

The rules are derived, explained and installed in [Isolated IoT network](../network/isolated-iot-network.md). In summary, on the XT8 three rules are needed:

| # | Where | Rule |
| --- | --- | --- |
| 1 | `iptables` FORWARD | Homebridge host (the k3s nodes) → `192.168.101.0/24` allowed |
| 2 | `iptables` FORWARD | `192.168.101.0/24` → those hosts allowed for **replies only** |
| 3 | `ebtables -t broute` | ICMP and TCP from the guest Wi-Fi to the node addresses accepted **ahead of** the guest-isolation DROP rules |

Rule 3 is the one that is easy to miss. ASUS guest isolation is done in `ebtables`, not `iptables`, so rules 1 and 2 alone look right and still do not work. A Wi-Fi restart on the router wipes rule 3; the `service-event-end` script puts it back by calling [`kasa-guest-allow.sh`](../../files/xt8/jffs-scripts/kasa-guest-allow.sh). All three are installed by [`xt8-bootstrap.sh`](../../files/xt8/xt8-bootstrap.sh); see [ASUS ZenWiFi XT8](../hardware/asus-zenwifi-xt8.md).

### Step 5. The node firewall

**If you also have a host firewall on the Homebridge node:** it must accept traffic from the IoT network, or the devices' replies are dropped at the node. [`files/firewall/k3s-firewall.sh`](../../files/firewall/k3s-firewall.sh) allows `192.168.101.0/24` (it is inside the allowed `192.168.0.0/16`, and there is an explicit rule on the Homebridge node as well). See [Node firewall](../kubernetes/node-firewall.md).

## Check it

**Run on: server-1** (the Homebridge host), using one device's address

```bash
ping -c 3 192.168.101.20
nc -vz -w 3 192.168.101.20 9999
```

Expected: three ping replies, and `succeeded` from `nc` (which tests that TCP port 9999 accepts a connection). Then toggle the device in the Home app; it should respond within a second or two.

> **Not verified:** port 9999 is the port of the older Kasa protocol and is what was tested here. Newer devices that need credentials may not listen on 9999; for those, rely on ping and the Homebridge log.

From the opposite side, confirm isolation still holds: from a device on `Home-IoT`, opening `http://192.168.50.1` must fail.

## Wyze devices on the IoT network

Wyze bulbs, plugs and light strips on the IoT network are driven through Wyze's cloud by `homebridge-wyze-smart-home` (account, API key and key ID in the plugin settings). Homebridge never connects to them directly, so **they need no router rules**. They do depend on Homebridge resolving `api.wyzecam.com`; see the DNS block in [Homebridge on k3s](homebridge.md).

A Wyze **camera** is different: it is streamed directly over RTSP, so keep it on the main LAN or give it the same treatment as the Kasa devices. See [Cameras](homebridge-cameras.md).

## Pitfalls

| What happens | Why | Avoid or recover |
| --- | --- | --- |
| Everything works until someone changes a Wi-Fi setting on the router | A Wi-Fi restart rebuilds the `ebtables` rules and drops rule 3 | The `service-event-end` hook restores it. Check `/jffs/scripts/service-event-end` exists and is executable |
| Rules 1 and 2 are in place, ping still fails | Isolation is in `ebtables` | Rule 3 |
| A device stops after it is moved to another room | It roamed to another access point or mesh node, where the guest rules may differ | [Isolated IoT network](../network/isolated-iot-network.md), [AiMesh node](../hardware/asus-aimesh-node.md) |
| One device times out far more than the others | Weak Wi-Fi at that device is the likely cause (suspected, not confirmed, for one ceiling-fan controller here) | Check its signal in the router's client list |
| Devices drop for short spells while you are moving them between networks | Their addresses are changing | Finish the move, reserve addresses, update `manualDevices` |
| Old plugin `homebridge-tplink-smarthome` | Unmaintained, no support for the newer Kasa protocol; its child bridge crashed | Use `homebridge-kasa-python` |

## Troubleshooting

Start with these.

**Run on: server-1**

```bash
ping -c 3 192.168.101.20
nc -vz -w 3 192.168.101.20 9999
sudo kubectl -n homebridge get pods -o wide
sudo kubectl -n homebridge logs deploy/homebridge --tail=40 | grep -i -E 'kasa|error|timeout'
```

| Symptom | Cause | Fix |
| --- | --- | --- |
| Ping fails; log says "Timeout after 5 seconds connecting to the device: 192.168.101.x:9999" | Rule 3 is missing (never installed, or wiped by a Wi-Fi restart) | **Run on: the router** `sh /jffs/scripts/kasa-guest-allow.sh` |
| Ping fails for **every** Kasa device | The router rules are gone | **Run on: the router** `sh /jffs/scripts/kasa-guest-allow.sh`, then `sh /jffs/xt8-bootstrap.sh verify` |
| Ping fails for **one** device | It is off the network or changed address | Kasa app; router client list; fix the reservation and `manualDevices` |
| Ping works, Homebridge never lists the device | Not in `manualDevices`, or its address changed | Step 3 |
| Ping works, port 9999 refused, or `AuthenticationError (host=...)` in the log | The device wants the TP-Link account and did not get valid credentials | Re-enter the account in the plugin settings. A device may still be added on the next start; check it actually responds |
| Worked until the node firewall was turned on; ping from the node works but Homebridge times out | The node firewall refuses the replies | Step 5 |
| Stopped right after a router Wi-Fi change | `ebtables` rules wiped and the hook did not restore them | Same as the first row; check the hook script |
| After a router restart or power cut | Rules not restored yet | Wait five minutes, then check as above |
| `[Errno 113] Connect call failed`, `[Errno 111]`, "No sys_info returned ... Marking offline" for a short spell | The device dropped off Wi-Fi or changed address | Reserve the address (Step 2) |
| Kasa works, but Wyze devices or the thermostat lag; log has `getaddrinfo ENOTFOUND` / `EAI_AGAIN` | DNS inside the Homebridge pod, not this page | [Homebridge on k3s](homebridge.md) |
| Every accessory says "No Response" | Homebridge itself | [Homebridge on k3s](homebridge.md) |

## Undo

Remove the devices from `manualDevices` (or uninstall the plugin), and remove the router rules as described in [Isolated IoT network](../network/isolated-iot-network.md). To stop isolating a device instead, move it back to the main SSID in the Kasa app and remove its entry from `manualDevices`; discovery finds it on the LAN.

## References

- [ZeliardM/homebridge-kasa-python](https://github.com/ZeliardM/homebridge-kasa-python): the plugin; `manualDevices`, `enableCredentials` and `waitTimeUpdate`.
- [python-kasa/python-kasa](https://github.com/python-kasa/python-kasa): the library underneath; discovery by broadcast to `255.255.255.255` and which devices need credentials.
- [jfarmer08/homebridge-wyze-smart-home](https://github.com/jfarmer08/homebridge-wyze-smart-home): the cloud-driven Wyze plugin and its API key fields.
- [homebridge/docker-homebridge](https://github.com/homebridge/docker-homebridge): why the Homebridge container uses the host network, which decides the source address your router rules must allow.
