# Reviewing a home network like this one

A checklist for reviewing a running network of this kind: an ASUS router on Asuswrt-Merlin, an OpenWrt access point, and a small k3s cluster. For each item it says what to look for, why it matters, and how to change it. It starts with how to export the settings for review without leaking the secrets they contain, because that step is where reviews most often go wrong.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | ASUS ZenWiFi XT8 (RT-AX95Q) and AiMesh node on GNUton Asuswrt-Merlin 3004.388.10_2; TP-Link Archer A7 v5 on OpenWrt 25.12.5 as a bridged access point; k3s v1.34 with Pi-hole, Homebridge and MetalLB. The checklist was built from a review of one live network of this design |
| **Also works for** | Other Asuswrt-Merlin and stock ASUS routers (menu names may differ), other OpenWrt devices, other small clusters. Not tested by the author |
| **Time** | 1 to 2 hours for the first review; 20 minutes for a repeat |
| **You need first** | SSH access to the router and the access point. Background: [ASUS ZenWiFi XT8](../hardware/asus-zenwifi-xt8.md), [Archer A7 on OpenWrt](../hardware/tp-link-archer-a7-openwrt.md), [Backups and secrets](backups-and-secrets.md) |

## How it works

A home network collects settings over the years: a VPN turned on once for a trip, a port forward for a game, a share on the router's USB drive, a deny list on an access point. Each made sense at the time. A review asks of each one: is it still needed, is it the safest way to do the job, and is the decision written down.

The router and the access point keep all their settings in one place each: **nvram** on the ASUS (the firmware's key/value settings store) and **UCI** on OpenWrt (the files in `/etc/config/`). Exporting those gives you the whole picture in one text file. The catch is that the same file holds every Wi-Fi key, VPN secret and password hash, often under key names that a simple "password" filter does not catch.

The checklist below is grouped by the page of the web interface where you change each setting. Each item has the same three parts: what to look for, why, and how to change it. Many items are trade-offs rather than faults: the goal is a deliberate, recorded decision.

> **Not verified:** menu paths are from Asuswrt-Merlin 3004.388 and OpenWrt 25.12 LuCI. The nvram key names and values quoted were read from a live router on 3004.388.10_2; their meaning was inferred from the matching GUI setting, not from documentation. The commands that change settings were not run by the author unless a line says so.

## Before you start

- Take the backups in [Backups and secrets](backups-and-secrets.md). Several changes below can lock you out (SSH keys, HTTPS, disabling password login).
- Keep a second way in while you change login settings: an open SSH session, or a cable to the device and the web UI.
- Decide where the exported files will live. They are secrets until you have checked them: keep them on your own computer, out of Git, out of chats and out of shared folders.
- Have your password manager open. Several items end with "rotate".

## Steps

### Step 1. Export the router settings safely

`nvram show` prints every setting as `key=value`. A filter that drops lines containing `pass` or `key` is **not enough**, for three reasons:

- **Secrets hide inside list values.** Some settings are records joined with `<` or `>` characters. The IPsec VPN profile (`ipsec_profile_*`) holds the pre-shared key as one field of such a record; the VPN client list (`ipsec_client_list_*`) holds user names and passwords. Neither key name contains `pass` or `psk`.
- **Mesh and device secrets have unusual names.** AiMesh pairing keys (`amas_*key*`), the mesh group secret (`cfg_group`, `cfg_rekeylist`) and the web session ID (`http_id`) do not look like passwords.
- **Values can span several lines.** Certificates and private keys stored in nvram continue on lines that do not start with a key name, so a key-name filter removes the first line and keeps the rest.

Your public IP address also appears in several places (`wan0_ipaddr`, `ddns_cache`, `ddns_ipaddr`).

**Run on: the router**

```sh
nvram show 2>/dev/null | sort \
 | grep -E '^[A-Za-z0-9_.:-]+=' \
 | grep -Ev '^(ipsec_profile|ipsec_client_list|cfg_group|cfg_rekeylist|ddns_cache|ddns_ipaddr|http_id|http_passwd)' \
 | grep -Ev '^amas_[^=]*key' \
 | grep -Ev '^[^=]*(_key|key_|psk|pass|secret|token|cert|crt|priv)[^=]*=' \
 | grep -Ev '^wl[^=]*_wpa_psk=' \
 | grep -Ev '^wan[0-9]*_(ipaddr|gateway|dns)|^wan_(ipaddr|gateway)' \
 > /tmp/nvram-review.txt
wc -l /tmp/nvram-review.txt
```

What each line does:

| Line | Removes |
| --- | --- |
| `grep -E '^[A-Za-z0-9_.:-]+='` | Every continuation line of a multi-line value. Only lines that start with a key name survive |
| first `grep -Ev` | The VPN profile and client list, the mesh group secrets, the dynamic DNS cache, the web session and password |
| `^amas_[^=]*key` | AiMesh pairing keys |
| `(_key\|key_\|psk\|pass\|secret\|token\|cert\|crt\|priv)` in the key name | Wi-Fi and VPN keys, passwords, tokens, certificates and private keys |
| `^wl[^=]*_wpa_psk=` | Every Wi-Fi passphrase, including guest networks (already caught above; kept as a second net) |
| `wan..._ipaddr` and friends | Your public address and the ISP's gateway and DNS |

Then look for anything the filter missed: long runs of hex or base64, which is what keys look like.

**Run on: the router**

```sh
grep -En '[A-Za-z0-9+/=]{24,}' /tmp/nvram-review.txt | cut -c1-80
grep -Ein 'ipsec|wgs_|wgc_|vpn_' /tmp/nvram-review.txt | cut -c1-80
```

Read every hit and delete the line if it is a secret. Then copy the file off and delete it from the router.

**Run on: your computer**

```sh
scp -O -P 22 admin@192.168.50.1:/tmp/nvram-review.txt ./nvram-review.txt
ssh -p 22 admin@192.168.50.1 'rm /tmp/nvram-review.txt'
```

> **Pitfall:** the filtered file still holds your Wi-Fi names, device names, MAC addresses, your domain and your DHCP reservations. That is fine for your own review. Before you show it to anyone else, or paste it into a chat or a forum, remove those too, or share only the lines you are asking about. If an unfiltered or badly filtered export was ever shared, treat every secret in it as exposed and rotate it ([Backups and secrets](backups-and-secrets.md#if-a-secret-was-exposed)).

> **Not verified:** the filter was written after a real export with a simpler filter was found to have leaked the VPN pre-shared key and VPN user passwords. The improved filter has not been run against every firmware version; the second `grep` pass is there because new key names appear with new firmware.

### Step 2. Export the access point settings safely

`uci export` prints every OpenWrt configuration file. The secrets are in a known set of options: Wi-Fi `key` (and `sae_password`, `password`, `auth_secret` for other modes), and any VPN `private_key` or `preshared_key`. The root password hash is in `/etc/shadow`, not in UCI.

**Run on: the access point** (`ssh root@192.168.50.3`)

```sh
uci export | sed -E \
 -e "s/^([[:space:]]*option (key|sae_password|password|auth_secret|acct_secret|private_key|preshared_key|wpa_psk)) .*/\1 '<REDACTED>'/" \
 -e "s/^([[:space:]]*(option|list) (macaddr|maclist)) .*/\1 '02:00:00:00:00:00'/" \
 > /tmp/uci-review.txt
grep -En "[A-Za-z0-9+/=]{24,}" /tmp/uci-review.txt
```

The first expression replaces every secret option's value. The second replaces MAC addresses (including MAC filter list entries) with a made-up one; leave it out for your own review if you want to check which devices a deny list names. The `grep` must print nothing; if it prints a line, look at it.

**Run on: your computer**

```sh
scp -O root@192.168.50.3:/tmp/uci-review.txt ./uci-review.txt
ssh root@192.168.50.3 'rm /tmp/uci-review.txt'
```

The settings backup from [Archer A7](../hardware/tp-link-archer-a7-openwrt.md#back-up-the-settings) is not a substitute: it is the unredacted configuration plus the password hash.

### Step 3. Router: administration

| Look for | Why | Change it |
| --- | --- | --- |
| SSH on with **password login and no keys**. On the reviewed router: `sshd_enable=2` (LAN only) and `sshd_authkeys` empty | A password can be guessed or reused; a key cannot | **Administration > System**: paste your public key into **Authorized Keys**, apply, test a new `ssh` session with the key, then turn password login off in the same section. Keep the SSH port LAN-only |
| SSH port forwarding allowed | Lets an SSH login tunnel into the LAN | Turn it off unless you use it |
| Web UI on **HTTP only** (`http_enable=0` was observed meaning HTTP only) | The admin password crosses the LAN in clear text, readable by any compromised device on Wi-Fi | **Administration > System > Authentication Method**: HTTPS, or Both while you test. Default HTTPS LAN port is `8443`. Browsers warn about the router's self-signed certificate; accept it once per browser, or use the Let's Encrypt option with DDNS |
| Web UI reachable from the WAN (`misc_http_x=1`) | The login page is exposed to the internet | Off. Use a VPN to manage the router from outside |
| Login name is a person's name | Helps guessing, and leaks into backups and screenshots | Use a neutral name when you next reset |
| Auto-logout disabled | A forgotten browser tab stays logged in | 30 minutes or less |

> **Pitfall:** turn password login off only after a key login has worked in a **new** session. If you lock yourself out, the web UI still works; turn password login back on there.

### Step 4. Router: VPN server

| Look for | Why | Change it |
| --- | --- | --- |
| **IPsec server with a pre-shared key** (IKEv1, "Host-to-Net") | The whole security rests on one shared secret. If it is short or simple it can be guessed offline from one captured handshake. Anyone holding it, plus one user's password, is on your LAN | If you do not use it, turn it off: **VPN > VPN Server > IPSec VPN**. If you do, prefer the **WireGuard** server (built into Merlin 388): one key pair per device, nothing to brute-force |
| The PSK or VPN user passwords were ever in an export, a backup you shared, a screenshot or a chat | They are exposed | **Rotate now**: a new long random PSK and new user passwords, then update every client. Better, move to WireGuard and turn IPsec off |
| OpenVPN server on, with old settings | Merlin 388.12 (upstream) removed static-key mode and server compression | Before taking a firmware with those changes, read its OpenVPN notes |
| PPTP server on | Broken encryption | Off |
| VPN clients' DNS pointing at Pi-hole | Fine, if Pi-hole should answer them | Check the address is still Pi-hole's |

To set up WireGuard: **VPN > VPN Server > WireGuard VPN**, enable it, add one client per device, and import each client's configuration (QR code or file) on that device. Then test from outside your network, and only then turn IPsec off.

> **Pitfall:** WireGuard on Merlin disables hardware NAT acceleration (Merlin 388.1 changelog), so routing throughput can drop while it is on. On a fast internet line, measure before and after.

> **Not verified:** the WireGuard menu path and client export on GNUton 388 were not walked through by the author.

### Step 5. Router: exposure to the internet

| Look for | Why | Change it |
| --- | --- | --- |
| **UPnP on** (`wan0_upnp_enable=1`) | Any program on the LAN, including malware or a cheap IoT device, can open ports to the internet without asking you | **WAN > Internet Connection > Enable UPnP = No**, unless a game console or app truly needs it. Use static port forwards for anything you know about. Upstream Merlin turned UPnP off by default from 388.10 |
| Port forwards (**WAN > Virtual Server / Port Forwarding**) | Each one is a hole in the firewall | Remove any you do not recognise or no longer use. For each one left, record what it is for |
| **A port-forward target with no DHCP reservation** | When its lease changes, the forward points at whatever device gets that address next | Reserve every forward target first ([Address plan](../network/address-plan.md)). A laptop's USB Ethernet dongle running a server is a typical case |
| DDNS name on | It publishes your public IP under a guessable name | Fine if you need it for VPN or HTTPS; off otherwise |
| AiCloud, FTP, media server on | Services reachable from outside | AiCloud is removed in 388.11; turn the others off unless used |
| Respond to WAN ping | Makes the router visible to scans | **Firewall > General**: off |
| DoS protection and SPI firewall | | On (`fw_dos_x=1`). Logging of dropped packets (`fw_log_x=drop`) is fine but noisy |
| DNS rebind protection (`dns_norebind=1`) | Stops web pages from making your browser talk to LAN devices by name | On |

### Step 6. Router: USB

| Look for | Why | Change it |
| --- | --- | --- |
| **Samba (network share) on** for the router's USB drive | The drive holds Entware, Skynet and the logs; a share exposes it to every LAN device, with a password that is often weak | **USB Application > Servers Center > Network Place (Samba) Share**: off, unless someone uses the share |
| **USB 3.0 mode on** (`usb_usb3=1`) | USB 3 interferes with 2.4 GHz Wi-Fi near the port. A drive used for logs and add-ons does not need USB 3 speed | **Administration > System > USB Mode**: USB 2.0, then reboot. Watch 2.4 GHz reliability before and after |

> **Not verified:** the exact menu names for Samba and USB mode on GNUton 388.

### Step 7. Router: wireless

| Look for | Why | Change it |
| --- | --- | --- |
| **A DFS channel** on a 5 GHz band (in the US, channels 52 to 144; for example 116 at 160 MHz) | DFS channels are shared with radar. When the radio hears radar it must leave the channel; the log shows `Radar detected` and clients on that band drop until it settles, typically around 30 minutes. With a **wired** backhaul only clients are affected; with a wireless backhaul on that band, the mesh link drops too | Decide: keep the wider DFS channel for speed and accept the drops, or move to a non-DFS channel (36 to 48, or 149 to 165, at 80 MHz) for stability. [Router logging](../network/router-logging.md) shows how to count radar events |
| WPA2/WPA3 mixed mode with PMF "capable" | A good default: WPA3 for devices that support it, WPA2 for the rest | Keep. Plain WPA2 only if a device cannot join |
| Roaming assistant thresholds | Too strict kicks devices off many times a day | Around -70 dBm ([ASUS ZenWiFi XT8](../hardware/asus-zenwifi-xt8.md#step-1-gui-settings)); stationary devices exempt ([Address plan](../network/address-plan.md#roaming-exclusions)) |
| WPS on | A known weak point | Off |
| Guest/IoT network: **Access Intranet** | Must be off, or the IoT network is not isolated | Off ([Isolated IoT network](../network/isolated-iot-network.md)) |
| Guest network with a time limit or a weak key | IoT devices drop when it expires | No time limit; a strong key |

### Step 8. Router: AiProtection

AiProtection is ASUS's Trend Micro security engine: malicious site blocking (`wrs_mals_enable`), two-way IPS (`wrs_vp_enable`) and infected device prevention (`wrs_cc_enable`).

| Choice | For | Against |
| --- | --- | --- |
| On | Blocks known-bad sites and some attacks for every device, including ones you cannot patch | The engine was seen to crash the kernel and reboot the router every few days on this hardware. It sends data to Trend Micro (you accept its terms to turn it on) |
| Off | Stability; no third-party data sharing | You rely on Pi-hole blocklists and Skynet instead |

Either is defensible. Record which you chose and why. If you keep it on and the router reboots unexpectedly (a `kernel:` crash dump followed by a boot sequence in the log), turn **Two-Way IPS** off first, then Infected Device Prevention.

### Step 9. Router: firmware and scheduled reboots

| Look for | Why | Change it |
| --- | --- | --- |
| Firmware older than the newest GNUton stable | Security fixes, including in httpd and IPsec | Update router and node to the same version: [Software and firmware](software-and-firmware.md#gnuton-asuswrt-merlin-for-the-xt8-rt-ax95q) |
| "Scheduled check for new firmware" on, reporting nothing new | ASUS's server does not offer GNUton builds, so it never reports one | Check the GNUton releases page yourself, monthly |
| Router and node on different versions | Mixed-era builds may not work together | Same version on both |
| **Reboots of router, node and access points at the same minute** | All Wi-Fi goes down at once, and the node can come back before the router it depends on | Stagger them: node and access points first (for example 03:30), main router 10 to 15 minutes later (03:45), so the node is back and settled before the router restarts. [Maintenance](maintenance.md) |
| The node's reboot job | `cru` jobs vanish at reboot unless `services-start` re-adds them | `cru l` on the node ([AiMesh node](../hardware/asus-aimesh-node.md#check-it)) |

### Step 10. Access point: logins and admin interface

| Look for | Why | Change it |
| --- | --- | --- |
| **Password login for root over SSH, no keys** (`dropbear` `PasswordAuth 'on'`, `RootPasswordAuth 'on'`, the defaults) | As on the router | Add your key in LuCI **System > Administration > SSH-Keys** (or append it to `/etc/dropbear/authorized_keys`), test a new session, then the commands below |
| **LuCI on HTTP** with no redirect (`uhttpd.main.redirect_https='0'`, the default) | The root password crosses the LAN in clear text | Redirect to HTTPS (below). The certificate is self-signed |
| No root password at all | A fresh OpenWrt has none | Set one ([Archer A7](../hardware/tp-link-archer-a7-openwrt.md#step-3-set-a-root-password)) |

**Run on: the access point**, after a key login has worked in a new session.

```sh
uci set dropbear.@dropbear[0].PasswordAuth='off'
uci set dropbear.@dropbear[0].RootPasswordAuth='off'
uci commit dropbear
/etc/init.d/dropbear restart
uci set uhttpd.main.redirect_https='1'
uci commit uhttpd
/etc/init.d/uhttpd restart
```

The first four lines turn off password logins over SSH. The last three make LuCI redirect `http://` to `https://`.

> **Pitfall:** if you lose the key, LuCI still lets you log in with the root password and add a key again. If you have also lost LuCI, failsafe mode is the way back (see the OpenWrt documentation for your device).

### Step 11. Access point: radios

First find which radio is which.

**Run on: the access point**

```sh
uci show wireless | grep -E "=wifi-device|\.band=|\.channel=|\.htmode=|\.txpower=|\.legacy_rates="
```

| Look for | Why | Change it |
| --- | --- | --- |
| **`legacy_rates='1'` on the 2.4 GHz radio** | It keeps the old 802.11b rates (1, 2, 5.5 and 11 Mbit/s) on. A single slow client or the beacons at those rates use a large share of airtime | `uci set wireless.<RADIO>.legacy_rates='0'`, `uci commit wireless`, `wifi reload`. Leave it on only if an old 802.11b device must connect |
| **Transmit power at or near the maximum** (for example `txpower='24'` dBm) on an **extra** access point | A loud extra AP pulls clients that are nearer the main router, and they cling to it ("sticky clients"). Clients cannot transmit as loudly back, so the link is lopsided | Lower it in steps (for example to 17 or 20 dBm): `uci set wireless.<RADIO>.txpower='17'`, commit, `wifi reload`. Walk around with a phone and check which AP it picks |
| Channels overlapping the main router's | Two radios on one channel share airtime | 2.4 GHz on 1, 6 or 11, not the router's; 5 GHz on a different block ([Archer A7](../hardware/tp-link-archer-a7-openwrt.md#step-6-configure-the-wi-fi)) |
| 802.11r (fast transition) on with WPA3 | A known 25.12 issue causes client problems | Leave 802.11r off |

> **Not verified:** the lower power values are a starting point for a two-storey house, not a measured recommendation.

### Step 12. Access point: per-SSID MAC deny lists

**Run on: the access point**

```sh
uci show wireless | grep -E "\.ssid=|\.macfilter=|\.maclist="
```

| Look for | Why | Change it |
| --- | --- | --- |
| A deny list (`macfilter='deny'`) on each SSID | Usually deliberate: it keeps stationary devices on the nearer mesh unit instead of this AP ([Address plan](../network/address-plan.md#on-an-access-point-that-is-not-part-of-the-mesh)) | Confirm every entry is a device you still own and still want kept off this AP. Write down why each is there |
| A deny list on the **IoT SSID** that lists most IoT devices | Then the IoT SSID on this AP serves almost nothing, and you are maintaining a network for a few devices | Either accept that (record why), or remove entries so nearby IoT devices can use it, or remove the IoT SSID from this AP |
| Entries for phones or laptops | Phones and laptops use private (randomised) MAC addresses per network, so the entry may no longer match | Turn private addressing off for that network on the device, or drop the entry |

A MAC deny list is a steering tool, not security: a MAC address is easy to copy.

### Step 13. Access point: the IoT SSID and leftovers

| Look for | Why | Change it |
| --- | --- | --- |
| The IoT SSID's encryption and isolation differ from what the setup script set (the script sets `encryption='psk2+ccmp'` and `isolate='1'`; a live device was found with WPA2/WPA3 compatibility mode and `bridge_isolate` instead) | Someone changed it in LuCI, or the device was set up another way. The settings backup then disagrees with the repo | Decide which is right, set it, and test isolation from an IoT device ([Isolated IoT network](../network/isolated-iot-network.md#check-it)) |
| An IPv6 gateway set on the AP's LAN interface (`ip6gw`) | The setup design has none. Harmless if the router never routes IPv6, but it differs from the documented build | Delete it (`uci -q delete network.lan.ip6gw`, commit, `/etc/init.d/network restart`) or record it |
| Disabled `dhcp`, `firewall` and `dnsmasq` sections still in the config, a stale static neighbor report | Harmless leftovers from an earlier routed setup | Leave, or tidy so the next review is shorter |
| `odhcpd`, `dnsmasq` or `firewall` running | They compete with the router | `ps` must not show them ([Archer A7](../hardware/tp-link-archer-a7-openwrt.md#check-it)) |
| OpenWrt older than the newest 25.12.x | 25.12.5 was a security release | [Software and firmware](software-and-firmware.md#openwrt-on-the-archer-a7-v5) |

### Step 14. Cluster and apps

| Look for | Why | Change it |
| --- | --- | --- |
| **k3s version drift**: the cluster on an old patch of its minor version, or the minor version near the end of support (in October 2026: v1.34.3 against a newest v1.34.12, with `stable` already at v1.36.5) | Security fixes and the upgrade path: you must go through every minor version | Upgrade one minor at a time. Never point an automatic upgrade plan at `stable` ([Software and firmware](software-and-firmware.md#k3s)) |
| Nodes on different k3s versions | A half-finished upgrade | Finish it |
| **Archived container images or charts** | No more security fixes. In this build: `crazymax/cloudflared` (archived December 2025, and `proxy-dns` gone from new cloudflared releases since February 2026) and the `k8s-at-home` Homebridge chart (archived 2022) | Plan replacements ([Software and firmware](software-and-firmware.md#the-cloudflared-dns-over-https-sidecar)). For the Homebridge chart, keep the image override to the current image and a saved copy of the chart |
| Images on `latest` | Each node keeps whatever it pulled; versions drift and you do not choose when to upgrade | Pin dated tags (Pi-hole, Homebridge, Seerr) |
| A HelmChart or chart without a version (kube-vip here) | It changes when k3s reinstalls it | Pin `version:` |
| MetalLB major update pending | 0.16 changes the default to FRR-K8s | Stay on 0.15.3 or move deliberately |
| The kubeconfig on laptops, the k3s token, the tunnel token | Each is full access | Only where needed; rotate after any exposure ([Backups and secrets](backups-and-secrets.md#if-a-secret-was-exposed)) |
| Node firewall | Without it every node port is open to the LAN | [Node firewall](../kubernetes/node-firewall.md) |

### Step 15. Record the decisions

For each item, write one line: kept, changed, or accepted with the reason. Keep it with your private notes, not in a public repository. Next time, review only what changed since.

## Check it

| Check | Run on | Expected |
| --- | --- | --- |
| `ssh -o PasswordAuthentication=no -p 22 admin@192.168.50.1 true` | Your computer | Succeeds (key login works) |
| `ssh -o PubkeyAuthentication=no -p 22 admin@192.168.50.1 true` | Your computer | Refused, once password login is off |
| The same two against `root@192.168.50.3` | Your computer | Same |
| `curl -sI http://192.168.50.3/ \| head -3` | Your computer | A redirect (`302` or `307`) to `https://` |
| `nvram get wan0_upnp_enable` | The router | `0` if you turned UPnP off |
| `nvram get usb_usb3` | The router | `0` if you chose USB 2.0 |
| Exported review files | Your computer | `grep -Ec '[A-Za-z0-9+/=]{24,}'` prints `0`, or only lines you have checked |
| Every port-forward target | The router's DHCP reservations | Has a reservation |
| Router, node and APs | `uptime` after the next scheduled reboot | Each rebooted at its own time |

## Pitfalls

| What happens | Why | Avoid or recover |
| --- | --- | --- |
| A "redacted" export still contained the VPN secret | The PSK lives inside a list value whose key name does not say "key" | Use the filter in Step 1, then the hex/base64 scan, then read it |
| Certificate or key fragments survive the filter | Multi-line values | The `^[A-Za-z0-9_.:-]+=` line in Step 1 |
| Locked out after turning off password login | No working key | Use the web UI to turn password login back on; always test a key in a new session first |
| Browser refuses the router UI after switching to HTTPS | Self-signed certificate, or the HTTPS port | Use `https://192.168.50.1:8443`; accept the certificate; or choose Both while testing |
| A game or app stops working after UPnP is off | It relied on UPnP | Add a static port forward for it, to a reserved address |
| A port forward silently goes to the wrong device | The target had no reservation | Reserve it |
| 5 GHz clients drop for half an hour now and then | Radar on a DFS channel | Accept, or move to a non-DFS channel |
| Clients cling to the extra AP | Its power is too high | Lower `txpower` |
| An old device cannot join 2.4 GHz after the change | It needs 802.11b rates | Turn `legacy_rates` back on |
| Router reboots by itself | AiProtection | Turn Two-Way IPS off |
| All Wi-Fi down at once at night, slow to recover | All reboots at one minute | Stagger them |

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `nvram show` output cut short | Very long values or a busy router | Run it again; redirect to a file in `/tmp` as shown |
| `scp` fails with a subsystem error | No SFTP on the router or AP | `scp -O` |
| `uci set dropbear.@dropbear[0]...` says "Invalid argument" | The section name differs | `uci show dropbear` and use the name it prints |
| LuCI still answers on HTTP after the redirect | `uhttpd` not restarted, or a browser cache | `/etc/init.d/uhttpd restart`; force-refresh |
| VPN clients cannot connect after rotating the PSK | Clients still have the old one | Update every client, or move them to WireGuard |
| Anything else | | [Troubleshooting](troubleshooting.md) |

## Undo

Each change has its reverse in the same place: tick password login back on, set the authentication method back to HTTP, re-enable UPnP or Samba, set `legacy_rates='1'` or raise `txpower`, and `uci set uhttpd.main.redirect_https='0'`. A rotated secret cannot be un-rotated, which is the point. To return a whole device to its state before the review, restore the backup you took first ([Backups and secrets](backups-and-secrets.md)).

## References

- [Asuswrt-Merlin changelog](https://www.asuswrt-merlin.net/changelog): UPnP off by default from 388.10, AiCloud removed in 388.11, WireGuard and hardware NAT, OpenVPN changes in 388.12.
- [Asuswrt-Merlin wiki: DNS Director](https://github.com/RMerl/asuswrt-merlin.ng/wiki/DNS-Director): what the per-device DNS rules do, for reviewing them.
- [gnuton/asuswrt-merlin.ng releases](https://github.com/gnuton/asuswrt-merlin.ng/releases): the current firmware to compare against.
- [OpenWrt dropbear default configuration](https://raw.githubusercontent.com/openwrt/openwrt/main/package/network/services/dropbear/files/dropbear.config): the `PasswordAuth` and `RootPasswordAuth` options and their defaults.
- [OpenWrt uhttpd default configuration](https://raw.githubusercontent.com/openwrt/openwrt/main/package/network/services/uhttpd/files/uhttpd.config): the `redirect_https` option and the HTTP and HTTPS listeners.
- [OpenWrt 25.12.5 service release](https://forum.openwrt.org/t/openwrt-25-12-5-service-release/251479): the security fixes, and known issues such as 802.11r with WPA3.
- [Cloudflare: cloudflared proxy-dns deprecation](https://developers.cloudflare.com/changelog/post/2025-11-11-cloudflared-proxy-dns/): why the DNS-over-HTTPS sidecar needs replacing.
- [crazy-max/docker-cloudflared](https://github.com/crazy-max/docker-cloudflared): the archived sidecar image.
- [k8s-at-home/charts](https://github.com/k8s-at-home/charts): the archived chart repository the Homebridge chart comes from.
- [K3s: Manual upgrades](https://docs.k3s.io/upgrades/manual): the one-minor-at-a-time rule behind the version drift item.
