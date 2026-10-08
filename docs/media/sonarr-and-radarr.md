# Sonarr and Radarr on an Intel Mac

You end up with Sonarr (TV series) and Radarr (films) running as native apps on the media Mac. They search your indexers, send releases to qBittorrent on another PC, pick up the finished files across the network, rename them into the Plex library with hardlinks, and tell Plex to scan. Seerr can then add requests to them.

Write and use this for media you have the right to download and keep.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | Observed on a working build: Sonarr 4.0.20.3014 (on the `develop` branch, .NET 6.0.13) and Radarr 6.4.4.10685 (reported as `master`, .NET 8.0.27), both as apps in `/Applications` on an Intel Mac with macOS 26; qBittorrent v5.1.0 on a Windows PC at `192.168.50.16`; Jackett v0.24.2756 on the same Mac; Plex Media Server 1.43.4 on the same Mac |
| **Also works for** | Apple Silicon Macs with the `arm64` builds; Prowlarr instead of Jackett ([Jackett and Prowlarr](jackett-and-prowlarr.md)); a downloader on the same Mac (then you need no remote path mapping). **Not tested by the author** |
| **Time** | 1 to 2 hours for both, plus importing an existing library |
| **You need first** | [Media stack overview](media-stack-overview.md) (design and paths), [Plex Media Server](plex-media-server.md) (the Mac prepared, libraries created), [qBittorrent on Windows behind a VPN](qbittorrent-windows-vpn.md), [Jackett and Prowlarr](jackett-and-prowlarr.md) |

Throughout this page, **"observed"** means the setting was read from the running working build, **"upstream"** means it comes from the project's documentation (linked), and **"not verified"** means neither.

## How it works

- Sonarr and Radarr are two separate apps from the same family (the "*arr" or Servarr apps). They work the same way; Sonarr thinks in series, seasons and episodes, Radarr in films. Each has its own database, settings, API key and port: Sonarr `8989`, Radarr `7878`.
- **Root folder**: the library folder an item is filed under, for example `/Volumes/Media/TV`. Every series or film belongs to exactly one root folder.
- **Indexer**: a source of release listings. Here every indexer is a **Torznab** feed (a standard search API for torrent indexers) served by Jackett on the same Mac.
- **Download client**: qBittorrent, reached over the LAN. Each app tags its downloads with its own **category** (`tv-sonarr`, `radarr`) and only looks after downloads in that category.
- **Completed download handling**: when qBittorrent reports a download finished, the app imports it. It needs to read the files, so the Windows path qBittorrent reports is translated by a **remote path mapping** into the Mac path.
- **Import**: the file is hardlinked (same volume) or copied (other volume) into the root folder under a new name. The original stays in `Downloads` so qBittorrent can keep seeding.
- **Connect**: after an import the app tells Plex to scan the folder.

## Before you start

| Decide or gather | Value in the examples |
| --- | --- |
| Mac address | `192.168.50.2` |
| qBittorrent Web UI | `192.168.50.16:8080`, a user name and password for the Web UI |
| Download folder, both views | Windows `M:\Downloads\`, Mac `/Volumes/Media/Downloads/` |
| Root folders | `/Volumes/Media/TV`, `/Volumes/Media/Movies` (on the same volume as `Downloads`) |
| Jackett | `http://127.0.0.1:9117`, its API key, and the indexer IDs you configured |
| Plex | `192.168.50.2:32400`, your Plex account to authorise the connection |
| A user name and password for each app's login | Your own; never reuse one that has been written down anywhere public |
| Branch | `main` for Sonarr, `master` for Radarr, unless you want test builds. See Step 3 |

## Steps

### Step 1. Download and install

Use the **app** build for Intel (`osx-x64`), not the `.tar.gz`:

| App | Download | Release asset name (Intel) |
| --- | --- | --- |
| Sonarr v4 | [sonarr.tv, macOS](https://sonarr.tv/#downloads-macos): "Download macOS App (Intel)" | `Sonarr.main.<version>.osx-x64-app.zip` on [GitHub releases](https://github.com/Sonarr/Sonarr/releases); 4.0.20.3014 was the latest stable when checked |
| Radarr | [radarr.video, macOS](https://radarr.video/#downloads-v3-macos): "Download Intel macOS App" | `Radarr.master.<version>.osx-app-core-x64.zip` on [GitHub releases](https://github.com/Radarr/Radarr/releases) |

Both need macOS 10.15 or later (upstream). Each bundles its own `ffprobe`, so you do not install ffmpeg.

1. Open the zip and **drag the app to Applications**. Sonarr's download page says it "MUST" be in Applications: run from Downloads, macOS's App Translocation (Gatekeeper running the app from a hidden temporary copy) blocks updates.
2. Remove the quarantine flag and self-sign it, as the projects' install guides say ([Sonarr on macOS](https://wiki.servarr.com/sonarr/installation/macos), [Radarr on macOS](https://wiki.servarr.com/radarr/installation/macos)).

**Run on: the Mac**

```sh
codesign --force --deep -s - /Applications/Sonarr.app && xattr -rd com.apple.quarantine /Applications/Sonarr.app
codesign --force --deep -s - /Applications/Radarr.app && xattr -rd com.apple.quarantine /Applications/Radarr.app
open /Applications/Sonarr.app
open /Applications/Radarr.app
```

`codesign -s -` signs the app with an ad-hoc (local) signature; `xattr -rd com.apple.quarantine` removes the "downloaded from the internet" mark that makes Gatekeeper (macOS's check on downloaded apps) refuse to open it.

3. Open `http://localhost:8989` (Sonarr) and `http://localhost:7878` (Radarr).
4. Add both apps to Login Items so they start after a restart; see [Plex Media Server, Step 2](plex-media-server.md#step-2-make-the-apps-come-back-after-a-restart).

> **Pitfall:** "Sonarr cannot be opened because the developer cannot be verified" or "Sonarr.app is damaged and cannot be opened": the quarantine flag is still set, or the download is corrupt. Run the two commands again; if it still says damaged, download again ([Sonarr FAQ](https://wiki.servarr.com/sonarr/faq)).

Where each app keeps its data (observed; the install guides do not state it):

| App | Data folder (appdata) |
| --- | --- |
| Sonarr | `~/.config/Sonarr` |
| Radarr | `~/Library/Application Support/Radarr` |

Each app shows its own under System > Status.

### Step 2. Log in, and decide who may skip the login

Settings > **General** (click **Show Advanced** to see every field).

| Field | Upstream meaning | Observed in both apps | Suggested |
| --- | --- | --- | --- |
| Bind Address | Which addresses the app listens on | `*` (all) | `*` |
| Port Number | | `8989` / `7878` | Default |
| URL Base | A path prefix for reverse proxies | Empty | Empty unless behind a proxy |
| Enable SSL | | Off | Off on the LAN |
| Authentication Method | **Forms** (login page), Basic (browser pop-up) or External. "None" cannot be chosen on a new install. Radarr v6 removed Basic | Forms | Forms |
| Authentication Required | **Enabled**: always ask. **Disabled for Local Addresses**: no login from the LAN | Disabled for Local Addresses | **Enabled** if the app is reachable through any proxy or tunnel; see the pitfall |
| Trusted Networks | Addresses whose `X-Forwarded-For` header (the "real client" address a proxy adds) the app believes | Sonarr: `192.168.0.0/16` | Only the addresses of proxies you run, or empty |
| Trust CGNAT IP addresses | Whether `100.64.0.0/10` addresses count as local | Sonarr: off | Off |
| Allowed hosts (`allowedHosts` in the host settings) | Not described on the Servarr settings page; **not verified** | Sonarr: `shows,192.168.50.2,<the Mac's IPv6 address>`; Radarr: `movies,...` in the same style | Include every name and address you open the app by |
| Analytics | Sends anonymous usage data | Sonarr off, Radarr on | Your choice |
| Log Level | | Info | Info; Debug or Trace only while chasing a problem |
| API Key | Used by Seerr, Prowlarr and scripts | Set (never shown here) | Keep secret |

> **Pitfall: "Disabled for Local Addresses" can be bypassed.** The Servarr settings pages warn that, without a properly configured reverse proxy, a caller could fake the `X-Forwarded-For` header to look local and skip the login (CVE-2026-30975). The apps only believe that header from addresses in **Trusted Networks**. If you do not run a trusted proxy in front of the app, set Authentication Required to **Enabled** ([Sonarr settings](https://wiki.servarr.com/sonarr/settings), [Radarr settings](https://wiki.servarr.com/radarr/settings)). Never publish Sonarr or Radarr on the internet; reach them through a VPN to home if you need them away.

> **Pitfall:** a range such as `192.168.0.0/16` in Trusted Networks also covers other `192.168.x.x` networks in the house, such as an IoT network at `192.168.101.0/24`. Keep it to what you need.

### Step 3. Choose the branch and how updates install

Settings > General > **Updates** (advanced).

| | Sonarr | Radarr |
| --- | --- | --- |
| Branches (upstream FAQ) | `main`: default, stable. `develop`: beta, updated as soon as code passes tests | `master`: default, stable, about monthly. `develop`: beta, weekly or fortnightly. `nightly`: alpha, unstable |
| Going back | Switching from `develop` to `main` may not be possible | You "may not be able to go back to `master`" |
| Observed branch | **`develop`** | `master` |
| Observed update setting | Automatic, built-in updater | Automatic updates off |

Sources: [Sonarr FAQ](https://wiki.servarr.com/sonarr/faq), [Radarr FAQ](https://wiki.servarr.com/radarr/faq).

Update mechanism (upstream): **Built-in** (the app updates itself), **Script** (runs a script you give it) or **Docker** (do nothing; you pull a new image). Use Built-in on a Mac.

> **Pitfall: a test branch on a server.** The working build's Sonarr was on `develop`, so it received beta builds as soon as they passed automated tests, and moving back to `main` may not be possible without restoring a backup taken before the switch. Choose `main` (Sonarr) and `master` (Radarr) on a fresh install.

> **Pitfall: updates and Gatekeeper.** Radarr's macOS guide says the updater must also be self-signed, or you install updates by hand. If an update leaves the app refusing to open, run the `codesign` / `xattr` line from Step 1 again. The app must be in `/Applications` for updates to work at all.

> **Not verified:** the Radarr version observed (6.4.4.10685, reported as `master`) was newer than what the Radarr GitHub releases page listed when checked (6.3.0.10514 as latest stable, 6.4.x as pre-releases). Check System > Updates in your own copy rather than relying on these numbers.

### Step 4. Add root folders

Settings > **Media Management** > **Root Folders** > **Add Root Folder**.

| App | Root folders |
| --- | --- |
| Sonarr | `/Volumes/Media/TV` (and `/Volumes/Media2/TV` for a second disk) |
| Radarr | `/Volumes/Media/Movies` (and `/Volumes/Media2/Movies`) |

These must be the same folders as the Plex libraries. Put the main root folder on the **same volume as `Downloads`**, so imports are hardlinks; see [Media stack overview](media-stack-overview.md#folder-layout-and-why-one-filesystem-matters).

If the folders already contain series or films, the root folder list shows them as **unmapped folders** (folders on disk that the app does not manage). The working build had hundreds. Bring them in with **Library Import** (Sonarr: Series > Library Import; Radarr: Movies > Library Import), or leave them; unmapped folders do no harm but are not monitored or upgraded.

### Step 5. Add qBittorrent as the download client

Settings > **Download Clients** > **+** > **qBittorrent**.

| Field | Sonarr (observed) | Radarr (observed) | Notes |
| --- | --- | --- | --- |
| Host | `192.168.50.16` | `192.168.50.16` | The address. Remember it: the remote path mapping must use the same text |
| Port | `8080` | `8080` | qBittorrent Web UI port |
| Use SSL | Off | Off | |
| Username, Password | qBittorrent Web UI login | same | |
| Category | `tv-sonarr` | `radarr` | Created in qBittorrent on first use. Each app only handles its own category |
| Recent / Older priority | `0` (default) | | |
| Initial State | Start (stored value `0`) | | |
| Client Priority | `1` | | Only matters with several clients |
| Remove Completed | **Off** | **On** | See below |
| Remove Failed | On | On | Removes failed downloads from qBittorrent |

Click **Test**; it should show a green tick.

How **Remove Completed** interacts with seeding (upstream: [Sonarr settings](https://wiki.servarr.com/sonarr/settings), [Radarr settings](https://wiki.servarr.com/radarr/settings)):

- The app removes a torrent only after it is imported **and** qBittorrent has stopped (paused) it at its seed goal. The torrent must stay in the same category.
- The seed goal comes from the **indexer's** Seed Ratio / Seed Time (Step 8). The app sends these to qBittorrent with each torrent. If they are empty, qBittorrent's own seeding limits apply.
- **Observed:** qBittorrent had no seeding limits of its own. Sonarr's indexers had Seed Ratio `1`, so Sonarr's torrents stopped at ratio 1 but, with Remove Completed off, stayed listed in qBittorrent (and their files stayed in `Downloads`) until removed by hand. Radarr had Remove Completed on; its indexers' seed settings were not recorded. A torrent with no seed goal from anywhere seeds forever and is never removed.
- When the torrent is removed, its file in `Downloads` goes. A hardlinked library copy is unaffected; it is the same data with another name.

### Step 6. Add the remote path mapping

Settings > **Download Clients** > **Remote Path Mappings** > **+**, in **both** apps:

| Field | Value |
| --- | --- |
| Host | `192.168.50.16` (exactly as in Step 5) |
| Remote Path | `M:\Downloads\` |
| Local Path | `/Volumes/Media/Downloads/` |

**Observed:** the two apps had the Local Path with different capitalisation of the volume name. It worked only because the volume is case-insensitive APFS. Copy the path from Finder or from `ls /Volumes`, and make both apps identical. Why the mapping exists, and the UNC alternative to a mapped drive letter, are explained in [Media stack overview](media-stack-overview.md#remote-path-mappings) and the [TRaSH remote path guide](https://trash-guides.info/Radarr/Tips/Radarr-remote-path-mapping/).

### Step 7. Completed download handling

Settings > Download Clients (advanced), observed in Sonarr:

| Setting | Observed | Meaning |
| --- | --- | --- |
| Enable (Completed Download Handling) | On | Import finished downloads automatically |
| Redownload Failed | On | Search again when a download fails |
| Redownload Failed from Interactive Search | On | Also for releases you picked by hand |
| Download client working folders | `_UNPACK_\|_FAILED_` | Folders the app ignores while a client is still working in them |

### Step 8. Add indexers through Jackett (Torznab)

Add **one Torznab indexer per Jackett indexer**. In Jackett, each indexer's **Copy Torznab Feed** button gives its URL. Settings > **Indexers** > **+** > **Torznab**:

| Field | Value | Notes |
| --- | --- | --- |
| Name | Your name for it | |
| Enable RSS | On (or off for interactive-only) | RSS: the app checks the indexer's newest releases on a timer |
| Enable Automatic Search | On (or off) | The app searches by itself for missing and wanted items |
| Enable Interactive Search | On | You search by hand and pick |
| URL | `http://127.0.0.1:9117/api/v2.0/indexers/<id>/results/torznab/` | `<id>` is Jackett's ID for that indexer. `127.0.0.1` because Jackett is on the same Mac |
| API Path | `/api` | Default |
| API Key | Jackett's API key (top right of Jackett's page) | |
| Categories | TV: `5000` (TV) and its subcategories; films: `2000` (Movies) and its subcategories | Indexer-specific categories (numbers of 100000 and up) appear when the indexer offers them |
| Minimum Seeders (advanced) | `1` observed | Ignore releases with fewer seeders |
| Seed Ratio (advanced) | `1` observed (Sonarr) | Goal sent to qBittorrent; see Step 5 |
| Seed Time, Season-Pack Seed Time (advanced) | Empty observed | Time-based goals |
| Indexer Priority (advanced) | `1` to `50`; `1` is highest. Default `25` | Breaks ties between equal releases. Observed: `1` and `2` for preferred indexers, `25` for an interactive-only one |
| Download Client (advanced) | Observed: most indexers pinned to the qBittorrent client | Leave empty unless you have several clients |
| Tags | | Limits the indexer to series/films with the same tag |

**Observed indexer pattern** (Sonarr): four Torznab indexers through Jackett. Three had RSS, automatic and interactive search on, with priorities `1` or `2`; one was **interactive-only** (RSS and automatic search off) at priority `25`, so it is only used when you search by hand. All had Minimum Seeders `1`; the three automatic ones had Seed Ratio `1`. Radarr had five Torznab indexers in the same style.

Other indexer options observed in Sonarr (Settings > Indexers > Options): RSS Sync Interval `120` minutes; Minimum Age, Retention and Maximum Size `0` (no limit).

> **Pitfall: one indexer per feed.** Jackett also offers an aggregate "all" endpoint (`.../indexers/all/results/torznab`). Jackett's README lists its drawbacks (no per-indexer categories or settings, the slowest indexer slows everything, results capped at 1000), and the apps raise a "Jackett All Endpoint Used" health warning. Add indexers individually.

> **Pitfall: an indexer removed in Jackett stays in the apps.** Observed: an indexer deleted from Jackett was still listed in Radarr and failed on every search. When you remove an indexer in Jackett, remove it from Sonarr and Radarr too. Prowlarr avoids this by syncing the list for you ([Jackett and Prowlarr](jackett-and-prowlarr.md)).

> **Pitfall: an indexer pointing at a client that does not exist.** Observed: Sonarr had a Usenet (Newznab) indexer whose Download Client setting pointed at a client ID that no longer existed, and no Usenet client at all. Sonarr raised "Indexer Download Client is Invalid". Remove indexers for a protocol you have no client for, or clear their Download Client field.

The **delay profile** (Settings > Profiles) was the default in the working build: prefer Usenet, no delay. With only torrent indexers, this has no effect.

### Step 9. Media management

Settings > **Media Management** (Show Advanced). Observed in Sonarr:

| Setting | Observed | Meaning (upstream where linked) |
| --- | --- | --- |
| Use Hard links instead of Copy | **On** | Hardlink files that are still seeding. Falls back to a copy if the hardlink fails ([Sonarr settings](https://wiki.servarr.com/sonarr/settings)) |
| Download Propers and Repacks | Prefer and Upgrade | A fixed re-release of the same quality replaces the original |
| Rescan Series Folder after Refresh | Always | The app rescans its folders on the refresh schedule. "Never" is only safe if nothing else ever changes files |
| Episode Title Required | Always | Wait for an episode title before importing, so the file name is complete |
| Minimum Free Space When Importing | 100 MB | Refuses to import if the disk would go below this |
| Import Extra Files | Off | `.srt` subtitles beside the video are not imported |
| Unmonitor Deleted Episodes | On | An episode file you delete is not downloaded again |
| Recycle Bin | Empty | Deleted files are gone. Set a folder on the same volume if you want a safety net |
| Create Empty Series Folders, Delete Empty Folders | Off, Off | |
| Change File Date | None | |

Radarr has the same page with film wording; "Use Hard links instead of Copy" is on by default for torrents (upstream).

### Step 10. Quality profiles

Observed: the default profiles in both apps (Sonarr: Any, SD, HD-720p, HD-1080p, HD - 720p/1080p), upgrades **off**, no custom formats, no release profiles; Radarr's profiles set to English. "Upgrades off" means the first release that meets the profile is kept; nothing replaces it later except a proper or repack (Step 9).

To get a different result, edit the profile Seerr uses (Step 13), or create a new one. Custom formats and the TRaSH Guides profiles are outside this page.

### Step 11. Connect Plex

Settings > **Connect** > **+** > **Plex Media Server**:

| Field | Value |
| --- | --- |
| Host | `192.168.50.2` |
| Port | `32400` |
| Use SSL | Off |
| Authenticate with Plex.tv | Click and sign in; this stores a token |
| Update Library | On |
| Triggers (observed in Sonarr) | On Import/Download, On Upgrade, On Rename, On Series Add, On Series Delete, On Episode File Delete, On Episode File Delete For Upgrade |

Click **Test**. **Observed:** Radarr used Plex's secure address `https://192-168-50-2.<hash>.plex.direct:32400` with SSL on, where `<hash>` is unique to that server; either form works. Plex's side is on [Plex Media Server](plex-media-server.md#step-12-let-sonarr-and-radarr-update-plex).

### Step 12. Metadata

Settings > **Metadata**. Observed:

| App | Consumer | State |
| --- | --- | --- |
| Sonarr | **Plex** (series Plex match file, episode mappings) | **On**. Writes a `.plexmatch` file into each series folder so Plex matches the right show |
| Sonarr | Kodi (XBMC) / Emby, Roksbox, WDTV | Off |
| Sonarr | Kometa | Off; marked deprecated |
| Radarr | All | Off. Radarr still showed health warnings about a legacy Emby entry and about Kometa |

Radarr's "Kometa metadata is deprecated" warning goes away when the Kometa consumer is **disabled** in Settings > Metadata ([Radarr System](https://wiki.servarr.com/radarr/system#kometa-metadata-is-deprecated)). If you see it with every consumer apparently off, open the Kometa entry and make sure **Enable** is off and saved.

### Step 13. Connect Seerr

In Seerr: Settings > **Services** > Add Radarr Server / Add Sonarr Server ([Seerr: Services](https://docs.seerr.dev/using-seerr/settings/services/)). Seerr in this build runs on k3s, so it must use the Mac's address, not `localhost`:

| Field | Sonarr | Radarr |
| --- | --- | --- |
| Default Server | On | On |
| Server Name | Your label | Your label |
| Hostname or IP Address | `192.168.50.2` | `192.168.50.2` |
| Port | `8989` | `7878` |
| Use SSL | Off | Off |
| API Key | Sonarr: Settings > General > API Key | Radarr: same place |
| Quality Profile, Root Folder | `/Volumes/Media/TV` | `/Volumes/Media/Movies` |
| Minimum Availability | | Released (or Announced, to search earlier) |
| Enable Scan | On, so people cannot request what you already have | On |
| Enable Automatic Search | On, so an approved request searches at once | On |

**Observed:** both apps had tags of the form `<id>-<username>`, one per Seerr user who had made a request. Seerr adds them so you can see who asked for what. They do no harm; you can use them to filter.

The Seerr page: [Seerr behind a Cloudflare tunnel](../apps/seerr-cloudflare-tunnel.md). Sonarr and Radarr themselves stay LAN-only; Seerr reaches them from inside the house.

## Naming

Settings > **Media Management** > **Episode Naming** / **Movie Naming**, with **Rename Episodes** / **Rename Movies** on.

**As configured on the working build:**

| Setting | Value |
| --- | --- |
| Sonarr Standard Episode Format | `{Series Title} - S{season:00}E{episode:00} - {Episode Title} {Quality Full}` |
| Sonarr Daily Episode Format | `{Series Title} - {Air-Date} - {Episode Title} {Quality Full}` |
| Sonarr Anime Episode Format | `{Series Title} - S{season:00}E{episode:00} - {Episode Title} {Quality Full}{ImdbId}` |
| Sonarr Series Folder Format | `{Series Title}` |
| Sonarr Season Folder Format | `Season {season}` |
| Sonarr Specials Folder Format | `Specials` |
| Sonarr Multi-Episode Style | Prefixed Range |
| Sonarr Colon Replacement | Smart replace (stored value `4`; label **not verified**) |
| Sonarr Replace Illegal Characters | On |
| Radarr Standard Movie Format | `{Movie Title} ({Release Year}) {Quality Full}` |
| Radarr Movie Folder Format | `{Movie Title} ({Release Year}){ImdbId}` |

That gives, for example, `Show Name/Season 1/Show Name - S01E01 - Pilot WEBDL-1080p.mkv` and `Film Title (2005)tt0372784/Film Title (2005) Bluray-1080p.mkv`.

> **Pitfall: the film folder format.** `{Movie Title} ({Release Year}){ImdbId}` produces `Film Title (2005)tt0372784`: the ID is glued to the year with no space and no braces. Plex does not read that as an ID hint, and the folder name is harder to read. The anime format has the same glued `{ImdbId}`. Use the braced form below.

**Recommended**, so that every folder carries the database ID Plex can match on ([Plex TV naming](https://support.plex.tv/articles/naming-and-organizing-your-tv-show-files/), [Plex movie naming](https://support.plex.tv/articles/naming-and-organizing-your-movie-media-files/)):

| Setting | Value | Source |
| --- | --- | --- |
| Sonarr Series Folder Format | `{Series CleanTitleWithoutYear} {(Series Year)} {tvdb-{TvdbId}}` | [TRaSH Sonarr naming](https://trash-guides.info/Sonarr/Sonarr-recommended-naming-scheme/) (Plex) |
| Sonarr Season Folder Format | `Season {season:00}` | TRaSH; matches Plex's `Season 01` examples |
| Radarr Movie Folder Format | `{Movie Title} ({Release Year}) {imdb-{ImdbId}}` or TRaSH's `{Movie CleanTitle} ({Release Year}) {imdb-{ImdbId}}` | [TRaSH Radarr naming](https://trash-guides.info/Radarr/Radarr-recommended-naming-scheme/); TRaSH notes `{tmdb-{TmdbId}}` usually matches more reliably than IMDb |

Keep the file formats as you like; the folder carries the ID. Do not put file tokens such as `{Quality Full}` in a **folder** format: Radarr warns "Movie Folder Format uses deprecated tokens" ([Radarr System](https://wiki.servarr.com/radarr/system#movie-folder-format-uses-deprecated-tokens)).

> **Not verified:** a new folder format applies to series and films added afterwards. Renaming existing folders in bulk (through the series or movie editor) moves files and makes Plex rescan them; try it on a few items first.

## Backups

Both apps make their own backups (Settings > General > **Backups**). Observed and upstream defaults agree:

| Setting | Value |
| --- | --- |
| Folder | `Backups`, relative to the appdata folder |
| Interval | Every 7 days |
| Retention | 28 days |

So the zip files are in `~/.config/Sonarr/Backups` and `~/Library/Application Support/Radarr/Backups`. System > **Backup** > **Backup Now** makes one on demand (kept until you delete it), and **Restore Backup** loads one.

**Run on: the Mac**. Copy the backups off the Mac now and then.

```sh
tar -czf ~/arr-backups.tar.gz -C ~ ".config/Sonarr/Backups" "Library/Application Support/Radarr/Backups"
```

The backups contain the API keys, the Plex token and the qBittorrent password. Keep them out of Git and off shared storage ([Backups and secrets](../operations/backups-and-secrets.md)).

## Check it

| Test | Where | Pass |
| --- | --- | --- |
| `curl -s -o /dev/null -w '%{http_code}\n' http://192.168.50.2:8989/ping` and `...:7878/ping` | any LAN computer | `200` |
| System > Status > Health | each app | No messages, or only ones you understand |
| Settings > Download Clients > qBittorrent > Test | each app | Green tick |
| Settings > Indexers > Test All | each app | Green ticks |
| Search one episode by hand (Interactive Search) | Sonarr | Results from several indexers |
| Grab it; watch Activity > Queue | Sonarr | Downloading, then imported; no "waiting to import" |
| `ls -li` on the download and the library file | the Mac | Same inode number: hardlinked |
| [`files/media/media-health.sh`](../../files/media/media-health.sh) | the Mac | See the script's header for expected output |

The `/ping` endpoint answers without a login; **not verified by the author** on these exact versions.

## Pitfalls

| What happens | Why | Avoid or recover |
| --- | --- | --- |
| App will not open after download or update | Gatekeeper quarantine / signature | Step 1 commands again; keep it in `/Applications` |
| Imports are copies, disk fills | Root folder on a different volume from `Downloads` | Main root folders on the download volume |
| One app imports, the other does not | Different remote path mappings | Make them identical |
| Torrents never leave qBittorrent | Remove Completed off, or no seed goal anywhere | Set Seed Ratio/Time on the indexers and turn Remove Completed on, or tidy qBittorrent by hand |
| Torrents vanish before you wanted | Remove Completed on with a low seed goal | Raise the indexer's Seed Ratio/Time |
| Login can be skipped through a proxy | Disabled for Local Addresses with a loose Trusted Networks | Step 2 |
| Stuck on a beta branch | `develop` chosen; switching back unsupported | Choose `main`/`master` from the start; keep a backup from before any switch |
| An indexer fails on every search | It was removed from Jackett, or it now needs FlareSolverr | Remove it from the app, or fix it in [Jackett and Prowlarr](jackett-and-prowlarr.md) |
| A series shows an error and will not refresh | It was removed from TheTVDB | See Troubleshooting |
| Plex matches a film wrongly | Folder format without a usable ID | Recommended naming |

## Troubleshooting

The Health list (System > Status) links each message to a Servarr wiki section. The ones met on the working build, and the usual cross-machine problems:

| Symptom (Health message or behaviour) | Cause | Fix |
| --- | --- | --- |
| Sonarr: **Indexer Download Client is Invalid** | An indexer's Download Client points at a client that was deleted or disabled. Observed: a Usenet indexer pointing at a client that did not exist | Settings > Indexers > that indexer > clear or change Download Client, or delete the indexer. [Sonarr System](https://wiki.servarr.com/sonarr/system#indexer-download-client-is-invalid). Sonarr 4.0.20's own link goes to `#invalid-indexer-download-client-setting`, which is the **Radarr** heading; on the Sonarr page the heading is the one linked here |
| Radarr: **Invalid Indexer Download Client Setting** | Same as above, Radarr's wording | [Radarr System](https://wiki.servarr.com/radarr/system#invalid-indexer-download-client-setting) |
| **Indexers are unavailable due to failures** (some for more than 6 hours) | Repeated errors from those indexers; the app backs off for up to 24 hours. Observed causes: an indexer removed from Jackett but still in the app; indexers behind a Cloudflare challenge failing in Jackett ("Challenge detected but FlareSolverr is not configured") | Test the indexer; read System > Logs; fix or remove it in Jackett and the app. [Sonarr System](https://wiki.servarr.com/sonarr/system#indexers-are-unavailable-due-to-failures), [Radarr System](https://wiki.servarr.com/radarr/system#indexers-are-unavailable-due-to-failures), [Jackett and Prowlarr](jackett-and-prowlarr.md) |
| All search-capable indexers are temporarily unavailable | Every indexer failed recently | As above; often Jackett itself is down: open `http://127.0.0.1:9117` |
| **Jackett All Endpoint Used** | An indexer uses Jackett's `all` feed | One Torznab indexer per Jackett indexer (Step 8) |
| **Series Removed from TheTVDB** | The series was removed from TheTVDB, often as a duplicate or merged into another entry | Remove the series from Sonarr (keep the files) and add the correct one. [Sonarr System](https://wiki.servarr.com/sonarr/system#series-removed-from-thetvdb) |
| **Bad Remote Path Mapping** | The path qBittorrent reports does not exist on the Mac after mapping: missing or wrong mapping, wrong Host, wrong case | Step 6. [Sonarr](https://wiki.servarr.com/sonarr/system#bad-remote-path-mapping), [Radarr](https://wiki.servarr.com/radarr/system#bad-remote-path-mapping) |
| **Remote Path is Used and Import Failed** | The mapping applied, but the file could not be read: share or volume not mounted, permissions | `ls /Volumes/Media/Downloads` on the Mac; check the share and that qBittorrent really saves there. [Sonarr System](https://wiki.servarr.com/sonarr/system#remote-path-is-used-and-import-failed) |
| Queue item stays at **Downloaded - waiting to import** (yellow or red icon) | The app cannot import: path not found (mapping), file not readable, a sample or unexpected file, or the release could not be matched to the series or film | Hover the icon in Activity > Queue for the reason. Fix the mapping, or use **Manual Import** for that item. [Sonarr FAQ](https://wiki.servarr.com/sonarr/faq) ("Why is there a number next to Activity") |
| Downloads never show in the queue at all | Category mismatch: qBittorrent's torrent has another or no category | Check the category in qBittorrent equals Step 5's |
| **Hardlink failing across volumes**: imports work but use double space, or the log says the hardlink failed and it copied | Root folder and `Downloads` on different volumes, or a filesystem without hardlinks (exFAT). There is no health message for this | Move root folders to the download volume; APFS or Mac OS Extended. [Sonarr FAQ](https://wiki.servarr.com/sonarr/faq) ("Why are there two files?"), [Radarr FAQ](https://wiki.servarr.com/radarr/faq) |
| Radarr: **Kometa metadata is deprecated** | The Kometa metadata consumer is still enabled | Disable it in Settings > Metadata. [Radarr System](https://wiki.servarr.com/radarr/system#kometa-metadata-is-deprecated) |
| Radarr: **Movie Folder Format uses deprecated tokens** | File-only tokens in the folder format | Remove them ([Naming](#naming)) |
| Download client test: cannot connect | qBittorrent down, Web UI bound elsewhere, firewall, VPN app blocking LAN | [qBittorrent on Windows behind a VPN](qbittorrent-windows-vpn.md); run [`files/media/qbit-check.ps1`](../../files/media/qbit-check.ps1) on the PC |
| Plex connection test fails | Token expired or revoked; possibly Plex set to require secure connections while SSL is off (**not verified**) | Authenticate with Plex.tv again; or use the `plex.direct` address with SSL |
| Database errors ("database disk image is malformed") | Corrupted SQLite database, often after a crash or power cut | Restore the latest backup (System > Backup). See the Sonarr FAQ |

## Undo

1. Remove the apps from Login Items and quit them.
2. Delete `/Applications/Sonarr.app` and `/Applications/Radarr.app`.
3. Delete the appdata folders `~/.config/Sonarr` and `~/Library/Application Support/Radarr` (back up first).
4. Remove the Sonarr and Radarr servers from Seerr, and the categories from qBittorrent if you no longer want them.

Media files in the root folders are not touched by any of this.

## References

- [Sonarr: downloads](https://sonarr.tv/#downloads-macos) and [Sonarr releases](https://github.com/Sonarr/Sonarr/releases): the macOS app build and current version.
- [Radarr: downloads](https://radarr.video/#downloads-v3-macos) and [Radarr releases](https://github.com/Radarr/Radarr/releases): the macOS app build and current version.
- [Servarr wiki: Sonarr on macOS](https://wiki.servarr.com/sonarr/installation/macos) and [Radarr on macOS](https://wiki.servarr.com/radarr/installation/macos): install, self-sign, first run.
- [Servarr wiki: Sonarr settings](https://wiki.servarr.com/sonarr/settings) and [Radarr settings](https://wiki.servarr.com/radarr/settings): authentication, trusted networks, remote path mappings, Remove Completed, hardlinks, backups, indexer seed settings.
- [Servarr wiki: Sonarr System](https://wiki.servarr.com/sonarr/system) and [Radarr System](https://wiki.servarr.com/radarr/system): every health check message and its fix.
- [Servarr wiki: Sonarr FAQ](https://wiki.servarr.com/sonarr/faq) and [Radarr FAQ](https://wiki.servarr.com/radarr/faq): branches, two files while seeding, mapped drives versus UNC, macOS open errors.
- [TRaSH Guides: Remote Path Mappings](https://trash-guides.info/Radarr/Tips/Radarr-remote-path-mapping/): the find-and-replace behind remote path mappings.
- [TRaSH Guides: Sonarr naming](https://trash-guides.info/Sonarr/Sonarr-recommended-naming-scheme/) and [Radarr naming](https://trash-guides.info/Radarr/Radarr-recommended-naming-scheme/): naming schemes with Plex ID folders. These pages showed a "Docs built by Pull Request" banner when checked.
- [Jackett README](https://github.com/Jackett/Jackett): Torznab feeds and why not to use the `all` endpoint.
- [Seerr: Services settings](https://docs.seerr.dev/using-seerr/settings/services/): connecting Seerr to Sonarr and Radarr.
