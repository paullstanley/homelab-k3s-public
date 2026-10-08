# Highly available k3s on embedded etcd

You end up with a k3s cluster in which every node is a server, the cluster database is etcd replicated across them, and pods and services have both IPv4 and IPv6 addresses (dual-stack). The cluster keeps working when any one node is switched off.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | k3s v1.34.3+k3s1 with embedded etcd and the bundled flannel pod network, on three Raspberry Pi 4 Model B (Raspberry Pi OS Lite 64-bit, Debian 12 and 13) plus one Ubuntu 26.04 arm64 VM. The running cluster was converted in place from a single SQLite server with agents; the fresh-build steps below use the same config files but were not themselves run end to end from nothing |
| **Also works for** | Any Linux hosts k3s supports; IPv4-only clusters (leave out the IPv6 halves). Not tested by the author |
| **Time** | About 15 minutes per server for a fresh build. Allow an evening for an in-place conversion |
| **You need first** | Hosts prepared as in [Raspberry Pi](../hardware/raspberry-pi.md) (fixed addresses, outside DNS, cgroups, a real disk). For dual-stack: a local IPv6 prefix, see [Local-only IPv6](../network/local-only-ipv6.md). Optional fourth server: [Mac in a Lima VM](../hardware/mac-lima-vm.md) |

## How it works

In k3s a **server** is control plane, etcd member and worker at once. `kubectl get nodes` shows servers with roles `control-plane,etcd`. An **agent** is a worker only. In this build every node is a server.

**Embedded etcd.** A single k3s server keeps the cluster state in a SQLite file. That cannot be shared, so a second server is impossible. Starting the first server with `cluster-init: true` makes it use etcd instead, a database that replicates itself between servers. Further servers join by pointing at an existing one with the shared **token** (the cluster's join secret).

**Quorum.** etcd only accepts changes while more than half of its members are running. That majority is called quorum.

| Servers | Needed running | Failures survived |
| --- | --- | --- |
| 1 | 1 | 0 |
| 2 | 2 | 0 |
| 3 | 2 | 1 |
| 4 | 3 | 1 |
| 5 | 3 | 2 |

Three servers survive one failure. **Four servers also survive only one**: a fourth member raises the number needed without adding tolerance. With four servers of which one is a laptop VM that is often off, losing one more stops the control plane until a server comes back. When quorum is lost, pods that are already running keep running, but nothing new can be scheduled and `kubectl` stops answering.

**Dual-stack.** Each node, pod and service gets an IPv4 and an IPv6 address. That needs four things to agree on every server: `node-ip` holds both of the node's addresses, `cluster-cidr` holds both pod ranges, `service-cidr` holds both service ranges, and `flannel-ipv6-masq` is on so that pods' outgoing IPv6 traffic is rewritten to the node's address (needed with local-only IPv6 addresses, which nothing outside the cluster can route back to).

**One config file per server.** k3s reads `/etc/rancher/k3s/config.yaml` at start. Everything is set there rather than on the install command line, so a reinstall or upgrade cannot lose a setting.

## Before you start

Values used in the config files under [files/k3s/config/](../../files/k3s/config/):

| Setting | Example value | Notes |
| --- | --- | --- |
| Pod ranges (`cluster-cidr`) | `10.42.0.0/16,fd00:1234:5678:4200::/56` | IPv6 part is a /56 from your own /48, not overlapping the LAN /64 |
| Service ranges (`service-cidr`) | `10.43.0.0/16,fd00:1234:5678:4300::/112` | /112 is the largest IPv6 service range k3s supports |
| Cluster DNS address | `10.43.0.10` and `fd00:1234:5678:4300::a` | Follows from the service ranges |
| Floating API address (`tls-san`) | `192.168.50.10` | Optional. Put it in now even if you add kube-vip later; it has to be in the API certificate. See [Load balancers](load-balancers.md) |
| k3s version | `v1.34.3+k3s1` | Same on every node. Always the full tag |

Decisions:

- **Dual-stack must be chosen at the start.** The k3s documentation says it cannot be enabled on a cluster that was started as IPv4-only. It was done in place here anyway, with breakage (see [Converting](#converting-a-single-sqlite-server-with-agents)). On a new cluster, decide now.
- **How many servers.** Three is the sensible number. Read the quorum table before adding a fourth.
- **The built-in load balancer is disabled** in every file (`disable: servicelb`), because MetalLB replaces it. If you do not plan to run MetalLB, remove those two lines from every file. See [Load balancers](load-balancers.md).

**One rule for every step:** on the nodes, put `sudo` in front of every `kubectl` command. Without it you get "permission denied" on `/etc/rancher/k3s/k3s.yaml`.

### What each config line does

| Line | In which files | Meaning |
| --- | --- | --- |
| `cluster-init: true` | first server only | Start embedded etcd. On a brand-new server this creates the etcd cluster. It is ignored once etcd exists |
| `server: https://…:6443` | joining servers | An existing server to join through. `server-2` and `server-3` use the first server's own address (`192.168.50.5`); `server-4` uses the floating address (`192.168.50.10`) |
| `token: <K3S_TOKEN>` | joining servers | The join secret. Never commit the real one |
| `node-ip: <v4>,<v6>` | all | Both of the node's addresses, comma between, no space |
| `node-name` | `server-4` only | Overrides the hostname as the node name. Needed where the hostname is not the name you want |
| `cluster-cidr`, `service-cidr` | all | Pod and service ranges. Must be identical on every server |
| `flannel-ipv6-masq: true` | all | Rewrite outgoing pod IPv6 traffic to the node's address |
| `flannel-iface: eth0` | all (`lima0` on the VM) | The interface the pod network uses between nodes. Must be the LAN interface |
| `tls-san: [192.168.50.10]` | all | Extra address to put in the API server's certificate |
| `disable: [servicelb]` | all | Do not run the built-in load balancer |

> **Pitfall:** every server's file must carry the same `cluster-cidr`, `service-cidr`, `flannel-ipv6-masq` and `disable` lines. A server that lacks `disable: servicelb` brings the built-in load balancer back for the whole cluster when it restarts.

## Steps

### Step 1. First server

**Run on: server-1.**

```sh
sudo mkdir -p /etc/rancher/k3s
sudo nano /etc/rancher/k3s/config.yaml
```

Paste the contents of [files/k3s/config/server-1.yaml](../../files/k3s/config/server-1.yaml), adjusted to your addresses, and save (Ctrl+O, Enter, Ctrl+X). This file has no secret in it. Then install:

```sh
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='v1.34.3+k3s1' sh -s - server
sudo kubectl get nodes
```

You should see `server-1` `Ready` with roles `control-plane,etcd`.

> **Pitfall:** `INSTALL_K3S_VERSION='v1.34'` fails to download. The value must be the full release tag, `v1.34.3+k3s1`.

Print the join token and store it in your password manager, not in a repository:

```sh
sudo cat /var/lib/rancher/k3s/server/token
```

### Step 2. Second and third server

Join servers **one at a time**.

**Run on: server-2.**

```sh
sudo mkdir -p /etc/rancher/k3s
sudo nano /etc/rancher/k3s/config.yaml
```

Paste [files/k3s/config/server-2.yaml](../../files/k3s/config/server-2.yaml), replace `<K3S_TOKEN>` with the token, save, then:

```sh
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='v1.34.3+k3s1' sh -s - server
```

**Run on: server-1.** Wait until `server-2` shows `Ready` and `control-plane,etcd` (up to two minutes) before starting the next node.

```sh
sudo kubectl get nodes
```

Repeat on **server-3** with [files/k3s/config/server-3.yaml](../../files/k3s/config/server-3.yaml).

### Step 3. Optional fourth server

A Mac VM as `server-4` is covered in [Mac in a Lima VM](../hardware/mac-lima-vm.md). Its config file joins through the floating API address, so set up kube-vip first ([Load balancers](load-balancers.md)) or change its `server:` line to `https://192.168.50.5:6443`.

### Step 4. Node labels

Labels let you pin workloads to particular nodes. Two are used elsewhere in this wiki, and both go on the Raspberry Pis only.

| Label | Used by | Put it on |
| --- | --- | --- |
| `kube-vip-host=true` | kube-vip, the floating API address ([Load balancers](load-balancers.md)) | Servers whose LAN interface is `eth0` |
| `pihole-host=true` | Pi-hole placement ([Pi-hole](../apps/pihole.md)) | Nodes that should run a Pi-hole pod |

**Run on: server-1.** One command per node, so all are labelled before anything is scheduled.

```sh
sudo kubectl label node server-1 kube-vip-host=true pihole-host=true
sudo kubectl label node server-2 kube-vip-host=true pihole-host=true
sudo kubectl label node server-3 kube-vip-host=true pihole-host=true
sudo kubectl get nodes -L kube-vip-host,pihole-host
```

Leave out whichever label you do not need. A Mac VM gets neither.

### Step 5. Take a snapshot

**Run on: server-1.**

```sh
sudo k3s etcd-snapshot save --name fresh-build
```

Snapshots land in `/var/lib/rancher/k3s/server/db/snapshots/` on the node where you ran the command. A snapshot can only be restored with the token that was in use when it was taken, so keep the token with it.

### Step 6. Scale cluster DNS

k3s installs cluster DNS (CoreDNS) as a single pod. On a cluster meant to survive a node failure that is a single point of failure. Scale it to three: [CoreDNS](coredns.md).

## Check it

**Run on: server-1.**

```sh
sudo kubectl get nodes -o wide
sudo kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.spec.podCIDRs}{"\n"}{end}'
sudo kubectl get pods -A | grep -v -E 'Running|Completed'
```

Expected:

| Command | Expected result |
| --- | --- |
| First | Every node `Ready`, roles `control-plane,etcd`, `INTERNAL-IP` is its `192.168.50.x` address |
| Second | Two pod ranges per node: one `10.42.x.0/24` and one inside `fd00:1234:5678:42xx::/64` |
| Third | Only the header line |

If you also have kube-vip: `sudo kubectl --server https://192.168.50.10:6443 get nodes` answers.

**Failover test.** Do this when a few minutes of disruption is acceptable. Reboot one server that is not `server-1` (`sudo reboot` on it). While it is down, `sudo kubectl get nodes` on `server-1` must still answer. Then reboot `server-1` and run `sudo kubectl get nodes` on another server (through the floating address if you have one). Anything that lives only on the rebooted node, such as a pod with a local volume, is down until the node is back.

> **Not verified:** the failover test was never run on the cluster this page describes.

## Converting a single SQLite server with agents

This is how the cluster described here actually came to be: one server on SQLite with agents, first converted to dual-stack, later to etcd with every node a server. It worked, but each stage had a trap. The k3s documentation does not support the dual-stack conversion at all; consider a fresh build instead.

> **Not verified:** the traps and fixes below are what was observed. The command blocks for the SQLite-to-etcd migration are written from that description; the exact commands used were not recorded.

### Back up first

**Run on: the existing server.**

```sh
sudo systemctl stop k3s
sudo cp -a /var/lib/rancher/k3s/server/db /root/k3s-db-backup
sudo cp -a /var/lib/rancher/k3s/server/token /root/k3s-token-backup
sudo ls -la /var/lib/rancher/k3s/server/db
```

The last command lists the database folder. `state.db` is the live SQLite database. **Look for a folder named `etcd` next to it.**

### The leftover etcd folder trap

If the server was ever started with etcd before (an abandoned earlier attempt), a stale `server/db/etcd` folder exists next to the live `state.db`. k3s starts from that folder and **skips the migration**, so you would come up with an old or empty cluster. Move it away before starting:

**Run on: the existing server.**

```sh
sudo mv /var/lib/rancher/k3s/server/db/etcd /root/k3s-old-etcd
```

### Migrate SQLite to etcd

Add `cluster-init: true` to `/etc/rancher/k3s/config.yaml` (and the other lines from [server-1.yaml](../../files/k3s/config/server-1.yaml) that are not there yet), then start k3s and watch the log:

**Run on: the existing server.**

```sh
sudo nano /etc/rancher/k3s/config.yaml
sudo systemctl start k3s
sudo journalctl -u k3s --no-pager | grep -i "Migrating content from sqlite to etcd"
sudo kubectl get nodes
sudo k3s etcd-snapshot save --name post-migration
```

The "Migrating content from sqlite to etcd" line is the proof that the migration ran. The server should now show roles `control-plane,etcd`, and all your workloads should still be there.

### Turn each agent into a server

Do one node at a time. This stops the agent, removes its service definition, moves any old server data aside, and installs k3s as a server with the joining config.

**Run on: the agent being converted.**

```sh
sudo systemctl disable --now k3s-agent
sudo mkdir -p /root/k3s-agent-old
sudo mv /etc/systemd/system/k3s-agent.service /etc/systemd/system/k3s-agent.service.env /root/k3s-agent-old/
sudo systemctl daemon-reload
sudo ls /var/lib/rancher/k3s/server && sudo mv /var/lib/rancher/k3s/server /root/k3s-server-old
sudo nano /etc/rancher/k3s/config.yaml
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='v1.34.3+k3s1' sh -s - server
```

In the `nano` step, paste the matching joining file ([server-2.yaml](../../files/k3s/config/server-2.yaml) or [server-3.yaml](../../files/k3s/config/server-3.yaml)) with the token filled in. The `ls … && mv …` line only moves the folder if it exists; "No such file or directory" there is the good case.

> **Pitfall (the leftover `server` folder):** a node that was once a server, even long ago, still has `/var/lib/rancher/k3s/server`. Installed as a joining server it refuses to start with "… newer than datastore and could cause a cluster outage". Moving the folder aside, as the line above does, is the fix; then install again.

When all have joined, take another snapshot (`sudo k3s etcd-snapshot save --name post-ha`).

### What broke during the conversion

| What happened | Cause | Fix |
| --- | --- | --- |
| Agent would not start: "cluster-cidr … and node-ip … must share the same IP version" | A dual-stack cluster needs an IPv4 **and** an IPv6 `node-ip` on every node | `node-ip: <v4>,<v6>` |
| Agent looped on 401 "unable to verify node identity: nodes … not found" | Stale certificates from an earlier join attempt under another name or address | Run `k3s-agent-uninstall.sh` on the node and join again |
| Single-stack to dual-stack: k3s crashed with a flannel "no IPv6" lease error | The old node record had no IPv6 address | Stop k3s, put the dual-stack config in place, start k3s, and run `sudo kubectl delete node <name>` during startup so the node re-registers |
| SQLite to etcd would have been skipped | Leftover `server/db/etcd` folder next to the live `state.db` | Move the folder away (above). Look for "Migrating content from sqlite to etcd" in the log |
| A node would not start as a server: "… newer than datastore and could cause a cluster outage" | It had once been a server and still had `/var/lib/rancher/k3s/server` | `sudo mv /var/lib/rancher/k3s/server /root/k3s-server-old`, then install again |
| A LoadBalancer service jumped from its MetalLB address to a node's own address after the k3s restart | The built-in load balancer (servicelb) and MetalLB were both running; the restart let servicelb win | `disable: servicelb` on **every** server. [Load balancers](load-balancers.md) |
| Apps logged intermittent DNS failures (`getaddrinfo ENOTFOUND`, `EAI_AGAIN`) for days afterwards | Pods created before the dual-stack conversion, CoreDNS among them, kept their single IPv4 address, so the IPv6 cluster DNS address answered nothing | Restart CoreDNS and any other old pod. [CoreDNS](coredns.md) |
| Things that used a node's own address for a service stopped working | With servicelb off, services are no longer published on every node's address | Point them at the service's MetalLB address |

After a single-stack to dual-stack conversion, list every pod's addresses and restart the ones that have only one:

**Run on: server-1.**

```sh
sudo kubectl get pods -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,IPS:.status.podIPs
```

> **Not verified:** only CoreDNS was checked and restarted on the cluster this was done on. Other pods older than the conversion may exist.

## Tokens

The token is the contents of `/var/lib/rancher/k3s/server/token` on any server. Anyone who has it can join a node to your cluster. Keep it in a password manager; the config files in this repo carry the placeholder `<K3S_TOKEN>`. If the token has been pasted anywhere it should not have been, rotate it.

**Run on: server-1.**

```sh
sudo k3s token rotate --token "$(sudo cat /var/lib/rancher/k3s/server/token)" --new-token "$(openssl rand -hex 32)"
sudo cat /var/lib/rancher/k3s/server/token
```

Then put the new token into `/etc/rancher/k3s/config.yaml` on every other server and restart k3s on each (`sudo systemctl restart k3s`), one at a time. Snapshots taken before the rotation still need the **old** token to restore, so keep it with them.

> **Not verified:** token rotation was not run by the author. The command is from the [k3s token documentation](https://docs.k3s.io/cli/token). The same goes for certificate rotation, which k3s also provides and which was never needed here.

## Upgrades

To upgrade, run the install command again on each server with the new version tag. Because all settings are in `config.yaml`, nothing else is needed on the command line.

**Run on: each server, one at a time.**

```sh
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='<NEW_VERSION_TAG>' sh -s - server
```

Wait for the node to be `Ready` again (`sudo kubectl get nodes`) before doing the next, so quorum is never at risk. Take a snapshot first.

> **Not verified:** no upgrade was performed on the cluster this page describes. The procedure is from the [k3s manual upgrade documentation](https://docs.k3s.io/upgrades/manual).

Things to check after every upgrade or reinstall, because k3s manages them itself and may reset them:

| Check | Command | If wrong |
| --- | --- | --- |
| CoreDNS still has three replicas | `sudo kubectl -n kube-system get deploy coredns` | [CoreDNS](coredns.md) |
| The built-in load balancer is still off | `sudo kubectl get pods -n kube-system \| grep svclb` prints nothing | [Load balancers](load-balancers.md) |
| Traefik still has its address | `sudo kubectl get svc -A \| grep LoadBalancer` | Re-apply the annotation, [Load balancers](load-balancers.md) |
| Every node runs the same version | `sudo kubectl get nodes` | Finish the upgrade on the remaining nodes |

## Pitfalls

| What happens | Why | How to avoid or recover |
| --- | --- | --- |
| "permission denied" on `/etc/rancher/k3s/k3s.yaml` | `kubectl` without `sudo` on a node | `sudo kubectl …` |
| Install: download failed | Short version such as `v1.34` | Full tag, `v1.34.3+k3s1` |
| "must share the same IP version" | `node-ip` has one address family on a dual-stack cluster | Both addresses, comma between |
| 401 "node not found", the node waits forever | Stale certificates from an earlier join | `k3s-agent-uninstall.sh` (agent) or `k3s-uninstall.sh` (server), rejoin |
| "… newer than datastore and could cause a cluster outage" | Leftover `/var/lib/rancher/k3s/server` folder | Move it aside, install again |
| Migration to etcd silently skipped | Leftover `server/db/etcd` folder | Move it aside before starting with `cluster-init` |
| Two servers joined at the same time, one fails | etcd adds one member at a time | Join one, wait for `Ready`, then the next |
| Control plane stops when the "spare" fourth server is off and one more node reboots | Four members need three | Keep to three servers, or accept it. See the quorum table |
| A node's address changed and it never rejoins | etcd members are known by address | Fixed addresses on the hosts ([Raspberry Pi](../hardware/raspberry-pi.md), Step 7); DHCP reservation for a VM |
| The token ends up in a repository or a chat | It was pasted into a config file that got shared | Placeholders in files; rotate if exposed |

## Troubleshooting

Start on the node in question:

**Run on: the affected node.**

```sh
sudo systemctl status k3s --no-pager | head -12
sudo journalctl -u k3s --no-pager -n 40
ip -br addr show eth0
free -h
df -h /
```

| Symptom | Cause | Fix |
| --- | --- | --- |
| k3s is `active` and `kubectl` on this node works, but the floating API address does not | kube-vip | `sudo kubectl -n kube-system get pods -o wide \| grep kube-vip`; use `--server https://192.168.50.5:6443` meanwhile. [Load balancers](load-balancers.md) |
| Log repeats "etcdserver: no leader" or "context deadline exceeded" | Quorum lost | Bring another server back. Is a VM host asleep? |
| Log shows "slow fdatasync" or "apply request took too long" again and again | The disk is too slow for etcd | Move that node to an SSD. [Raspberry Pi](../hardware/raspberry-pi.md), Step 3 |
| `eth0` has no LAN address | The node lost its address | Reach it over IPv6 from another node (`ssh <USER>@fd00:1234:5678:50::7`), pin the address |
| Fatal line naming files "newer than datastore" | Leftover server folder | Move `/var/lib/rancher/k3s/server` aside, install again |
| Flannel "no IPv6" lease error after going dual-stack | Stale node record without an IPv6 address | Delete the node record during startup |
| Disk at 100% | Logs or images | `sudo k3s crictl rmi --prune`; `sudo journalctl --vacuum-size=200M` |
| Node is healthy locally but `NotReady` as seen from the others | The nodes cannot talk to each other | Host firewall: [Node firewall](node-firewall.md) |
| A pod is `Pending`: "didn't match Pod's node affinity/selector" | A node label is missing | `sudo kubectl get nodes -L pihole-host,kube-vip-host`, Step 4 |
| A pod is `Pending`: "persistentvolumeclaim … not found" or "node affinity conflict" | Its `local-path` volume lives on a different node | Such a pod can only run on the node holding its data |
| A pod is `ImagePullBackOff` | The node's own DNS | [Raspberry Pi](../hardware/raspberry-pi.md), Step 7 |
| A pod is `CrashLoopBackOff` | The app starts and dies | `sudo kubectl -n <namespace> logs <name> --previous --tail=40` |
| A pod is `OOMKilled` | Out of memory, usually on a 2 GB node | `sudo kubectl top nodes` |
| Cluster DNS stops when one node is down | CoreDNS is back to one replica | [CoreDNS](coredns.md) |

To see why any pod will not start: `sudo kubectl -n <namespace> describe pod <name> | tail -25`. The last lines give the reason.

## Recovery and undo

| Situation | Do this |
| --- | --- |
| One server will not rejoin | On another server `sudo kubectl delete node <name>`. On the node run `k3s-uninstall.sh`, then repeat Step 2 |
| Remove a server for good | `sudo kubectl drain <name> --ignore-daemonsets --delete-emptydir-data`, `sudo kubectl delete node <name>`, then `sudo k3s-uninstall.sh` on the node |
| Quorum lost for good (too many servers gone) | On one surviving server: `sudo systemctl stop k3s`, then `sudo k3s server --cluster-reset`. Add `--cluster-reset-restore-path=<snapshot file>` to restore a snapshot. Then start k3s, and rejoin the other servers after moving their `/var/lib/rancher/k3s/server/db` aside |
| Back out an in-place conversion | Stop k3s, restore the `server/db` backup taken in "Back up first", remove `cluster-init` from the config, start k3s |
| Remove k3s from a node entirely | `sudo k3s-uninstall.sh` (server) or `sudo k3s-agent-uninstall.sh` (agent). This deletes the node's cluster data |

> **Not verified:** `--cluster-reset`, restoring a snapshot, and backing out a conversion were never run on the cluster this page describes. Read the k3s [backup and restore](https://docs.k3s.io/datastore/backup-restore) and [etcd-snapshot](https://docs.k3s.io/cli/etcd-snapshot) pages before relying on them.

## References

- [K3s: High availability embedded etcd](https://docs.k3s.io/datastore/ha-embedded): `cluster-init`, joining servers, quorum, and converting an existing SQLite server by restarting it with `--cluster-init`.
- [K3s: Configuration options](https://docs.k3s.io/installation/configuration): the `/etc/rancher/k3s/config.yaml` file and how it relates to command-line flags.
- [K3s: Basic network options](https://docs.k3s.io/networking/basic-network-options): dual-stack `cluster-cidr` and `service-cidr`, `flannel-ipv6-masq`, and the statement that dual-stack must be configured when the cluster is created.
- [K3s: server CLI reference](https://docs.k3s.io/cli/server): every server option, including `--cluster-reset`, `--tls-san`, `--node-name`, `--flannel-iface` and `--disable`.
- [K3s: token](https://docs.k3s.io/cli/token): token types and `k3s token rotate`.
- [K3s: etcd-snapshot](https://docs.k3s.io/cli/etcd-snapshot): taking, listing and restoring snapshots.
- [K3s: Backup and restore](https://docs.k3s.io/datastore/backup-restore): what to back up, including the token file.
- [K3s: Manual upgrades](https://docs.k3s.io/upgrades/manual): upgrading with the install script, servers first and one at a time.
- [K3s: Uninstalling](https://docs.k3s.io/installation/uninstall): the uninstall scripts.
- [etcd FAQ](https://etcd.io/docs/v3.5/faq/): the failure-tolerance table and why an even number of members adds nothing.
