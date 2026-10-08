# Load balancers: MetalLB, kube-vip and Traefik's address

You end up with a small set of fixed LAN addresses that float between nodes: one for the Kubernetes API, one for each service that truly needs its own (such as DNS), and one shared by every web app. When the node holding an address dies, another node takes it over and clients notice nothing but a short pause.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | k3s v1.34.3+k3s1 (with its bundled Traefik), MetalLB v0.15.3 in layer-2 mode, kube-vip installed from its Helm chart through k3s's Helm controller, on Raspberry Pi 4 servers with wired `eth0` |
| **Also works for** | Other k3s versions and other hardware on one flat Ethernet LAN. Not tested by the author |
| **Time** | 30 minutes |
| **You need first** | A running k3s cluster: [Highly available k3s](k3s-ha-cluster.md). kube-vip only makes sense with more than one server |

## How it works

A Kubernetes Service of type `LoadBalancer` asks for an address that the outside world can reach. On a cloud that is the cloud's job. On your own hardware something else has to do it.

| Piece | What it does |
| --- | --- |
| **ServiceLB** (also called klipper; pods named `svclb-…`) | k3s's built-in answer. It publishes every LoadBalancer Service on **each node's own address**. No extra addresses, but a service has no single address that survives a node failure |
| **MetalLB, layer-2 mode** | Hands each Service an address from a pool you define. One node at a time answers for that address on the LAN (by ARP for IPv4, NDP for IPv6). If that node dies, another takes over. It is failover, not traffic spreading |
| **kube-vip** | The same floating-address idea, used here only for the Kubernetes API (port 6443), so `kubectl` and joining nodes have one address that is always up |
| **Traefik** | The ingress controller that ships with k3s. It holds one LoadBalancer address and routes web requests to the right app by host name |

The design rule is **as few load-balancer addresses as possible**. DNS gets its own because every device points at it. Every web app shares Traefik's. A new web app gets an Ingress, not a MetalLB address.

The example layout:

| Address | Owned by | Serves | Moves when |
| --- | --- | --- | --- |
| `192.168.50.10` | kube-vip | Kubernetes API (6443) | The server holding it dies |
| `192.168.50.11` and `fd00:1234:5678:50::11` | MetalLB | A DNS service (Pi-hole): 53, and its web port 80 | The announcing node dies or has no healthy pod of that service |
| `192.168.50.12` | MetalLB | Traefik (80, 443): every web app | The announcing node dies |
| `192.168.50.13` to `.15` | MetalLB | Free | |

**ServiceLB and MetalLB cannot both run.** Both act on the same Services. See the next section.

## What happens if you leave ServiceLB on

With both running, things can look fine for months: MetalLB assigns the addresses, and a dozen `svclb` pods sit in `Pending`. Then k3s restarts, ServiceLB wins the race, and:

- A Service that was on its MetalLB address (`192.168.50.11`) now shows a node's own address (`192.168.50.5`) as its external address, and is published on every node.
- IPv6 LoadBalancer Services go to `<pending>`.
- Clients configured with the MetalLB address get no answer. The values file that clearly asks for `.11` looks as if it is being ignored.

The fix is `disable: servicelb` in `/etc/rancher/k3s/config.yaml` on **every** server, then a k3s restart on each. One server without the line is enough to bring ServiceLB back. All four example files in [files/k3s/config/](../../files/k3s/config/) carry it.

Turning it off has side effects wherever something relied on "the service answers on every node's address":

| What breaks | Why | Fix |
| --- | --- | --- |
| Anything pointed at a node's address for web traffic, for example a tunnel or reverse proxy aimed at `localhost:80` on a node | Traefik moves from the nodes' own addresses to its MetalLB address | Point it at `192.168.50.12`. See [Seerr behind a Cloudflare tunnel](../apps/seerr-cloudflare-tunnel.md) |
| Devices or router rules using a node's address as DNS server | The node's address stops answering on port 53 | Point them at `192.168.50.11`. See [DNS design](../network/dns-design.md) |
| Local names that pointed at a node's address | Same | Point them at `192.168.50.12` |
| The nodes themselves, if they used a node address for DNS | Same, and now they cannot pull images | Nodes use outside DNS: [Raspberry Pi](../hardware/raspberry-pi.md), Step 7 |

## Before you start

| Decide | Example | Notes |
| --- | --- | --- |
| MetalLB IPv4 pool | `192.168.50.11-192.168.50.15` | Outside the router's DHCP pool, on the LAN subnet |
| MetalLB IPv6 pool | `fd00:1234:5678:50::11/128` | One address, only for a service that asks for it. Leave the pool out on an IPv4-only cluster |
| API address | `192.168.50.10` | **Outside** the MetalLB pool, so MetalLB can never hand it out. Must be listed under `tls-san` in every server's k3s config |
| Traefik address | `192.168.50.12` | Inside the MetalLB pool |
| MetalLB version | `v0.15.3` | Use exactly this one; see Pitfalls |

Edit [files/metallb/config.yaml](../../files/metallb/config.yaml) and [files/k3s/kube-vip/helmchart.yaml](../../files/k3s/kube-vip/helmchart.yaml) to your addresses before applying them.

## Steps

### Step 1. Disable ServiceLB on every server

Skip this if you built the cluster from the config files in this repo; it is already there.

**Run on: each server, one at a time.**

```sh
sudo nano /etc/rancher/k3s/config.yaml
```

Add these two lines (or add `- servicelb` to an existing `disable:` list):

```yaml
disable:
  - servicelb
```

Then restart k3s and wait for the node to be `Ready` before doing the next server:

```sh
sudo systemctl restart k3s
sudo kubectl get nodes
```

**Run on: server-1**, when all servers are done.

```sh
sudo kubectl get pods -n kube-system | grep svclb
```

No output is correct. Until MetalLB is installed, LoadBalancer Services show `<pending>`.

### Step 2. Install MetalLB

**Run on: server-1**, from the root of this repo.

```sh
sudo kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml
sudo kubectl -n metallb-system rollout status deploy/controller --timeout=180s
sudo kubectl apply -f files/metallb/config.yaml
sudo kubectl get ipaddresspools,l2advertisements -n metallb-system
```

The first line installs MetalLB. The second waits for its controller. The third creates the address pools and the layer-2 advertisement. The last lists them.

What [files/metallb/config.yaml](../../files/metallb/config.yaml) defines:

| Object | Name | Content | Why |
| --- | --- | --- | --- |
| `IPAddressPool` | `pool` | `192.168.50.11-192.168.50.15` | General pool. Services get the next free address unless they ask for one |
| `IPAddressPool` | `pool-v6` | `fd00:1234:5678:50::11/128`, `autoAssign: false` | A separate IPv6 pool that is never handed out automatically, so no other Service can take the DNS service's IPv6 address. It is only given to a Service that asks for it by address |
| `L2Advertisement` | `l2-advertisement` | both pools | Announce these addresses on the LAN by ARP/NDP |

> **Pitfall:** if the `apply` of the config fails with a webhook error, the controller is not ready yet. Wait for the rollout and apply again.

### Step 3. Give Traefik a fixed address

Traefik comes with k3s. With ServiceLB off and MetalLB running, it takes the first free address in the pool. Which one that is depends on install order: if a service that asks for `.11` by name is installed first, Traefik gets `.12`. To make it certain, pin it with MetalLB's annotation:

**Run on: server-1.**

```sh
sudo kubectl -n kube-system annotate svc traefik metallb.io/loadBalancerIPs=192.168.50.12 --overwrite
sudo kubectl get svc -A | grep LoadBalancer
```

You should see `traefik` with external address `192.168.50.12`.

> **Not verified:** the annotation is MetalLB's documented way to request an address, but on the cluster this was written on Traefik received `.12` simply by being second in line, so the annotation itself was not tested. k3s manages its bundled Traefik and may reset annotations when k3s is upgraded; if Traefik ever moves, run the line again. The k3s documentation describes a permanent alternative, a `HelmChartConfig` for Traefik, which was not used here.

### Step 4. The HTTPS redirect middleware

A Traefik **Middleware** is a small rule applied to requests before they reach the app. [files/traefik/middleware-redirect-https.yaml](../../files/traefik/middleware-redirect-https.yaml) defines one named `redirect-https` that sends `http://` requests to `https://` with a permanent redirect.

An Ingress can only refer to a Middleware as `<namespace>-<name>@kubernetescrd`, so the file contains **one copy per namespace** that needs it. As shipped it has copies for the namespaces `pihole` and `homebridge`. Edit it to the namespaces of your own apps: copy one block and change `namespace:`.

**Run on: server-1**, from the root of this repo.

```sh
sudo kubectl create namespace pihole
sudo kubectl create namespace homebridge
sudo kubectl apply -f files/traefik/middleware-redirect-https.yaml
```

"AlreadyExists" on the namespace lines is fine. The namespaces must exist before the Middleware can be created in them.

An app's Ingress then switches the redirect on with this annotation (the example values files for [Pi-hole](../apps/pihole.md) and [Homebridge](../apps/homebridge.md) already contain it):

```yaml
traefik.ingress.kubernetes.io/router.middlewares: pihole-redirect-https@kubernetescrd
```

Do **not** use the redirect on an app that sits behind a proxy which talks plain HTTP to Traefik and does HTTPS itself, such as a Cloudflare tunnel; it would redirect forever. See [Seerr behind a Cloudflare tunnel](../apps/seerr-cloudflare-tunnel.md).

Traefik serves its own self-signed certificate for local names, so browsers show a warning once per name. That is expected.

### Step 5. kube-vip for the API address

[files/k3s/kube-vip/helmchart.yaml](../../files/k3s/kube-vip/helmchart.yaml) is a `HelmChart` object. k3s has a built-in Helm controller that installs any chart described this way, so no `helm` command is needed. What it sets:

| Value | Setting | Meaning |
| --- | --- | --- |
| `config.address` | `192.168.50.10` | The floating address |
| `vip_interface` | `eth0` | The interface the address is added to |
| `vip_arp` | `true` | Announce by ARP (layer 2) |
| `cp_enable` | `true` | Float the control plane (API) address |
| `svc_enable`, `lb_enable` | `false` | Do not handle Services or load-balance; MetalLB does Services |
| `vip_leaderelection` | `true` | The kube-vip pods elect one holder |
| `nodeSelector` | `kube-vip-host: "true"` | Only run on nodes carrying this label |
| `tolerations` | `operator: Exists` | Run on control-plane nodes whatever their taints |

Two conditions must hold first:

1. `192.168.50.10` is listed under `tls-san` in **every** server's `/etc/rancher/k3s/config.yaml`, so the API certificate is valid for it.
2. The servers that may hold the address carry the label. Only label nodes whose LAN interface is really `eth0`.

**Run on: server-1**, from the root of this repo.

```sh
sudo kubectl label node server-1 kube-vip-host=true
sudo kubectl label node server-2 kube-vip-host=true
sudo kubectl label node server-3 kube-vip-host=true
sudo kubectl apply -f files/k3s/kube-vip/helmchart.yaml
sleep 60
sudo kubectl -n kube-system get pods -o wide | grep kube-vip
ping -c 3 192.168.50.10
sudo kubectl --server https://192.168.50.10:6443 get nodes
```

You should see one `kube-vip` pod `Running` on each labelled node, three ping replies, and the node list.

If you use `kubectl` from a laptop, set the `server:` line in its kubeconfig to `https://192.168.50.10:6443`.

#### If you also have a Mac VM node

A [Lima VM node](../hardware/mac-lima-vm.md) must **not** carry the `kube-vip-host` label: its LAN interface is `lima0`, not `eth0`, and a kube-vip pod there crash-loops.

```sh
sudo kubectl label node server-4 kube-vip-host-
```

The chart is installed by a short-lived installer pod, and that pod can land on any node. If it lands on a node whose pod network is broken it hangs. Cordon that node (`sudo kubectl cordon server-4`), delete the stuck pod, let it run elsewhere, then `sudo kubectl uncordon server-4`.

### Step 6. Put more web apps behind the one Traefik address

For each new web app:

1. Give its Service type `ClusterIP` (internal only), not `LoadBalancer`.
2. Give it an Ingress with class `traefik` and a host name, for example `app.home.example.com`.
3. Make that name resolve to `192.168.50.12` on your LAN. With Pi-hole from this wiki, that is a line `address=/app.home.example.com/192.168.50.12` in [files/pihole/values.yaml](../../files/pihole/values.yaml); see [Pi-hole](../apps/pihole.md).
4. For a client that does not use your LAN's DNS (a laptop on a work VPN, say), add the name to its hosts file; see [Client devices](../apps/client-devices.md).

Traefik tells the apps apart by the host name in each request, which is how they all share one address.

## Check it

**Run on: server-1.**

```sh
sudo kubectl get svc -A | grep LoadBalancer
sudo kubectl get pods -n kube-system | grep svclb
sudo kubectl --server https://192.168.50.10:6443 get nodes
curl -I http://192.168.50.12
```

| Command | Expected result |
| --- | --- |
| First | Each LoadBalancer Service shows an address from the pool. `traefik` on `192.168.50.12`. Nothing `<pending>`, and no node's own address |
| Second | No output (ServiceLB is off) |
| Third | The node list: the API answers on the floating address |
| Fourth | An HTTP response from Traefik (a `404` is fine; it means Traefik answered and has no rule for a bare address) |

To test one app through Traefik without relying on DNS, send its host name by hand. A `301` proves the routing rule and the redirect:

```sh
curl -sI -H 'Host: pihole.home.example.com' http://192.168.50.12/admin/ | head -1
```

Which node holds which address right now:

```sh
sudo kubectl -n kube-system get lease | grep -i vip
sudo kubectl -n metallb-system get servicel2statuses.metallb.io
sudo kubectl -n <namespace> get events --sort-by=.lastTimestamp | grep -i announc | tail -5
```

The first shows the kube-vip leader. The second lists, per Service, the node MetalLB is announcing from. The third shows recent announcement changes for the Services in one namespace.

**Run on: your computer** (macOS or Linux on the LAN).

```sh
arp -a | grep '192.168.50.1[012]'
```

This shows the MAC address answering for each floating address; compare with your nodes' MAC addresses.

## Pitfalls

| What happens | Why | How to avoid or recover |
| --- | --- | --- |
| `ping 192.168.50.11` or `.12` fails although the service works | MetalLB addresses do not answer ping; only the Service's ports are forwarded | Test with the real protocol: `nslookup example.com 192.168.50.11`, `curl -I http://192.168.50.12`. (The kube-vip address does answer ping) |
| A Service shows a node's own address, or `<pending>` on IPv6, after a k3s restart | ServiceLB is back | `disable: servicelb` on every server; [above](#what-happens-if-you-leave-servicelb-on) |
| MetalLB controller in `CrashLoopBackOff` or failing its liveness probe | Version. v0.16.0's controller failed its liveness probe on this hardware, and the `:main` image crash-looped | Use exactly v0.15.3 |
| `kubectl apply` of the MetalLB config: webhook error | Controller not ready | Wait for the rollout, apply again |
| MetalLB gives a Service the API address | The API address was inside the pool | Keep kube-vip's address outside the pool (`.10` outside `.11`-`.15`) |
| Another Service takes the IPv6 address meant for DNS | The IPv6 pool was auto-assigned | `autoAssign: false` on that pool |
| Traefik moves to another address | It was never pinned, or an upgrade reset the annotation | Step 3 again |
| `http://` does not redirect | The Middleware is missing in that app's namespace | Add a copy for the namespace and apply the file |
| kube-vip installer hangs | It landed on a node with a broken pod network | Cordon, delete the pod, uncordon (Step 5) |
| kube-vip pod crash-loops on one node | The node is labelled but its LAN interface is not `eth0` | Remove the label from that node |
| Certificate error when using the floating API address | The address is not in `tls-san` on the servers | Add it to every server's config and restart k3s on each |

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| LoadBalancer shows `<pending>` | MetalLB controller down, pool missing, or pool exhausted | `sudo kubectl -n metallb-system get pods -o wide`; Step 2 |
| Pods healthy and the Service has its address, but nothing answers on it | MetalLB is not announcing, or announcing from a node with no healthy pod | `sudo kubectl -n metallb-system logs -l component=speaker --tail=30`. Restart the speakers: `sudo kubectl -n metallb-system rollout restart daemonset speaker` |
| `curl` to `192.168.50.12` cannot connect at all | Traefik is not on that address | `sudo kubectl -n kube-system get pods \| grep traefik`; Step 3 |
| `404 page not found` | Traefik is up but has no rule for that host name | The Ingress is missing or names another host. `sudo kubectl get ingress -A` |
| `502` or `Bad Gateway` | Traefik has the rule but the app does not answer | The pod is down, or the app is serving HTTPS itself while Traefik speaks HTTP to it |
| `301`, `302`, `307` or `200` from `curl -H 'Host: …'`, but the browser fails | The cluster side is fine | The name does not resolve to `192.168.50.12` on that client, or stale browser state. Check with `nslookup <name>` on the client |
| An app that worked through Traefik stopped after ServiceLB was disabled | It was reached on a node's own address | Point it at `192.168.50.12` |
| `kubectl` on a node works, the floating API address does not | kube-vip | `sudo kubectl -n kube-system get pods -o wide \| grep kube-vip`. Use `--server https://192.168.50.5:6443` meanwhile |
| Speakers log "Suspect <node> has failed"; an address keeps moving between nodes | Not explained. Suspects: a host firewall blocking MetalLB's port 7946 between nodes, or a VM node's networking | [Node firewall](node-firewall.md#the-ipv6-gap); [Mac in a Lima VM](../hardware/mac-lima-vm.md#open-point-metallb-on-the-vm) |

## Undo

**Run on: server-1**, from the root of this repo.

```sh
sudo kubectl -n kube-system delete helmchart kube-vip
sudo kubectl delete -f files/traefik/middleware-redirect-https.yaml
sudo kubectl -n kube-system annotate svc traefik metallb.io/loadBalancerIPs-
sudo kubectl delete -f files/metallb/config.yaml
sudo kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml
```

In order: remove kube-vip (first set any kubeconfig that uses `192.168.50.10` back to a server's own address), remove the redirect rules, unpin Traefik, remove the pools, remove MetalLB. To get ServiceLB back, remove `servicelb` from the `disable:` list on every server and restart k3s on each.

> **Not verified:** only the kube-vip removal line comes from the original configuration. The rest is the standard reverse of the install and was not run by the author.

## References

- [MetalLB: installation](https://metallb.io/installation/): installing by manifest, including the native-mode manifest used here.
- [MetalLB: configuration](https://metallb.io/configuration/): `IPAddressPool` and `L2Advertisement`.
- [MetalLB: advanced AddressPool configuration](https://metallb.io/configuration/_advanced_ipaddresspool_configuration/): `autoAssign: false` and other pool controls.
- [MetalLB: usage](https://metallb.io/usage/): requesting a specific address with `metallb.io/loadBalancerIPs`, sharing an address, dual-stack Services.
- [MetalLB in layer 2 mode](https://metallb.io/concepts/layer2/): how one node announces an address, how failover works, and its limits.
- [MetalLB: issues with K3s](https://metallb.io/configuration/k3s/): why Klipper (ServiceLB) must be disabled.
- [K3s: networking services](https://docs.k3s.io/networking/networking-services): how ServiceLB works, `--disable=servicelb`, and how the bundled Traefik is managed.
- [K3s: Helm](https://docs.k3s.io/add-ons/helm): the `HelmChart` and `HelmChartConfig` resources and `valuesContent`.
- [kube-vip: K3s](https://kube-vip.io/docs/usage/k3s/): a control-plane address on k3s and the matching `tls-san` requirement.
- [kube-vip Helm charts](https://github.com/kube-vip/helm-charts): the chart installed by the `HelmChart` object.
- [Traefik: RedirectScheme middleware](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/redirectscheme/): the `scheme` and `permanent` options.
