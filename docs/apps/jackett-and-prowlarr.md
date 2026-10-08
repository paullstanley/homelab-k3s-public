# Jackett and Prowlarr: indexers for Sonarr and Radarr on a Mac

You end up with an indexer manager on the media server Mac: one program that knows how to search each of your indexers (the sites or services that list releases you are entitled to download) and offers them to Sonarr and Radarr in one standard format. The page covers Jackett, which is what the build runs, and Prowlarr, its successor, including how to move from one to the other.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own. This page is written for media you have the right to download. It does not name or recommend any indexer; "your indexers" means whichever ones you use legitimately.

| | |
| --- | --- |
| **Applies to** | Jackett v0.24.2756 (the macOS x64 build) running as a per-user service on an Intel Mac (2019 MacBook Pro) on macOS 26 (Tahoe), feeding Sonarr v4 and Radarr v6 on the same Mac through per-indexer Torznab URLs. Settings on this page were read from that running install |
| **Also works for** | Apple silicon Macs (use the ARM64 download). Jackett on Windows or Linux works the same way once installed. **Prowlarr is described from its official documentation and is not yet installed by the author**; the migration steps are not tested by the author |
| **Time** | 20 minutes for Jackett plus a few minutes per indexer. About 30 minutes to move to Prowlarr |
| **You need first** | [Media stack overview](./media-stack-overview.md), and Sonarr and/or Radarr installed: [Sonarr and Radarr](./sonarr-and-radarr.md). The Mac set up as an always-on server as described in [Plex Media Server](./plex-media-server.md) (no sleep, restart after power failure, automatic login) |

## How it works

- **Torznab** is a small web API (an extension of the Newznab API used for Usenet) that Sonarr and Radarr speak. Each indexer has its own search page and login; Jackett translates between those and Torznab. Sonarr and Radarr send a search such as "series X, season 2" to Jackett, Jackett asks the indexer, and returns a list of results.
- **One URL per indexer.** Jackett gives every configured indexer its own Torznab address, for example `http://127.0.0.1:9117/api/v2.0/indexers/<indexer-id>/results/torznab/`. You add each one to Sonarr and Radarr as a separate Torznab indexer, with Jackett's API key. Jackett also has an "all" address that searches everything at once; do not use it (see [Step 6](#step-6-add-each-indexer-to-sonarr-and-radarr)).
- **Jackett does not download anything itself.** Sonarr or Radarr picks a result and hands it to the download client (here qBittorrent on another PC: [qBittorrent on Windows behind a VPN](./qbittorrent-windows-vpn.md)). When the result is a `.torrent` file, Sonarr or Radarr fetches it through a link that Jackett serves, so Jackett fetches it from the indexer.
- **Everything Jackett does goes out from the Mac.** Searches, RSS polls and `.torrent` downloads leave through the Mac's own internet connection, not through any VPN on the download PC. See [Indexer traffic and privacy](#indexer-traffic-and-privacy).
- **Sonarr and Radarr keep their own copy of the indexer list.** Removing an indexer from Jackett does not remove it from Sonarr or Radarr. Prowlarr fixes this: it pushes its indexer list into Sonarr and Radarr and keeps them in step.
- **Jackett runs as a per-user service on macOS.** The installer creates a LaunchAgent (a background job that starts when that user logs in). It runs only while that user is logged in, which is why the Mac must log in automatically after a restart.

## Before you start

| Decide or gather | Notes |
| --- | --- |
| Jackett or Prowlarr | Prowlarr is the newer project from the same family as Sonarr and Radarr, and it keeps their indexer lists in sync for you. For a new build, consider starting with Prowlarr ([Prowlarr instead of Jackett](#prowlarr-instead-of-jackett)). The rest of this page also suits an existing Jackett install |
| macOS version | Jackett needs **macOS 13 (Ventura) or later**. Prowlarr needs macOS 10.15 or later |
| Intel or Apple silicon | `uname -m` prints `x86_64` (Intel) or `arm64` (Apple silicon). It decides which download you take |
| Which user runs it | The same user that runs Sonarr, Radarr and Plex and that logs in automatically. The service, its settings and its API key belong to that user |
| A permanent folder for Jackett | The service runs the program from where you extracted it. Choose a folder you will not tidy away, for example `~/Applications/Jackett` |
| Whether other machines need the Jackett page | If Sonarr and Radarr run on the same Mac they use `127.0.0.1` and Jackett can stay local-only. Turn on external access only if another machine must reach it |
| An admin password for Jackett | A new one, kept in your password manager. Written here as `<JACKETT_ADMIN_PASSWORD>` |
| Your indexers and any logins they need | Some need an account, a cookie or an API key of their own |

## Steps

### Step 1. Download Jackett

Open the [Jackett releases page](https://github.com/Jackett/Jackett/releases/latest) and download:

| Mac | File |
| --- | --- |
| Intel | `Jackett.Binaries.macOS.tar.gz` |
| Apple silicon | `Jackett.Binaries.macOSARM64.tar.gz` |

Jackett publishes a new release almost every day, so the version number you see will be newer than the one on this page. That is expected.

### Step 2. Extract it to its permanent folder

**Run on: the media server Mac**, in Terminal, as the user that will run Jackett.

```bash
mkdir -p ~/Applications
tar -xzf ~/Downloads/Jackett.Binaries.macOS.tar.gz -C ~/Applications
ls ~/Applications/Jackett
```

The archive unpacks into a folder named `Jackett`. The listing shows `jackett` and `install_service_macos` among many other files. On Apple silicon, use the `macOSARM64` file name in the `tar` line.

> **Pitfall:** do not install the service from inside `~/Downloads` and then delete the download folder. The service would point at files that no longer exist and Jackett would not start at the next login.

### Step 3. Install it as a service

The [Jackett README](https://github.com/Jackett/Jackett) says to open the extracted folder and double-click `install_service_macos`. A Terminal window opens and runs the install; close it when it says it is finished. The same from Terminal:

**Run on: the media server Mac**

```bash
cd ~/Applications/Jackett
./install_service_macos
```

The service is a LaunchAgent at `~/Library/LaunchAgents/org.user.Jackett.plist`. It starts Jackett now and at every login of this user. To stop and start it:

```bash
launchctl unload ~/Library/LaunchAgents/org.user.Jackett.plist
launchctl load ~/Library/LaunchAgents/org.user.Jackett.plist
```

To run Jackett once in the foreground instead (useful for watching errors), stop the service and run `./jackett` from the folder.

Open `http://127.0.0.1:9117` in a browser on the Mac. The Jackett dashboard appears.

> **Not verified:** if macOS refuses to run the files because they were downloaded from the internet, removing the quarantine flag from the folder with `xattr -rd com.apple.quarantine ~/Applications/Jackett` should allow it. The Jackett README does not mention this and the author did not need it.

### Step 4. Configure Jackett

The settings are in the **Jackett Configuration** section at the bottom of the dashboard. Click **Apply server settings** after changing them.

| Setting | Value in the build | Recommendation and why |
| --- | --- | --- |
| Admin password | Set | Always set one, `<JACKETT_ADMIN_PASSWORD>`. It protects the dashboard. The API key protects only the Torznab feeds |
| Server port | `9117` | The default. Change it only if something else uses 9117. From the command line the port is `--Port`, for example `./jackett --Port 9118` |
| External access | On | Off, unless another machine must reach Jackett. When it is off Jackett accepts only connections from the Mac itself, which is all Sonarr and Radarr on the same Mac need. If you turn it on, the admin password matters more, and the macOS firewall may ask whether to allow incoming connections |
| Disable auto-update | On (updates disabled) | Prefer automatic updates. Indexers change their pages often and Jackett fixes its indexer definitions in new releases, so an old Jackett slowly loses indexers. If you keep updates off, update by hand regularly ([Updating](#updating-jackett)) |
| Cache enabled, cache TTL | On, TTL `2100` seconds | Fine as is. Jackett keeps recent results for the TTL (time to live) so repeated identical searches do not hit the indexer again |
| Proxy | None | See [Indexer traffic and privacy](#indexer-traffic-and-privacy) |
| FlareSolverr API URL | Empty | See [FlareSolverr](#flaresolverr-and-cloudflare-challenges) |
| Enhanced logging | Off | Turn it on only while troubleshooting; it writes much more |

**The API key** is shown at the top right of the dashboard. Sonarr and Radarr need it. It is stored in `~/.config/Jackett/ServerConfig.json`. Treat it as a password: anyone with it can use your configured indexers through Jackett.

### Step 5. Add your indexers

1. Click **+ Add indexer**.
2. Search for the indexer by name, or filter by type (public, semi-private, private).
3. Click the wrench or **+** next to it. Indexers that need a login ask for it now: user name and password, a cookie, or the indexer's own API key, as that indexer requires.
4. Click **Okay**. Jackett tests the indexer while saving.
5. Back on the dashboard, click **Test** next to the indexer. A green message means it answered.

Add only indexers you will actually use and add to Sonarr or Radarr. An indexer that exists only in Jackett does nothing: Sonarr and Radarr search only the indexers they have been given.

### Step 6. Add each indexer to Sonarr and Radarr

For every indexer, copy its own feed address: on the Jackett dashboard click **Copy Torznab Feed** on that indexer's row. It looks like this:

```text
http://127.0.0.1:9117/api/v2.0/indexers/<indexer-id>/results/torznab/
```

Then in Sonarr (and the same in Radarr): **Settings > Indexers > + > Torznab** (under Torrents).

| Field | Value | Notes |
| --- | --- | --- |
| Name | The indexer's name | Something you will recognise in health warnings |
| Enable RSS | On | Sonarr and Radarr poll the indexer's newest releases. Turn off for an indexer you want to use only on demand |
| Enable Automatic Search | On | Used when Sonarr or Radarr search by themselves |
| Enable Interactive Search | On | Used when you search by hand. An indexer with only this one on is "interactive only": the build uses that for an indexer that is slow or unreliable |
| URL | The copied feed address | Per indexer, not `.../indexers/all/...` |
| API Path | `/api` | The default |
| API Key | `<JACKETT_API_KEY>` | From the Jackett dashboard |
| Categories | Leave the defaults, or pick the TV (Sonarr) or Movie (Radarr) categories the indexer offers | Click **Test** first so the list fills in |
| Minimum Seeders | `1` in the build | Results with fewer seeders are ignored |
| Seed Ratio | `1` in the build | How long the download client should seed. See seeding in [qBittorrent on Windows behind a VPN](./qbittorrent-windows-vpn.md) |
| Indexer Priority | `1` to `50`, lower is preferred; the build uses `1` and `2` for the main indexers and `25` for the interactive-only one | When equal releases are found on several indexers, the lower number wins |

Click **Test**, then **Save**.

> **Why per indexer and not "all":** Jackett's "all" endpoint (`/api/v2.0/indexers/all/results/torznab`) searches every configured indexer at once. The Jackett README lists its limits: results are capped at 1000 in total, the slowest indexer slows every search, you lose per-indexer settings such as priority, seeders and categories, and indexer-specific categories (number 100000 and above) cannot be used. When one indexer fails, Sonarr cannot tell which, and backs off the whole "all" entry. Sonarr and Radarr raise the health warning **"Jackett All Endpoint Used"** when they see it; the [Servarr wiki](https://wiki.servarr.com/sonarr/system) says its only benefit is convenience.

### Step 7. Keep Sonarr and Radarr in step with Jackett

Sonarr and Radarr do not learn about changes in Jackett. Whenever you change the list:

| You did this in Jackett | Also do this in Sonarr and Radarr |
| --- | --- |
| Added an indexer | Add its Torznab feed (Step 6), or it is never searched |
| Removed an indexer | Delete its entry under **Settings > Indexers** |
| An indexer started failing permanently | Fix it in Jackett, or remove it from both |

A stale entry (one that points at an indexer Jackett no longer has) fails on every search and RSS sync. Sonarr and Radarr then show **"Indexers are unavailable due to failures"**, and, as seen in the build, a second warning once the indexers have been unavailable for more than six hours. Each app backs off a failing indexer for longer and longer, up to 24 hours, so the warning comes back again and again until you delete the entry. In the build, an indexer that had been removed from Jackett was still in Radarr and kept the warning alive.

> **Pitfall:** if you also add a Usenet indexer (Newznab) to Sonarr or Radarr and point it at a download client that does not exist, the app warns **"Indexer Download Client is Invalid"** (Sonarr's wording; Radarr says "Invalid Indexer Download Client Setting"). Either add that client, or set the indexer's download client back to "Any", or delete the indexer. Details on [Sonarr and Radarr](./sonarr-and-radarr.md).

Prowlarr removes this chore. See [Prowlarr instead of Jackett](#prowlarr-instead-of-jackett).

## FlareSolverr and Cloudflare challenges

Some indexer sites sit behind Cloudflare or a similar service that shows a "checking your browser" challenge. Jackett cannot answer those challenges. When it meets one and nothing is set up to help, the indexer's test fails with:

```text
Challenge detected but FlareSolverr is not configured
```

**FlareSolverr** is a separate proxy program that opens the page in a real browser, gets past the challenge, and hands the resulting cookies back to Jackett. You install it somewhere, then put its address (port `8191` by default, for example `http://<FLARESOLVERR_HOST>:8191`) in Jackett's **FlareSolverr API URL** setting. The Jackett README says it is optional and that most indexers do not need it.

What limits it here:

- **There is no macOS build.** The [FlareSolverr README](https://github.com/FlareSolverr/FlareSolverr) offers Docker images (for x86, ARM and others) and ready-made programs for Windows x64 and Linux x64 only. On a Mac you would have to run it from source. Running it on another machine (a Linux host, a container on your cluster, or the Windows PC) and pointing Jackett at that address is the practical route. **Not verified by the author.**
- **It may not help anyway.** The FlareSolverr README currently says: "At this time none of the captcha solvers work." Indexers whose challenge needs a captcha stay broken even with FlareSolverr.

In the build no FlareSolverr was set up, and three indexers failed their test with the message above while the others worked. If an indexer needs a challenge solved, the simplest fix is to remove it from Jackett **and** from Sonarr and Radarr (Step 7), and rely on indexers that answer directly.

## Indexer traffic and privacy

Jackett runs on the media server Mac. Every search, every RSS poll every few minutes, and every `.torrent` download that goes through Jackett leaves from the **Mac's own internet connection**, not through the VPN on the torrent PC. That means:

- Each indexer sees your home's public IP address and the titles you search for.
- Your ISP can see which indexer sites the Mac contacts (from DNS lookups and the site name sent when the HTTPS connection opens), though not the content of the searches.
- The VPN on the torrent PC still covers the actual torrent traffic (the peers you download from and upload to). It does not cover the indexer side.

Whether this matters to you depends on why you use the VPN. Options, none of them tested by the author:

| Option | How | Trade-off |
| --- | --- | --- |
| Accept it | Leave as is | Simplest. Searches are tied to your home address |
| Proxy the indexer traffic | Jackett has a **Proxy** setting (HTTP or SOCKS) in its configuration; Prowlarr has **indexer proxies** (HTTP, SOCKS4, SOCKS5, FlareSolverr) applied per tag | Needs a proxy that goes out through a VPN, for example one your VPN provider offers, or a proxy running on a machine that is on the VPN |
| Run the indexer manager on the torrent PC | Install Jackett or Prowlarr on the Windows PC behind the VPN, and point Sonarr and Radarr at `http://192.168.50.16:9117` (Jackett) or `:9696` (Prowlarr) | The VPN app must allow LAN connections so the Mac can reach it, and the Windows firewall must allow the port from the LAN only. Searches stop when the VPN drops |
| Put the whole Mac on the VPN | Run a VPN app on the Mac | Affects Plex remote access and everything else on the Mac. Not recommended for a media server |

## Prowlarr instead of Jackett

Prowlarr is an indexer manager from the same family as Sonarr and Radarr. It does what Jackett does, and in addition it **pushes its indexers into Sonarr and Radarr** and keeps them in sync, so you never edit indexers in two places. It also has per-indexer proxy settings and sync profiles. **Not yet installed by the author.** The steps follow the [Servarr wiki](https://wiki.servarr.com/prowlarr/quick-start-guide).

### Install Prowlarr on macOS

1. Download the macOS app from [prowlarr.com](https://prowlarr.com/): the x64 build for Intel, the arm64 build for Apple silicon.
2. Open the archive and move `Prowlarr.app` into `/Applications`.
3. Self-sign it and clear the quarantine flag, as the [macOS install page](https://wiki.servarr.com/prowlarr/installation/macos) says:

**Run on: the media server Mac**

```bash
codesign --force --deep -s - /Applications/Prowlarr.app
xattr -rd com.apple.quarantine /Applications/Prowlarr.app
open /Applications/Prowlarr.app
```

4. Open `http://localhost:9696`. On first start it asks you to set up authentication; choose Forms (a login page) and a new password.
5. Add `Prowlarr` to **System Settings > General > Login Items & Extensions** so it starts at login, like Sonarr and Radarr.

> **Pitfall:** Prowlarr's built-in updater must also be self-signed, or you install updates by hand. After an update that macOS refuses to start, run the two commands in step 3 again.

### Move from Jackett to Prowlarr

1. **Add your indexers in Prowlarr.** **Indexers > +**, search, enter any login the indexer needs, **Test**, **Save**. An indexer Prowlarr does not list can be added as Generic Torznab.
2. **Add the apps.** **Settings > Apps > +**, choose Sonarr, then repeat for Radarr:

| Field | Sonarr | Radarr |
| --- | --- | --- |
| Sync Level | **Full Sync** | **Full Sync** |
| Prowlarr Server | `http://127.0.0.1:9696` | `http://127.0.0.1:9696` |
| Sonarr / Radarr Server | `http://127.0.0.1:8989` | `http://127.0.0.1:7878` |
| API Key | Sonarr's key, from Sonarr's **Settings > General** | Radarr's key, from Radarr's **Settings > General** |

   **Full Sync** means Prowlarr adds, removes and updates the indexers in the app, and overwrites changes made to them in the app. **Add and Remove Only** leaves later edits in the app alone. **Disabled** stops syncing. Click **Test**, then **Save**, then **Sync App Indexers**.
3. **Check the result.** In Sonarr and Radarr, **Settings > Indexers** now shows each indexer twice: the old Jackett entry and a new one named `<indexer> (Prowlarr)`. Prowlarr sends each indexer only to apps whose categories it supports, so a TV-only indexer appears only in Sonarr.
4. **Copy your per-indexer choices across.** Minimum seeders and whether an indexer is used for RSS, automatic and interactive search are set in Prowlarr's sync profiles (on its **Settings > Apps** page), and seed ratio and priority in each indexer's settings in Prowlarr. With Full Sync, set them there, not in Sonarr or Radarr.
5. **Delete the old Jackett Torznab entries** in Sonarr and Radarr once a search finds results through the `(Prowlarr)` entries. Leaving both doubles every search and keeps old failures alive.
6. **Stop Jackett** once nothing uses it: `launchctl unload ~/Library/LaunchAgents/org.user.Jackett.plist`. Remove it later ([Undo](#undo)).

Prowlarr's own download clients (under its **Settings > Download Clients**) are only for grabs you start inside Prowlarr. Sonarr and Radarr keep using their own download client settings.

## Check it

**Run on: the media server Mac**

Jackett's service is loaded:

```bash
launchctl list | grep -i jackett
```

Expected: one line containing `org.user.Jackett`. A number in the first column is its process ID; `-` means it is loaded but not running.

Jackett listens on its port:

```bash
lsof -nP -iTCP:9117 -sTCP:LISTEN
```

Expected: a line with `jackett` and `TCP *:9117 (LISTEN)` or `127.0.0.1:9117`.

One indexer answers through its feed. Replace the indexer ID and the key:

```bash
curl -s "http://127.0.0.1:9117/api/v2.0/indexers/<indexer-id>/results/torznab/api?apikey=<JACKETT_API_KEY>&t=caps" | head -5
```

Expected: XML starting with `<?xml` and containing `<caps>`. An `<error code="100"` line means the API key is wrong.

The health script on this Mac checks Jackett, Sonarr, Radarr, Plex and the qBittorrent PC in one go and counts Jackett's configured indexers. From the root of this repo:

```bash
bash files/media/media-health.sh
```

The Jackett part prints `[ OK ] listening on TCP 9117` and `[ OK ] <n> configured indexers`. Sonarr and Radarr health warnings about indexers show as `[HLTH]` lines. The script is read-only. It has been tested against a mock Sonarr API on Linux, **not yet run on a Mac by the author**. See [`files/media/media-health.sh`](../../files/media/media-health.sh) for its settings.

In Sonarr and Radarr: **Settings > Indexers > Test All** passes, and **System > Status** shows no indexer warnings.

## Pitfalls

| What happens | Why | How to avoid or recover |
| --- | --- | --- |
| Health warnings "Indexers are unavailable due to failures" never go away | An indexer was removed from Jackett but its Torznab entry is still in Sonarr or Radarr | Delete the entry in the app (Step 7). Or move to Prowlarr with Full Sync |
| Some indexers fail with "Challenge detected but FlareSolverr is not configured" | The site is behind a Cloudflare challenge | Remove those indexers from Jackett and the apps, or run FlareSolverr on another machine. Its README says the captcha solvers do not currently work |
| "Jackett All Endpoint Used" warning | The "all" feed was added as one indexer | Replace it with one Torznab entry per indexer |
| Indexers break one by one over weeks | Auto-update is off and indexer sites changed | Turn auto-update on, or update by hand regularly |
| Jackett is not running after a restart of the Mac | It is a LaunchAgent: it runs only after the user logs in | Turn on automatic login for that user, or log in. See [Plex Media Server](./plex-media-server.md) for the always-on Mac settings |
| Jackett stops working after you clean up Downloads | The service runs the program from the folder you extracted it to | Keep it in a permanent folder (Step 2); reinstall the service from there |
| Searches are tied to your home address | Jackett on the Mac goes out through the Mac's normal connection, not the VPN | See [Indexer traffic and privacy](#indexer-traffic-and-privacy) |
| An indexer added in Jackett never gets used | Sonarr and Radarr only search indexers they have been given | Add its feed in each app, or use Prowlarr |
| Searches return duplicates after moving to Prowlarr | Both the old Jackett entries and the `(Prowlarr)` entries are enabled | Delete the Jackett entries in Sonarr and Radarr |
| Changes made to a synced indexer in Sonarr disappear | Prowlarr's Full Sync overwrites them | Make the change in Prowlarr |
| Dashboard reachable from the whole LAN without a password | External access on and no admin password | Set an admin password; turn external access off if only the Mac uses Jackett |

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `http://127.0.0.1:9117` does not load | Service not loaded or crashed | `launchctl load ~/Library/LaunchAgents/org.user.Jackett.plist`. Read the log at `~/.config/Jackett/log.txt` or `~/Library/Application Support/Jackett/log.txt` |
| Jackett starts by hand (`./jackett`) but not as a service | The plist points at an old folder, or the user is not logged in | Run `./install_service_macos` again from the current folder |
| Sonarr indexer test: "Unable to connect to indexer" | Wrong URL, Jackett not running, or a different port | Copy the feed again with **Copy Torznab Feed**; check `lsof -nP -iTCP:9117 -sTCP:LISTEN` |
| Sonarr indexer test: invalid API key | The key was regenerated or mistyped | Copy it again from the top of the Jackett dashboard into every Torznab entry |
| Indexer test fails in Jackett with a login error | The indexer's own credentials or cookie expired | Open the indexer's settings in Jackett and enter them again |
| Indexer test fails with "Challenge detected..." | Cloudflare challenge | See [FlareSolverr](#flaresolverr-and-cloudflare-challenges) |
| Another computer cannot open Jackett | External access is off (the default) | Turn it on if you need it, set the admin password, and allow the connection in the macOS firewall |
| Prowlarr does not start after an update | The updated app is not signed | Run the `codesign` and `xattr` commands again |
| Prowlarr's app test fails | Wrong server URL or API key; a URL base is in use and was not included | Use `http://127.0.0.1:8989` / `:7878` and the key from each app's **Settings > General**; include any URL base |

## Updating Jackett

With auto-update on, Jackett updates itself. With it off, update by hand, as the README describes:

1. Download the newest `Jackett.Binaries.macOS.tar.gz` (Step 1).
2. Stop the service: `launchctl unload ~/Library/LaunchAgents/org.user.Jackett.plist`.
3. Extract the new files over the existing folder: `tar -xzf ~/Downloads/Jackett.Binaries.macOS.tar.gz -C ~/Applications`.
4. Start it: `launchctl load ~/Library/LaunchAgents/org.user.Jackett.plist`.

Your settings and indexers live in `~/.config/Jackett`, not in the program folder, so they survive. Back up `~/.config/Jackett` with the rest of the Mac; it contains the API key and indexer logins, so treat the backup as secret. See [Backups and secrets](../operations/backups-and-secrets.md).

## Undo

**Run on: the media server Mac**

Remove Jackett once nothing uses it (delete its Torznab entries in Sonarr and Radarr first):

```bash
launchctl unload ~/Library/LaunchAgents/org.user.Jackett.plist
rm ~/Library/LaunchAgents/org.user.Jackett.plist
rm -rf ~/Applications/Jackett
```

Its settings are in `~/.config/Jackett`; delete that folder too if you do not want to keep them.

To remove Prowlarr: delete its apps under **Settings > Apps** first if you want the synced indexers removed from Sonarr and Radarr (or delete the `(Prowlarr)` indexers in each app afterwards), quit it, remove it from Login Items, and delete `/Applications/Prowlarr.app`.

## References

- [Jackett on GitHub (README)](https://github.com/Jackett/Jackett): macOS requirements and service install, ports, the "all" endpoint and its limits, FlareSolverr, command-line options.
- [Jackett releases](https://github.com/Jackett/Jackett/releases/latest): downloads for each platform.
- [FlareSolverr on GitHub](https://github.com/FlareSolverr/FlareSolverr): what it is, supported platforms, default port, and the note that captcha solvers do not currently work.
- [Sonarr system and health checks (Servarr wiki)](https://wiki.servarr.com/sonarr/system): "Jackett All Endpoint Used", "Indexers are unavailable due to failures", "Indexer Download Client is Invalid".
- [Prowlarr quick start guide (Servarr wiki)](https://wiki.servarr.com/prowlarr/quick-start-guide): adding indexers and apps, sync levels, the `(Prowlarr)` suffix.
- [Prowlarr macOS installation (Servarr wiki)](https://wiki.servarr.com/prowlarr/installation/macos): install, self-signing, port 9696.
- [Prowlarr settings (Servarr wiki)](https://wiki.servarr.com/prowlarr/settings): indexer proxies, apps, sync profiles.
- [Prowlarr downloads](https://prowlarr.com/): the macOS app builds.
