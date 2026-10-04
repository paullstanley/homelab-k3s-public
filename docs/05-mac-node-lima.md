# 05. The Mac node (Lima VM)

The M1 MacBook Pro runs a Linux VM under Lima. The VM is the fourth k3s server, `lima-k3s-mac`, at 192.168.50.146. The Mac is wired. The RuneScape: Dragonwilds servers keep running in Docker on the Mac itself, outside the VM.

**"Mac Terminal" and "inside the VM" are different places.** Commands starting with `limactl` or `brew` go in the Mac's Terminal. Everything else on this page goes inside the VM, which you enter from the Mac's Terminal with:

```bash
limactl shell k3s-mac
```

The prompt changes to `homeuser@lima-k3s-mac`. Type `exit` to leave.

**How much of this page is proven.** The k3s settings, the name, the addresses and every "Trouble we hit" note are from what actually happened on 3 October. The VM-creation commands in Steps 1 to 3 are written from Lima's documentation and my notes; the original commands were not kept. Save the real VM definition now (next section) so a rebuild does not depend on my reconstruction.

## Save the real VM definition (do this now)

**Paste on: Mac Terminal**, in the root of this repo.

```bash
cp ~/.lima/k3s-mac/lima.yaml k3s/lima/k3s-mac.yaml
limactl list
```

Commit the file. It has no secrets in it.

## Step 1. Install Lima and the bridged network helper

**Paste on: Mac Terminal.**

```bash
brew install lima socket_vmnet
```

Lima must not use the Homebrew copy of `socket_vmnet` directly, because it insists on a root-owned binary. Copy it into place:

```bash
sudo mkdir -p /opt/socket_vmnet/bin
sudo install -o root -m 755 "$(brew --prefix)/opt/socket_vmnet/bin/socket_vmnet" /opt/socket_vmnet/bin/socket_vmnet
```

Tell Lima which Mac interface to bridge to. Find the wired interface (the one holding the Mac's 192.168.50.x address):

```bash
ifconfig | grep -B4 "inet 192.168.50"
```

Open `~/.lima/_config/networks.yaml` and make sure the `bridged` network names that interface, for example `interface: en0`.

## Step 2. Sudoers

**Paste on: Mac Terminal.**

```bash
limactl sudoers > /tmp/etc_sudoers.d_lima
sudo install -o root -g wheel -m 644 /tmp/etc_sudoers.d_lima /private/etc/sudoers.d/lima
```

> **Trouble we hit:** `limactl start` refused with a sudoers "out of sync" error. The sudoers file must be generated **after** `networks.yaml` is final, and regenerated whenever that file changes. Run the two lines above again.

## Step 3. Create and start the VM

**Paste on: Mac Terminal**, in the root of this repo.

```bash
limactl start --name=k3s-mac k3s/lima/k3s-mac.yaml
limactl shell k3s-mac
```

**Inside the VM**, check the network:

```bash
ip -br addr
```

You should see `lima0` with `192.168.50.146` and an `fd00:1234:5678:50:…` address, and `eth0` with `192.168.5.15`. `eth0` is Lima's private link to the Mac; `lima0` is the real LAN.

If `lima0` has a different 192.168.50.x address, the MAC address changed. Either set `macAddress: "52:55:55:15:F1:69"` in the VM definition, or accept the new address and change `node-ip` (both halves), the router reservation, the Pi-hole host entry and the firewall script's node list to match.

Reserve 192.168.50.146 for MAC `52:55:55:15:F1:69` on the XT8 (LAN → DHCP Server → manual assignment). **This is an etcd member; its address must never change.**

## Step 4. Join the cluster as a server

**Inside the VM.**

```bash
sudo mkdir -p /etc/rancher/k3s
sudo nano /etc/rancher/k3s/config.yaml
```

Paste [`k3s/config/lima-k3s-mac.yaml`](../k3s/config/lima-k3s-mac.yaml), replace `<K3S_TOKEN>`, save, then:

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='v1.34.3+k3s1' sh -s - server
```

**Paste on: k3sprimary.**

```bash
sudo kubectl get nodes -o wide
sudo kubectl get node lima-k3s-mac -o jsonpath='{.metadata.annotations.flannel\.alpha\.coreos\.com/public-ip}{"\n"}'
sudo kubectl label node lima-k3s-mac kube-vip-host- pihole-host-
```

You should see `lima-k3s-mac` `Ready` as `control-plane,etcd`, and the second command must print `192.168.50.146`. If it prints `192.168.5.15`, the `flannel-iface` line is wrong.

### The four lines that matter in the Mac's config

| Line | Why |
| --- | --- |
| `node-name: lima-k3s-mac` | Without it k3s uses the VM's hostname. The node first joined as `k3s-mac`, later re-registered as `lima-k3s-mac`, and left a dead `k3s-mac` record behind |
| `node-ip: 192.168.50.146,fd00:…:f169` | Both families. Without the IPv6 half the agent exits with "must share the same IP version" |
| `flannel-iface: lima0` | **The big one.** With `eth0`, the VM advertised its private NAT address 192.168.5.15, pods on the Mac could not reach cluster DNS, and the kube-vip installer pod that happened to land on the Mac hung |
| `disable: servicelb` | Must match the other servers |

## Step 5. Make it survive reboots

**Paste on: Mac Terminal.**

```bash
sudo pmset -a sleep 0 disablesleep 1
limactl autostart enable --condition=boot k3s-mac
```

If the second line reports an unknown command, your Lima is older than 2.2; use `limactl start-at-login k3s-mac` instead.

As of 4 October the autostart line had not been run yet.

## Trouble we hit, in one place

| Symptom | Cause | Fix |
| --- | --- | --- |
| `limactl start`: sudoers out of sync | Sudoers file generated before `networks.yaml` was final | Step 2 again |
| k3s download failed | `INSTALL_K3S_VERSION='v1.34'` | Full tag `v1.34.3+k3s1` |
| "cluster-cidr … and node-ip … must share the same IP version" | Only an IPv4 `node-ip` | Both addresses, comma between |
| 401 "nodes \"k3s-mac\" not found", agent waiting forever | Stale certificates in the VM from an earlier attempt | `sudo k3s-agent-uninstall.sh`, then join again |
| Node `NotReady`, or two Mac nodes in the list | Joined without `node-name`, so it registered under the hostname | `sudo kubectl delete node k3s-mac` (the dead one), keep `lima-k3s-mac` |
| Pods on the Mac cannot resolve names; kube-vip install hangs | `flannel-iface: eth0` | Change to `lima0`, `sudo systemctl restart k3s`. To unstick the installer: `sudo kubectl cordon lima-k3s-mac`, delete the stuck pod, wait for it to run on a Pi, `sudo kubectl uncordon lima-k3s-mac` |
| kube-vip pod crash-looping on the Mac | The Mac carried `kube-vip-host=true`; its interface is not `eth0` | `sudo kubectl label node lima-k3s-mac kube-vip-host-` |

## Test that pods on the Mac can reach the cluster

**Paste on: k3sprimary.**

```bash
sudo kubectl run nettest --image=busybox --restart=Never --overrides='{"spec":{"nodeName":"lima-k3s-mac","tolerations":[{"operator":"Exists"}]}}' -- sh -c 'nslookup kubernetes.default.svc.cluster.local'
sleep 30
sudo kubectl logs nettest
sudo kubectl delete pod nettest
```

You should see a DNS answer for `kubernetes.default`.

## Removing the Mac from the cluster

**Paste on: k3sprimary.**

```bash
sudo kubectl drain lima-k3s-mac --ignore-daemonsets --delete-emptydir-data
sudo kubectl delete node lima-k3s-mac
```

**Inside the VM:**

```bash
sudo k3s-uninstall.sh
```

With three servers left, the cluster still survives one failure.

## Open point: MetalLB on the Mac

On 4 October the MetalLB speaker on the Mac VM and the one on k3snode2 logged "Suspect k3snode2 has failed" against each other, and the Pi-hole IPv6 address had moved between nodes 34 times. The cause was not found. Lima's own discussions report ARP problems for MetalLB inside macOS VMs. If the Pi-hole address keeps moving, keep the MetalLB speaker off the Mac:

```bash
sudo kubectl label node lima-k3s-mac node.kubernetes.io/exclude-from-external-load-balancers=true
```

This label is the standard Kubernetes way to keep a node out of load-balancer duty and MetalLB honours it. It has not been tried here.
