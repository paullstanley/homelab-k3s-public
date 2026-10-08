# An Apple-silicon Mac as a k3s server in a Lima VM

You end up with a Linux virtual machine on a Mac that sits on your LAN with its own address and is a full k3s server (control plane, etcd member and worker). It is a cheap way to add capacity or an extra server to a Raspberry Pi cluster using a Mac that is switched on anyway.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | M1 MacBook Pro on wired Ethernet, Lima with `socket_vmnet` installed through Homebrew, guest Ubuntu 26.04 arm64 (kernel 7.0), k3s v1.34.3+k3s1, joining a dual-stack (IPv4 and IPv6) cluster of Raspberry Pi servers |
| **Also works for** | Other Apple-silicon Macs and other Lima-supported guests. Not tested by the author |
| **Time** | About an hour |
| **You need first** | A working k3s cluster to join: [Highly available k3s](../kubernetes/k3s-ha-cluster.md). If you want the VM to join through the floating API address, also [Load balancers](../kubernetes/load-balancers.md) (kube-vip step) |

**How much of this page is proven.** The k3s settings, the node name, the addresses and every pitfall are from a VM that ran as a cluster member. The VM-creation commands in Steps 1 to 3 and the VM definition file [k3s-vm.yaml](../../files/k3s/lima/k3s-vm.yaml) were **reconstructed** from Lima's documentation after the fact; the commands originally used were not kept, and the reconstruction has never been run. Those parts are marked "Not verified" below.

## How it works

Lima runs Linux VMs on macOS. By default a Lima VM has one network interface, `eth0`, on a private network that only the Mac can reach (address `192.168.5.15`). That is no use for a cluster node: the other nodes cannot reach it.

So the VM gets a second interface, `lima0`, that is **bridged** onto the Mac's wired LAN through a helper called `socket_vmnet`. Bridged means the VM appears on the LAN as its own machine, with its own software MAC address, and gets its own address from your router.

The result is a VM with two interfaces, and that is the source of most trouble on this page:

| Interface | Address | What it is |
| --- | --- | --- |
| `eth0` | `192.168.5.15` | Lima's private link to the Mac. `limactl shell` uses it. Useless to the cluster |
| `lima0` | `192.168.50.146` and an `fd00:1234:5678:50:…` address | The real LAN. Everything k3s does must use this one |

k3s picks the first interface it finds unless told otherwise, and it names the node after the VM's hostname unless told otherwise. Both defaults are wrong here.

**Two places to type.** Commands starting with `limactl` or `brew` go in the Mac's Terminal. Everything else goes inside the VM, which you enter from the Mac's Terminal with:

```sh
limactl shell k3s-vm
```

The prompt changes to `<USER>@<vm-hostname>`. Type `exit` to leave.

## Before you start

| Decide | Example | Notes |
| --- | --- | --- |
| Lima instance name | `k3s-vm` | Only Lima uses it |
| Kubernetes node name | `server-4` | Set explicitly in the k3s config |
| VM address | `192.168.50.146` | Given by the router to the VM's MAC. You will reserve it |
| VM MAC address | `52:55:55:15:F1:69` (an example) | Fixed in the VM definition so the addresses survive a rebuild |
| VM size | 4 CPUs, 6 GiB memory, 40 GiB disk | From the reconstructed template; adjust to your Mac |

Think about quorum before adding the Mac as a **server**. With three Pi servers plus the Mac there are four etcd members, and four members need three running. A fourth server adds no extra fault tolerance over three, and a Mac that sleeps or is carried away counts as a failed member. See [quorum arithmetic](../kubernetes/k3s-ha-cluster.md#how-it-works).

The Mac should be on **wired** Ethernet. Anything else running on the Mac itself (for example Docker containers) is unaffected; it runs outside the VM.

## Steps

### Step 1. Install Lima and the bridged network helper

> **Not verified:** Steps 1 to 3 are reconstructed from Lima's documentation and were not re-run. Read [Lima's VMNet network page](https://lima-vm.io/docs/config/network/vmnet/) alongside them.

**Run on: the Mac (Terminal).**

```sh
brew install lima socket_vmnet
```

Lima will not use the Homebrew copy of `socket_vmnet` directly, because it insists on a binary that only root can replace. Copy it into place:

```sh
sudo mkdir -p /opt/socket_vmnet/bin
sudo install -o root -m 755 "$(brew --prefix)/opt/socket_vmnet/bin/socket_vmnet" /opt/socket_vmnet/bin/socket_vmnet
```

Now tell Lima which Mac interface to bridge to. Find the wired interface, the one holding the Mac's LAN address:

```sh
ifconfig | grep -B4 "inet 192.168.50"
```

Open `~/.lima/_config/networks.yaml` and make sure the `bridged` network names that interface, for example `interface: en0`.

### Step 2. Install the sudoers file

Lima starts `socket_vmnet` as root through `sudo`. It generates the exact sudoers rules it needs.

**Run on: the Mac (Terminal).**

```sh
limactl sudoers > /tmp/etc_sudoers.d_lima
sudo install -o root -g wheel -m 644 /tmp/etc_sudoers.d_lima /private/etc/sudoers.d/lima
```

> **Pitfall:** `limactl start` refuses with a sudoers "out of sync" error if the sudoers file was generated before `networks.yaml` was final. Generate it **after** editing `networks.yaml`, and run these two lines again whenever that file changes. This error and its fix were seen for real.

### Step 3. Create and start the VM

The VM definition is [files/k3s/lima/k3s-vm.yaml](../../files/k3s/lima/k3s-vm.yaml). What it sets:

| Setting | Value | Why |
| --- | --- | --- |
| `images` | Ubuntu 26.04 server cloud image, `aarch64` | The guest operating system |
| `cpus`, `memory`, `disk` | `4`, `6GiB`, `40GiB` | Size of the VM |
| `mounts: []` | none | No Mac folders are shared into the VM; a k3s node does not need them |
| `containerd` `system: false`, `user: false` | off | k3s brings its own containerd |
| `networks` | `lima: bridged`, `macAddress: "52:55:55:15:F1:69"`, `interface: lima0` | The bridged LAN interface, with a fixed MAC |

> **Not verified:** this file is a reconstructed template, not a copy of a definition that was run. Only these facts about the working VM are certain: Ubuntu 26.04 arm64, a bridged interface named `lima0` with a fixed MAC, and the private interface `eth0` at `192.168.5.15`. Change the `macAddress` to one of your own choosing, or remove the line and let Lima generate one from the instance name.

**Run on: the Mac (Terminal)**, from the root of this repo.

```sh
limactl start --name=k3s-vm files/k3s/lima/k3s-vm.yaml
limactl shell k3s-vm
```

**Run on: inside the VM.**

```sh
ip -br addr
```

You should see `lima0` with a `192.168.50.x` address and an `fd00:1234:5678:50:…` address, and `eth0` with `192.168.5.15`.

Once the VM works, save the definition Lima actually used, so a rebuild does not depend on the template.

**Run on: the Mac (Terminal)**, from the root of this repo.

```sh
cp ~/.lima/k3s-vm/lima.yaml files/k3s/lima/k3s-vm.yaml
limactl list
```

The file has no secrets in it and can be committed.

### Step 4. Reserve the VM's address on the router

The VM's `lima0` address comes from your router's DHCP. **An etcd member's address must never change**, so reserve it: on the router, bind the address (`192.168.50.146`) to the VM's MAC address (the `link/ether` value from `ip link show lima0` inside the VM). On an ASUS router that is LAN → DHCP Server → manual assignment; see [ASUS ZenWiFi XT8](asus-zenwifi-xt8.md).

The VM's IPv6 address is generated automatically from the same MAC (for the example MAC it ends in `5055:55ff:fe15:f169`), so it stays the same for as long as the MAC does.

> **Pitfall:** if `lima0` comes up with a different `192.168.50.x` address after a rebuild, the MAC changed. Either set `macAddress` in the VM definition back to the old value, or accept the new address and change every place that names the old one: both halves of `node-ip` in the k3s config, the router reservation, any local DNS entry for the node, and the node list in the [firewall script](../kubernetes/node-firewall.md).

### Step 5. Join the cluster as a server

Edit a copy of [files/k3s/config/server-4.yaml](../../files/k3s/config/server-4.yaml). Replace `<K3S_TOKEN>` with the cluster's join token and set both halves of `node-ip` to the addresses you saw in Step 3.

**Run on: inside the VM.**

```sh
sudo mkdir -p /etc/rancher/k3s
sudo nano /etc/rancher/k3s/config.yaml
```

Paste the edited file, save (Ctrl+O, Enter, Ctrl+X), then install k3s with the same version as the rest of the cluster:

```sh
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='v1.34.3+k3s1' sh -s - server
```

The four lines that matter in this node's config:

| Line | Why |
| --- | --- |
| `node-name: server-4` | Without it k3s uses the VM's hostname. The node then registers under that name, and if you later rename it you are left with a dead node record under the old name |
| `node-ip: 192.168.50.146,fd00:1234:5678:50:5055:55ff:fe15:f169` | Both address families, comma between. With only the IPv4 half the node exits with "must share the same IP version" on a dual-stack cluster |
| `flannel-iface: lima0` | **The big one.** Flannel is the pod network. With `eth0` the VM advertises its private address `192.168.5.15` to the other nodes, pods on the VM cannot reach cluster DNS, and anything scheduled there hangs |
| `disable: servicelb` | Must match the other servers. See [Load balancers](../kubernetes/load-balancers.md) |

The example file joins through `server: https://192.168.50.10:6443`, the floating API address from kube-vip. If you have no floating address, use the first server's own address (`https://192.168.50.5:6443`).

### Step 6. Check the join and remove labels the VM must not have

**Run on: server-1.**

```sh
sudo kubectl get nodes -o wide
sudo kubectl get node server-4 -o jsonpath='{.metadata.annotations.flannel\.alpha\.coreos\.com/public-ip}{"\n"}'
```

You should see `server-4` `Ready` with roles `control-plane,etcd`. The second command must print `192.168.50.146`. If it prints `192.168.5.15`, the `flannel-iface` line is wrong.

**If you also have kube-vip or Pi-hole** placed by node label, make sure the VM carries neither label:

```sh
sudo kubectl label node server-4 kube-vip-host- pihole-host-
```

The trailing `-` removes a label; it is harmless if the label is not there. kube-vip is configured for interface `eth0`, which on the VM is the wrong network, so a kube-vip pod there crash-loops.

### Step 7. Keep the Mac awake and start the VM at boot

**Run on: the Mac (Terminal).**

```sh
sudo pmset -a sleep 0 disablesleep 1
limactl autostart enable --condition=boot k3s-vm
```

The first line stops the Mac sleeping. The second registers the VM to start automatically. If the second line reports an unknown command, your Lima is older than 2.2; use `limactl start-at-login k3s-vm` instead.

> **Not verified:** the `pmset` line was used. The autostart line had not been run when this was written, and the `--condition=boot` flag was not checked against a running Lima.

## Check it

**Run on: server-1.** This starts a throwaway pod pinned to the VM and resolves a cluster name from it.

```sh
sudo kubectl run nettest --image=busybox --restart=Never --overrides='{"spec":{"nodeName":"server-4","tolerations":[{"operator":"Exists"}]}}' -- sh -c 'nslookup kubernetes.default.svc.cluster.local'
sleep 30
sudo kubectl logs nettest
sudo kubectl delete pod nettest
```

Expected: a DNS answer for `kubernetes.default.svc.cluster.local`. That proves pods on the VM can reach the rest of the cluster.

**Run on: the Mac (Terminal).**

```sh
limactl list
```

Expected: `k3s-vm` with status `Running`.

## What to expect

- The VM is a normal node. Pods are scheduled on it like on any other, including replicas of cluster DNS.
- When the Mac sleeps, is shut down or loses its wired connection, the node goes `NotReady`. With four servers, the cluster then cannot afford to lose another one.
- Things that live on a specific Pi (pods with a local volume, pods selected by a Pi-only label) never move to the VM.
- MetalLB's speaker may not get along with the VM. See the next section.

## Pitfalls

| What happens | Why | How to avoid or recover |
| --- | --- | --- |
| `limactl start`: sudoers "out of sync" | The sudoers file was generated before `networks.yaml` was final | Step 2 again |
| k3s download fails | `INSTALL_K3S_VERSION='v1.34'`. The value must be the full tag | `v1.34.3+k3s1` |
| k3s exits: "cluster-cidr … and node-ip … must share the same IP version" | Only an IPv4 `node-ip` on a dual-stack cluster | Both addresses, comma between |
| k3s loops on 401 "nodes \"k3s-vm\" not found" and waits forever | Stale certificates in the VM from an earlier join attempt under another name or address | Inside the VM: `sudo k3s-agent-uninstall.sh` (or `sudo k3s-uninstall.sh` if it was installed as a server), then join again |
| Node `NotReady`, or two entries for the Mac in `kubectl get nodes` | It first joined without `node-name` and registered under the VM's hostname, then re-registered under the name you wanted | `sudo kubectl delete node k3s-vm` (the dead one); keep `server-4` |
| Pods on the VM cannot resolve names; an installer job that landed there hangs | `flannel-iface: eth0` (or no `flannel-iface` at all) | Change to `lima0`, then inside the VM `sudo systemctl restart k3s`. To unstick a hung pod: `sudo kubectl cordon server-4`, delete the stuck pod, wait for it to run on another node, `sudo kubectl uncordon server-4` |
| kube-vip pod crash-looping on the VM | The node carried `kube-vip-host=true`; its LAN interface is not `eth0` | `sudo kubectl label node server-4 kube-vip-host-` |
| VM came back on a different address | The MAC changed | Step 4 pitfall |
| `limactl shell` stops working after a host firewall is enabled in the VM | The firewall blocked `eth0`, Lima's private link | The [firewall script](../kubernetes/node-firewall.md) allows `eth0` when it detects `lima0` |

### Open point: MetalLB on the VM

On one occasion the MetalLB speakers on the VM and on one Pi each logged "Suspect server-3 has failed" about the other, and a MetalLB IPv6 address moved between nodes 34 times. **The cause was not found.** It may be the VM's networking (Lima's own discussions report ARP problems for MetalLB inside macOS VMs), or the [host firewall's IPv6 gap](../kubernetes/node-firewall.md#the-ipv6-gap).

If a MetalLB address keeps moving, keep the VM out of load-balancer duty:

**Run on: server-1.**

```sh
sudo kubectl label node server-4 node.kubernetes.io/exclude-from-external-load-balancers=true
```

> **Not verified:** this is the standard Kubernetes label for excluding a node from load balancers, and MetalLB's documentation says it honours it. It was not tried here.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `server-4` is `NotReady` | The Mac slept, or the VM is stopped | On the Mac: `limactl list`, then `limactl start k3s-vm`. Step 7 to stop it recurring |
| k3s log on other servers repeats "etcdserver: no leader" or "context deadline exceeded" | Quorum lost: fewer than three of four servers are up. Is the Mac asleep? | Bring a server back. With the Mac off, one more server down stops the control plane |
| `flannel…/public-ip` annotation shows `192.168.5.15` | Wrong `flannel-iface` | `lima0`, restart k3s |
| `lima0` missing inside the VM | Bridged network not set up | Steps 1 and 2; check `~/.lima/_config/networks.yaml` |
| Need to see why k3s will not start | | Inside the VM: `sudo journalctl -u k3s --no-pager -n 40` |

## Undo

Remove the VM from the cluster first, then uninstall.

**Run on: server-1.**

```sh
sudo kubectl drain server-4 --ignore-daemonsets --delete-emptydir-data
sudo kubectl delete node server-4
```

**Run on: inside the VM.**

```sh
sudo k3s-uninstall.sh
```

With three servers left, the cluster still survives one failure.

To remove the VM itself and the autostart entry:

**Run on: the Mac (Terminal).**

```sh
limactl autostart disable k3s-vm
limactl stop k3s-vm
limactl delete k3s-vm
sudo pmset -a disablesleep 0
```

> **Not verified:** the `limactl` and `pmset` lines in this last block are standard usage and were not run by the author. After `disablesleep 0`, set the sleep timer you want in System Settings. Also remove the DHCP reservation and take the VM's addresses out of the firewall script's node list on every other node.

## References

- [Lima documentation](https://lima-vm.io/docs/): what Lima is and how instances, templates and `limactl` work.
- [Lima: VMNet networks](https://lima-vm.io/docs/config/network/vmnet/): `socket_vmnet`, the root-owned install location, `limactl sudoers`, the `bridged` network in `networks.yaml`, `lima0` and `macAddress`.
- [socket_vmnet on GitHub](https://github.com/lima-vm/socket_vmnet): the helper itself, and why a Homebrew-installed binary is not trusted for running as root.
- [limactl autostart](https://lima-vm.io/docs/reference/limactl_autostart/): the `enable` and `disable` subcommands for starting an instance automatically.
- [limactl start-at-login](https://lima-vm.io/docs/reference/limactl_start-at-login/): the older command for the same job.
- [K3s server CLI reference](https://docs.k3s.io/cli/server): `--node-name`, `--flannel-iface`, `--node-ip` and the other options used in the config file.
- [K3s uninstalling](https://docs.k3s.io/installation/uninstall): the `k3s-uninstall.sh` and `k3s-agent-uninstall.sh` scripts.
- [MetalLB troubleshooting](https://metallb.io/troubleshooting/): mentions the `node.kubernetes.io/exclude-from-external-load-balancers` label.
