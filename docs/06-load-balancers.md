# 06. Floating addresses: kube-vip, MetalLB, Traefik

Three addresses float between nodes. Everything else is reached through them.

| Address | Owned by | Serves | Moves when |
| --- | --- | --- | --- |
| 192.168.50.10 | kube-vip | Kubernetes API (port 6443) | The Pi holding it dies |
| 192.168.50.11 and `fd00:1234:5678:50::11` | MetalLB | Pi-hole DNS (53) and web (80) | The announcing node dies or has no healthy Pi-hole pod |
| 192.168.50.12 | MetalLB | Traefik (80, 443): Pi-hole UI, Homebridge, Seerr | The announcing node dies |

The design rule is **as few load-balancer addresses as possible**: DNS gets its own because every device points at it, and every web app shares Traefik's. A new web app gets an Ingress, not a MetalLB address.

## The built-in k3s load balancer must stay off

k3s ships its own load balancer, "servicelb" (pods named `svclb-…`). It publishes every LoadBalancer Service on the nodes' own addresses. It ran next to MetalLB for months, mostly harmlessly, with a dozen `svclb` pods stuck `Pending`.

> **Trouble we hit:** during the etcd conversion k3s restarted, servicelb won the race, and Pi-hole's address became 192.168.50.5 instead of .11. The Pi-hole UI stopped loading and the `values.yaml`, which clearly said .11, looked like it was being ignored. The fix was `disable: servicelb` in `/etc/rancher/k3s/config.yaml` on every server, then a k3s restart. It is in all four config files in this repo.

Side effects of turning it off, all handled elsewhere in this repo:

- Traefik moved from the nodes' own addresses to 192.168.50.12. The Cloudflare tunnel pointed at `localhost:80` and broke ([09](09-seerr-and-cloudflare.md)).
- 192.168.50.5 stopped answering DNS. Nodes and the router's DNS Director rule that used it broke ([02](02-router-xt8.md), [04](04-k3s-cluster.md)).
- `hb.home.example.com` had to point at .12 instead of .5 ([08](08-homebridge.md)).

Check it is off:

```bash
sudo kubectl get pods -n kube-system | grep svclb
```

No output is correct.

## Step 1. MetalLB

**Paste on: k3sprimary**, in the root of this repo. Use exactly v0.15.3.

```bash
sudo kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml
sudo kubectl -n metallb-system rollout status deploy/controller --timeout=180s
sudo kubectl apply -f metallb/config.yaml
sudo kubectl get ipaddresspools,l2advertisements -n metallb-system
```

If the last `apply` fails with a webhook error, the controller is not ready. Wait for the rollout and apply again.

The pool is 192.168.50.11 to .15. It was .10 to .15 until 3 October; .10 was taken out so MetalLB can never hand out kube-vip's address.

## Step 2. Traefik on 192.168.50.12

Traefik comes with k3s. With servicelb off and MetalLB running, it takes the first free pool address. To make sure that is .12 on a rebuild, install Pi-hole first so it claims .11, or pin Traefik:

```bash
sudo kubectl -n kube-system annotate svc traefik metallb.io/loadBalancerIPs=192.168.50.12 --overwrite
sudo kubectl get svc -A | grep LoadBalancer
```

You should see `traefik` on 192.168.50.12. The annotation is the documented MetalLB way to request an address; on this cluster Traefik got .12 without it, so the annotation itself has not been tested here. k3s may reset annotations on its bundled Traefik when k3s is upgraded; if Traefik ever moves, run the line again.

Then the redirect rules:

```bash
sudo kubectl create namespace pihole
sudo kubectl create namespace homebridge
sudo kubectl apply -f traefik/middleware-redirect-https.yaml
```

"AlreadyExists" on the namespace lines is fine.

## Step 3. kube-vip on 192.168.50.10

The three Pis must carry `kube-vip-host=true` first ([04](04-k3s-cluster.md), Step 6).

```bash
sudo kubectl apply -f k3s/kube-vip/helmchart.yaml
sleep 60
sudo kubectl -n kube-system get pods -o wide | grep kube-vip
ping -c 3 192.168.50.10
sudo kubectl --server https://192.168.50.10:6443 get nodes
```

You should see three `kube-vip` pods `Running`, one on each Pi, three ping replies, and the node list.

If you use `kubectl` from a laptop, set the `server:` line in its kubeconfig to `https://192.168.50.10:6443`.

> **Trouble we hit:** the installer job landed on the Mac VM while the Mac's pod network was broken, and hung. Cordon the Mac, delete the stuck pod, let it run on a Pi, uncordon. And the Mac must not carry the `kube-vip-host` label ([05](05-mac-node-lima.md)).

## Which node holds which address right now

```bash
sudo kubectl -n kube-system get lease | grep -i vip
sudo kubectl -n metallb-system get servicel2statuses.metallb.io
sudo kubectl -n pihole get events --sort-by=.lastTimestamp | grep -i announc | tail -5
```

From any Mac on the LAN, `arp -a | grep 192.168.50.1[012]` shows the MAC address answering for each; compare with the node MACs in [01](01-inventory.md).

MetalLB addresses do not answer ping. Test .11 with `nslookup example.com 192.168.50.11` and .12 with `curl -I http://192.168.50.12`.

## Adding another web app

Give its Service type `ClusterIP`, give it an Ingress with class `traefik` and a host name, and add `address=/<name>.home.example.com/192.168.50.12` to `pihole/values.yaml`. On the work Mac, add the name to `/etc/hosts` too ([11](11-clients.md)).
