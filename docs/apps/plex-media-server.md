# Plex Media Server on an Intel Mac

You end up with Plex Media Server running on a Mac that stays awake, comes back by itself after a power cut, keeps its media disks mounted, and serves the house on the LAN and the outside world through one forwarded port. Sonarr and Radarr tell it when something new arrives, so the library updates without a manual scan.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | Plex Media Server 1.43.4.10903 on an Intel MacBook Pro (2019) with macOS 26, wired Ethernet, two external media volumes, server claimed with a Plex Pass account, Remote Access through a manual port forward on an ASUS XT8 router. Settings in the working example table were read from that running server |
| **Also works for** | Intel Mac desktops (mini, iMac): the energy settings have different names, covered below. Apple Silicon Macs: Plex ships a universal installer, **not tested by the author**. Any router that can forward a port |
| **Time** | 45 minutes, plus the first library scan (hours for a large library) |
| **You need first** | A Mac with a fixed address (`media-1`, `192.168.50.2`), the media volume attached, a Plex account. For the overall design see [Media stack overview](media-stack-overview.md) |

## How it works

- Plex Media Server is a background app with no window of its own. You manage it in a browser through the Plex Web App, at `http://127.0.0.1:32400/web` on the Mac or `http://192.168.50.2:32400/web` from another device ([Plex: Installation](https://support.plex.tv/articles/200288586-installation/)).
- **Claiming** means signing the server in to your Plex account during the setup wizard. Players find a claimed server through plex.tv, and sharing and Remote Access need it.
- A **library** is a type (Movies, TV Shows, ...) plus one or more folders. Plex merges all folders of a library into one view ([Plex: Creating Libraries](https://support.plex.tv/articles/200288926-creating-libraries/)). That is how two disks become one Movies library.
- Plex matches files by **folder and file names**. Names that follow Plex's convention, optionally with a database ID in the folder name, match first time. Sonarr and Radarr produce such names for you.
- Every player connects to port `32400`. On the LAN it connects directly. From outside, it connects to your public address on the port you forward to `32400`, or through Plex's relay if nothing else works.
- The server runs as an app in the logged-in user's session. If the Mac sleeps, logs out, or comes back from a power cut to a login screen, Plex is gone. Preparing the Mac is therefore half the job.

## Before you start

| Decide or gather | Notes |
| --- | --- |
| Fixed address | `192.168.50.2`. The router's port forward, Sonarr's and Radarr's Connect settings and any local DNS name point at it |
| Wired network | Recommended for a server; the working build uses Ethernet through an adapter |
| Library folders | `/Volumes/Media/TV` and `/Volumes/Media/Movies` (plus `/Volumes/Media2/...` if you have a second disk). Do not use the root of a volume as a library folder |
| Volume format | APFS or Mac OS Extended, so that Sonarr and Radarr can hardlink. See [Media stack overview](media-stack-overview.md#folder-layout-and-why-one-filesystem-matters) |
| A transcoder temporary folder | On a disk with free space of about the size of the largest file plus 100 MB. Not a library folder, not a network share ([Plex: Transcoder](https://support.plex.tv/articles/transcoder/)) |
| Plex Pass | Several settings below need it: LAN Networks, bandwidth limits, hardware transcoding, HDR tone mapping, HEVC encoding |
| Remote Access or not | If yes: a public IPv4 address on the router's WAN (no double NAT / CGNAT) and a port forward. See Step 9 |
| Moving from another Mac | Follow [Plex: Move an install to another system](https://support.plex.tv/articles/201370363-move-an-install-to-another-system/) instead of a fresh claim, to keep watch history |

## Steps

### Step 1. Stop the Mac sleeping and make it restart after a power cut

**Run on: the Mac**

```sh
sudo pmset -a sleep 0
sudo pmset -a disksleep 0
sudo pmset -a womp 1
sudo pmset -a autorestart 1
pmset -g
```

What they do ([Eclectic Light: using pmset](https://eclecticlight.co/2017/01/20/power-management-in-detail-using-pmset/); `man pmset` on the Mac is the full reference):

| Command | Effect |
| --- | --- |
| `sleep 0` | The system never sleeps. `-a` applies it on mains, battery and UPS |
| `disksleep 0` | Disks never spin down. External media disks stay mounted and ready |
| `womp 1` | Wake for network access |
| `autorestart 1` | Start again when power returns after a power failure |
| `pmset -g` | Shows the current values. Check that `sleep` is `0` and `autorestart` is `1` |

> **Not verified:** `autorestart` is not supported on every Mac, in particular on laptops. `pmset -g cap` lists what your Mac supports. If it is missing from that list, the Mac will not start by itself after a power cut. A UPS covers that gap.

The same settings in System Settings on macOS 26 ([Apple: Set sleep and wake settings](https://support.apple.com/guide/mac-help/set-sleep-and-wake-settings-mchle41a6ccd/26.0/mac/26.0), [Apple: Energy settings on a Mac desktop](https://support.apple.com/guide/mac-help/mchlp1168/26.0/mac/26.0)):

| Mac | Where | Setting |
| --- | --- | --- |
| Laptop | Battery > Options | **Prevent automatic sleeping on power adapter when the display is off**: on. **Put hard disks to sleep when possible**: off. **Wake for network access**: Always |
| Desktop (mini, iMac, Studio) | Energy | **Prevent automatic sleeping when the display is off**: on. **Put hard disks to sleep when possible**: off. **Wake for network access**: on. **Start up automatically after a power failure**: on |

On a laptop used as a server, keep it on the power adapter. The display can turn off; only system sleep matters.

### Step 2. Make the apps come back after a restart

1. **Log in automatically.** Plex, Sonarr and Radarr run in your user session. After a power cut the Mac must reach the desktop without anyone typing a password. Turn on automatic login for the server's user in System Settings > Users & Groups.
   > **Not verified:** this step is general macOS knowledge, not from the working build's notes. macOS does not offer automatic login while FileVault disk encryption is on. Choose between encryption and unattended restart, and accept that without automatic login the stack stays down after a power cut until someone logs in.
2. **Add Plex as a login item.** System Settings > General > **Login Items & Extensions** > **+** under "Open at Login", choose **Plex Media Server** in Applications ([Apple: Open items automatically when you log in](https://support.apple.com/guide/mac-help/mh15189/26.0/mac/26.0)). Do the same for Sonarr and Radarr. If macOS lists them under the apps allowed to run in the background, leave them allowed.
3. **Mount the media volumes.** External disks mount when they are connected and the user is logged in. Plug them in directly (or through a powered hub), and check after a test restart that every library volume shows in `/Volumes`.

**Run on: the Mac**, after a test restart

```sh
ls /Volumes
pgrep -fl "Plex Media Server" | head -3
```

The media volumes are listed, and at least one `Plex Media Server` process is running.

> **Pitfall:** if Plex starts before a volume is mounted, that library's items show as unavailable until the next scan after the disk appears. If "Empty trash automatically after every scan" is on, a scan of a missing folder may remove the items from the library and lose their watch state when the disk is back. Keep the disks always connected. **Not verified** how Plex 1.43 treats a whole missing volume.

### Step 3. Create the library folders

**Run on: the Mac**

```sh
mkdir -p /Volumes/Media/TV /Volumes/Media/Movies /Volumes/Media/Downloads
```

`Downloads` is for the download client and is **not** added to Plex.

### Step 4. Download and install Plex Media Server

1. Get the macOS installer from the [Plex Media Server downloads page](https://www.plex.tv/media-server-downloads/). (When checked, the page's list of builds did not load; reload or try later.)
2. Open the download and drag **Plex Media Server** to Applications, then open it from Applications.
3. A browser opens the Plex Web App. If it does not, go to `http://127.0.0.1:32400/web` **on the Mac itself**.

> **Pitfall:** do the first setup in a browser on the Mac itself. Plex's installation guide gives an SSH tunnel for when you cannot: from another computer, `ssh -L 8888:127.0.0.1:32400 <user>@192.168.50.2` and then `http://127.0.0.1:8888/web` makes the browser appear local ([Plex: Installation](https://support.plex.tv/articles/200288586-installation/)).

### Step 5. Claim the server and run the setup wizard

The setup wizard ([Plex: Basic Setup Wizard](https://support.plex.tv/articles/200288896-basic-setup-wizard/)):

1. **Sign in** with your Plex account. This claims the server. Plex recommends signing in even for home-only use, because players find servers through the account.
2. **Friendly Name**: a name for the server, such as `media-1`. Left blank, Plex uses the Mac's network name.
3. **Remote access** ("allow me to access my media outside my home"): you can leave it for Step 8.
4. **Libraries**: add them here or in Step 6.

Check: Settings (wrench) > the server's name at the top of the sidebar > General shows that the server is signed in to your account.

### Step 6. Add the libraries

Settings > Manage > **Libraries** > **Add Library**.

| Library | Type | Folders | Agent and language (as observed) |
| --- | --- | --- | --- |
| Movies | Movies | `/Volumes/Media/Movies` (and `/Volumes/Media2/Movies`) | Plex Movie, English (United States) |
| TV Shows | TV Shows | `/Volumes/Media/TV` (and `/Volumes/Media2/TV`) | Plex TV Series, English (United States) |

Click **Browse for Media Folder** once per folder; a library can have several ([Plex: Creating Libraries](https://support.plex.tv/articles/200288926-creating-libraries/)). Keep films and series in separate libraries of the right type, because the type decides how files are matched.

Then in Settings > **Library** ([Plex: Library settings](https://support.plex.tv/articles/200289526-library/)):

| Setting | Working build | Why |
| --- | --- | --- |
| Scan my library automatically | On | macOS reports file changes, so new imports appear without waiting. Does not work for network-mounted folders |
| Run a partial scan when changes are detected | On (advanced) | Only the changed folder is scanned |
| Scan my library periodically | Every 12 hours | A safety net in case a change notification is missed |
| Run scanner tasks at a lower priority | On (advanced) | Keeps scanning from disturbing playback |
| Generate video preview thumbnails | As a scheduled task | Uses a lot of time, CPU and disk; done in the maintenance window instead of at import |

Sonarr and Radarr also tell Plex to scan after each import (Step 12), so automatic scanning is a second line, not the only one.

### Step 7. Name the files the way Plex expects

Plex's rules ([Plex: TV show files](https://support.plex.tv/articles/naming-and-organizing-your-tv-show-files/), [Plex: Movie files](https://support.plex.tv/articles/naming-and-organizing-your-movie-media-files/)):

```
/Volumes/Media/TV/Show Name (2001) {tvdb-123456}/Season 01/Show Name (2001) - s01e01 - Optional Info.mkv
/Volumes/Media/Movies/Film Title (2005) {imdb-tt0372784}/Film Title (2005).mkv
```

- Series: one folder per show, then `Season 01`, `Season 02`... (the English word "Season"). Specials go in `Season 00` or `Specials`.
- Films: one folder per film, `Title (Year)`.
- The ID hint in curly braces is optional but stops wrong matches: `{tvdb-...}` or `{tmdb-...}` for series, `{imdb-tt...}` or `{tmdb-...}` for films. The film hint needs the current "Plex Movie" agent.

You rarely name files by hand: set Sonarr's and Radarr's naming once and they do it on every import. The schemes, and a known mistake in the film folder format, are on [Sonarr and Radarr](sonarr-and-radarr.md#naming).

### Step 8. Network settings

Settings > **Network** (click **Show Advanced**) ([Plex: Network settings](https://support.plex.tv/articles/200430283-network/)):

| Setting | What it does | Suggested | Working build |
| --- | --- | --- | --- |
| Enable server support for IPv6 | Lets the server use IPv6 | Off unless your players and your Remote Access path use IPv6 | Off |
| LAN Networks | Addresses that count as local. By default only the server's own subnet. Plex Pass | `192.168.50.0/24` | `192.168.0.0/16` |
| List of IP addresses and networks that are allowed without auth | Devices here get in **as the server's admin, without signing in**, with access to every library and setting. Meant for old apps that cannot sign in | **Empty** | `192.168.0.0/16` (see the pitfall below) |
| Custom server access URLs | Extra addresses published to plex.tv so players can find the server, for example a reverse proxy or tunnel name. A URL without a port gets the Remote Access port | Only if you publish Plex under another name (Step 10) | `https://plex.example.com` |
| Enable Relay | Lets players reach the server through Plex's relay, bandwidth-limited, when a direct connection fails | On, unless you are sure direct connections work everywhere | Off |
| Enable local network discovery (GDM) | Lets players on the LAN find the server without plex.tv | On | Off |
| Remote streams allowed per user | Cap on simultaneous remote streams per user | Your choice | `1` |

> **Pitfall: "allowed without auth" is admin access.** A range such as `192.168.0.0/16` covers **every** `192.168.x.x` network, including an IoT or guest network such as `192.168.101.0/24` if anything there can reach the Mac. Any device inside the range can change server settings and delete media. Leave the list empty. If you must use it, list single addresses of the old devices that need it.

> **Pitfall: tunnels and proxies look local.** If remote players reach Plex through a Cloudflare tunnel or reverse proxy running on your LAN (Step 10), Plex sees the proxy's LAN address, not the player's. With that address in "allowed without auth", anyone on the internet who reaches the public name gets admin access; with it in LAN Networks, remote streams are treated as local and escape remote bandwidth limits. **Not verified by the author**: this follows from Plex's description of the two settings, not from a test.

> **Pitfall: relay off.** With Relay off, a player that cannot connect directly (for example on a network that blocks the port) gets no connection at all, rather than a slow one.

### Step 9. Remote Access with a manual port forward

Automatic Remote Access asks the router through UPnP or NAT-PMP. A manual forward is more predictable and lets you keep UPnP off on the router ([Plex: Remote Access](https://support.plex.tv/articles/200289506-remote-access/)).

1. **On the router**, forward TCP `32400` (or any free port from `20000` to `50000`) to `192.168.50.2` port `32400`. On the ASUS XT8 this is WAN > Virtual Server / Port Forwarding; see [ASUS ZenWiFi XT8](../hardware/asus-zenwifi-xt8.md). Use a static rule, not UPnP.
2. **In Plex**, Settings > **Remote Access** > **Show Advanced**: tick **Manually specify public port**, enter the external port from step 1, click **Apply** / **Retry**.
3. The page should turn green: "Fully accessible outside your network". It shows the public address and port it found.
4. Optional, under the same page: **Internet upload speed** and **Limit remote stream bitrate**. Plex keeps total remote streaming to about 80% of the upload speed you enter. Plex Pass ([Plex: Bandwidth and transcoding limits](https://support.plex.tv/articles/227715247-server-settings-bandwidth-and-transcoding-limits/)).

**Check for double NAT or CGNAT first** ([Plex: Troubleshooting Remote Access](https://support.plex.tv/articles/200931138-troubleshooting-remote-access/)). Compare the router's WAN IPv4 address (router web page, WAN or Network Map) with your public address as a website shows it:

| Router WAN address | Means | What to do |
| --- | --- | --- |
| Same as the public address | Direct | The forward above works |
| A private address (`192.168.x.x`, `10.x.x.x`, `172.16-31.x.x`) | Double NAT: another router (often the ISP's modem-router) in front of yours | Put the ISP device in bridge mode, or forward the port on both devices |
| `100.64.0.0` to `100.127.255.255` | CGNAT: your ISP shares one public address among customers | A forward cannot work. Ask the ISP for a public or static IPv4, or use the relay or a tunnel |

> **Pitfall:** the forward points at an address. If the Mac's address changes, Remote Access fails silently. Keep the address fixed.

### Step 10. Plex behind Cloudflare (optional)

**Observed on a working build:** the custom server access URL was `https://plex.example.com`, and that public name resolved to Cloudflare's addresses, the same as the [Seerr tunnel](seerr-cloudflare-tunnel.md) name. How Cloudflare forwarded it to the Mac (a tunnel route, or a proxied DNS record to the home address) was not recorded. The port forward from Step 9 was also in place, so most players probably connected directly.

If you want to do the same, the tunnel route would look like the Seerr one, with `plex` as the subdomain and `http://192.168.50.2:32400` as the URL. **Not verified by the author.** Before you do it:

> **Pitfall: Cloudflare's terms on video.** Cloudflare's [Service-Specific Terms for Application Services](https://www.cloudflare.com/service-specific-terms-application-services/) say that serving video and other large files through its CDN requires one of its paid video or developer services (unless you are an Enterprise customer), and that Cloudflare may disable or limit CDN use otherwise. Traffic through a proxied name, including one published through a tunnel, passes through that CDN. Streaming Plex video that way can break those terms and get the name limited. The direct port forward (Step 9) avoids the question.

> **Pitfall: the port in the custom URL.** Plex adds the Remote Access port to a custom URL that has none. `https://plex.example.com` may then be published as `https://plex.example.com:32400`, a port Cloudflare does not proxy. Write `https://plex.example.com:443`. **Not verified by the author.**

Also read the "tunnels and proxies look local" pitfall in Step 8.

### Step 11. Transcoder and scheduled tasks

Transcoding is Plex converting a file on the fly for a player that cannot play it directly. Settings > **Transcoder** > Show Advanced ([Plex: Transcoder](https://support.plex.tv/articles/transcoder/)):

| Setting | What it does | Working build |
| --- | --- | --- |
| Transcoder quality | Speed against quality: Automatic, Prefer higher speed, Prefer higher quality, Make my CPU hurt. Plex advises Automatic | Not the default (stored value `3`; **not verified** which option that is) |
| Transcoder temporary directory | Where the transcoder writes while streaming. Needs free space, not a library or network folder; create the folder first | A folder in the user's home on the internal disk, `~/_transcode_cache` |
| Background transcoding x264 preset | Speed preset for downloads, sync and optimised versions. Default Very fast | Faster |
| Enable HEVC video encoding | HEVC output, hardware only, Plex Pass | Never |
| Enable HDR tone mapping | Converts HDR to normal range when transcoding. Off makes transcoded HDR look dim and washed out. Plex Pass | Off |
| Use hardware acceleration when available | Uses Intel Quick Sync on Intel Macs, 2nd-generation Core or later; HEVC encoding needs 7th generation. Plex Pass ([Plex: hardware-accelerated streaming](https://support.plex.tv/articles/115002178853-using-hardware-accelerated-streaming/)) | Not recorded |

**Run on: the Mac**, before you point the setting at it

```sh
mkdir -p ~/_transcode_cache
```

Settings > **Scheduled Tasks** ([Plex: Scheduled Tasks](https://support.plex.tv/articles/201553286-scheduled-tasks/)): set the maintenance window (default 3 am to 6 am) to hours when nobody watches. Keep **Backup database every three days**, **Optimize database every week**, **Remove old bundles every week** and **Remove old cache files every week** on. "Update all libraries during maintenance" is off by default; the periodic scan in Step 6 already covers it.

### Step 12. Let Sonarr and Radarr update Plex

In each of Sonarr and Radarr: Settings > **Connect** > **+** > **Plex Media Server**.

| Field | Value |
| --- | --- |
| Host | `192.168.50.2` |
| Port | `32400` |
| Use SSL | Off for a plain local connection |
| Authenticate with Plex.tv | Click it and sign in; this stores a token |
| Update Library | On |
| Triggers (Sonarr, as observed) | On Import/Download, On Upgrade, On Rename, On Series Add, On Series Delete, On Episode File Delete, On Episode File Delete For Upgrade |

**Observed on a working build:** Radarr's connection used Plex's secure address, `https://192-168-50-2.<hash>.plex.direct:32400`, with SSL on. That address is specific to each server (`<hash>` is your server's own); copy it from your server if you want an SSL connection, never from someone else's notes. Both forms worked.

More on these settings: [Sonarr and Radarr](sonarr-and-radarr.md#step-11-connect-plex).

## A working example: non-default settings on a running server

These were read from a running server. Use them as a reference, not as a recipe; the right column says where they need care.

| Setting (UI name) | Preference key as observed | Value | Comment |
| --- | --- | --- | --- |
| Friendly name | `FriendlyName` | set | Any name |
| Scan my library automatically, partial scan | | On, on | |
| Scan my library periodically | | Every 12 hours | |
| Enable server support for IPv6 | | Off (IPv4 only) | |
| Local network discovery (GDM) | | Off | Players on the LAN then rely on plex.tv to find the server |
| Manually specify public port | `ManualPortMappingMode` | On, port `32400` forwarded on the router | |
| Custom server access URLs | `customConnections` | `https://plex.example.com` | See Step 10 about the port and Cloudflare's terms |
| Enable Relay | `RelayEnabled` | Off | |
| Allowed without auth | `allowedNetworks` | `192.168.0.0/16` | **Too wide.** Leave empty |
| LAN Networks | `LanNetworksBandwidth` | `192.168.0.0/16` | Narrow to `192.168.50.0/24` |
| Internet upload speed | `WanTotalMaxUploadRate` | `410000` kbps | Set from your real upload speed |
| Remote streams allowed per user | `WanPerUserStreamCount` | `1` | |
| Transcoder quality | `TranscoderQuality` | `3` | |
| Transcoder temporary directory | | `~/_transcode_cache` | Folder must exist |
| Temporary folder for downloads | | `~/temp_downloads` | Folder must exist |
| Enable HEVC video encoding | | Never | |
| Enable HDR tone mapping | | Off | Transcoded HDR looks dim |
| Background transcoding x264 preset | | Faster | |
| Run scanner tasks at a lower priority | | On | |
| Video preview thumbnails, voice activity detection | | As a scheduled task | |
| Chapter thumbnails, loudness analysis, music analysis | | As soon as possible | |
| Recently added | | Merged into one row | |

To read a value, or change one the UI does not show, Plex documents the `defaults` command on macOS ([Plex: Advanced, hidden server settings](https://support.plex.tv/articles/201105343-advanced-hidden-server-settings/)):

**Run on: the Mac**

```sh
defaults read com.plexapp.plexmediaserver ManualPortMappingMode
defaults write com.plexapp.plexmediaserver GdmEnabled -boolean true
```

Quit and reopen Plex after a `defaults write`.

> **Pitfall:** `defaults read com.plexapp.plexmediaserver` without a key prints the whole file, including `PlexOnlineToken`, the server's login token. Do not paste that output anywhere.

## Check it

| Test | Where | Pass |
| --- | --- | --- |
| `curl -s -o /dev/null -w '%{http_code}\n' http://192.168.50.2:32400/identity` | any LAN computer | `200` |
| `pmset -g \| grep -E ' sleep\|autorestart'` | the Mac | `sleep 0`, `autorestart 1` |
| Restart the Mac and wait | the Mac | Back at the desktop, volumes mounted, Plex reachable, without anyone touching it |
| Settings > Remote Access | Plex Web | Green, "Fully accessible outside your network" |
| Open Plex on a phone on mobile data (Wi-Fi off) | phone | Libraries load and a film plays |
| Import something with Sonarr or Radarr | Plex | It appears within a minute without a manual scan |

## Pitfalls

| What happens | Why | Avoid or recover |
| --- | --- | --- |
| Plex unreachable every morning | The Mac slept | Step 1. On a laptop, the "on power adapter" setting matters |
| After a power cut nothing comes back | Mac did not restart, or stopped at the login screen | `autorestart 1` (if supported), automatic login, login items, or a UPS |
| Setup page says no server found | Opened from another computer before claiming | Open `http://127.0.0.1:32400/web` on the Mac, or use the SSH tunnel |
| Remote Access stays red | Double NAT, CGNAT, forward to the wrong address, or public port not entered | Step 9 checks |
| Wrong film or series matched | Folder name without year or ID | Use the naming in Step 7; Fix Match in Plex for the odd one |
| Two copies of a film | Same film in both disks' Movies folders | Delete one; Plex shows both versions under one item |
| Transcoded HDR looks grey | HDR tone mapping off | Turn it on (Plex Pass) or play on a player that handles HDR directly |
| Remote players get admin access, or remote limits do not apply | Too wide an "allowed without auth" or LAN Networks range, especially with a tunnel | Step 8 |
| Cloudflare limits your domain | Video through Cloudflare's proxy | Step 10. Use the direct port forward for video |

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `curl .../identity` cannot connect | Plex not running, or the Mac is asleep | `pgrep -fl "Plex Media Server"`; open the app; Step 1 |
| A library shows items as unavailable | Its volume is not mounted | `ls /Volumes`; reconnect the disk; rescan |
| New imports do not appear | No Connect entry in Sonarr/Radarr, the folder is not part of the library, or automatic scan is off | Step 12, Step 6 |
| Remote Access shows "Not available outside your network" | See Step 9 table | Check the router WAN address; check the forward; enter the public port; Retry |
| Remote Access worked, then stopped | Mac's address changed, router reset, or the ISP moved you behind CGNAT | Check the forward target and the WAN address again |
| Players on the LAN only find the server through the internet, or not at all when the internet is down | GDM off and LAN Networks not set | Turn GDM on; set LAN Networks |
| Streams buffer remotely | Upload too small for the bitrate, or transcoding too slow | Lower "Limit remote stream bitrate"; check hardware acceleration |
| Disk fills on the internal drive | Transcoder temp folder or Plex data growing | Move the transcoder folder; the Plex data folder includes cache and thumbnails |

## Backup and move

Plex keeps everything (database, metadata, thumbnails, settings) in its data folder, plus a preferences file ([Plex: data directory](https://support.plex.tv/articles/202915258-where-is-the-plex-media-server-data-directory-located/)):

| What | Where on macOS |
| --- | --- |
| Data folder | `~/Library/Application Support/Plex Media Server/` |
| Preferences (includes the server's identity and token) | `~/Library/Preferences/com.plexapp.plexmediaserver.plist` |
| Automatic database backups | Made every three days by the scheduled task, inside the data folder unless you set **Backup directory** in Scheduled Tasks |

**Run on: the Mac**. Quit Plex first so the database is consistent.

```sh
osascript -e 'quit app "Plex Media Server"'
sleep 10
tar -czf ~/plex-backup.tar.gz --exclude 'Plex Media Server/Cache' -C ~/Library/"Application Support" "Plex Media Server"
cp ~/Library/Preferences/com.plexapp.plexmediaserver.plist ~/plex-prefs.plist
open -a "Plex Media Server"
```

The data folder can be tens of gigabytes. Both files contain the server's token: keep them off shared storage and out of Git ([Backups and secrets](../operations/backups-and-secrets.md)).

To move the server to another Mac, follow [Plex: Move an install to another system](https://support.plex.tv/articles/201370363-move-an-install-to-another-system/): turn off "Empty trash automatically after every scan", stop both servers, copy the data folder and the plist, **restart the new Mac** (macOS caches preferences), add the new library paths, scan, remove the old paths, then Empty Trash, Clean Bundles and Optimize Database, and update the router's port forward.

## Upgrades

- The working build ran 1.43.4.10903, which Plex announced as a public release ([Plex forum: Plex Media Server releases](https://forums.plex.tv/t/plex-media-server/30447/717)). Plex has published security fixes in the 1.43 line; stay on a current release.
- To upgrade, install the new macOS build from the downloads page over the old app, or accept the update the server offers in Plex Web. Which of the two the working build used was not recorded. Back up first.
- After an upgrade, check Remote Access and one stream from outside.

## Undo

1. Remove the router's port forward.
2. Remove Plex from Login Items; quit it.
3. Delete `/Applications/Plex Media Server.app`, `~/Library/Application Support/Plex Media Server/` and `~/Library/Preferences/com.plexapp.plexmediaserver.plist`. Back them up first if you may come back.
4. In your Plex account on plex.tv, remove the server from your authorised devices.
5. Restore sleep settings: `sudo pmset -a sleep 1` (or your preferred minutes) and `sudo pmset -a autorestart 0`.

## References

- [Plex: Installation](https://support.plex.tv/articles/200288586-installation/): installing, the local Web App address and the SSH tunnel trick.
- [Plex: Basic Setup Wizard](https://support.plex.tv/articles/200288896-basic-setup-wizard/): signing in, friendly name, remote access and libraries.
- [Plex: Creating Libraries](https://support.plex.tv/articles/200288926-creating-libraries/): library types and several folders per library.
- [Plex: Naming and organizing your TV show files](https://support.plex.tv/articles/naming-and-organizing-your-tv-show-files/) and [movie files](https://support.plex.tv/articles/naming-and-organizing-your-movie-media-files/): folder and file naming and ID hints.
- [Plex: Library settings](https://support.plex.tv/articles/200289526-library/), [Network settings](https://support.plex.tv/articles/200430283-network/), [Transcoder settings](https://support.plex.tv/articles/transcoder/), [Scheduled Tasks](https://support.plex.tv/articles/201553286-scheduled-tasks/): every setting used above.
- [Plex: Remote Access](https://support.plex.tv/articles/200289506-remote-access/) and [Troubleshooting Remote Access](https://support.plex.tv/articles/200931138-troubleshooting-remote-access/): manual port, double NAT and CGNAT.
- [Plex: Advanced, hidden server settings](https://support.plex.tv/articles/201105343-advanced-hidden-server-settings/): the `defaults` command and preference keys on macOS.
- [Plex: Where is the data directory](https://support.plex.tv/articles/202915258-where-is-the-plex-media-server-data-directory-located/) and [Move an install to another system](https://support.plex.tv/articles/201370363-move-an-install-to-another-system/): backup and migration.
- [Apple: Set sleep and wake settings (macOS 26)](https://support.apple.com/guide/mac-help/set-sleep-and-wake-settings-mchle41a6ccd/26.0/mac/26.0) and [Open items automatically when you log in](https://support.apple.com/guide/mac-help/mh15189/26.0/mac/26.0): keeping a Mac awake and starting apps at login.
- [Cloudflare Service-Specific Terms: Application Services](https://www.cloudflare.com/service-specific-terms-application-services/): the CDN clause on video and large files.
