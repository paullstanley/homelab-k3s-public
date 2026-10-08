# CoreDNS on k3s: replicas, dual-stack and host-network pods

You end up with cluster DNS that does not depend on one node, that answers on both its IPv4 and its IPv6 address, and with a known fix for the one kind of pod that cannot use the IPv6 address at all. This page also gives a step-by-step way to find out why a pod cannot resolve names.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | k3s v1.34.3+k3s1 with its bundled CoreDNS, on a dual-stack cluster (IPv4 plus local-only IPv6 with no IPv6 default route), flannel pod network |
| **Also works for** | IPv4-only k3s clusters (only the replica section applies); other Kubernetes distributions that label CoreDNS `k8s-app=kube-dns`. Not tested by the author |
| **Time** | 10 minutes to scale; the diagnosis walk-through takes as long as the fault |
| **You need first** | A running cluster: [Highly available k3s](k3s-ha-cluster.md) |

## How it works

**CoreDNS** is the DNS server for the inside of the cluster. Pods ask it for service names (`kubernetes.default.svc.cluster.local`) and for outside names (`example.com`). It is reached through a Service called `kube-dns`, which has one fixed address per address family:

| Family | Address in the example | Comes from |
| --- | --- | --- |
| IPv4 | `10.43.0.10` | the IPv4 service range `10.43.0.0/16` |
| IPv6 | `fd00:1234:5678:4300::a` | the IPv6 service range `fd00:1234:5678:4300::/112` |

Three facts explain every problem on this page.

1. **k3s installs CoreDNS as one pod.** If that pod's node is down, nothing in the cluster resolves names until the pod is rescheduled.
2. **A pod gets its addresses when it is created, and never again.** A CoreDNS pod created while the cluster was IPv4-only has no IPv6 address, even after the cluster becomes dual-stack. The IPv6 `kube-dns` address then has nothing behind it.
3. **A service address is not a real address on any interface.** It only works because the kernel rewrites packets sent to it. An ordinary pod sends everything through its node, so the rewrite happens. A pod with `hostNetwork: true` (it uses the node's own network instead of getting its own) relies on the **node's routing table** to decide whether the packet can be sent at all, and the node may have no route that covers the service range.

For outside names, CoreDNS forwards to the resolvers in its **node's** `/etc/resolv.conf`. That is one more reason the nodes must use working outside DNS and not a DNS server inside the cluster; see [Raspberry Pi](../hardware/raspberry-pi.md), Step 7.

What a pod's `/etc/resolv.conf` normally contains:

```
search <namespace>.svc.cluster.local svc.cluster.local cluster.local home.example.com
nameserver 10.43.0.10
nameserver fd00:1234:5678:4300::a
options ndots:5
```

`ndots:5` means: a name with fewer than five dots is first tried with each `search` suffix appended. So `api.example.com` (two dots) is looked up as `api.example.com.<namespace>.svc.cluster.local`, then with the next suffix, and so on, before it is tried as written. With four search domains that is four wasted lookups for every outside name, and four more chances for one of them to time out.

## Steps

### Step 1. Scale CoreDNS to three replicas

**Run on: server-1.**

```sh
sudo kubectl -n kube-system scale deployment coredns --replicas=3
sudo kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
```

The first line asks for three CoreDNS pods. The second lists them with the node each landed on.

> **Why a command and not a file:** CoreDNS is managed by k3s itself, so there is no manifest of yours to edit.

**Does it survive upgrades?** The replica count had survived k3s restarts on the cluster this was written on. Whether it survives a k3s **upgrade** or reinstall is not known.

> **Not verified:** the count is believed to persist across a k3s upgrade but this has not been observed. **Check it after every k3s upgrade or reinstall**, and run the scale command again if it is back to one.

### Step 2. Make sure every CoreDNS pod has both addresses

Only for dual-stack clusters.

**Run on: server-1.**

```sh
sudo kubectl -n kube-system get pod -l k8s-app=kube-dns -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.status.podIPs}{"\n"}{end}'
sudo kubectl -n kube-system get endpointslices -l kubernetes.io/service-name=kube-dns
```

Every pod must list **two** addresses: a `10.42.x.x` one and an `fd00:1234:5678:42xx::` one. Both endpoint slices (one IPv4, one IPv6) must list endpoints, not `<unset>`.

If a pod has only one address, it is older than the cluster's dual-stack conversion. Recreate the pods:

```sh
sudo kubectl -n kube-system rollout restart deployment coredns
sudo kubectl -n kube-system rollout status deployment coredns
```

Cluster DNS drops for a few seconds. On a cluster built dual-stack from the start this does not arise.

> **What this looked like:** a single CoreDNS pod, 245 days old, with only an IPv4 address. The IPv6 endpoint slice for `kube-dns` was empty and `fd00:1234:5678:4300::a` answered nothing from any pod. Every pod in the cluster had that dead address as its second name server.

The same applies to every other pod that predates the conversion. List all pods with their addresses and restart the ones that show only one:

```sh
sudo kubectl get pods -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,IPS:.status.podIPs
```

### Step 3. Fix DNS for host-network pods

Only if you run a pod with `hostNetwork: true` that uses cluster DNS, on a cluster whose nodes have no route to the IPv6 service range. Home-automation bridges are the usual case, because they need the node's own network for device discovery.

First confirm that you are affected.

**Run on: the node the pod runs on.**

```sh
ip -6 route get fd00:1234:5678:4300::a
ip -6 route show default
```

If the first answers "Network is unreachable" and the second prints nothing, a host-network pod on this node cannot reach the IPv6 cluster DNS address. With local-only IPv6 this is the **expected state, not a fault**: the nodes have routes for the IPv6 pod ranges (`fd00:1234:5678:4200::/56`, through `flannel-v6.1` and `cni0`) but none for the service range, and there is deliberately no IPv6 default route. The rewrite rules for the address exist (`sudo ip6tables-save | grep -i '4300::a'` shows them), but the kernel refuses the packet before they are consulted.

The consequence: the pod's second name server can never be reached. Every time a lookup on the first one is slow or lost, the lookup fails outright instead of being retried elsewhere. It shows up as intermittent errors, a few times an hour, such as `getaddrinfo ENOTFOUND <name>` and `getaddrinfo EAI_AGAIN <name>` in a Node.js app. Knock-on errors follow: an app that renews a login token through the day and hits a failed lookup logs "401" or "Unauthorized" until the next successful renewal.

**The fix** is to give that pod its own DNS settings: the IPv4 cluster DNS address only, and `ndots` lowered to 1. In the pod spec (or the equivalent keys of the app's Helm values file):

```yaml
dnsPolicy: None
dnsConfig:
  nameservers:
    - 10.43.0.10
  searches:
    - <namespace>.svc.cluster.local
    - svc.cluster.local
    - cluster.local
    - home.example.com
  options:
    - name: ndots
      value: "1"
```

| Line | Meaning |
| --- | --- |
| `dnsPolicy: None` | Do not generate DNS settings for this pod; use exactly what `dnsConfig` says |
| `nameservers: [10.43.0.10]` | One name server: the IPv4 `kube-dns` address. Confirm yours with `sudo kubectl -n kube-system get svc kube-dns` |
| `searches` | Keeps short service names working |
| `ndots: 1` | A name containing at least one dot is tried as written first, so outside names cost one lookup instead of five |

A complete working example is the DNS block in [files/homebridge/values.yaml](../../files/homebridge/values.yaml); see [Homebridge](../apps/homebridge.md). Any other host-network app needs the same block.

Ordinary pods (not `hostNetwork`) are not affected. They reach the IPv6 service address through their node.

**A cluster-wide alternative** is to add a route for the service range on every node, made permanent in each node's network configuration:

```sh
sudo ip -6 route add fd00:1234:5678:4300::/112 dev cni0
```

> **Not verified:** this route was never applied or tested. It is listed as an idea only. The `dnsConfig` block is the fix that was used and observed to work.

## Check it

**Run on: server-1.**

```sh
sudo kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
sudo kubectl -n kube-system get pod -l k8s-app=kube-dns -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.status.podIPs}{"\n"}{end}'
sudo kubectl -n kube-system get endpointslices -l kubernetes.io/service-name=kube-dns
```

Pass: three pods `Running` on different nodes; every pod has two addresses; both endpoint slices list endpoints.

If one of your nodes is a part-time machine (a laptop VM), make sure at least one CoreDNS pod is on an always-on node.

For a host-network pod with the DNS block, **run in: the pod's shell**:

```sh
cat /etc/resolv.conf
for i in $(seq 1 20); do getent hosts example.com >/dev/null && echo ok || echo FAIL; done | sort | uniq -c
```

Pass: one `nameserver 10.43.0.10` line, no `fd00:` line, `options ndots:1`, and `20 ok`.

**Run on: server-1** to confirm the policy took effect:

```sh
sudo kubectl -n <namespace> get pod -o jsonpath='{.items[0].spec.dnsPolicy}{"\n"}'
```

Prints `None`.

## Testing DNS from inside a pod, step by step

Use this when the LAN has DNS and the cluster looks healthy, but an app in a pod intermittently cannot look names up. It works for any pod you can get a shell in (`sudo kubectl -n <namespace> exec -it <pod> -- sh`, or the app's own web terminal if it has one).

### 1. Which name servers does the pod use?

**Run in: the pod's shell.**

```sh
cat /etc/resolv.conf
```

| You see | Meaning |
| --- | --- |
| `10.43.0.10` **and** `fd00:1234:5678:4300::a`, `ndots:5` | The normal generated settings. Correct for an ordinary pod. For a host-network pod this is the fault: add the DNS block (Step 3) |
| Only `nameserver 10.43.0.10`, `options ndots:1` | The DNS block is in effect. Go to 2 |
| The node's resolvers (`1.1.1.1`, `9.9.9.9`) | The pod is using the node's DNS, not the cluster's. It cannot resolve service names. Look at its `dnsPolicy` |

### 2. Test each name server on its own, 20 times

Intermittent faults need repetition, and each server must be tested separately because a normal lookup hides which one failed.

If the image has Node.js, **run in: the pod's shell**, as one line (do not let it break across lines when pasting):

```sh
node -e 'const d=require("dns").promises;(async()=>{for(const s of process.argv.slice(1)){const r=new d.Resolver({timeout:2000,tries:1});r.setServers([s]);let ok=0,e={};for(let i=0;i<20;i++){try{await r.resolve4("example.com");ok++}catch(x){e[x.code]=(e[x.code]||0)+1}}console.log(s,"ok:",ok,JSON.stringify(e))}})()' 10.43.0.10 fd00:1234:5678:4300::a 1.1.1.1
```

It queries each listed server 20 times with a 2-second timeout and prints how many succeeded and which errors occurred. A healthy answer **from a host-network pod**:

```
10.43.0.10 ok: 20 {}
fd00:1234:5678:4300::a ok: 0 {"ECONNREFUSED":20}
1.1.1.1 ok: 20 {}
```

The middle line failing is normal from a host-network pod and stays that way. `ECONNREFUSED` is how Node reports "could not contact the server"; the real reason is "Network is unreachable". From an ordinary pod all three lines should show `ok: 20`.

If the image has no Node.js, start a throwaway pod instead. **Run on: server-1.**

```sh
sudo kubectl run dnstest --image=busybox --restart=Never -- sh -c 'for s in 10.43.0.10 fd00:1234:5678:4300::a; do echo "== $s"; nslookup kubernetes.default.svc.cluster.local $s; done'
sleep 30
sudo kubectl logs dnstest
sudo kubectl delete pod dnstest
```

> **Not verified:** the Node one-liner was used for real (with the app's own API host name in place of `example.com`). The busybox variant with an explicit server is added here as an equivalent and was not run by the author; a simpler form, `nslookup kubernetes.default.svc.cluster.local` with no server argument, was. To pin the test pod to one node, add `--overrides='{"spec":{"nodeName":"<node>","tolerations":[{"operator":"Exists"}]}}'`.

| Result | Meaning | Next |
| --- | --- | --- |
| `10.43.0.10` fails, `1.1.1.1` works | CoreDNS, or the pod network path to it | 3 |
| Both fail | The node has lost its way out, or the router is intercepting DNS | Check the node's own DNS and your router's DNS redirection: [DNS design](../network/dns-design.md) |
| The IPv6 address fails from an ordinary pod | CoreDNS has no IPv6 endpoints | 3, then Step 2 above |
| Everything listed in the pod's `resolv.conf` passes | The failures come in bursts | Run it again when the app logs a fresh error |

### 3. Look at CoreDNS

**Run on: server-1.**

```sh
sudo kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
sudo kubectl -n kube-system get pod -l k8s-app=kube-dns -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.status.podIPs}{"\n"}{end}'
sudo kubectl -n kube-system get endpointslices -l kubernetes.io/service-name=kube-dns
sudo kubectl -n kube-system logs -l k8s-app=kube-dns --tail=100 | grep -v 'import glob'
```

| Result | Meaning | Fix |
| --- | --- | --- |
| Fewer than three pods, or all on one node | The replica count was reset | Step 1 |
| A pod with one address only; the IPv6 endpoint slice shows `<unset>` | The pod is older than dual-stack | Step 2 |
| `i/o timeout` or `SERVFAIL` in the log | CoreDNS cannot reach its upstream, which is the node's own DNS | Fix the node's DNS: [Raspberry Pi](../hardware/raspberry-pi.md), Step 7 |
| Only "No files matching import glob pattern" warnings | Normal | Nothing |

### 4. Is it the route?

**Run on: the node the pod runs on.**

```sh
ip -6 route get fd00:1234:5678:4300::a
ip -6 route show default
sudo ip6tables-save | grep -i '4300::a'
ping -6 -c 3 "$(sudo kubectl -n kube-system get pod -l k8s-app=kube-dns -o jsonpath='{.items[0].status.podIPs[1].ip}')"
```

The last line pings a CoreDNS pod's own IPv6 address. On a cluster with local-only IPv6 the normal state is: "Network is unreachable", no default route, rules present, ping answers. That proves the IPv6 **pod** network is fine and only the **service** address is unreachable from the host, which is exactly the host-network case in Step 3.

### 5. Did it stop?

Search the app's log for the errors and look at the newest timestamps. For example:

```sh
grep -E 'ENOTFOUND|EAI_AGAIN' <path-to-app-log> | tail -5
```

Pass: nothing newer than the fix. If there was an error every half hour before, a few quiet hours is good evidence; a clean day is better.

## Pitfalls

| What happens | Why | How to avoid or recover |
| --- | --- | --- |
| Cluster DNS stops when one node goes down | CoreDNS is a single pod and it was on that node | Three replicas (Step 1) |
| CoreDNS is back to one pod after an upgrade | k3s manages the deployment and may reset it | Check after every upgrade; scale again |
| The IPv6 `kube-dns` address answers nothing from any pod | CoreDNS pod older than the dual-stack conversion | `rollout restart` (Step 2) |
| A host-network pod has intermittent `ENOTFOUND` / `EAI_AGAIN` | It was given an IPv6 name server it has no route to | `dnsPolicy: None` with an IPv4-only `dnsConfig` (Step 3) |
| An app logs "401" / "Unauthorized" / "failed to refresh token" alongside DNS errors | A token renewal hit a failed lookup | Fix DNS first. It recovers at the next successful renewal or restart; re-link the account only if the errors continue with no DNS errors |
| Removing the DNS block from a host-network app "to tidy up" | It looks optional | It is required for as long as the pod is `hostNetwork` on such a cluster |
| The CoreDNS log is full of `[WARNING] No files matching import glob pattern: /etc/coredns/custom/*.override` | No custom configuration is installed | Normal. Filter it out with `grep -v 'import glob'` |
| CoreDNS answers cluster names but outside names fail | The node's `/etc/resolv.conf` points at something dead, often a DNS server that runs in the cluster | Nodes use outside resolvers |
| A long one-line test command runs as garbage in a web terminal | It was pasted as several lines | Paste it as one line |

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `fd00:1234:5678:4300::a` answers nothing from any pod; IPv6 endpoint slice for `kube-dns` is `<unset>` | CoreDNS pod older than the dual-stack conversion, so IPv4-only | `sudo kubectl -n kube-system rollout restart deployment coredns` |
| `fd00:1234:5678:4300::a` unreachable **from a node or a host-network pod only**: "Network is unreachable" | No route to the IPv6 service range on the host. Normal with local-only IPv6 | IPv4-only DNS block for that pod |
| Cluster DNS stops when one node is down | CoreDNS back to one replica | Scale to three |
| Pods on one node cannot resolve anything | That node's pod network is broken, for example the wrong `flannel-iface` on a VM | [Mac in a Lima VM](../hardware/mac-lima-vm.md) |
| `i/o timeout` / `SERVFAIL` in the CoreDNS log | Upstream (node DNS) unreachable | Node DNS |
| Lookups from pods fail after a host firewall was enabled | The firewall blocks pod or node traffic | [Node firewall](node-firewall.md) |

## Undo

```sh
sudo kubectl -n kube-system scale deployment coredns --replicas=1
```

To remove the host-network fix, delete the `dnsPolicy` and `dnsConfig` keys from the app's values file and redeploy it. Expect the intermittent failures to return.

## References

- [Kubernetes: DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/): pod DNS policies, `dnsConfig`, search domains and `ndots`.
- [Kubernetes: Debugging DNS resolution](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/): the upstream checklist for DNS problems in a cluster.
- [Kubernetes: IPv4/IPv6 dual-stack](https://kubernetes.io/docs/concepts/services-networking/dual-stack/): how pods and Services get an address per family.
- [K3s: networking services](https://docs.k3s.io/networking/networking-services): CoreDNS is deployed automatically by k3s on server start.
- [K3s: basic network options](https://docs.k3s.io/networking/basic-network-options): dual-stack service ranges and the statement that dual-stack is meant to be set at cluster creation.
- [CoreDNS: forward plugin](https://coredns.io/plugins/forward/): forwarding outside names to the resolvers in `/etc/resolv.conf`.
