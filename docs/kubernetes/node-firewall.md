# A host firewall on k3s nodes that does not break k3s

You end up with `ufw` (Ubuntu and Debian's simple firewall front end) running on each k3s node. Devices on your networks can still use everything the cluster serves and can still SSH to the nodes, but they can no longer talk to etcd, the kubelet or the cluster's internal network. The goal is modest: keep a compromised gadget on the LAN or the IoT network away from the cluster's internals.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | `ufw` on Raspberry Pi OS Lite 64-bit (Debian 12 and 13), k3s v1.34.3+k3s1 with flannel (VXLAN) and embedded etcd, MetalLB layer-2. The script ran and stayed active on three Raspberry Pi servers. It was not confirmed on the Ubuntu VM node |
| **Also works for** | Other Debian or Ubuntu k3s nodes. Not tested by the author |
| **Time** | 15 minutes per node, one node at a time |
| **You need first** | A running cluster: [Highly available k3s](k3s-ha-cluster.md). Read [The IPv6 gap](#the-ipv6-gap) before enabling this on a dual-stack cluster |

> **Not verified:** one open problem remains. On a dual-stack cluster the script may block cluster traffic between nodes that arrives from an IPv6 address the script does not list. The reasoning and a test are in [The IPv6 gap](#the-ipv6-gap). The diagnosis has not been confirmed.

## How it works

A default-deny host firewall blocks k3s in three ways unless it is told otherwise:

1. **Node to node.** Servers replicate etcd, reach each other's kubelet, and carry pod traffic in a tunnel (flannel VXLAN). All of that arrives as ordinary inbound traffic from the other nodes.
2. **Pod to host.** Traffic from pods arrives on the virtual interfaces `cni0`, `flannel.1` and `flannel-v6.1`, with source addresses in the pod and service ranges.
3. **Forwarded traffic.** A request to a service's floating address is not delivered to the host; it is **forwarded** (routed on) to a pod. `ufw` denies forwarded traffic by default. Without `default allow routed`, Kubernetes networking stops.

The script [files/firewall/k3s-firewall.sh](../../files/firewall/k3s-firewall.sh) builds the rules in an order that matters, because `ufw` uses the first rule that matches:

| Order | Rule | Effect |
| --- | --- | --- |
| defaults | deny incoming, allow outgoing, **allow routed** | Block by default; let the node talk out; let traffic to pods and services through |
| 1 | allow from each cluster node's address | Nodes may reach each other on every port |
| 2 | allow from the pod and service ranges, and anything arriving on `cni0`, `flannel.1`, `flannel-v6.1` | Pods may reach the host |
| 3 | **deny** the cluster-internal ports | For everyone who did not match rules 1 and 2 |
| 4 | allow from your home ranges | Everything else (SSH, the API, app ports) for your own networks |
| 5 | allow from the IoT network, on one named node only | See [the IoT allowance](#the-iot-network-allowance) |
| VM only | allow in on `eth0` when `lima0` exists | Keeps `limactl shell` working on a [Lima VM node](../hardware/mac-lima-vm.md) |
| end | everything else inbound | Blocked by the default |

Because rule 3 comes before rule 4, a device on the LAN is allowed everything **except** the cluster-internal ports.

### Every port and range, and why

| Port or range | What it is | Who may reach it |
| --- | --- | --- |
| 2379-2380/tcp | etcd client and peer traffic (the cluster database) | Nodes only |
| 10250/tcp | kubelet API (runs and inspects containers on the node) | Nodes and pods only |
| 8472/udp | flannel VXLAN, the tunnel carrying pod traffic between nodes | Nodes only |
| 7946 (tcp and udp) | MetalLB memberlist, by which the speakers watch each other | Nodes only |
| 6443/tcp | Kubernetes API | Nodes, pods, and your home ranges (so `kubectl` works from a laptop) |
| 22/tcp | SSH | Your home ranges |
| App ports on the node itself, for example a host-network app's web UI | | Your home ranges |
| `10.42.0.0/16`, `fd00:1234:5678:4200::/56` | Pod ranges (`cluster-cidr`) | Allowed in full |
| `10.43.0.0/16`, `fd00:1234:5678:4300::/112` | Service ranges (`service-cidr`) | Allowed in full |
| `192.168.0.0/16` (`LAN4`) | Home IPv4 ranges: the main LAN `192.168.50.x`, a VPN subnet `192.168.0.x`, the IoT network `192.168.101.x` | Everything except the cluster-internal ports |
| `fd00:1234:5678:50::/64` (`LAN6`) | The LAN's IPv6 range | Same |
| `fe80::/10` | IPv6 link-local addresses, used by mDNS and HomeKit discovery | Same |
| `192.168.101.0/24` (`IOT4`) | The IoT network, on the home-automation node only | Same |

**What this firewall does not filter:** traffic to the floating service addresses (the MetalLB addresses for DNS and Traefik). That traffic is forwarded to pods, and forwarded traffic is allowed from anywhere. So if a web app behind Traefik is unreachable from some network, look at routing and DNS before blaming this firewall.

### The safety timer

Enabling a firewall over SSH can lock you out. The script arms a systemd timer (`ufw-safety`) that runs `ufw --force disable` **10 minutes** after the script starts. If everything works you cancel the timer and the firewall stays on. If you are locked out, wait 10 minutes and the node opens up again by itself.

## Before you start

Edit the variables at the top of [files/firewall/k3s-firewall.sh](../../files/firewall/k3s-firewall.sh):

| Variable | Example | Set it to |
| --- | --- | --- |
| `LAN4` | `192.168.0.0/16` | The IPv4 range(s) you manage the nodes from. See [the VPN range](#the-vpn-range) for why it is a /16 |
| `LAN6` | `fd00:1234:5678:50::/64` | Your LAN's IPv6 prefix |
| `IOT4` | `192.168.101.0/24` | Your IoT or guest network, if you have one |
| `HOMEBRIDGE_NODE` | `server-1` | The hostname of the node running a host-network home-automation app. Leave it as a name no node has if you have none |
| `NODES` | the four example nodes, IPv4 and IPv6 | **Every** address of **every** node |
| `CLUSTER_NETS` | the pod and service ranges | The `cluster-cidr` and `service-cidr` values from `/etc/rancher/k3s/config.yaml` |

Find each node's addresses with `ip -br addr show eth0` (or `lima0` on a Lima VM). On an IPv4-only cluster, delete the IPv6 entries.

Plan the order. Do the least important node first and the node with the most to break last. In the example that is `server-2`, `server-3`, the VM `server-4`, then `server-1` (which carries the single-instance apps).

## Steps

### Step 1. Run the script on one node

**Run on: your computer**, from the root of this repo. Change the address for each node.

```sh
scp files/firewall/k3s-firewall.sh <USER>@192.168.50.6:/tmp/
```

**Run on: that node.**

```sh
sudo bash /tmp/k3s-firewall.sh
```

For a Lima VM node, copy the file's contents in instead: `limactl shell k3s-vm`, then `nano /tmp/k3s-firewall.sh`, paste, save, and run the same `sudo bash` line inside the VM.

What the script does, in order: installs `ufw`; arms the 10-minute safety timer; resets `ufw` to a clean state and makes sure IPv6 support is on (`IPV6=yes` in `/etc/default/ufw`); sets the defaults; adds the rules in the table above; enables the firewall; prints the resulting rules.

### Step 2. Check, within the 10 minutes

**Run on: server-1** (or any other server).

```sh
sudo kubectl get nodes
sudo kubectl get pods -A | grep -v -E 'Running|Completed'
```

Expected: all nodes `Ready`; only the header line from the second command.

Then test what your cluster serves. With the DNS service and Traefik from this wiki:

```sh
nslookup example.com 192.168.50.11
curl -sI -H 'Host: pihole.home.example.com' http://192.168.50.12/admin/ | head -1
```

Expected: a DNS answer, and `301`.

After doing the home-automation node, also operate a device on the IoT network from your home app, and open any app you publish to the internet from a phone on mobile data.

**Run on: the node you just did.** Look for anything the firewall refused:

```sh
sudo journalctl -k --since "10 min ago" | grep "UFW BLOCK" | tail -20
```

How to read the result:

| Lines show | Meaning |
| --- | --- |
| `SRC=192.168.50.x` or `SRC=fd00:…` from phones and other devices, on assorted ports | Things on your own network probing ports. A few are normal |
| `SRC=` a **node's** address | The `NODES` list in the script is incomplete. Stop and fix it; see [The IPv6 gap](#the-ipv6-gap) |
| `SRC=` your own computer's address | Your management range is not covered by `LAN4`/`LAN6` |

### Step 3. Keep it

If everything checked out, cancel the safety timer on that node:

**Run on: that node.**

```sh
sudo systemctl stop ufw-safety.timer
```

If you do nothing, the firewall turns itself off after 10 minutes and the node is open again. Then move on to the next node and repeat Steps 1 to 3.

### Step 4. Changing the rules later

Edit the lists at the top of the script and run it again on each node. The script resets `ufw` every time, so rules never stack up as duplicates.

> **Pitfall:** a new node must be added to `NODES` in the script and the script re-run on **every** existing node, or the others will refuse its cluster traffic.

## The VPN range

`LAN4` is `192.168.0.0/16`, not just the LAN's `192.168.50.0/24`. The first version used the /24, and anything addressed to a node itself from a remote-access VPN subnet (`192.168.0.x` in the example) was refused: SSH, the Kubernetes API, and a host-network app's web port. Widening the range fixed it. The /16 also happens to cover the IoT network.

If your VPN clients come from a different range, add that range instead (a second `ufw allow from <range>` line next to the `LAN4` one in the script). Cluster-internal ports stay blocked for all of it, because rule 3 comes first.

If something still fails from the VPN and the firewall log shows no blocks, the reply probably has no route back. On the node, `ip route get 192.168.0.10` (an address in the VPN range) should leave through your router, `192.168.50.1`.

## The IoT network allowance

This matters only if a node runs a home-automation app on the host network that talks to devices on a separate IoT network; see [Isolated IoT network](../network/isolated-iot-network.md) and [Kasa devices across networks](../apps/homebridge-kasa-across-networks.md).

Smart plugs and cameras answer the app on the node. Not every answer is recognised by the firewall as a reply to something the app sent: discovery replies and status pushes arrive on their own, as new inbound connections. With only the main LAN allowed, those devices stopped working the moment the firewall went on.

So the script allows the IoT network in, on the one node whose hostname equals `HOMEBRIDGE_NODE`. The devices still cannot reach etcd, the kubelet, flannel or MetalLB's port, because rule 3 comes first.

With `LAN4` set to a /16 that already contains the IoT network, this separate rule is redundant. It is kept on purpose: if you later narrow `LAN4`, the IoT devices keep working. If the app moves to another node, change `HOMEBRIDGE_NODE` and re-run the script on both nodes.

## The IPv6 gap

> **Not verified:** this is a best reading of the evidence. It has not been tested.

The script lists each node's **fixed** IPv6 address. A node usually has more:

- an automatically generated address in the LAN prefix (from the router's advertisement), in addition to the short fixed one;
- possibly an address in a **second prefix** that your router does not hand out. On the network this was written on, every node also had an address in another `fd…::/64` range, most likely advertised by an Apple TV or HomePod acting as a Thread border router. The source was not confirmed.

A node may use any of these as the source address when it talks to another node. Such traffic does not match rule 1 (the node list). If the address is inside `LAN6` it falls through to the "main LAN" rule, which is fine for most ports but comes **after** the deny for 2379, 2380, 10250, 8472 and 7946. If it is in a second prefix it matches nothing and is blocked on every port.

What that would look like: MetalLB speakers logging "Suspect <node> has failed" about each other, and a floating address moving between nodes over and over. Exactly that was seen once, around the time the firewall was first enabled, between a VM node and a Pi. It was never established whether the firewall or the VM's networking caused it.

Before leaving the firewall on for good on a dual-stack cluster:

**First**, enable it on two nodes only, and on each watch what it refuses for a few minutes.

**Run on: each of the two nodes.**

```sh
sudo journalctl -k -f | grep "UFW BLOCK"
```

**If you see blocks** with `DPT=7946` (or 2379, 2380, 10250, 8472) and a `SRC=fd…` address that belongs to another node, the gap is confirmed. Stop the nodes generating changing addresses. On each node (use that node's connection name; see [Raspberry Pi](../hardware/raspberry-pi.md), Step 7):

```sh
sudo nmcli con mod "Wired connection 1" ipv6.addr-gen-mode eui64 ipv6.ip6-privacy 0
sudo nmcli con up "Wired connection 1"
ip -6 addr show eth0
```

This makes the automatic address a fixed one derived from the network card's MAC address, with no temporary privacy addresses. Then add each node's remaining automatic addresses, in every prefix, to the `NODES` list and run the script again on every node.

**If you see no such blocks** and MetalLB still complains, the firewall is not the cause. Look at the node the complaints are about, particularly if it is a VM: [Mac in a Lima VM](../hardware/mac-lima-vm.md#open-point-metallb-on-the-vm).

## Check it

**Run on: each node.**

```sh
sudo ufw status verbose
systemctl is-active ufw-safety.timer
```

Expected: `Status: active`, `Default: deny (incoming), allow (outgoing), allow (routed)`, the rules from the table above; and `inactive` for the timer once you have cancelled it.

**Run on: your computer** (on the LAN). The API port should answer and the etcd port should not:

```sh
nc -vz -w 3 192.168.50.6 6443
nc -vz -w 3 192.168.50.6 2379
```

Expected: the first connects; the second times out.

> **Not verified:** the two `nc` probes are added here as an obvious confirmation and were not run by the author.

## Is the firewall the cause?

Suspect it when something worked, the firewall was enabled or re-enabled, and now a connection **to a node itself** times out; or when you arrive from a network other than the main LAN.

**Run on: the node being contacted.**

```sh
sudo ufw status | head -1
sudo journalctl -k --since "10 min ago" | grep "UFW BLOCK" | tail -20
```

Then retry the failing thing while watching live:

```sh
sudo journalctl -k -f | grep "UFW BLOCK"
```

To narrow it to one client range, for example a VPN subnet:

```sh
sudo journalctl -k --since "5 min ago" | grep "UFW BLOCK" | grep "SRC=192.168.0."
```

| Result | Meaning | Fix |
| --- | --- | --- |
| `Status: inactive` | Not the firewall | Look elsewhere |
| Block lines with your client's address as `SRC`, appearing as you retry | The firewall is refusing that client | Add the range: `sudo ufw allow from <range>`, and put it in the script so a re-run keeps it |
| Block lines with another **node's** address as `SRC` and `DPT` 7946, 2379, 2380, 10250 or 8472 | The firewall is breaking the cluster | [The IPv6 gap](#the-ipv6-gap); complete the `NODES` list |
| No block lines while it fails | Not the firewall | Routing, DNS, or the app |

The quickest proof either way is to switch it off on that node for a minute:

```sh
sudo ufw disable
```

Retry, then:

```sh
sudo ufw enable
```

## Pitfalls

| What happens | Why | How to avoid or recover |
| --- | --- | --- |
| Locked out of a node over SSH | Your address is not in an allowed range | Wait 10 minutes for the safety timer. Never cancel the timer before you have opened a **new** SSH session successfully |
| The firewall "turned itself off" | The safety timer was never cancelled | `sudo systemctl stop ufw-safety.timer` after checking, then run the script again or `sudo ufw enable` |
| All service traffic stops when the firewall goes on | Forwarded traffic denied | `ufw default allow routed`. The script sets it; do not remove it |
| SSH, the API or a host-network app unreachable from a VPN | The allowed range covered only the LAN /24 | Widen `LAN4` or add the VPN range |
| IoT devices stop responding in the home app when the firewall goes on | Their unsolicited answers are new inbound connections from the IoT network | The IoT allowance on the home-automation node |
| A node that was patched by hand loses the fix on the next run | The script resets `ufw` each time | Put every change in the script, not only in a live `ufw allow` |
| A new node cannot join, or goes `NotReady` on the others | It is not in `NODES` on the existing nodes | Add it and re-run everywhere |
| MetalLB "Suspect … has failed", addresses hopping | Possibly node-to-node traffic from an unlisted IPv6 address | [The IPv6 gap](#the-ipv6-gap) |
| `limactl shell` stops working on a Lima VM node | The VM's private `eth0` link to the Mac was blocked | The script allows `eth0` when it sees `lima0`; keep that block |
| A web app behind Traefik is unreachable and you blame the firewall | Traffic to floating addresses is forwarded and not filtered here | Check DNS and routing first |
| An unrelated fault appears at the same time and gets blamed on the firewall | Coincidence. A web-login loop seen right after enabling the firewall continued with the firewall off on every node | Use the test in [Is the firewall the cause?](#is-the-firewall-the-cause) before changing rules |

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Node is fine locally but `NotReady` as seen from the others | Nodes cannot reach each other | Check for `UFW BLOCK` lines with a node address as `SRC`; fix `NODES` |
| Cannot SSH or open a node-hosted app from the VPN range | Range not allowed | [The VPN range](#the-vpn-range) |
| Works on home Wi-Fi, not from VPN, and no block lines | No return route | `ip route get <vpn address>` on the node should leave via the router |
| IoT device reachable by `ping` from the node, app still times out, firewall recently enabled | Replies refused | Check `HOMEBRIDGE_NODE` matches `hostname` on that node exactly, re-run the script |
| Pods cannot resolve names after enabling | Pod ranges or pod interfaces not allowed | `CLUSTER_NETS` must match the cluster's real ranges |
| Script fails at "Run with sudo" | Not root | `sudo bash /tmp/k3s-firewall.sh` |

## Undo

To switch the firewall off and keep the rules for later:

**Run on: the node.**

```sh
sudo ufw disable
```

`sudo ufw enable` brings the same rules back. Both survive reboots.

To remove the rules entirely and cancel any pending safety timer:

```sh
sudo systemctl stop ufw-safety.timer 2>/dev/null || true
sudo ufw --force reset
```

`reset` disables the firewall and returns it to installation defaults.

## References

- [ufw manual page](https://manpages.ubuntu.com/manpages/noble/en/man8/ufw.8.html): `default … routed`, `allow from`, `deny`, `comment`, `reset` and `disable`.
- [Ubuntu community help: UFW](https://help.ubuntu.com/community/UFW): basics, and how to read the `UFW BLOCK` log lines.
- [K3s requirements](https://docs.k3s.io/installation/requirements): the inbound port table for k3s nodes (6443, 2379-2380, 8472, 10250) and its notes on running with `ufw` or `firewalld`.
- [K3s basic network options](https://docs.k3s.io/networking/basic-network-options): the pod and service ranges the firewall has to allow.
- [MetalLB in layer 2 mode](https://metallb.io/concepts/layer2/): the speakers use memberlist to detect a failed node, which is what a blocked port 7946 would disturb.
- [nm-settings-nmcli reference](https://networkmanager.dev/docs/api/latest/nm-settings-nmcli.html): the NetworkManager connection properties, including the IPv6 address-generation settings used for the IPv6 gap.
