# qBittorrent on Windows behind a VPN app

You end up with qBittorrent (a free BitTorrent client) on a Windows PC whose torrent traffic can only leave through a VPN, while its web interface stays reachable from the media server on the LAN. Sonarr and Radarr on the media server send it downloads, and it saves them straight onto the media server's disk over the network, so finished files can be imported without copying them across.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own. This page is written for content you have the right to download and share.

| | |
| --- | --- |
| **Applies to** | qBittorrent v5.1.0 (Qt 6.9, libtorrent 1.2.20, Web API 2.11.4) on a Windows PC, run in a signed-in user session (not as a service), bound to the network adapter of the Proton VPN app. Downloads go to a mapped drive that points at an SMB share on a Mac running Sonarr, Radarr and Plex. Settings on this page were read from that running install |
| **Also works for** | qBittorrent 5.2.x (the current stable line, 5.2.4 at the time of writing, with Web UI hardening; update to it). Other VPN apps that create their own network adapter (the binding works the same; their menu names differ). Running qBittorrent as a Windows service is described from community sources and is **not tested by the author** |
| **Time** | 45 minutes |
| **You need first** | [Media stack overview](./media-stack-overview.md). A VPN subscription and its Windows app. The media server's download share: see [Plex Media Server](./plex-media-server.md) for the Mac and its File Sharing. To use it from Sonarr and Radarr: [Sonarr and Radarr](./sonarr-and-radarr.md) |

Example values on this page:

| Thing | Example |
| --- | --- |
| Torrent PC | `torrent-pc`, `192.168.50.16`, name `torrent.home.example.com` |
| Media server (Mac) | `media-1`, `192.168.50.2` |
| Download folder on the Mac | `/Volumes/Media/Downloads` |
| Mac's SMB share | `\\192.168.50.2\Media` (the volume `/Volumes/Media`) |
| The same folder on Windows | `M:\Downloads` (the share mapped as drive `M:`) |
| Web UI | `http://192.168.50.16:8080`, user `<QBIT_USER>`, password `<QBIT_PASSWORD>` |
| VPN adapter name | `ProtonVPN` (the name the VPN app gives its network adapter; yours may differ) |

## How it works

```
Sonarr / Radarr on media-1 ──LAN──> qBittorrent Web UI 192.168.50.16:8080
                                        │
qBittorrent torrent traffic ──only──> VPN adapter ──> VPN server ──> peers
                                        │
qBittorrent writes files ──LAN, SMB──> M:\Downloads = media-1:/Volumes/Media/Downloads
```

- **Two separate bindings.** The Web UI (the browser interface and the API that Sonarr and Radarr use) listens on the PC's LAN address. The torrent engine is told to use only the VPN app's network adapter (**Network interface** in the advanced options). The two do not affect each other.
- **Binding is a kill switch of its own.** When the VPN is disconnected its adapter goes down, and qBittorrent has no other interface it is allowed to use, so torrent traffic stops instead of falling back to your normal connection. This works even if the VPN app's own kill switch is off or fails. The Web UI keeps working, because it is on the LAN address.
- **The VPN app must let LAN traffic through.** The PC must still talk to the Mac: Sonarr and Radarr call the Web UI, and qBittorrent writes to the Mac's share. VPN apps have a setting for this (Proton calls it **Allow LAN connections**).
- **Ports.** Incoming torrent connections arrive at the VPN server's public address, not at your router. Opening or forwarding a port on your own router (by hand or by UPnP, the protocol programs use to ask a router to open ports) does nothing for them. Only port forwarding offered by the VPN provider helps.
- **Paths differ between the machines.** qBittorrent saves to `M:\Downloads\...`. Sonarr and Radarr on the Mac see the same files as `/Volumes/Media/Downloads/...`. A *remote path mapping* in Sonarr and Radarr translates one into the other.
- **Categories** tag each torrent with who sent it (`tv-sonarr`, `radarr`). With Automatic Torrent Management, a category also decides the sub-folder the files go into.

## Before you start

| Decide or gather | Notes |
| --- | --- |
| A fixed address for the PC | `192.168.50.16`, as a DHCP reservation on the router or set on the PC. The Web UI binds to this exact address; if it changes, the Web UI is not reachable |
| A Windows account to run it under | qBittorrent keeps its settings per user. Use a normal (non-administrator) account if you can. In the build it ran in an administrator's session; that works, but anything that takes over qBittorrent then has full control of the PC |
| Automatic sign-in and start-up | qBittorrent, the VPN app and the mapped drive all need that user to be signed in. Plan for the PC to sign in by itself after a restart, or sign in by hand after every reboot |
| Sleep | Set **Settings > System > Power > Sleep** to **Never** on mains power. A sleeping PC drops off the network and Sonarr reports the client as unreachable |
| VPN app | Installed, signed in, set to connect at start-up. Find its adapter name: run `Get-NetAdapter` in PowerShell while it is connected |
| VPN port forwarding | Optional; needs a plan and server type that support it. Without it qBittorrent shows as "firewalled" and still downloads, with fewer peers |
| The Mac's share | File Sharing on the Mac shares the volume holding `Downloads` (here `/Volumes/Media` as `Media`), with read and write access for a Mac user. You need that user's name and password: `<MAC_USER>`, `<MAC_PASSWORD>` |
| Web UI login | A user name and a new password for qBittorrent's Web UI |

> **Why on the same volume as the library:** if `Downloads` is on the same Mac volume as the TV and Movies folders (`/Volumes/Media/TV`, `/Volumes/Media/Movies`), Sonarr and Radarr can import with hard links: the file appears in the library without being copied and without using space twice while it is still seeding. A download on one volume imported to another volume is a full copy. See [Sonarr and Radarr](./sonarr-and-radarr.md).

## Steps

### Step 1. Install qBittorrent

Download the installer from the [official download page](https://www.qbittorrent.org/download): `qbittorrent_<version>_x64_setup.exe` (libtorrent 1.2, as in the build) or `qbittorrent_<version>_lt20_x64_setup.exe` (libtorrent 2.0). The page lists Windows 10 or later. Get it only from that page or the project's GitHub; do not install a copy from an app store or another site.

Run the installer with the defaults. Start qBittorrent once as the user that will run it, accept the legal notice, then close it again (**File > Exit**) before changing anything in Step 5, so that you start from a saved settings file.

When Windows Defender Firewall asks whether qBittorrent may communicate on networks, allow it. That creates a rule for the program; the Web UI gets its own narrower rule in Step 6.

### Step 2. Set up the VPN app

The settings that matter, in Proton VPN's terms; other VPN apps have equivalents. A page with the exact VPN app settings used in this build is to come; until then follow the vendor's articles linked here.

| Setting | Value | Why |
| --- | --- | --- |
| Connect at start-up | On | qBittorrent has no traffic until the VPN is up |
| **Allow LAN connections** (Settings > Connection > Advanced settings) | On | Lets traffic to devices on your LAN skip the tunnel. Without it the PC cannot reach the Mac's share and may not answer Sonarr and Radarr. It is on by default and needs a paid plan ([Proton article](https://protonvpn.com/support/lan-connections)) |
| Kill switch | Your choice | **Standard** blocks the internet only when the VPN drops by accident. **Advanced** blocks all internet traffic unless the VPN is connected, also after a restart ([Proton article](https://protonvpn.com/support/what-is-kill-switch)). qBittorrent's interface binding (Step 5) protects torrent traffic either way |
| Split tunnelling | Not needed if LAN connections are allowed | An alternative: in **Exclude** mode, list `192.168.50.0/24` so LAN traffic stays outside the tunnel. On Windows both kill switch modes work together with split tunnelling ([Proton article](https://protonvpn.com/support/protonvpn-split-tunneling)) |
| Port forwarding | Optional | See Step 7 |

> **Not verified:** whether Proton's **Advanced** kill switch on Windows also blocks LAN connections is not stated in Proton's documentation and was not tested by the author. After changing kill switch settings, re-run the checks in [Check it](#check-it).

### Step 3. Map the Mac's share as drive M:

On the PC, signed in as the user that runs qBittorrent:

1. Open File Explorer, right-click **This PC**, choose **Map network drive**.
2. **Drive:** `M:`. **Folder:** `\\192.168.50.2\Media`.
3. Tick **Reconnect at sign-in** and **Connect using different credentials**. Click **Finish**.
4. Enter `<MAC_USER>` and `<MAC_PASSWORD>` and tick **Remember my credentials**. Windows stores them in Credential Manager (Control Panel > Credential Manager > Windows Credentials), so the drive reconnects at the next sign-in without asking.
5. Create the folder `M:\Downloads` if it does not exist yet. It is `/Volumes/Media/Downloads` on the Mac.

Check from PowerShell:

**Run on: torrent-pc**, in PowerShell, as the same user

```powershell
net use
cmdkey /list
Test-Path M:\Downloads
```

`net use` lists `M:` with `\\192.168.50.2\Media` and status `OK`. `cmdkey /list` shows a Windows credential for `192.168.50.2`. `Test-Path` prints `True`.

> **Pitfall:** a mapped drive belongs to the signed-in user's session. A program running as a service, or as a different user, does not see `M:` at all. If you ever run qBittorrent as a service, use the UNC path `\\192.168.50.2\Media\Downloads` as its save path instead. See [Running as a service](#running-qbittorrent-as-a-windows-service).

### Step 4. Find the VPN adapter's name

**Run on: torrent-pc**, in PowerShell, with the VPN connected

```powershell
Get-NetAdapter | Format-Table Name, InterfaceDescription, Status
```

The VPN app's adapter appears with status `Up`; with Proton its name is `ProtonVPN`. Note the exact name. Disconnect the VPN and run the command again: the adapter shows `Disconnected` or disappears. That is the behaviour the binding relies on.

### Step 5. Configure qBittorrent

Open **Tools > Options**. Each table is one page of the dialog. "Build" is the value found in the running install; "Recommended" is what this page suggests where the two differ.

**Downloads**

| Setting | Build | Recommended | Why |
| --- | --- | --- | --- |
| Default Torrent Management Mode (under Saving Management) | Manual | **Automatic** | Only in Automatic mode do categories put files into their own folder. In Manual mode everything lands directly in the default save path |
| When Category Save Path changed | | Relocate torrent | Keeps files where the category says |
| Default Save Path | `M:\Downloads` | `M:\Downloads` | The Mac's download folder |
| Keep incomplete torrents in | Off | Off | A separate incomplete folder is optional. If you use one, keep it on the same Mac volume so the final move is instant |
| Excluded file names | On, a list | On, see [Excluded file names](#excluded-file-names) | Files matching the list are never downloaded |

**Connection**

| Setting | Build | Recommended | Why |
| --- | --- | --- | --- |
| Port used for incoming connections | A fixed port | The port your VPN provider forwards, if any; otherwise any fixed port | See Step 7 |
| Use different port on each startup | Off | Off | A random port cannot match a forwarded one |
| Use UPnP / NAT-PMP port forwarding from my router | **On** | **Off** | Your router is not on the torrent path when traffic goes through the VPN. Proton advises turning UPnP and NAT-PMP off in the torrent client because they can conflict with its port forwarding |

**Speed**

| Setting | Build | Notes |
| --- | --- | --- |
| Global upload limit | 100 KiB/s | A deliberate cap. The Web API reports the same value as 102400 bytes per second |
| Alternative rate limits | 10 MiB/s | Used only when you switch to the alternative limits |

**BitTorrent**

| Setting | Build | Recommended | Why |
| --- | --- | --- | --- |
| DHT, PeX, Local Peer Discovery | On | On for public torrents | Ways of finding peers without a tracker. qBittorrent turns them off for torrents marked private |
| Encryption mode | Allow encryption | Allow encryption | "Require" shuts out peers that do not encrypt; "Allow" lets more peers connect |
| Enable anonymous mode | **On** | Your choice; off if you use private trackers | It makes qBittorrent identify itself less to peers and trackers. It can reduce speeds, and private trackers may reject it. With all traffic in a VPN the gain is small |
| Torrent queueing | On: 10 active downloads, 3 active uploads, 15 active torrents, "Do not count slow torrents" on | Fine | Limits how much runs at once |
| Seeding limits | None | See [Seeding and "Remove Completed"](#seeding-limits-and-remove-completed) | |

**Web UI**

| Setting | Build | Recommended | Why |
| --- | --- | --- | --- |
| Web User Interface (Remote control) | On | On | Sonarr and Radarr use it |
| IP address | `192.168.50.16` | `192.168.50.16` | Only the LAN address. `*` would also listen on the VPN adapter and on `127.0.0.1` |
| Port | `8080` | `8080` | If you change it, change it in Sonarr and Radarr and in the firewall rule too |
| Use UPnP / NAT-PMP to forward the port from my router | **On** | **Off** | It asks your router to open the Web UI port to the internet. Never wanted |
| Use HTTPS instead of HTTP | Off | Off on a home LAN | HTTPS needs a certificate here; the Web UI is only reachable from the LAN |
| Username / Password | Set | `<QBIT_USER>` / `<QBIT_PASSWORD>` | Sonarr and Radarr log in with these |
| Bypass authentication for clients on localhost | On | Either | Only matters if something on the PC itself uses the Web UI. With the Web UI bound to `192.168.50.16` it does not listen on `127.0.0.1` anyway |
| Bypass authentication for clients in whitelisted IP subnets | On | Off, or only the media server: `192.168.50.2/32` | See the risk below |
| Ban client after consecutive failures | 100 | A small number, for example `5` | 100 lets someone guess passwords for a long time |
| Ban for | 3600 seconds | 3600 seconds | |
| Session timeout | 3600 seconds | 3600 seconds | |
| Enable clickjacking protection | On | On | Stops other web pages embedding the Web UI |
| Enable Cross-Site Request Forgery (CSRF) protection | On | On | Stops other web pages sending commands through your browser |
| Enable Host header validation | On, server domains `*` | On, server domains `torrent.home.example.com;192.168.50.16` | With `*` every host name is accepted, which defeats the check. List the names you actually use |

> **Pitfall: the auth bypass whitelist.** Every client in a whitelisted subnet gets full control without a password. Full control includes options such as **Run external program**, so anyone on that subnet can make the PC run commands. Whitelisting the whole LAN (`192.168.50.0/24`) trusts every phone, TV and guest device on it. If you use the whitelist at all, list only the media server's address. Sonarr and Radarr work fine with the user name and password instead.

qBittorrent 5.2 and later can also give the Web API an API key (**Web UI > API Key**), sent as `Authorization: Bearer <key>`. Radarr supports it from v6.2.1. The build uses the user name and password.

**Behavior**

| Setting | Recommended | Why |
| --- | --- | --- |
| Start qBittorrent on Windows start up | On | It then starts when the user signs in |
| Log file | On (default) | The log is in `%LOCALAPPDATA%\qBittorrent\logs` |

**Advanced**

| Setting | Build | Recommended | Why |
| --- | --- | --- | --- |
| Network interface | `ProtonVPN` | Your VPN adapter (Step 4) | The kill switch. "Any interface" would let torrents use the normal connection when the VPN is down |
| Optional IP address to bind to | All addresses | All addresses | Leave as is with the interface set |

Click **OK**. Restart qBittorrent (**File > Exit**, then start it) so the interface binding takes effect cleanly.

> **Pitfall:** pick the adapter in the list while the VPN is connected. If the VPN app is reinstalled or renamed and its adapter gets a different name, qBittorrent stays bound to the old one and transfers nothing. The check script flags this.

### Step 6. Allow the Web UI from the LAN only

Windows Defender Firewall must let the media server reach port 8080. This rule allows it from the LAN and nowhere else.

**Run on: torrent-pc**, in PowerShell **as Administrator**

```powershell
New-NetFirewallRule -DisplayName "qBittorrent Web UI (LAN only)" -Direction Inbound -Protocol TCP -LocalPort 8080 -RemoteAddress 192.168.50.0/24 -Action Allow -Profile Any
```

`-RemoteAddress` limits the rule to senders in the LAN. `-Profile Any` makes it apply whichever network profile Windows gives the LAN adapter. To allow only the media server, use `-RemoteAddress 192.168.50.2`.

> **Pitfall:** the program rule Windows created on first start (Step 1) may already allow qBittorrent on all ports from anywhere on that network profile. The Web UI is still only reachable on the LAN address, but if you want the narrow rule to be the only way in, review **Windows Defender Firewall > Inbound Rules** for `qBittorrent` entries. Do not delete the program rule without checking that torrent connections still work; the listening port needs to be allowed too.

### Step 7. Listening port and port forwarding

- **Without VPN port forwarding:** leave a fixed port set and UPnP off. Your client can still connect out to peers and download; peers just cannot connect in. The status bar shows the connection as firewalled. This is normal.
- **With VPN port forwarding** (Proton: a paid plan, a P2P server, and the **Port forwarding** toggle): read the active port in the VPN app, then in qBittorrent **Tools > Options > Connection**, turn off UPnP / NAT-PMP and enter that number as the incoming port ([Proton article](https://protonvpn.com/support/port-forwarding)). Proton's port usually **changes every time the VPN reconnects**, so check it again after each reconnect, or the client goes back to firewalled.
- **Never** forward the port on your home router for this. Torrent traffic exits at the VPN server; a forward on your router opens a port on your home address for nothing.

### Step 8. Categories

Create one category per app. In the main window, show the side panel (**View > Side Panel**), right-click under **Categories**, choose **Add category**.

| Category | Used by | Save path |
| --- | --- | --- |
| `tv-sonarr` | Sonarr | Leave empty: with Automatic mode it becomes `M:\Downloads\tv-sonarr` |
| `radarr` | Radarr | Leave empty: `M:\Downloads\radarr` |

Sonarr and Radarr set the category on every torrent they add, and use it to find their own downloads again. The category names must match what you enter in each app's download client settings.

With Automatic Torrent Management **off** (as in the build), the category is still set but the save path is not: every download lands directly in `M:\Downloads`. That works, since Sonarr and Radarr follow each torrent by its ID, but the folder gets crowded and the check script warns about it.

### Excluded file names

**Tools > Options > Downloads > Excluded file names.** Tick it and enter one pattern per line. Files that match are marked "do not download" when a torrent is added. Media releases never need programs or shortcuts; fake releases often contain exactly those. This list is a sensible safety list:

```text
*.exe
*.bat
*.cmd
*.com
*.scr
*.pif
*.lnk
*.vbs
*.vbe
*.js
*.jse
*.wsf
*.hta
*.msi
*.ps1
*.jar
*.iso
```

Remove `*.iso` if you legitimately download disc images. If your indexers only carry packed (RAR) releases you need extra unpacking anyway; the TRaSH guide's note on `*.rar` covers that case.

### Seeding limits and "Remove Completed"

Seeding means continuing to upload a finished torrent to others. Two settings interact:

- **In qBittorrent:** **Options > BitTorrent > Seeding Limits**: when ratio reaches *n*, or after *m* minutes of seeding, then **Stop torrent** (called Pause in older versions) or **Remove torrent**.
- **In Sonarr and Radarr:** the download client option **Remove Completed** removes a torrent from qBittorrent, after import, **once it has stopped because it reached its seeding limit**. The build has it off in Sonarr and on in Radarr. Each indexer also has a **Seed Ratio** and **Seed Time** in the apps (`1` in the build).

In the build, qBittorrent has no seeding limits. Torrents therefore seed for ever, and Radarr's "Remove Completed" never fires, because no torrent ever reaches a limit. Files stay in `M:\Downloads` until you remove them by hand.

Choose one way:

| Approach | Set | Result |
| --- | --- | --- |
| Limits in qBittorrent | A global ratio and/or time, action **Stop torrent**; **Remove Completed** on in Sonarr and Radarr | Torrents stop at the limit, then the apps remove them and their download files |
| Limits per indexer (the TRaSH guide's recommendation) | qBittorrent limits off; seed ratio and seed time on each indexer in Sonarr and Radarr (or in Prowlarr); **Remove Completed** on | The apps pass the goals on with each torrent they add. **Not verified by the author** |
| No limits | As in the build | Seeds for ever; clean up by hand |

> **Pitfall:** do not set qBittorrent's action to **Remove torrent** while you rely on Sonarr or Radarr to import. If a torrent is removed before the app has imported it, the app loses track of it. Use **Stop torrent** and let the app remove it.

With hard links, a finished download that keeps seeding costs no extra space; without them (download and library on different volumes), every seeding download is a second full copy.

## If you also have Sonarr and Radarr

In each app, **Settings > Download Clients > + > qBittorrent**:

| Field | Sonarr | Radarr |
| --- | --- | --- |
| Host | `192.168.50.16` | `192.168.50.16` |
| Port | `8080` | `8080` |
| Use SSL | Off | Off |
| Username / Password | `<QBIT_USER>` / `<QBIT_PASSWORD>` | the same |
| Category | `tv-sonarr` | `radarr` |
| Remove Completed | see above (build: off) | see above (build: on) |
| Remove Failed | On | On |

And a remote path mapping under **Settings > Download Clients > Remote Path Mappings**: host `192.168.50.16`, remote path `M:\Downloads\`, local path `/Volumes/Media/Downloads/`. Type the host exactly as in the download client and end both paths with their separator. Full details, including the case-sensitivity trap, are in [Sonarr and Radarr](./sonarr-and-radarr.md).

If you want to reach the Web UI by name, give the PC a local DNS name such as `torrent.home.example.com` pointing at `192.168.50.16` (with Pi-hole: [Local names](./pihole.md#local-names-in-the-values-file)), and add that name to the Host header validation list.

## Running qBittorrent as a Windows service

qBittorrent has no built-in Windows service mode. A long-running [community discussion](https://github.com/qbittorrent/qBittorrent/discussions/17526) (a feature request with no maintainer answer) describes wrapping `qbittorrent.exe` with NSSM, a service wrapper. **Not tested by the author.** What that discussion and the Servarr FAQ agree on:

- A service does not see the mapped drive letters of a signed-in user. Save to a UNC path such as `\\192.168.50.2\Media\Downloads`, run the service as an account that can open that share, and change the remote path mapping in Sonarr and Radarr to that UNC remote path. The [Servarr FAQ](https://wiki.servarr.com/sonarr/faq) recommends UNC paths over mapped drives for the same reason.
- The service runs under a different profile, so it starts with default settings unless you copy `qBittorrent.ini` and `BT_backup` into that account's profile.
- Users report having to stop the service to change settings in the normal window.

The signed-in user session used in the build is simpler; it needs automatic sign-in after a restart.

## Check it

**Run on: torrent-pc**, in PowerShell, as the user that runs qBittorrent. Copy [`files/media/qbit-check.ps1`](../../files/media/qbit-check.ps1) to the PC first.

```powershell
powershell -ExecutionPolicy Bypass -File .\qbit-check.ps1 -VpnAdapter "ProtonVPN" -SavePath "M:\Downloads" -MediaServer 192.168.50.2
```

`-VpnAdapter` is your VPN app's adapter name from Step 4. The script reads `qBittorrent.ini`, checks the process, the adapter and binding, the save path and mapped drive, the Web UI listener and firewall rule, Web UI UPnP, the auth whitelist, whether the PC can reach the Mac on port 8989 while the VPN is up, and seeding limits. It changes nothing and prints no passwords. Expected: `[ OK ]` lines and a summary of `0 failures`. It exits with the number of failures. **Parse-checked only: not yet run by the author.**

Two of its warnings can be expected: "Automatic Torrent Management is off" if you chose to keep Manual mode, and "no ratio limit" if you set seeding goals per indexer instead (it only looks at the global ratio).

**Run on: media-1**, in Terminal

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.50.16:8080/api/v2/app/version
```

Expected: `403` (reachable, login required) or `200` (reachable, and this Mac is in the auth bypass whitelist). No output or `000` means the Mac cannot reach the Web UI.

```bash
curl -s -i -H 'Referer: http://192.168.50.16:8080' --data-urlencode 'username=<QBIT_USER>' --data-urlencode 'password=<QBIT_PASSWORD>' http://192.168.50.16:8080/api/v2/auth/login
```

Expected: `HTTP/1.1 200 OK`, a `set-cookie: SID=...` header and the body `Ok.`. A body of `Fails.` means wrong credentials; `403` means this address is banned after too many failures.

The media server's health script runs the first check too, together with the Sonarr and Radarr download client tests: `bash files/media/media-health.sh` ([Jackett and Prowlarr](./jackett-and-prowlarr.md#check-it) describes it).

**The kill switch.** With a torrent active, disconnect the VPN in the VPN app. Transfer speeds in qBittorrent drop to zero and stay there. Reconnect: transfers resume. If they do not resume within a minute or two, restart qBittorrent (see Troubleshooting).

**The external address.** qBittorrent 5.x shows the external IP address it detected in the status bar. It must be the VPN's address, not your home address.

In Sonarr and Radarr: **Settings > Download Clients > Test** passes, and **System > Status** shows no download client warning.

## Backups

| What | Where | Contains |
| --- | --- | --- |
| Settings | `%APPDATA%\qBittorrent\qBittorrent.ini` | All options, categories, the Web UI user name and a hash of its password |
| Torrent state | `%LOCALAPPDATA%\qBittorrent\BT_backup` | One `.torrent` and one `.fastresume` file per torrent, so qBittorrent can resume them |
| Logs | `%LOCALAPPDATA%\qBittorrent\logs` | Not needed in a backup |

Quit qBittorrent first (**File > Exit**), so the files are complete. Not run by the author:

**Run on: torrent-pc**, in PowerShell, as the user that runs qBittorrent

```powershell
$dest = "M:\Backups\qbittorrent-$(Get-Date -Format yyyyMMdd)"
New-Item -ItemType Directory -Path $dest -Force | Out-Null
Copy-Item "$env:APPDATA\qBittorrent\qBittorrent.ini" $dest
Copy-Item "$env:LOCALAPPDATA\qBittorrent\BT_backup" $dest -Recurse
```

To restore, quit qBittorrent and copy both back to the same places. Treat the backup as secret: it holds the Web UI credentials. See [Backups and secrets](../operations/backups-and-secrets.md).

## Pitfalls

| What happens | Why | How to avoid or recover |
| --- | --- | --- |
| Torrents use your home connection when the VPN drops | Network interface left at "Any interface" | Bind to the VPN adapter (Step 5, Advanced) |
| Web UI exposed to the internet | **Web UI > Use UPnP / NAT-PMP** asked the router to forward 8080 | Turn it off; check the router's UPnP mapping list and remove the entry |
| Any LAN device can control qBittorrent without a password | Auth bypass whitelist covers the whole subnet | Whitelist only `192.168.50.2/32`, or nothing |
| Password guessing is barely slowed | Ban after 100 failures | Lower it to about 5 |
| Router UPnP and port forwards do nothing | Torrent traffic exits at the VPN server | Use the VPN provider's port forwarding, or accept firewalled status |
| Forwarded port stops working after a while | Proton changes the forwarded port on reconnect | Re-enter the new port in qBittorrent after each reconnect |
| Downloads all land in `M:\Downloads`, not in category folders | Default Torrent Management Mode is Manual | Set it to Automatic; existing torrents can be switched with right-click **Automatic Torrent Management** |
| Torrents show errors after a reboot | qBittorrent started before `M:` reconnected, or the drive did not reconnect | Open `M:` in File Explorer, then select the torrents and **Force resume** (or **Force recheck**). Make sure **Reconnect at sign-in** and the saved credential exist |
| `M:` missing when run as a service or another user | Mapped drives are per user session | Use the UNC path |
| Web UI unreachable after the PC got a new address | The Web UI is bound to `192.168.50.16` | Reserve or fix the address; or update the bind address |
| Mac cannot reach the Web UI while the VPN is connected | VPN app blocks LAN traffic | Turn on **Allow LAN connections**, or exclude the LAN by split tunnelling |
| Torrents seed for ever; Radarr never removes completed ones | No seeding limits anywhere | See [Seeding limits](#seeding-limits-and-remove-completed) |
| A torrent disappears before import | qBittorrent action set to **Remove torrent** | Use **Stop torrent** |
| PC goes offline overnight | Windows sleep | Sleep **Never** on mains power |
| Nothing runs after a Windows update restart | No automatic sign-in, so qBittorrent, the VPN app and `M:` all wait for a user | Sign in, or set up automatic sign-in |

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Sonarr or Radarr: "Unable to connect to qBittorrent" | PC asleep or off; qBittorrent not running; Web UI off or on another address or port; firewall rule missing; VPN app blocking LAN | On the Mac run the `curl ... app/version` check. On the PC run `qbit-check.ps1`; it names the failing piece |
| Test fails with an authentication error, or the login check returns `403` | Wrong user name or password in the app, then the address was banned after repeated failures | Correct the credentials in Sonarr and Radarr. Wait out the ban time (3600 seconds by default in the build), or restart qBittorrent (not verified to clear the ban list) |
| Login check returns `Fails.` | Wrong credentials | Reset them in **Options > Web UI** on the PC |
| Web UI loads the login page but the API rejects requests from a tool | CSRF protection: the request's `Referer` or `Origin` does not match the address used | Send a `Referer` header with the same scheme, host and port, as in the `curl` example |
| Web UI refuses to load when opened by a host name, but works by IP address | Host header validation does not list that name | Add the name to **Server domains** |
| Downloads land in the wrong folder | Manual torrent management, a category with a custom save path, or a different default save path | Check **Downloads > Default Save Path** and each category's path; set Automatic mode |
| Sonarr: "Import failed, path does not exist" or remote path warnings | Remote path mapping missing or not matching `M:\Downloads\` | Fix the mapping ([Sonarr and Radarr](./sonarr-and-radarr.md)) |
| `M:` shows a red cross after a reboot | Windows reconnects mapped drives lazily, or the credential was not saved | Open `M:` once; check `cmdkey /list`; map again with **Remember my credentials** |
| No transfers at all, status bar shows disconnected | The VPN is down and the binding stops traffic: by design | Reconnect the VPN. If transfers do not resume, restart qBittorrent |
| No transfers although the VPN is connected | Bound to an adapter name that no longer exists | Re-select the adapter in **Advanced > Network interface**; run `Get-NetAdapter` |
| Status shows firewalled | No incoming port reaches you through the VPN | Expected without VPN port forwarding. With it, make sure the port in qBittorrent matches the VPN app's current port and UPnP is off |
| Where to look for errors | | `%LOCALAPPDATA%\qBittorrent\logs\qbittorrent.log`, or **View > Log** |

## Undo

**Run on: torrent-pc**, in PowerShell as Administrator, to remove the firewall rule:

```powershell
Remove-NetFirewallRule -DisplayName "qBittorrent Web UI (LAN only)"
```

To remove the mapped drive: `net use M: /delete`, and delete the credential for `192.168.50.2` in Credential Manager. To remove qBittorrent: uninstall it from **Settings > Apps**, then delete `%APPDATA%\qBittorrent` and `%LOCALAPPDATA%\qBittorrent` if you do not want to keep its settings and torrent list. Remove the download client entries in Sonarr and Radarr.

## References

- [qBittorrent download page](https://www.qbittorrent.org/download): current stable release and the Windows installers.
- [Explanation of Options in qBittorrent (wiki)](https://github.com/qbittorrent/qBittorrent/wiki/Explanation-of-Options-in-qBittorrent): what the options do, including Advanced > Network interface.
- [qBittorrent Web API (v5.0)](https://github.com/qbittorrent/qBittorrent/wiki/WebUI-API-(qBittorrent-5.0)): login, the SID cookie, the Referer/Origin requirement, the 403 ban response.
- [TRaSH Guides: qBittorrent basic setup](https://trash-guides.info/Downloaders/qBittorrent/Basic-Setup/): Automatic torrent management, ports, seeding limits, encryption, anonymous mode. When checked the page carried a "Docs built by Pull Request" banner; recheck it.
- [Proton VPN: Allow LAN connections](https://protonvpn.com/support/lan-connections): where the setting is and what it does.
- [Proton VPN: kill switch](https://protonvpn.com/support/what-is-kill-switch): Standard and Advanced modes.
- [Proton VPN: split tunneling](https://protonvpn.com/support/protonvpn-split-tunneling): Exclude and Include modes, IP ranges.
- [Proton VPN: port forwarding](https://protonvpn.com/support/port-forwarding): requirements, changing ports, setting the port in qBittorrent.
- [New-NetFirewallRule (Microsoft Learn)](https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule): parameters and remote address formats.
- [Running qBittorrent as a Windows service (community discussion)](https://github.com/qbittorrent/qBittorrent/discussions/17526): NSSM, accounts, mapped drives under services.
