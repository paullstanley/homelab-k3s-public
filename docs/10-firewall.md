# 10. Host firewall on the k3s nodes

`firewall/k3s-firewall.sh` sets up `ufw` on one node. **As of the evening of 4 October it is active on all three Pis.** The Mac VM was not checked. It had been switched off earlier that day during the Pi-hole login troubleshooting and was turned back on afterwards.

**The live Pis were patched by hand** with `sudo ufw allow from 192.168.0.0/16` after the script (which then said 192.168.50.0/24) had run. The script in this repo now uses the /16 itself, so re-running it gives the same result.

## What it allows and blocks

| Traffic | Result |
| --- | --- |
| From the other cluster nodes (.5, .6, .7, .146 and their IPv6 addresses) | Everything allowed |
| From the pod and service ranges, and on `cni0`, `flannel.1`, `flannel-v6.1` | Everything allowed |
| Forwarded traffic (to pods and services) | Allowed (`default allow routed`). **Without this Kubernetes networking stops** |
| etcd 2379-2380, kubelet 10250, flannel 8472/udp, MetalLB 7946 from anyone else | Blocked |
| Everything else from 192.168.0.0/16 (main LAN 192.168.50.x, VPN subnet 192.168.0.x, IoT 192.168.101.x), the LAN's IPv6 range and link-local | Allowed: SSH, the API on 6443, DNS, Traefik, Homebridge, HomeKit discovery |
| IoT devices specifically | Covered by the /16 on every node, so Kasa and Wyze devices can answer Homebridge. Still blocked from the cluster-internal ports |
| Lima VM only: anything on `eth0` | Allowed. That is Lima's private link to the Mac; without it `limactl shell` stops working |
| Anything else inbound | Blocked |

The point is modest: a device on the LAN or the IoT network can use the services but cannot talk to etcd, the kubelet or the cluster's internal network.

## Step 1. Run it, one node at a time

Do the nodes in this order: **funkyfresh, k3snode2, the Mac VM, k3sprimary last** (k3sprimary carries Homebridge and the tunnel, so it has the most to break).

**Paste on: your Mac**, in the root of this repo. Change the address for each node.

```bash
scp firewall/k3s-firewall.sh pi@192.168.50.6:/tmp/
```

**Paste on: that node.**

```bash
sudo bash /tmp/k3s-firewall.sh
```

For the Mac VM, copy the file's contents into the VM (`limactl shell k3s-mac`, then `nano /tmp/k3s-firewall.sh`, paste, save) and run the same line there.

The script prints the rules and tells you the firewall will switch itself **off again in 10 minutes**.

## Step 2. Check, within the 10 minutes

**Paste on: k3sprimary.**

```bash
sudo kubectl get nodes
sudo kubectl get pods -A | grep -v -E 'Running|Completed'
nslookup example.com 192.168.50.11
curl -sI -H 'Host: pihole.home.example.com' http://192.168.50.12/admin/ | head -1
```

All nodes `Ready`, no pods in a bad state, a DNS answer, and `301`. After doing k3sprimary also toggle a Kasa switch in the Home app and open `https://request.example.com` from your phone on mobile data.

**Paste on: the node you just did.** Look for anything the firewall refused:

```bash
sudo journalctl -k --since "10 min ago" | grep "UFW BLOCK" | tail -20
```

Lines with `SRC=192.168.50.x` or `SRC=fd00:…` are things on your own network being refused. A few from phones probing ports are normal. Any with a **node's** address as `SRC` mean the node list in the script is incomplete (see "Open problem" below).

## Step 3. Keep it

If everything checked out, cancel the safety timer on that node:

```bash
sudo systemctl stop ufw-safety.timer
```

If you do nothing, the firewall turns itself off after 10 minutes and the node is back to open. If you get locked out, wait 10 minutes.

To turn it off by hand: `sudo ufw disable`. That keeps the rules; `sudo ufw enable` brings them back.

## Why the range is 192.168.0.0/16

You reach the house over VPN from 192.168.0.x. With the range set to 192.168.50.0/24, anything addressed to a Pi itself from the VPN was refused: SSH, the Kubernetes API, Homebridge on port 8581. Widening to /16 fixed it.

What this firewall does **not** filter is traffic to the floating addresses (.11 Pi-hole, .12 Traefik). That traffic is passed on to pods, and passed-on traffic is allowed from anywhere. So if a web app behind Traefik is unreachable from some network, look at routing and DNS before blaming this firewall.

To test whether the firewall is the reason something is refused, on the Pi being contacted:

```bash
sudo journalctl -k --since "5 min ago" | grep "UFW BLOCK" | grep "SRC=192.168.0."
```

Lines appearing while you retry mean the firewall is refusing that client.

## Why the IoT rule exists

The first version of the script allowed only the main LAN. Kasa and Wyze devices on 192.168.101.0/24 answer Homebridge on k3sprimary, and not every answer is recognised by the firewall as a reply to something Homebridge sent (discovery and status pushes arrive on their own). The script therefore allows the IoT network in, on the node whose hostname is `k3sprimary`. If Homebridge ever moves to another node, change `HOMEBRIDGE_NODE` at the top of the script.

## Open problem: why it is off

When the firewall first went on (4 October), two things happened around the same time:

- The Pi-hole login loop. That turned out to be unrelated; it kept looping with the firewall off everywhere ([07](07-pihole.md)).
- MetalLB's speakers on the Mac VM and k3snode2 logged "Suspect k3snode2 has failed". **Not explained.** It may be the firewall, or the Mac VM's networking ([05](05-mac-node-lima.md)).

The readings from 4 October show the gap is real in principle: besides its fixed address, every Pi has a second address in the LAN range (`fd00:1234:5678:50:…`) **and** one in a range the XT8 does not hand out (`fd00:aaaa:bbbb:cccc::/64`, most likely from an Apple Thread border router). The script knows neither.

One real gap in the script: it lists each node's **fixed** IPv6 address. Every node also has automatically generated IPv6 addresses in the same range, and a node may use one of those as the source when it talks to another node. Such traffic falls through to the "main LAN" rule, which is fine for most ports but **refused on 7946 (MetalLB) and the other cluster-internal ports**. That would produce exactly the "suspect … has failed" message.

Before turning the firewall back on for good:

**First**, run it on funkyfresh and k3snode2 only, and on each watch what it refuses for a few minutes:

```bash
sudo journalctl -k -f | grep "UFW BLOCK"
```

**If you see blocks** with `DPT=7946` (or 2379, 2380, 10250, 8472) and a `SRC=fd00:…` address that belongs to another node, that confirms the gap. Stop the nodes generating extra addresses. On each Pi (on funkyfresh the connection is `netplan-eth0`):

```bash
sudo nmcli con mod "Wired connection 1" ipv6.addr-gen-mode eui64 ipv6.ip6-privacy 0
sudo nmcli con up "Wired connection 1"
ip -6 addr show eth0
```

Then add each node's remaining automatic address to the `NODES` list in the script and run the script again on every node.

**If you see no such blocks** and MetalLB still complains, the firewall is not the cause; look at the Mac VM.

This diagnosis is my best reading of the evidence. It has not been tested.

## Changing the rules

Edit the lists at the top of `firewall/k3s-firewall.sh` (node addresses, LAN, IoT network) and run it again on each node. The script resets `ufw` every time, so it never stacks duplicates.

A new node needs to be added to `NODES` on **every** node, or the others will refuse its cluster traffic.
