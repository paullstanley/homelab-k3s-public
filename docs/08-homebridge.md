# 08. Homebridge, Kasa switches and cameras

Homebridge v2.4.0 runs as one pod on k3sprimary, on the node's own network (`hostNetwork`), so its traffic comes from 192.168.50.5. Chart `k8s-at-home/homebridge`, namespace `homebridge`.

**Not highly available, on purpose.** HomeKit pairs with one bridge identity, stored on one volume, on one node's disk. Running two would mean two bridges fighting over the same accessories. If k3sprimary dies, restore the Homebridge backup onto another node.

## Step 1. Install

**Paste on: k3sprimary**, in the root of this repo.

```bash
helm repo add k8s-at-home https://k8s-at-home.com/charts/
helm repo update
sudo kubectl create ns homebridge
sudo kubectl apply -f traefik/middleware-redirect-https.yaml
helm upgrade --install homebridge k8s-at-home/homebridge -n homebridge -f Homebridge/values.yaml
sudo kubectl -n homebridge get pods -o wide
```

The pod must land on k3sprimary. Its volume is a `local-path` folder on that Pi, so once created it cannot move by itself.

## Step 2. Restore the backup

Open `http://192.168.50.5:8581`, finish the first-run screen, then **Settings → Backup → Restore** and choose the backup archive. That brings back `config.json`, the plugins and the HomeKit pairing, and you can skip to "Check it".

Without a backup, carry on with Steps 3 to 7 and re-pair every bridge in the Home app.

## Step 3. UI settings

**Settings**, in the Homebridge UI.

| Setting | Value | Why |
| --- | --- | --- |
| Enable HTTPS | **Off** | Traefik does the HTTPS. On gives "Bad Gateway" |
| UI port | 8581 | Do not change to 80 or 443; Traefik is in front |
| Host IP | `0.0.0.0` | Traefik reaches the UI over the pod network |
| Reverse Proxy Hostname | `hb.home.example.com` | So the UI accepts requests arriving under that name |
| Network Interfaces (mDNS) | `eth0` only | `flannel-v6.1`, `flannel.1` and `cni0` off. Advertising HomeKit on the cluster's internal interfaces is useless and confused discovery |
| mDNS advertiser | leave at the default | |

Then the UI is at `https://hb.home.example.com` (no port; `http://` redirects). `http://192.168.50.5:8581` keeps working as the fallback.

> **Trouble we hit, in order.** (1) After Traefik moved, `hb.home` still pointed at .5 and only answered with `:8581`. (2) Pointing the name at .12 failed while the UI had its own HTTPS on, because Traefik talks plain HTTP to it. (3) With HTTPS off in Homebridge and the Ingress in place it worked on `https://` without a port. (4) Turning "Enable HTTPS" back on later gave Bad Gateway again. (5) The redirect from `http://` needed the Traefik middleware.

## Step 4. Plugins

Install from the **Plugins** page, not from the startup script.

| Plugin | For | Child bridge |
| --- | --- | --- |
| `homebridge-kasa-python` (3.2.0) | Kasa switches, dimmers and fans | Yes |
| `homebridge-wyze-smart-home` (0.5.61) | Wyze bulbs, plugs, LED strips | Yes |
| `homebridge-wiz-lan` (3.4.2) | WiZ bulb | |
| `@homebridge-plugins/homebridge-camera-ffmpeg` (4.1.0) | Cameras | No (cameras are on the main bridge) |
| `@homebridge-plugins/homebridge-resideo` (3.2.3) | Resideo thermostat | |

**Do not install the old `homebridge-camera-ffmpeg` (3.1.4).** The old startup script reinstalled it on every start, which put two camera plugins side by side registering the same platform. That line is gone from `Homebridge/values.yaml`; uninstall the old plugin in the UI if it is still listed.

**Do not go back to `homebridge-tplink-smarthome`.** It is unmaintained, has no support for the newer Kasa protocol, and its child bridge crashed here.

## Step 5. Kasa switches on the guest network

The Kasa devices sit on the isolated guest network (`Home-IoT`, 192.168.101.0/24). Homebridge sits on the main LAN. Getting the two to talk was the hardest part of this whole setup, and it takes **four things, all of them**.

### 5a. Put the switch on the IoT network

In the Kasa phone app: add the device, and when it asks for Wi-Fi choose `Home-IoT` (2.4 GHz). Finish setup in the app and check it works there. If the app offers a "Third-Party Compatibility" setting, leave it on.

### 5b. Give it a fixed address

On the XT8: **LAN → DHCP Server → Manually Assigned IP**, add the device's MAC with its 192.168.101.x address. (With YazDHCP, the same list.) The current addresses are in [01](01-inventory.md). If a switch changes address, Homebridge loses it.

### 5c. Tell the plugin about it by address

Discovery is a broadcast and broadcasts do not cross from one network to the other. **Every Kasa device must be listed under `manualDevices`.** The full block is in [`Homebridge/config-examples/kasa-python.json`](../Homebridge/config-examples/kasa-python.json); paste it into the plugin's JSON config and fill in the TP-Link account.

`enableCredentials` with the TP-Link/Kasa account email and password is required for newer devices. On 4 October the log showed `AuthenticationError (host=192.168.101.116)` for the living-room ceiling fan: that is a device that wants credentials and did not get valid ones. The fan was added on the next start, so check it responds; if it does not, re-enter the account in the plugin settings.

`pollingInterval: 5` and `waitTimeUpdate: 100` are the values in use. If devices time out under load, 15 and 1000 give more headroom.

### 5d. The router rules

Three rules on the XT8, all installed by `xt8-bootstrap.sh` ([02](02-router-xt8.md)):

1. `iptables` FORWARD: k3s nodes → 192.168.101.0/24 allowed.
2. `iptables` FORWARD: 192.168.101.0/24 → k3s nodes allowed for replies only.
3. `ebtables -t broute`: ICMP and TCP from the guest Wi-Fi to the three node addresses accepted **ahead of** the guest-isolation DROP rules.

Rule 3 is the one nobody tells you about. ASUS guest isolation is done in `ebtables`, not `iptables`, so rules 1 and 2 alone look right and still do not work. And a Wi-Fi restart on the router wipes rule 3; the `service-event-end` script puts it back.

The other direction stays blocked: a guest device cannot open a connection to anything on the main LAN.

### 5e. The node firewall

If the host firewall is on ([10](10-firewall.md)), k3sprimary must allow the IoT network in. The firewall script does this on the node named `k3sprimary` only.

### Test

**Paste on: k3sprimary.**

```bash
ping -c 3 192.168.101.201
nc -vz -w 3 192.168.101.201 9999
```

Replies and "succeeded". Then toggle the device in the Home app.

| Symptom | Missing piece |
| --- | --- |
| Ping fails, Homebridge logs "Timeout after 5 seconds connecting to the device: 192.168.101.x:9999" | Rule 3. On the XT8: `sh /jffs/scripts/kasa-guest-allow.sh` |
| Ping works, Homebridge never lists the device | Not in `manualDevices`, or its address changed |
| `AuthenticationError` in the log | TP-Link account missing or wrong in the plugin |
| Worked until the firewall was turned on | 5e |
| One device stopped after moving rooms | It roamed to the AiMesh node; see "Things that will bite you again" in [02](02-router-xt8.md) |

### Wyze devices

The Wyze bulbs, plugs and strips on the guest network are driven through Wyze's cloud by `homebridge-wyze-smart-home` (account, API key and key ID in the plugin settings). They need no router rules. Only the Wyze **camera** is reached directly, and it is on the main LAN.

## Step 6. Resideo thermostat

The plugin links to your Resideo/Honeywell account with a login flow started from the plugin's settings page ("Start Resideo Login Server" in the log). It needs the consumer key and secret from your Resideo developer app, and the app's redirect/callback address must match what the plugin shows. You got this working on 4 October after reinstalling the plugin (3.2.3); I do not have the detail of what you changed, so write the callback address down here when you next open it:

- Callback URL registered in the Resideo developer app: `<FILL IN>`

## Step 7. Cameras

Config in [`Homebridge/config-examples/camera-ffmpeg.json`](../Homebridge/config-examples/camera-ffmpeg.json).

| Camera | Address | Setting | Why |
| --- | --- | --- | --- |
| Living Room (Axis) | 192.168.50.127 | `libx264`, 1280×720, 15 fps, max bitrate 2000, `forceMax` false, packet size 564 | See below |
| Entrance (Axis) | 192.168.50.209 | same | |
| Backyard (Wyze) | 192.168.50.69 | `vcodec: copy`, audio on, still image over TCP | The Wyze stream is already in a format HomeKit takes; copying it costs the Pi almost nothing |

**What was tried on the Axis cameras:**

| Attempt | Result |
| --- | --- |
| Extra Axis URL parameters and a separate snapshot URL | ffmpeg exited with code 8; no picture |
| `vcodec: copy` | Picture, but very slow and mostly buffering |
| `libx264` at 1280×720, 15 fps, 2000 kbps (current) | **Result not reported.** If it is poor, fall back to your original: 1920×1080, 20 fps, max bitrate 150000, `forceMax` true, `videoFilter` none, `mapvideo` 0 |

The Wyze entry's `source` line in the example uses the usual Wyze RTSP form. Check it against your live config before trusting it; I only have the address, not your exact URL.

**Bridged or unbridged.** The cameras are bridged on the main bridge (no `unbridge` setting), so they did not need re-pairing. The plugin's authors recommend unbridged cameras for performance. If you switch, each camera is added to the Home app separately with the bridge's PIN, and the old tiles must be removed first.

## Check it

- `https://hb.home.example.com` loads, and `http://hb.home.example.com` redirects to it.
- The status page shows every child bridge running.
- A Kasa switch toggles from the Home app.
- Each camera shows a live picture within a few seconds.

## Known leftovers

- The pod installs `ffmpeg` with `apt-get` at every start. If the package servers are unreachable the pod still starts, with whatever ffmpeg the image has.
- `PUID`, `PGID` and `HOMEBRIDGE_CONFIG_UI` were removed from the values file; the current image ignores them.
- The image tag is `latest`. `ghcr.io/oznu/homebridge` is the older image name; the project now publishes as `homebridge/homebridge`. It works today. If a pull ever fails, that is the first thing to change.
