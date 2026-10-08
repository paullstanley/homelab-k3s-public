# IP address plan, DHCP reservations and roaming exclusions

You end up with a written plan for which address every kind of device gets, a router that always hands the same address to the devices that need one, names that keep pointing at the right machine, and a short list of stationary devices that the mesh no longer pushes around. This is for a network where everything has so far taken whatever address DHCP gave it, and things now break "at random" when an address changes.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | A plan; the author's own network has not been migrated to it yet. The facts it builds on were read from an ASUS ZenWiFi XT8 on GNUton Asuswrt-Merlin 3004.388.10_2 with the YazDHCP add-on, with a `192.168.50.0/24` LAN and an ASUS guest network on `192.168.101.0/24`. Router-UI details that could not be confirmed from documentation are marked "Not verified" |
| **Also works for** | Any home router whose DHCP server is dnsmasq (Asuswrt-Merlin, OpenWrt, many others). The block layout is plain arithmetic and works anywhere. Not tested by the author |
| **Time** | 1 hour for the inventory and phase 1. Phase 2 (renumbering) is an evening, spread over several days if you let leases expire by themselves |
| **You need first** | Admin access to the router. For the ASUS parts: [ASUS ZenWiFi XT8](../hardware/asus-zenwifi-xt8.md). Only if you have them: [Isolated IoT network](isolated-iot-network.md), [Pi-hole](../apps/pihole.md), [Kasa devices across networks](../apps/homebridge-kasa-across-networks.md) |

## How it works

DHCP (Dynamic Host Configuration Protocol) is how a device asks the router for an address when it joins. A device can end up with an address in three ways:

| Way | Where it is set | What happens | Good for |
| --- | --- | --- | --- |
| **Static on the device** | On the device itself | The device never asks the router. The router does not know the address is taken unless you tell it | Things that must work when the router's DHCP is down or not yet up: the router, access points, cluster servers |
| **DHCP reservation** | On the router: "this MAC address always gets this IP address" | The device still asks by DHCP and always gets the same answer. Change it in one place, on the router | Almost everything else that needs a fixed address, especially devices with no settings screen |
| **Dynamic lease** | Nowhere | The router picks a free address from its **pool** (the range it may hand out) and lends it for the **lease time**. The device usually keeps it while it stays on the network, but nothing promises that | Phones, laptops, guests |

A MAC address is the hardware address of one network interface, such as `02:00:00:00:00:21`. A reservation is keyed on it.

**The one rule.** A device needs a fixed address when **anything else refers to it by address**, or by a DNS name that you maintain by hand. Examples: a Homebridge plugin that lists a switch by IP, a camera URL, a port forward, a line in Pi-hole's local names, a hosts file. If nothing refers to the device, a dynamic lease is fine.

**Why addresses change at all.** A device that was off for longer than the lease time loses its claim. A router reset empties the lease table. A device that rotates its MAC address looks like a new device. Each of these gives a device a new address, and whatever pointed at the old one fails. The failures arrive one device at a time and look like Wi-Fi faults.

**Two different things move Wi-Fi clients between ASUS units,** which is why this page also covers roaming. That part is separate from addressing and has its own section, [Roaming exclusions](#roaming-exclusions).

## Before you start

Decide these first.

| Decision | Recommendation |
| --- | --- |
| Which block each kind of device goes in | The layout below. Adapt the sizes, keep the idea |
| Whether to renumber at all | Optional. Phase 1 (reserve everything where it is now) removes the breakage. Renumbering into blocks only makes the network easier to read |
| Where the plan is written down | One file, kept with your other notes. Wherever you keep it, the router's reservation list is the truth and the file is the explanation |
| Host naming | The convention in [Host naming](#host-naming) |

Take a backup of the router's lists before changing them. On the XT8 this is the `backup` command in [ASUS ZenWiFi XT8](../hardware/asus-zenwifi-xt8.md), Step 6; it saves the reservation list (`dhcp_staticlist`), the hostnames and the client names.

### Recommended block layout: main LAN

This layout agrees with the fixed addresses used across the wiki (see [Conventions](../start-here/conventions.md)).

| Range | Use | How the address is set | In the DHCP pool? |
| --- | --- | --- | --- |
| `192.168.50.1` | Router | Static on the device | No |
| `.2` to `.9` | Infrastructure and servers: access points (`ap-openwrt` `.3`, `ap-stock` `.4`), cluster servers (`server-1` to `server-3`, `.5` to `.7`), an always-on media server | Static on the device | No |
| `.10` to `.19` | Floating and load-balancer addresses: the Kubernetes API address held by kube-vip (`.10`), MetalLB addresses (`.11` Pi-hole, `.12` Traefik, `.13` to `.15` spare). `.16` to `.19` stay free for more of the same | Set in the cluster's config. No device owns them | **Never** |
| `.20` to `.29` | Home hubs and streaming boxes (Apple TV, HomePod, other smart speakers) | Reservation | See the note below the table |
| `.30` to `.39` | Cameras, doorbells and recorders | Reservation | |
| `.40` to `.49` | Climate and hubs: thermostats, blinds hubs, robot vacuums | Reservation | |
| `.50` to `.59` | Game consoles and TVs | Reservation | |
| `.60` to `.79` | Smart plugs, bulbs and similar devices that are on the main LAN rather than the IoT network | Reservation | |
| `.80` to `.99` | Wired computers, printers, NAS | Reservation (or static on the device for a NAS) | |
| `.100` to `.199` | **Dynamic pool**: phones, laptops, tablets, watches, guests on the main network | Dynamic lease | Yes |
| `.200` to `.254` | Spare and lab: test machines, temporary static addresses, a future block | As needed | No |

The reasoning:

- **Fixed things low, changing things high.** You can tell what a device is from its address in a log line. `192.168.50.34` is a camera; `192.168.50.143` is somebody's phone.
- **Floating addresses get their own block outside every DHCP range.** No device asks for them, so the router has no record that they are in use. If one sits inside the pool, the router will sooner or later lend it to a phone, and then DNS or every web UI in the house breaks. See [Load balancers](../kubernetes/load-balancers.md).
- **Blocks of ten are easy to remember and big enough for a house.** A block that fills up spills into the spare range; it does not need to be contiguous.
- **One hundred dynamic addresses is plenty.** Count the phones, laptops, tablets and watches in the house, double it for guests and for devices with rotating private addresses, and round up.
- **A spare range costs nothing** and saves a second renumbering later.

How to adapt it:

- **A different subnet:** keep the last number, change the first three.
- **More of one kind than ten:** make that block bigger before you start. Changing a block later means renumbering the block after it.
- **No cluster:** `.10` to `.19` becomes a second infrastructure block. Keep it out of the pool anyway.
- **A machine that is already in the "wrong" place and hard to move:** leave it there and reserve it. A reserved address inside the dynamic range is safe; the router does not lend a reserved address to another device.

> **Pitfall:** do not move a k3s server to fit the plan. An etcd member (etcd is the cluster's database; each server is a member) is known to the others by its address. Changing a server's address means removing it from the cluster and joining it again; see [k3s HA cluster](../kubernetes/k3s-ha-cluster.md). In the wiki's example, `server-4` (a VM on a Mac) got `192.168.50.146` from DHCP, in the middle of the dynamic range. Reserve it at `.146` and leave it there. The same goes for an AiMesh node: the example one sits at `192.168.50.117`; reserve it where it is.

> **Note on the pool.** The wiki's router pages use a pool of `192.168.50.20` to `192.168.50.254`, which is the state before this plan. Whether you can shrink the pool to `.100` to `.199` and still reserve addresses in `.20` to `.99` depends on your router's interface, not on DHCP itself; see [Step 5](#step-5-shrink-the-dynamic-pool-if-your-router-allows-it). If it does not allow that, keep the wide pool. The blocks then still hold your reserved devices, and the only cost is that a phone may now and then get an unreserved address inside a block.

### Recommended block layout: IoT network

For the isolated network from [Isolated IoT network](isolated-iot-network.md).

| Range | Use | How the address is set |
| --- | --- | --- |
| `192.168.101.1` | Router side of the guest bridge | Set by the firmware |
| `.2` to `.19` | Leave unused | |
| `.20` to `.59` | Devices **controlled by IP address** from the main LAN, such as TP-Link Kasa switches listed in Homebridge. The wiki's examples use `192.168.101.20` and `.21` | Reservation, mandatory |
| `.60` to `.99` | Cloud-controlled plugs and bulbs that you want a stable name for (Wyze, Tuya and similar) | Reservation, optional |
| `.100` to `.254` | Everything else on the IoT network | Dynamic lease |

The low block is the one that matters. Everything in it is written down somewhere else by address, so it gets reserved first and is never left to chance.

> **Not verified:** on the ASUS firmware the guest network's own DHCP range is created by the firmware, and the author found no documented GUI setting to change it. Treat the IoT layout as a convention for which addresses you reserve, not as a pool you can resize.

### Which kinds of device need a fixed address

"Where else the address is written" is the list of places to update if the address ever changes.

| Kind of device | Fixed address? | Why | Where else the address is written |
| --- | --- | --- | --- |
| Router | Static on the device | It is the gateway and the DHCP server; everything else is configured relative to it | Every static device's gateway setting; scripts; bookmarks; Pi-hole local names |
| Access points and mesh nodes | Static on the device where the firmware allows it (an OpenWrt AP); reservation otherwise (a stock-firmware AP in AP mode, an AiMesh node) | You need to reach the admin page or SSH when things are broken | SSH config, reboot scripts, Pi-hole local names, backups |
| Cluster servers and etcd members | Static on the device, below the pool | Members find each other by address. They must come up when the router's DHCP is not ready | k3s config (`node-ip`, `server:`), router rules that name the servers (for example `HB_HOSTS` in the IoT rules), host firewall rules, DNS Director entries, Pi-hole local names |
| A VM that is a cluster member | Reservation, at the address it already has | Its address comes from the router by DHCP, keyed on the VM's MAC. If either changes, the node cannot rejoin | The VM definition (its MAC), k3s config, Pi-hole local names. See [Mac with a Lima VM](../hardware/mac-lima-vm.md) |
| Floating addresses (kube-vip, MetalLB) | Neither. **Never DHCP, always outside the pool** | No device asks for them, so the router cannot know they are taken | kube-vip and MetalLB config, the router's DHCP "DNS server" field, Pi-hole local names, TLS names |
| Pi-hole or any DNS server | Static, or a floating address outside the pool | Every device is told this address by DHCP and keeps it until its lease renews | Router DHCP settings, DNS Director, nodes' own resolver settings. See [DNS design](dns-design.md) |
| Port-forward targets | Reservation or static | A port forward names an internal address. If the address moves, the forward points at nothing, or at another device | The router's port-forwarding page |
| Cameras and recorders reached by RTSP | Reservation (or static in the camera's own settings) | The stream URL contains the address | Camera plugin config, recorder config. See [Homebridge cameras](../apps/homebridge-cameras.md) |
| Smart switches driven locally by IP (TP-Link Kasa through `homebridge-kasa-python` `manualDevices`, on the IoT network) | Reservation. **Mandatory** | Discovery broadcasts do not cross from the LAN to the IoT network, so each device is listed by address. When the address changes, Homebridge loses the device: the log shows `[Errno 113] Connect call failed`, `[Errno 111]` or "No sys_info returned ... Marking offline", and the accessory shows "No Response" in the Home app until the list is corrected | The plugin's `manualDevices` list; Pi-hole local names. See [Kasa devices across networks](../apps/homebridge-kasa-across-networks.md) |
| Cloud-driven plugs and bulbs (Wyze, Tuya) | Optional | They call out to the maker's cloud and nothing at home addresses them. Reserve only if you want a stable name in logs and client lists | Pi-hole local names, if you named them |
| HomeKit hubs (Apple TV, HomePod) | Reservation, recommended | Nothing addresses them by IP (HomeKit finds them by Bonjour), but a stable address makes router logs, per-device rules and troubleshooting readable | Pi-hole local names |
| Thermostats, blinds hubs, robot vacuums | Reservation if a local integration talks to them by address; otherwise optional | Local plugins usually take an address. Cloud-only ones do not care | The plugin or integration config; Pi-hole local names |
| Printers and NAS | Reservation; static on the device is also fine for a NAS | Computers remember a printer or a share by address or by a name you maintain | Printer queues, mounted shares, backup jobs, Pi-hole local names |
| Game consoles | Reservation if you forward ports to the console or it reports a strict NAT type; otherwise optional | Port forwards need a fixed target | The router's port-forwarding page |
| Devices with a per-device DNS rule on the router (DNS Director) | No fixed IP needed for the rule | The rule is keyed by MAC address, not by IP. Such a device often needs a fixed address for another reason (a cluster node, for example) | The DNS Director client list |
| Anything you gave a name in Pi-hole | Reservation or static | A local name is a fixed line "address, name". When the device gets another address, the name still answers, with the old address | `additionalHostsEntries` in [`files/pihole/values.yaml`](../../files/pihole/values.yaml) |
| Phones, tablets, laptops, watches | **No** | They come and go, nothing addresses them, and many use private MAC addresses (below), so a reservation may not even match | Nowhere. Do not give them Pi-hole names either |
| Guests | **No** | Same, and you will never see them again | Nowhere |

#### Private (randomised) MAC addresses

A reservation matches on the MAC address. Modern phones, tablets, watches and laptops do not show a network their real hardware address. They make one up, per network, so they are harder to track.

- **Apple** (iOS, iPadOS, watchOS, and macOS 15 or later): the setting is "Private Wi-Fi Address", **per network**. On iOS 18, iPadOS 18, macOS 15 and watchOS 11 or later the choices are **Off** (hardware address), **Fixed** (a made-up address that stays the same for that network; the default on networks using WPA2 or stronger) and **Rotating** (changes every two weeks; the default on weakly secured networks). See [Apple's page](https://support.apple.com/en-us/102509).
- **Android** (10 or later): "MAC randomization" or "Privacy" in each network's details, **per network**. By default the made-up address is persistent for that network. Android 12 or later can also use a non-persistent address in some cases, which is renewed after about a day. See [the Android documentation](https://source.android.com/docs/core/connect/wifi-mac-randomization-behavior).

What follows from this:

- A device on a **fixed** private address can be reserved like any other, using the private address the router sees. The reservation breaks if you forget the network and the address changes, or if you change the SSID (the address is derived per network name).
- A device on a **rotating** address will not match a reservation for long. It also uses up a new lease each time, which is one reason to keep the dynamic pool generous.
- **How to recognise one:** a made-up address is "locally administered". Look at the **second hex digit** of the MAC. If it is `2`, `6`, `A` or `E` (as in `d6:1f:...` or `3a:0c:...`), the address is not a manufacturer's address. The router usually cannot show a vendor name for it either.
- For the rare phone or laptop that really needs a reservation, set its private address to **Off** or **Fixed** for your home network only, then reserve what the router shows.

The made-up example addresses in this wiki start `02:` for the same reason: `02` marks a locally administered address that belongs to no manufacturer.

## Steps

The order matters. Phases 1 and 2 are separate on purpose: after phase 1 nothing can break any more, and you can stop there.

### Step 1. Export the client list and build an inventory

You need one line per device: MAC address, current address, name, and which network it is on.

On an ASUS router, open the client list (Network Map > View List) and use its export button if your firmware has one. Or read the lease table directly.

**Run on: the router**

```sh
cat /var/lib/misc/dnsmasq.leases
```

Each line is: expiry time (seconds since 1970), MAC address, IP address, the name the device announced (`*` if none), and a client ID. Devices with a static address set on the device do **not** appear here, because they never asked. List what the router can see on the wire to find those:

```sh
arp -a
nvram get dhcp_staticlist
```

The first command prints every address the router has recently talked to, with its MAC. The second prints the reservations that already exist (empty if there are none).

> **Not verified:** the lease file path is the usual one on Asuswrt-Merlin. If it is missing, run `ps | grep dnsmasq` and `grep -i lease /etc/dnsmasq.conf` to find where your firmware keeps it. With YazDHCP installed, reservations are kept in files under `/jffs/addons/YazDHCP.d/` instead of in `dhcp_staticlist`.

Put the result in a spreadsheet or text file with these columns:

| Column | Example |
| --- | --- |
| Name you will use | `kitchen-switch` |
| MAC | `02:00:00:00:00:21` |
| Network | IoT |
| Address now | `192.168.101.137` |
| Kind (from the table above) | Switch driven by IP |
| Needs a fixed address? | Yes, mandatory |
| Planned address | `192.168.101.20` |
| Where else the address is written | Homebridge `manualDevices`, Pi-hole |

Identify unknown devices before you go on. Switch a device off and see which line disappears, or look the MAC's first three bytes up in a vendor database. A locally administered MAC (second hex digit `2`, `6`, `A` or `E`) is a phone, tablet, watch or laptop using a private address.

> **Pitfall:** keep this file out of public Git. A list of MAC addresses, device names and rooms describes your household.

### Step 2. Find the pool, the lease time and the limits

**Run on: the router**

```sh
nvram get dhcp_start
nvram get dhcp_end
nvram get dhcp_lease
grep dhcp-range /etc/dnsmasq.conf
```

The first two print the main pool, for example `192.168.50.20` and `192.168.50.254`. The third prints the lease time in seconds (`86400` is one day). The last prints the ranges dnsmasq is really using, one per network; with an ASUS guest network you should see a second line for `192.168.101.x`.

Write these down. You need the lease time in Step 4 to know how long a device may hold on to its old address.

### Step 3. Phase 1, zero risk: reserve every fixed-role device at the address it has now

For every device your inventory marks as needing a fixed address, add a reservation for **its current address**. Nothing moves, so nothing can break. From this moment the address can no longer change by accident.

On Asuswrt-Merlin:

1. Open **LAN > DHCP Server**.
2. Set **Enable Manual Assignment** to **Yes**.
3. Under **Manually Assigned IP around the DHCP list**, pick the device from the drop-down (or type its MAC), enter the address it has now, optionally a host name, and click the **+** button.
4. Repeat for each device, then click **Apply**. The router restarts its DHCP service; devices stay connected.

Things to know about that page:

| Point | Detail |
| --- | --- |
| Entry limit | The stock list is limited; the page shows the maximum for your model (ASUS's example shows 128). The limit comes from how much the firmware can store in one setting |
| YazDHCP | The [YazDHCP](https://github.com/jackyaz/YazDHCP) add-on (installed through amtm) keeps reservations in files under `/jffs/addons/YazDHCP.d/` instead, which raises the limit. It replaces the list on the same LAN > DHCP Server page and also has a command-line menu (`YazDHCP`). Use it if you have more reservations than the stock list holds |
| Editing | ASUS documents that the stock web page cannot edit an entry: delete it, apply, and add it again |
| Devices on the guest/IoT network | Reservations for `192.168.101.x` devices go in the **same list**. Confirmed on GNUton Asuswrt-Merlin 3004.388.10_2 with YazDHCP: a dozen smart switches entered there with `192.168.101.x` addresses and host names hold exactly those addresses |
| Static-on-device machines | Also add a reservation for each one at its static address, if the page accepts it. The device never uses it, but the router then knows not to hand that address to anyone else |

> **Confirmed with YazDHCP; not verified without it:** the entries above were made in YazDHCP's list (limit 240). Whether the firmware's built-in Manually Assigned IP page accepts an address outside the main LAN's subnet was not tried. ASUS's own FAQ says a reserved address must be inside the DHCP server's pool, so the built-in page may refuse it; if it does, install YazDHCP.

Then take a backup of the lists again (Step 6 of [ASUS ZenWiFi XT8](../hardware/asus-zenwifi-xt8.md)). A factory reset empties the reservation list, and this backup is what puts it back.

**Check before going on:** every mandatory device in your inventory has a reservation, and each one still answers at its address.

### Step 4. Phase 2, optional: renumber into blocks, one category at a time

Only do this if you want the tidy layout. Move **one category** per session (for example, all cameras), and finish it before starting the next.

For each device in the category:

1. **List every place its address is written.** Use the last column of the table above. The usual ones:

   | Place | Where |
   | --- | --- |
   | Pi-hole local names | `additionalHostsEntries` in [`files/pihole/values.yaml`](../../files/pihole/values.yaml); see [Pi-hole](../apps/pihole.md) |
   | Homebridge Kasa plugin | `manualDevices` in the plugin config; see [Kasa devices across networks](../apps/homebridge-kasa-across-networks.md) |
   | Camera URLs | `source` and `stillImageSource` in the camera plugin config; see [Homebridge cameras](../apps/homebridge-cameras.md) |
   | Port forwards | WAN > Virtual Server / Port Forwarding on the router |
   | Hosts files | On client machines; see [Client devices](../apps/client-devices.md) |
   | Router rules and scripts | Anything in `/jffs/scripts/` that names an address, for example `HB_HOSTS` in [`homenet.conf`](../../files/xt8/jffs-scripts/homenet.conf) |
   | Host firewalls | Rules that allow a named address |

2. **Check the new address is free.**

   **Run on: your computer**

   ```sh
   ping -c 2 192.168.50.30
   ```

   No reply is what you want. Also check that the address is not in the router's lease table from Step 1.

3. **Change the reservation** on the router to the new address and apply.

4. **Make the device ask again.** A device keeps its old address until it next talks to the DHCP server. Any of these works:
   - turn the device's Wi-Fi off and on, or unplug and replug its network cable;
   - restart the device (for a smart plug: power it off and on);
   - wait. A device renews halfway through its lease, so within half the lease time from Step 2 the router refuses the old address and the device takes the new one.

5. **Update every place from item 1** straight away. For Pi-hole names, edit the values file and apply it:

   **Run on: server-1**, from the root of this repo

   ```bash
   helm upgrade --install pihole mojo2600/pihole -n pihole --version 2.38.0 -f files/pihole/values.yaml
   ```

   For Homebridge, edit the plugin's config in the Homebridge UI and restart Homebridge.

6. **Check that device** before touching the next one:

   **Run on: your computer**

   ```sh
   ping -c 3 192.168.50.30
   dig +short living-room-camera.home.example.com @192.168.50.11
   ```

   The ping must answer and the name must print the **new** address. Then check the thing that uses the device: the camera shows a picture, the switch toggles from the Home app, the forwarded port answers from outside.

For devices where the order matters:

| Device | Order |
| --- | --- |
| A device another system polls constantly (Kasa switches, cameras) | Move the device first, update the config right after. The gap is a minute of "No Response" |
| A port-forward target | Update the forward right after the device has its new address. Until then the forward points at an unused address, which is safe |
| A DNS server, the router, a floating address | Do not renumber these as part of this page. They are already in the plan's fixed blocks; moving them touches every device in the house |
| A cluster server | Do not move it. Reserve it where it is |

### Step 5. Shrink the dynamic pool, if your router allows it

Do this **last**, after every reserved device is in its block.

Whether a reservation may sit outside the pool depends on which layer you ask:

| Layer | What it says |
| --- | --- |
| dnsmasq, the DHCP server underneath | Allowed. The [dnsmasq manual](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html) says of `--dhcp-host`: "Addresses allocated like this are not constrained to be in the range given by the --dhcp-range option, but they must be in the same subnet as some valid dhcp-range" |
| The ASUS web interface | The [ASUS FAQ on manual assignment](https://www.asus.com/support/faq/1000906/) says: "Please make sure the IP address needs to be in the IP pool of your DHCP server" |

> **Not verified:** whether the Asuswrt-Merlin page (or YazDHCP's version of it) actually refuses a reserved address outside the pool was not tested by the author. Test it with one device before relying on it.

So test, then choose:

1. Take one reserved device in `.20` to `.99`. Note its reservation.
2. On **LAN > DHCP Server**, set **IP Pool Starting Address** to `192.168.50.100` and **IP Pool Ending Address** to `192.168.50.199`. Apply.
3. If the page refuses because of the existing reservations, or the test device stops getting its reserved address after a reconnect, put the pool back to its old range. Keep the wide pool; the plan still works as a convention.
4. If the device still gets its reserved address, the narrow pool is in force. Dynamic clients move into `.100` to `.199` as their leases renew.

Whatever the pool ends up as, these must hold:

- `192.168.50.10` to `.19` (floating addresses) are outside it.
- Every address that is set statically on a device is either outside it or has a matching reservation.

### Step 6. Record the plan

Write down, in the file from Step 1:

- the block table (which range is for what);
- for each reserved device: name, MAC, address, kind, and where else the address is written;
- the pool, the lease time, and the date you last compared the file with the router.

Then take the router backup again. If you keep Pi-hole local names, mark each line `[static]` in the values file once the device is reserved, as described in [Pi-hole](../apps/pihole.md).

### On OpenWrt or another dnsmasq router

The plan and the phases are the same. Only the screens differ.

In LuCI (OpenWrt's web interface): **Network > DHCP and DNS > Static Leases**, add a lease with the host name, MAC address and IPv4 address, then **Save & Apply**. The pool is under **Network > Interfaces > LAN > Edit > DHCP Server**, as a start number and a count ("Start" 100, "Limit" 100 gives `.100` to `.199`), with the lease time beside it.

From the command line:

**Run on: the OpenWrt router**

```sh
uci add dhcp host
uci set dhcp.@host[-1].name='printer'
uci set dhcp.@host[-1].mac='02:00:00:00:00:21'
uci set dhcp.@host[-1].ip='192.168.1.80'
uci commit dhcp
service dnsmasq restart
```

This adds one static lease to `/etc/config/dhcp` and restarts dnsmasq so that it reads it.

> **Not verified:** the OpenWrt steps were not run by the author, and the OpenWrt wiki pages for them could not be opened to check the menu names against the current release. The OpenWrt device in this wiki is a bridged access point with its DHCP server switched off ([Archer A7 on OpenWrt](../hardware/tp-link-archer-a7-openwrt.md)), so none of this applies to it; reservations belong on whichever device is your DHCP server.

In plain dnsmasq terms, for any other firmware, a reservation is one `dhcp-host` line and the pool is one `dhcp-range` line:

```sh
dhcp-range=192.168.50.100,192.168.50.199,255.255.255.0,24h
dhcp-host=02:00:00:00:00:21,192.168.50.80,printer
```

## Host naming

A name is used in three places: the router's client list, the name the device announces by DHCP, and the DNS name in Pi-hole. Make them the same string, so that a log line on any of the three leads you to the same device.

| Rule | Example | Why |
| --- | --- | --- |
| Lower case, letters, digits and hyphens only | `living-room-tv` | Valid everywhere a host name is used. No spaces, underscores or apostrophes |
| `<room>-<thing>` | `kitchen-switch`, `office-printer`, `hall-thermostat` | You find a device by where it is |
| No owner names | `bedroom-2-tv`, not a person's name | Names end up in logs, backups and screenshots. Rooms change hands less often than devices |
| Suffix by kind where it helps | `-cam`, `-switch`, `-plug`, `-bulb`, `-tv`, `-atv`, `-ap` | Sorting and filtering |
| A number only when there are two alike | `garage-cam-1`, `garage-cam-2` | |
| Never a name for a phone, watch or guest | | Their address is not fixed, so the name would go stale |

Where each name is set:

| Place | How |
| --- | --- |
| Router client list | Click the device in the client list and rename it (stored in `custom_clientlist` on ASUS) |
| DHCP host name | The host name column of the reservation (stored in `dhcp_hostnames` on ASUS, or in YazDHCP's files). Many small devices announce a meaningless name of their own; the reservation's name overrides what the router serves |
| Pi-hole | One line in `additionalHostsEntries`: `<address>  <name>  <name>.home.example.com` |

> **Pitfall:** do not rename a cluster node to fit the convention. A k3s node's name is part of its identity in the cluster and in etcd; changing the host name creates what looks like a new node. Kubernetes also lower-cases node names, so a host name with capitals already gives two spellings of one machine. Leave `server-1` and its siblings alone, and add a second DNS name in Pi-hole if you want a friendlier one.

> **Pitfall:** if a device asks for a different address than the one reserved for its name, the router logs "not giving name X to the DHCP lease of ... because the name exists in ... .hostnames with address ...". That is brief noise during a move. If it continues, the reservation and the device disagree; see [Router logging](router-logging.md).

## Roaming exclusions

This part is about Wi-Fi, not addresses. It belongs here because it uses the same inventory, and because its symptoms ("the plug went offline again") are easy to mistake for address problems.

### What moves a client

On an ASUS mesh, two separate mechanisms push a Wi-Fi client from one unit to another:

| Mechanism | What it does | Where it is set |
| --- | --- | --- |
| **Roaming Assistant** | Disconnects any client whose signal (RSSI, in dBm; closer to zero is stronger) is weaker than a threshold, in the hope that it reconnects to a nearer unit. ASUS's default is -70 dBm | Wireless > Professional, per band. The wiki recommends -70 dBm on all bands (2.4 GHz may be -72 to -75); see [ASUS ZenWiFi XT8](../hardware/asus-zenwifi-xt8.md) |
| **AiMesh steering** | The mesh decides a client would be better off on another unit and tells it to move, or disconnects it so that it does | Part of AiMesh; no single switch |

Both are useful for a phone that walks from one end of the house to the other. Both are harmful for a device that never moves: a plug behind a sofa with a weak but perfectly usable signal is disconnected again and again, and each time it has to rejoin, get its address and reconnect to its cloud or to Homebridge.

**Observed on this hardware.** Over three weeks, with the threshold already at -70 dBm, the roaming assistant logged about 250 "disconnect weak signal strength station" events, and the kernel logged thousands of "not mesh client, can't update it's ip" lines. Most of both were for stationary smart-home devices, not for phones. With the threshold at -55 dBm the disconnects were about 25 a day. How to count these lines in your own log is in [Router logging](router-logging.md).

### The Roaming Block List

ASUS provides a list of devices that AiMesh leaves alone. From the [ASUS FAQ on the Roaming Block List](https://www.asus.com/support/faq/1039647/):

- "Those devices on the list will no longer have AiMesh roaming active."
- The device can still move by its own decision: "AiMesh will not trigger roaming, however device will do self roaming to a better mesh node."
- You enable the list, pick a device by client name or type its MAC address, click **+**, and apply. ASUS notes that applying requires a router reboot.
- The page is in the web interface under the wireless settings as **Roaming Block List** (ASUS gives the address `http://www.asusrouter.com/Advanced_Roaming_Block_Content.asp`).

What the FAQ does **not** say:

> **Not verified:** the FAQ documents no maximum number of entries. It speaks only of "AiMesh roaming" and does not say whether a listed device is also exempt from the Roaming Assistant's signal threshold. It does not say whether the list applies to clients of a guest network, such as devices on `Home-IoT`. The author has not used the list. After adding devices, count the "disconnect weak signal strength station" lines for those MAC addresses over a few days to find out what it exempts on your firmware.

### Binding a client to one unit

AiMesh can also pin a client to a chosen unit. From the [ASUS FAQ on binding](https://www.asus.com/support/FAQ/1046957):

- In the web interface: **AiMesh > Topology**, find the device in the client list on the right, click **Bind**, choose the unit, **OK**. The icon turns white when the device is bound; click it again to unbind. The ASUS Router app has the same under Devices.
- It needs firmware later than 3.0.0.4.386. ASUS lists ZenWiFi AC models (CD6, CT8) as unsupported.
- A binding is a preference, not a lock. If the chosen unit's signal is too weak or the unit is off, the mesh connects the device to another unit.

> **Not verified:** the author has not used binding, and the FAQ does not say whether it works for guest-network clients or survives a firmware update.

Use binding when a device keeps choosing the wrong unit (a TV that clings to the far node). Use the block list when the device is on the right unit and the mesh keeps disturbing it.

### Which kinds of device to put on the block list

| Kind of device | Block list? | Why |
| --- | --- | --- |
| Stationary smart plugs, switches, bulbs and LED strips | Yes | They never move. Their radios are weak and often sit below the threshold while working fine |
| Cameras and doorbells on Wi-Fi | Yes | A disconnect drops the video stream and a doorbell press can be missed while it rejoins |
| Thermostats | Yes | Fixed to a wall; a dropped cloud session shows as "offline" in the app |
| Smart speakers and streaming boxes on Wi-Fi | Yes | Fixed in place; a disconnect interrupts playback, and a HomeKit hub that drops takes remote access with it |
| TVs | Yes | Fixed in place; a disconnect interrupts streaming |
| Blinds hubs and other hubs | Yes | Fixed, and every device behind the hub goes offline with it |
| Printers | Yes | Fixed; a printer that was kicked is often "offline" until woken by hand |
| Game consoles that stay docked | Yes | A disconnect in the middle of a game or download |
| Anything that takes minutes to rejoin, or drops its cloud session when deauthenticated | Yes | The cost of each forced move is far higher than any gain from a slightly better signal |
| Phones, tablets, laptops, watches, anything carried around | **No** | These are the devices roaming is for. On the list, they cling to a distant unit as you walk away |
| A handheld console | No | It is carried around |
| A robot vacuum | Judgement call | It moves, but slowly, and many handle being kicked badly: they stop mid-run or lose the map upload. If it covers one floor near one unit, list it. If it crosses the house, leave it off and see how it behaves |

Take the MAC addresses from your inventory. A device with a rotating private address cannot be listed usefully, which does not matter because those are the devices that should roam.

### On an access point that is not part of the mesh

A second access point of another brand is not steered by AiMesh at all. Devices choose between it and the mesh units by themselves, because the network name and password match (see "Roaming" in [Isolated IoT network](isolated-iot-network.md)). Some stationary devices choose badly and hold on to the farther transmitter.

The complementary tool there is a **MAC deny list on that access point's SSID**: the listed devices are refused by that access point, so they can only join the nearer unit. On OpenWrt this is the MAC filter on the wireless interface (in LuCI: Network > Wireless > Edit on the SSID > MAC-Filter tab; in the config file, `option macfilter 'deny'` with a `maclist`). See [Archer A7 on OpenWrt](../hardware/tp-link-archer-a7-openwrt.md), Step 6. The author's access point carries such lists on both of its main SSIDs.

> **Pitfall:** a deny list is **per SSID**, and per radio. A new SSID starts with none. When you add the IoT SSID to the access point, the devices you had kept off its main SSID are free to join the new one there. Copy the entries across if they apply.

> **Pitfall:** on that access point the deny lists exist only in the device's own configuration and its settings backup. Nothing in this repo recreates them.

> **Pitfall:** a deny list and a block list do opposite jobs. A deny list keeps a device **off** one transmitter. A block list stops the mesh from **moving** a device. Do not deny a device on every transmitter; it then has no Wi-Fi at all.

## Check it

**Reservations are in place.**

**Run on: the router**

```sh
nvram get dhcp_start; nvram get dhcp_end
grep -c . /var/lib/misc/dnsmasq.leases
```

The first line prints the pool you chose. The second prints how many leases are live. With YazDHCP, also open its page and confirm the entry count matches your inventory.

**A reserved device gets its reserved address.** Restart one device from each category and look it up in the lease table by MAC:

```sh
grep -i "02:00:00:00:00:21" /var/lib/misc/dnsmasq.leases
```

It must print one line with the reserved address.

**No floating address is in the lease table.**

```sh
grep -E " 192\.168\.50\.1[0-9] " /var/lib/misc/dnsmasq.leases
```

This must print nothing.

**Names match addresses.**

**Run on: your computer**

```sh
dig +short living-room-camera.home.example.com @192.168.50.11
ping -c 2 living-room-camera.home.example.com
```

The first prints the reserved address; the second gets replies from it.

**Devices driven by IP still answer.** For a Kasa switch on the IoT network:

**Run on: server-1** (or whichever host runs Homebridge)

```sh
ping -c 3 192.168.101.20
nc -vz -w 3 192.168.101.20 9999
```

Both must succeed. Then toggle the switch from the Home app.

**Roaming exclusions work.** A few days after adding devices to the Roaming Block List, count the disconnects for one of them:

**Run on: the router**

```sh
grep -i "disconnect weak signal strength station" /tmp/syslog.log | grep -ci "02:00:00:00:00:21"
```

Expect `0` or close to it. If you use Scribe, the log is at `/opt/var/log/messages` instead; see [Router logging](router-logging.md).

## Pitfalls

| What happens | Why | How to avoid or recover |
| --- | --- | --- |
| You shrink the pool first, and devices lose their network one by one over the next day | Devices outside the new pool are refused when they renew. Unreserved ones get a new address, and everything that pointed at the old one fails | Shrink the pool **last** (Step 5). To recover, put the pool back, then do phase 1 |
| Two devices fight over one address: both drop in and out | A device has an address set statically on itself, and that address is also inside the dynamic pool. The router does not know it is taken and lends it to someone else | Keep static-on-device addresses outside the pool, or add a matching reservation for each. dnsmasq's check before lending an address does not catch a device that is switched off at that moment |
| You changed a reservation and the device still has the old address | It holds its lease until it next asks | Reconnect or restart the device, or wait up to half the lease time |
| You changed a reservation, the device moved, and the name still gives the old address | The Pi-hole line was not updated, or your computer cached the answer | Update `additionalHostsEntries` and run the upgrade command; flush the computer's DNS cache |
| A phone ignores its reservation | It uses a private MAC address, so the router sees a different MAC from the one you reserved | Reserve the private address the router shows, with the phone set to Fixed; or do not reserve phones |
| A floating address is handed to a phone; DNS or all web UIs stop | The floating block is inside the pool | Keep `.10` to `.19` out of every DHCP range |
| A cluster server is renumbered and never rejoins | etcd members are known by address | Do not renumber it. If it happened, see [k3s HA cluster](../kubernetes/k3s-ha-cluster.md) |
| Devices on automatic addresses work for weeks, then fail one at a time with timeouts that look like Wi-Fi faults | A lease changed | Phase 1 |
| Reservations vanish after a router reset | They are stored in the router's settings (or YazDHCP's files) | Back up the lists after every change; restore as in [ASUS ZenWiFi XT8](../hardware/asus-zenwifi-xt8.md), Step 5 |
| The reservation list is full | The stock list has a fixed maximum | Install YazDHCP, or reserve only what the table says needs it |
| You renumber ten devices at once and cannot tell which change broke what | Too many moving parts | One category per session, one check per device |
| The MAC of a VM changes after a rebuild and its reservation no longer matches | The VM definition generated a new MAC | Pin the MAC in the VM definition; see [Mac with a Lima VM](../hardware/mac-lima-vm.md) |
| A wired and a Wi-Fi interface on the same machine | Each has its own MAC and needs its own reservation, at different addresses | Reserve the one you use; note both in the inventory |
| A phone on the Roaming Block List holds on to a far unit | The mesh no longer nudges it | Take carried devices off the list |
| A device is on a deny list on every access point | It cannot join anywhere | Deny it only on the transmitter you want it to avoid |
| Applying the Roaming Block List reboots the router | Documented by ASUS | Do it when nobody is in a call |

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Duplicate IP: a device drops in and out, a computer warns "another device is using your IP address", or `arp -a` shows one address with a MAC that keeps changing | A static-on-device address is also in the pool, or two reservations or two static settings use the same address | Find both MACs (`arp -a` on the router, repeated a few times). Move the static one out of the pool or reserve it; correct the duplicate entry. Restart both devices |
| A device ignores its reservation | It uses a private (randomised) MAC, so the reservation's MAC never appears | Compare the MAC in the lease table with the one you reserved. Set the device's private address to Fixed or Off for this network and reserve what the router shows |
| A device ignores its reservation and its MAC is right | It still holds its old lease | Reconnect or restart it, or wait up to half the lease time. `DHCPNAK` lines for its MAC in the router log are the router refusing the old address, which is the move happening |
| A device ignores its reservation, MAC right, restarted | The address is set statically on the device, so it never asks | Switch the device to automatic (DHCP) addressing |
| A reservation outside the pool is refused or has no effect | The router's page requires addresses inside the pool | Widen the pool again (Step 5) |
| A name resolves to the old address | The Pi-hole local name was not updated; or the answer is cached | Fix the line in [`files/pihole/values.yaml`](../../files/pihole/values.yaml) and run the upgrade command. Check with `dig +short <name> @192.168.50.11`. Flush the client's cache (on macOS: `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`) |
| A name resolves to two addresses | Two lines for the same name, one stale | Remove the old line |
| A Kasa device is unreachable after renumbering; log shows `[Errno 113] Connect call failed`, `[Errno 111]` or "Marking offline" | `manualDevices` still lists the old address; or the device has not yet taken the new one | Power the device off and on, confirm the new address with `ping` and `nc -vz -w 3 <address> 9999`, correct `manualDevices`, restart Homebridge |
| A Kasa device answers ping at the new address but times out on port 9999 | Not an address problem: the router rule that lets replies out of the guest network is missing | [Kasa devices across networks](../apps/homebridge-kasa-across-networks.md), Troubleshooting |
| A camera shows no picture after renumbering | The stream URL has the old address | Update `source` and `stillImageSource`; restart Homebridge |
| A port forward stopped working | It names the old internal address | Update it on the router |
| A phone gets a new address every couple of weeks | Rotating private address | Expected. Do not reserve it |
| The router log says "not giving name X to the DHCP lease of ..." | A device asked for an address other than the one reserved for that name | Brief noise during a move. If it continues, make the reservation and the device agree |
| The dynamic pool runs out; new devices cannot join | Pool too small for the number of devices plus rotating private addresses, with a long lease time | Widen the pool or shorten the lease time |
| A stationary device still drops off Wi-Fi many times a day after going on the Roaming Block List | The Roaming Assistant threshold still applies to it (not verified either way), or the signal really is too weak | Check the threshold is -70 dBm or lower; move the device or the unit; bind the device to the nearer unit |
| A stationary device keeps joining the far access point | It chooses by itself and chooses badly | Bind it (AiMesh), or deny it on the far access point's SSID (non-mesh AP) |

## Undo

- **A single reservation:** delete the entry and apply. The device keeps its current address until its lease runs out, then gets one from the pool.
- **The pool:** set the start and end back to what they were (`192.168.50.20` to `192.168.50.254` in the wiki's router pages).
- **Everything, on ASUS:** restore the lists from the backup you took before Step 3, as in [ASUS ZenWiFi XT8](../hardware/asus-zenwifi-xt8.md), Step 5.
- **A renumbered device:** change its reservation back, make it reconnect, and put the old address back in every place you edited. Your inventory's "address before" column is what makes this possible, so keep it.
- **Roaming Block List:** remove the entries or switch the list off, and apply (the router reboots). **Binding:** click the white icon to unbind.
- **A MAC deny list on an access point:** remove the entries, or set the filter to disabled, on that SSID.

Going back to "everything automatic" brings back the original problem. Phase 1 on its own has no downside worth undoing.

## References

- [dnsmasq manual page](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html): `--dhcp-range` and `--dhcp-host`, including the sentence that a reserved address need not be inside the range but must be in the same subnet as one, and the default lease time.
- [ASUS FAQ: How to manually assign LAN IP around the DHCP list](https://www.asus.com/support/faq/1000906/): the LAN > DHCP Server manual-assignment list, its entry limit, and ASUS's statement that the address must be inside the pool.
- [YazDHCP on GitHub](https://github.com/jackyaz/YazDHCP): the Asuswrt-Merlin add-on that moves reservations into files under `/jffs/addons/YazDHCP.d/` to raise the limit.
- [Asuswrt-Merlin wiki: Custom config files](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Custom-config-files): `dnsmasq.conf.add` and `dnsmasq.postconf`, for adding dnsmasq lines the web interface does not offer.
- [ASUS FAQ: What is Roaming Block list? How does it work?](https://www.asus.com/support/faq/1039647/): what the list exempts (AiMesh-triggered roaming) and how to add devices.
- [ASUS FAQ: How to bind my device to one specific AiMesh router or AiMesh node](https://www.asus.com/support/FAQ/1046957): binding in AiMesh > Topology and in the app, its firmware requirement and its limits.
- [ASUS FAQ: How to enable the Roaming Assistant](https://www.asus.com/support/faq/1036730/): where the threshold is set and the -70 dBm default.
- [Apple: Use private Wi-Fi addresses on Apple devices](https://support.apple.com/en-us/102509): Off, Fixed and Rotating, per network, and how to change it.
- [Android: MAC randomization behavior](https://source.android.com/docs/core/connect/wifi-mac-randomization-behavior): persistent and non-persistent randomised addresses and the per-network setting.
