# FlareSolverr for Jackett and Prowlarr

You end up with FlareSolverr, a small proxy that opens Cloudflare-protected indexer pages in a real browser, gets past the "checking your browser" challenge, and hands the result back to Jackett or Prowlarr. Indexers that fail with "Challenge detected but FlareSolverr is not configured" can then work again, as long as their challenge is not a captcha.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own. This page is written for indexers you use legitimately. It does not name or recommend any.

| | |
| --- | --- |
| **Applies to** | Written for Jackett v0.24 on an Intel Mac (`media-1`, `192.168.50.2`) and a k3s v1.34 cluster with MetalLB v0.15.3 (Raspberry Pi 4 servers plus an arm64 Lima VM). The manifest [`files/flaresolverr/flaresolverr.yaml`](../../files/flaresolverr/flaresolverr.yaml) was **validated with kubeconform but not yet applied by the author**. Nothing on this page has been run against a live indexer yet |
| **Also works for** | Prowlarr instead of Jackett (its settings are described from the Servarr wiki). Any Kubernetes cluster with a load balancer, or any Docker host. FlareSolverr on the same Mac, or on a Windows PC, is described below and **not verified by the author** |
| **Time** | 15 minutes on the cluster, plus a test per indexer |
| **You need first** | Jackett or Prowlarr running: [Jackett and Prowlarr](./jackett-and-prowlarr.md). For the recommended option, a k3s cluster with MetalLB: [Highly available k3s](../kubernetes/k3s-ha-cluster.md) and [Load balancers](../kubernetes/load-balancers.md) |

## What it can and cannot solve

Read this before you install anything. FlareSolverr fixes some indexers, not all.

| Challenge the indexer shows | Result with FlareSolverr |
| --- | --- |
| Cloudflare's JavaScript "checking your browser" or managed challenge (a page that waits a few seconds and then lets you in) | Usually solved |
| DDoS-GUARD challenge | Supported by FlareSolverr, per its README |
| hCaptcha, or any image captcha ("click all the buses") | **Not solved.** Jackett reports "FlareSolverr was able to process the request, but a captcha was detected" |

The FlareSolverr README says plainly: "At this time none of the captcha solvers work." Jackett's troubleshooting page says "There is currently no solution for the hCaptcha challenge" and "Currently Captcha Solvers do not work", and points to FlareSolverr issues [#24](https://github.com/FlareSolverr/FlareSolverr/issues/24) and [#31](https://github.com/FlareSolverr/FlareSolverr/issues/31) for progress. There is no fix today for an indexer that shows a captcha. Remove it from Jackett and from Sonarr and Radarr instead ([Jackett and Prowlarr, Step 7](./jackett-and-prowlarr.md#step-7-keep-sonarr-and-radarr-in-step-with-jackett)).

Most indexers need no FlareSolverr at all. Jackett's README calls it optional.

## How it works

1. Jackett requests an indexer page and gets a Cloudflare challenge instead of results.
2. If a **FlareSolverr API URL** is set, Jackett sends the request to FlareSolverr (a `POST` to `/v1` on port `8191`).
3. FlareSolverr opens the page in Google Chrome, driven by Selenium and undetected-chromedriver (tools that steer a real browser and hide that it is automated). It waits for the challenge to pass.
4. It returns the page and the **cookies** Cloudflare issued, plus the browser's **User-Agent** (the string a browser uses to identify itself).
5. Jackett repeats its request with those cookies and that User-Agent, and Cloudflare lets it through.

Two things follow from step 5:

- **The cookies only work from where they were earned.** Cloudflare's clearance cookie may be tied to the public IP address that solved the challenge, and to browser details such as the User-Agent. If FlareSolverr's traffic leaves the house by a different public address than Jackett's, Jackett gets "The cookies provided by FlareSolverr are not valid". Jackett's troubleshooting page says to keep both on the same network, ideally the same device, with no proxy or VPN between them.
- **FlareSolverr has no login.** Anyone who can reach port `8191` can make it fetch any page. **Never expose port 8191 to the internet**: no router port forward, no tunnel. The FlareSolverr README says "DO NOT expose FlareSolverr to the internet".

A full Chrome runs inside FlareSolverr, so it needs a few hundred MB of memory while solving.

## Before you start

### Choose where to run it

| | Where | How | Same public IP as Jackett? | Notes |
| --- | --- | --- | --- | --- |
| **(a)** | **The k3s cluster** (recommended for this build) | The provided manifest: one pod, MetalLB address `192.168.50.13`, port `8191` | **Yes.** The nodes and the Mac leave the house through the same WAN address | The image is multi-arch (amd64, arm64, arm/v7, 386), so it runs on a Pi or the Lima VM. Always on, restarted if it crashes, and it keeps Chrome off the media Mac |
| **(b)** | **The same Mac as Jackett** | From source (Python 3.11 + Google Chrome, x64 only, so Intel Macs only), or the Docker image under Docker Desktop or Colima | Yes, by definition | There is no ready-made macOS build. Jackett's troubleshooting page calls the same device the best case. **Not verified by the author** on macOS 26 |
| **(c)** | **The Windows torrent PC** (`torrent-pc`, `192.168.50.16`) | The Windows x64 binary from the releases page | **No**, if that PC's traffic goes through a VPN app and Jackett's does not | Not recommended in a build like this one; see below |

**Why (c) breaks.** In the [qBittorrent behind a VPN](./qbittorrent-windows-vpn.md) setup, the Windows PC's internet traffic leaves through the VPN, from a public address in another country. Jackett runs on the Mac and leaves through the home WAN address ([Indexer traffic and privacy](./jackett-and-prowlarr.md#indexer-traffic-and-privacy)). FlareSolverr on the PC would earn its cookies from the VPN's address, and Cloudflare would reject them when Jackett presents them from the home address. Jackett then reports "The cookies provided by FlareSolverr are not valid". Option (c) only makes sense if Jackett also runs on that PC behind the same VPN, or if the VPN app excludes FlareSolverr (split tunnelling); neither is tested here.

The rest of this page follows option (a). Option (b) is in [If you run it on the Mac instead](#if-you-run-it-on-the-mac-instead).

### Gather

| Value | Example | Notes |
| --- | --- | --- |
| A free MetalLB address | `192.168.50.13` | Inside the MetalLB pool (`192.168.50.11` to `.15` here), not used by another Service. See [Load balancers](../kubernetes/load-balancers.md) |
| The LAN range allowed to connect | `192.168.50.0/24` | Later you can narrow it to the Jackett host only, `192.168.50.2/32` |
| Your time zone | `Etc/UTC` in the file | For example `America/New_York`. Only affects log times |
| Which indexers fail | From Jackett's dashboard | Note the exact error on each: "Challenge detected..." can be helped, "captcha was detected" cannot |

## Steps

### Step 1. Check the address is free

**Run on: server-1** (or any machine with `kubectl` access to the cluster)

```sh
sudo kubectl get svc -A | grep 192.168.50.13
```

Expected: no output. If a Service already holds `192.168.50.13`, pick another free pool address and change the `metallb.io/loadBalancerIPs` annotation in the manifest to match.

### Step 2. Read and adjust the manifest

Open [`files/flaresolverr/flaresolverr.yaml`](../../files/flaresolverr/flaresolverr.yaml). It creates:

| Object | What it does |
| --- | --- |
| Namespace `flaresolverr` | Keeps it apart from other apps |
| Deployment `flaresolverr` | One pod with the image `ghcr.io/flaresolverr/flaresolverr:latest`, port `8191`, `LOG_LEVEL=info`, `TZ=Etc/UTC`. Requests 100m CPU and 256 MiB, memory limit 1 GiB. A 256 MiB in-memory `/dev/shm`, because Chrome uses shared memory and the container default is small. Readiness and liveness probes on `GET /`. Strategy `Recreate`, so an update never runs two browsers at once |
| Service `flaresolverr` | Type `LoadBalancer` with the annotation `metallb.io/loadBalancerIPs: 192.168.50.13`, port `8191`. `loadBalancerSourceRanges: 192.168.50.0/24` lets only the main LAN connect |

Change `TZ` to your time zone if you like. Change the address if Step 1 found it taken.

> **Why one replica:** FlareSolverr holds no state worth sharing, and one browser is enough for a home indexer manager. If the pod or its node dies, Kubernetes starts another one.

### Step 3. Apply it

**Run on: server-1**, from the root of this repo.

```sh
sudo kubectl apply -f files/flaresolverr/flaresolverr.yaml
sudo kubectl -n flaresolverr rollout status deploy/flaresolverr --timeout=300s
sudo kubectl -n flaresolverr get pods,svc -o wide
```

The first line creates the objects. The second waits until the pod is ready; the first image pull can take a few minutes on a Pi. The third shows the pod `1/1 Running` and the Service with `EXTERNAL-IP` `192.168.50.13`.

### Step 4. Check it answers from the Jackett host

**Run on: the media server Mac `media-1`**

```sh
curl -s http://192.168.50.13:8191/
```

Expected: a JSON line containing `"msg": "FlareSolverr is ready!"`, a `version` and a `userAgent`. Opening the same address in a browser on the Mac shows the same JSON.

### Step 5. Point Jackett at it

1. Open the Jackett dashboard, `http://127.0.0.1:9117`, and scroll down to the **Jackett Configuration** settings.
2. Set **FlareSolverr API URL** to `http://192.168.50.13:8191`.
3. Leave **FlareSolverr Max Timeout (ms)** at its default (`55000` was the value seen in the build). Jackett's README recommends the default.
4. Click **Apply server settings**.
5. On the dashboard, click **Test** on each indexer that failed with "Challenge detected but FlareSolverr is not configured". The first solve takes several seconds.
6. In Sonarr and Radarr, open **Settings > Indexers**, click the indexer, and click **Test**. Both must pass before searches use it.

> **Pitfall:** `127.0.0.1` or `localhost` as the API URL only works when FlareSolverr runs natively on the same machine as Jackett. For the cluster, use the MetalLB address.

### Step 6. Prowlarr instead of Jackett

Prowlarr uses FlareSolverr as an **indexer proxy**, applied by tag. Described from the [Servarr wiki](https://wiki.servarr.com/prowlarr/settings#indexer-proxies); **not verified by the author**.

1. **Settings > Indexer Proxies > + > FlareSolverr.**
2. **Name:** `FlareSolverr`. **Tags:** a new tag such as `flaresolverr`. **Host:** `http://192.168.50.13:8191` (the full URL, with protocol and port).
3. **Request Timeout** (shown with advanced settings): leave `60` seconds, the default; it can be 1 to 180.
4. **Test**, then **Save**.
5. Open each Cloudflare-protected indexer under **Indexers**, add the tag `flaresolverr`, and save.

Prowlarr only uses the proxy when it detects Cloudflare, and only for indexers that share its tag. A FlareSolverr proxy with no tag is inactive.

### Step 7. Optional: pin the version and narrow access

Once it works:

- **Pin the image tag.** Replace `:latest` with a release tag, for example `ghcr.io/flaresolverr/flaresolverr:v3.5.0` (marked Latest on the [releases page](https://github.com/FlareSolverr/FlareSolverr/releases) at the time of writing). Then updates happen only when you change the tag ([Software and firmware](../operations/software-and-firmware.md#flaresolverr)). Avoid v3.4.4; its release notes report a Linux binary bug and recommend v3.4.3 or v3.4.5 and later.
- **Allow only the Jackett host.** Change `loadBalancerSourceRanges` from `192.168.50.0/24` to `192.168.50.2/32`.

**Run on: server-1**, after editing the file.

```sh
sudo kubectl apply -f files/flaresolverr/flaresolverr.yaml
sudo kubectl -n flaresolverr rollout status deploy/flaresolverr --timeout=300s
```

> **Not verified:** the source-range restriction is enforced by kube-proxy on the nodes, as the comment in the manifest says. It was not tested on the cluster. Check from another LAN machine that `curl http://192.168.50.13:8191/` fails after the change, and from the Mac that it still works.

### If you run it on the Mac instead

**Not verified by the author.** From the [FlareSolverr README](https://github.com/FlareSolverr/FlareSolverr).

From source (Intel Macs only, because the from-source route is x64 only): install Python 3.11, Google Chrome, and XQuartz (the README lists XQuartz as a macOS requirement). Then:

**Run on: the media server Mac**

```sh
git clone https://github.com/FlareSolverr/FlareSolverr.git ~/Applications/FlareSolverr
cd ~/Applications/FlareSolverr
python3.11 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
python src/flaresolverr.py
```

It listens on port `8191` on all addresses (`HOST` defaults to `0.0.0.0`). Set `HOST=127.0.0.1` in the environment before starting it so only the Mac can reach it. Jackett's API URL is then `http://127.0.0.1:8191`. Running it at every login needs a LaunchAgent, which is not written here. The virtual environment (`.venv`) keeps its Python packages apart from the system; the README itself only shows `pip install -r requirements.txt`.

With Docker Desktop or Colima on the Mac, the README's command publishes the port on the Mac's loopback address only:

```sh
docker run -d --name=flaresolverr -p 127.0.0.1:8191:8191 -e LOG_LEVEL=info --restart unless-stopped ghcr.io/flaresolverr/flaresolverr:latest
```

Jackett, running natively on the Mac, then uses `http://127.0.0.1:8191`. (If Jackett itself ran in Docker, `127.0.0.1` would point at Jackett's own container and would not work.)

## Check it

**Run on: the media server Mac**

FlareSolverr is up and reachable:

```sh
curl -s http://192.168.50.13:8191/
```

Expected: `{"msg": "FlareSolverr is ready!", "version": "...", "userAgent": "..."}`.

It can fetch a page:

```sh
curl -s -X POST http://192.168.50.13:8191/v1 -H 'Content-Type: application/json' -d '{"cmd": "request.get", "url": "https://example.com/", "maxTimeout": 60000}' | head -c 300; echo
```

Expected: JSON that includes `"status": "ok"`. The page HTML and cookies follow in the full reply.

**Run on: server-1**

```sh
sudo kubectl -n flaresolverr get pods,svc
```

Expected: the pod `1/1 Running` with few or no restarts, and the Service with `EXTERNAL-IP` `192.168.50.13`.

In Jackett, **Test** on each previously failing indexer is green. In Sonarr and Radarr, **Settings > Indexers > Test All** passes and **System > Status** shows no indexer warning.

## Pitfalls

| What happens | Why | How to avoid or recover |
| --- | --- | --- |
| An indexer still fails with "captcha was detected" | It shows hCaptcha or an image captcha, which FlareSolverr cannot solve | Nothing fixes this today. Remove the indexer from Jackett and from Sonarr and Radarr |
| "The cookies provided by FlareSolverr are not valid" | FlareSolverr and Jackett leave the house by different public addresses, usually because one of them is behind a VPN or proxy | Run FlareSolverr where Jackett's traffic goes: the cluster or the same Mac. Not on the VPN'd torrent PC |
| Anyone can use your FlareSolverr | It has no authentication | Never forward `8191` on the router or publish it through a tunnel. Keep `loadBalancerSourceRanges` to the LAN or the Jackett host |
| `localhost` as the API URL fails | FlareSolverr is on another machine, or in a container | Use the address Jackett can actually reach, here `http://192.168.50.13:8191` |
| The behaviour changes after a pod restart | `:latest` pulled a new release | Pin a release tag (Step 7) |
| The pod is killed during a solve | Chrome needed more than the 1 GiB limit | Jackett retries the request. If it happens often, raise the limit (Troubleshooting) |
| A Service already used `.13` | Two Services asked for the same address | Check first (Step 1); choose another free pool address |
| Indexers time out after a long wait | The solve took longer than Jackett's FlareSolverr Max Timeout, or than Jackett's own limit of roughly 100 seconds | Keep the default timeout; read FlareSolverr's log; update FlareSolverr |

## Troubleshooting

### Jackett messages

These are the cases on [Jackett's troubleshooting page](https://github.com/Jackett/Jackett/wiki/Troubleshooting#error-connecting-to-flaresolverr-server).

| Symptom | Cause | Fix |
| --- | --- | --- |
| "Challenge detected but FlareSolverr is not configured" | The indexer is behind Cloudflare and no FlareSolverr API URL is set | Try the indexer's alternate site links in its Jackett settings, if it has any that do not use Cloudflare. Otherwise set the API URL (Step 5), or wait and test again later |
| "Error connecting to FlareSolverr server" | FlareSolverr is set but not running, or the URL is wrong | Open the API URL in a browser on the Jackett host: it must show `FlareSolverr is ready!`. Check the URL form: native on the same machine `http://127.0.0.1:8191`; another machine or Docker host by its LAN address, for example `http://192.168.50.13:8191`; a container by its IP or name only if Jackett is in the same Docker network. With Jackett in Docker, `127.0.0.1` and `localhost` do not work |
| "FlareSolverr was able to process the request, but a captcha was detected" | Image captcha or hCaptcha | No captcha solver works at present ([What it can and cannot solve](#what-it-can-and-cannot-solve)). Remove the indexer, or follow FlareSolverr issues #24 and #31 |
| "The cookies provided by FlareSolverr are not valid" | Different networks or public addresses, a proxy or VPN between them; or the site changed its login page; or the site is offline (for example an expired domain) | Put both on the same network, ideally the same device, with no VPN between. If they already are, check the site in a browser; wait for a Jackett update that fixes the indexer |
| Timeout on an indexer test | FlareSolverr did not solve within the Max Timeout set on the Jackett dashboard; Jackett gives up after roughly 100 seconds with no reply | Read FlareSolverr's log (below). Update FlareSolverr. Keep the Max Timeout at its default |

### On the cluster

| Symptom | Cause | Fix |
| --- | --- | --- |
| Pod stays `Pending` | No node has 256 MiB of memory free to reserve, or the image is still pulling | `sudo kubectl -n flaresolverr describe pod -l app=flaresolverr` and read the Events at the bottom. "Insufficient memory": free memory on a node or lower the request. Pulling: wait |
| Pod restarts with reason `OOMKilled` | Chrome used more than the 1 GiB limit | `sudo kubectl -n flaresolverr describe pod -l app=flaresolverr \| grep -A3 "Last State"`. Raise `limits.memory` to `2Gi` in the manifest and apply it again; keep the node's free memory in mind on a Pi |
| Service `EXTERNAL-IP` shows `<pending>` | The address is taken by another Service, is outside the MetalLB pool, or MetalLB is not running | `sudo kubectl get svc -A \| grep 192.168.50.13`; `sudo kubectl -n flaresolverr describe svc flaresolverr` shows MetalLB's reason in its Events; `sudo kubectl -n metallb-system get pods`. See [Load balancers](../kubernetes/load-balancers.md#troubleshooting) |
| `curl` from the Mac: connection refused or timed out | The Mac's address is not in `loadBalancerSourceRanges` (for example it moved to Wi-Fi with another address, or the range was narrowed to the wrong `/32`), or the pod is not ready | `ipconfig getifaddr en0` on the Mac and compare with the range. `sudo kubectl -n flaresolverr get pods`. Note that a MetalLB address does not answer `ping`; test with `curl` |
| Pod `0/1`, readiness probe failing | Chrome is still starting (slow on a Pi), or FlareSolverr failed to start | `sudo kubectl -n flaresolverr logs deploy/flaresolverr`. Wait a minute after start. If the log shows a Chrome error, try a different release tag. If it is only slow, raise `initialDelaySeconds` and `timeoutSeconds` on the probes |
| Need the detailed log | | `sudo kubectl -n flaresolverr logs deploy/flaresolverr --tail=100`. For more detail set `LOG_LEVEL` to `debug` in the manifest and apply it again |

## Undo

**Run on: server-1**, from the root of this repo.

```sh
sudo kubectl delete -f files/flaresolverr/flaresolverr.yaml
```

This deletes the namespace, the pod and the Service and frees `192.168.50.13`. Then clear **FlareSolverr API URL** in Jackett and click **Apply server settings**, or delete the FlareSolverr indexer proxy in Prowlarr (**Settings > Indexer Proxies**) and its tag from the indexers. Indexers that needed it will fail again with "Challenge detected but FlareSolverr is not configured".

For the Mac variants: stop `python src/flaresolverr.py` and delete its folder, or run `docker rm -f flaresolverr`.

## References

- [FlareSolverr on GitHub (README)](https://github.com/FlareSolverr/FlareSolverr): how it works, images and architectures, binaries, running from source, environment variables, the `/v1` API, the captcha-solver status and the security warning.
- [FlareSolverr releases](https://github.com/FlareSolverr/FlareSolverr/releases): release tags to pin, and the v3.4.4 Linux binary note.
- [FlareSolverr issue #24](https://github.com/FlareSolverr/FlareSolverr/issues/24) and [issue #31](https://github.com/FlareSolverr/FlareSolverr/issues/31): the captcha issues Jackett's troubleshooting page points to.
- [Jackett README: configuring FlareSolverr](https://github.com/Jackett/Jackett#configuring-flaresolverr): the API URL and Max Timeout settings.
- [Jackett troubleshooting: Error connecting to FlareSolverr server](https://github.com/Jackett/Jackett/wiki/Troubleshooting#error-connecting-to-flaresolverr-server): every FlareSolverr error message, URL forms, captcha and cookie problems, timeouts.
- [Prowlarr settings: indexer proxies (Servarr wiki)](https://wiki.servarr.com/prowlarr/settings#indexer-proxies): the FlareSolverr proxy fields and how tags select indexers.
- [MetalLB usage](https://metallb.io/usage/): requesting a specific address with the `metallb.io/loadBalancerIPs` annotation.
