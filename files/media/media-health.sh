#!/bin/bash
# media-health.sh - read-only health check for a Plex + Sonarr + Radarr + Jackett Mac,
# with qBittorrent on another machine.
#
# Run on: the media server Mac, as the user that runs the apps, from the root of this repo.
#   bash files/media/media-health.sh            # all checks
#   QBIT_HOST=192.168.50.16 VOLUMES="/Volumes/Media" bash files/media/media-health.sh
#
# Tested against a mock Sonarr API on Linux; not yet run on a Mac by the author.
# Volume paths must not contain spaces (VOLUMES is split on spaces).
#
# It reads each app's API key from that app's own config file on this Mac and uses it only
# for local requests. It never prints a key, a token or a password. It changes nothing.
# Works with the bash 3.2 that ships with macOS.

# ---- Settings (override with environment variables) ---------------------------------------
QBIT_HOST="${QBIT_HOST:-192.168.50.16}"
QBIT_PORT="${QBIT_PORT:-8080}"
SONARR_URL="${SONARR_URL:-http://127.0.0.1:8989}"
RADARR_URL="${RADARR_URL:-http://127.0.0.1:7878}"
JACKETT_URL="${JACKETT_URL:-http://127.0.0.1:9117}"
PLEX_URL="${PLEX_URL:-http://127.0.0.1:32400}"
# Volumes that must be mounted (space separated). Media and the download share live here.
VOLUMES="${VOLUMES:-/Volumes/Media}"
# The folder qBittorrent writes into (seen from this Mac). Remote path mappings point here.
DOWNLOADS="${DOWNLOADS:-/Volumes/Media/Downloads}"
MIN_FREE_GB="${MIN_FREE_GB:-100}"

SONARR_CFG="${SONARR_CFG:-$HOME/.config/Sonarr/config.xml}"
RADARR_CFG="${RADARR_CFG:-$HOME/Library/Application Support/Radarr/config.xml}"
JACKETT_CFG="${JACKETT_CFG:-$HOME/.config/Jackett/ServerConfig.json}"
# Jackett may keep its config here instead on some installs.
[ -r "$JACKETT_CFG" ] || [ ! -r "$HOME/Library/Application Support/Jackett/ServerConfig.json" ] || JACKETT_CFG="$HOME/Library/Application Support/Jackett/ServerConfig.json"
# ---------------------------------------------------------------------------------------------

PASS=0; WARN=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  [ OK ] %s\n' "$*"; }
warn() { WARN=$((WARN+1)); printf '  [WARN] %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  [FAIL] %s\n' "$*"; }
hdr()  { printf '\n== %s\n' "$*"; }

xmlkey() { [ -r "$1" ] && sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' "$1" | head -1; }
http()   { curl -s -o /dev/null -m 8 -w '%{http_code}' "$@"; }
listening() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

hdr "This Mac"
printf '  macOS %s, %s\n' "$(sw_vers -productVersion 2>/dev/null)" "$(uname -m)"
PM=$(pmset -g 2>/dev/null)
if [ -z "$PM" ]; then warn "pmset gave no output; cannot check sleep settings"
else
  if printf '%s\n' "$PM" | awk '$1=="sleep"{f=1; exit ($2==0)?0:1} END{if(!f) exit 1}'; then ok "system sleep is off (pmset sleep 0)"
  else warn "system sleep is on: the apps stop when the Mac sleeps (pmset -g | grep sleep)"; fi
  if printf '%s\n' "$PM" | awk '$1=="autorestart"{f=1; exit ($2==1)?0:1} END{if(!f) exit 1}'; then ok "restart after power failure is on"
  else warn "restart after power failure is off (sudo pmset -a autorestart 1)"; fi
fi

hdr "Volumes"
for v in $VOLUMES; do
  if [ -d "$v" ] && mount | grep -q " on $v "; then
    free_gb=$(df -g "$v" | awk 'NR==2{print $4}')
    if [ "${free_gb:-0}" -ge "$MIN_FREE_GB" ]; then ok "$v mounted, ${free_gb} GB free"
    else warn "$v mounted but only ${free_gb} GB free (minimum ${MIN_FREE_GB})"; fi
  else bad "$v is not mounted: Plex shows missing items and imports fail"; fi
done
if [ -d "$DOWNLOADS" ]; then ok "download folder $DOWNLOADS exists"
else bad "download folder $DOWNLOADS is missing: remote path mappings will fail"; fi
if command -v sharing >/dev/null 2>&1; then
  if sharing -l 2>/dev/null | grep -q "path:.*$(basename "$DOWNLOADS")\|path:.*$(dirname "$DOWNLOADS")"; then ok "a File Sharing share covers the download folder"
  else warn "could not confirm a File Sharing share for $DOWNLOADS (System Settings > General > Sharing > File Sharing)"; fi
fi

check_arr() { # name url cfg port
  local name="$1" url="$2" cfg="$3" port="$4" key code
  hdr "$name"
  if listening "$port"; then ok "listening on TCP $port"; else bad "nothing listening on TCP $port (is $name running?)"; return; fi
  key=$(xmlkey "$cfg")
  if [ -z "$key" ]; then warn "no API key found in $cfg; skipping API checks"; return; fi
  code=$(http -H "X-Api-Key: $key" "$url/api/v3/system/status")
  if [ "$code" = 200 ]; then
    ver=$(curl -s -m 8 -H "X-Api-Key: $key" "$url/api/v3/system/status" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | head -1)
    br=$(curl -s -m 8 -H "X-Api-Key: $key" "$url/api/v3/system/status" | sed -n 's/.*"branch": *"\([^"]*\)".*/\1/p' | head -1)
    ok "API answers: version $ver, branch $br"
  else bad "API returned HTTP $code"; return; fi
  # The API returns indented JSON over many lines: join it first, then split per object.
  health=$(curl -s -m 8 -H "X-Api-Key: $key" "$url/api/v3/health" | tr -d '\r\n' | tr '{' '\n' | sed -n 's/.*"type": *"\([a-z]*\)".*"message": *"\([^"]*\)".*/\1: \2/p; s/.*"message": *"\([^"]*\)".*"type": *"\([a-z]*\)".*/\2: \1/p')
  if [ -z "$health" ]; then ok "no health issues"
  else printf '%s\n' "$health" | while IFS= read -r l; do printf '  [HLTH] %s\n' "$l"; done; WARN=$((WARN+1)); fi
  # Ask the app to test its download clients (same as the Test All button).
  tr_out=$(curl -s -m 30 -w '\n%{http_code}' -X POST -H "X-Api-Key: $key" "$url/api/v3/downloadclient/testall")
  tc=$(printf '%s' "$tr_out" | tail -n 1)
  if [ "$tc" = 200 ]; then
    if printf '%s' "$tr_out" | tr -d '\r\n ' | grep -q '"isValid":false'; then
      bad "a download client test failed (Settings > Download Clients > Test)"
    else ok "download client test passed"; fi
  else warn "download client test returned HTTP $tc"; fi
}
check_arr Sonarr "$SONARR_URL" "$SONARR_CFG" "${SONARR_URL##*:}"
check_arr Radarr "$RADARR_URL" "$RADARR_CFG" "${RADARR_URL##*:}"

hdr "Jackett"
jport="${JACKETT_URL##*:}"
if listening "$jport"; then ok "listening on TCP $jport"
  jkey=""
  [ -r "$JACKETT_CFG" ] && jkey=$(plutil -extract APIKey raw -o - "$JACKETT_CFG" 2>/dev/null)
  if [ -n "$jkey" ]; then
    list=$(curl -s -m 20 "$JACKETT_URL/api/v2.0/indexers/all/results/torznab/api?apikey=$jkey&t=indexers&configured=true")
    n=$(printf '%s' "$list" | grep -o '<indexer ' | wc -l | tr -d ' ')
    if [ "${n:-0}" -gt 0 ]; then ok "$n configured indexers"; else warn "no configured indexers returned"; fi
    unset jkey list
  else warn "no API key read from $JACKETT_CFG; skipping indexer list"; fi
else bad "nothing listening on TCP $jport (is Jackett running?)"; fi

hdr "Plex Media Server"
pport="${PLEX_URL##*:}"
if listening "$pport"; then ok "listening on TCP $pport"; else bad "nothing listening on TCP $pport"; fi
ident=$(curl -s -m 8 "$PLEX_URL/identity")
pv=$(printf '%s' "$ident" | sed -n 's/.*version="\([^"]*\)".*/\1/p')
if [ -n "$pv" ]; then ok "server answers, version $pv"
  case "$ident" in *'claimed="1"'*) ok "server is claimed";; *) bad "server is not claimed (open $PLEX_URL/web on this Mac and sign in)";; esac
else bad "no answer from $PLEX_URL/identity"; fi

hdr "qBittorrent on $QBIT_HOST:$QBIT_PORT"
if nc -z -G 5 "$QBIT_HOST" "$QBIT_PORT" >/dev/null 2>&1; then ok "TCP $QBIT_PORT is reachable from this Mac"
  code=$(http "http://$QBIT_HOST:$QBIT_PORT/api/v2/app/version")
  case "$code" in
    200) ok "Web API answers without login (this Mac is in the auth-bypass whitelist)";;
    403) ok "Web API answers and asks for login (normal when this Mac is not whitelisted)";;
    *)   warn "Web API returned HTTP $code";;
  esac
else bad "cannot reach $QBIT_HOST:$QBIT_PORT: check the PC is on, qBittorrent is running, the Windows firewall rule, and the VPN's LAN access setting"; fi

printf '\nSummary: %d ok, %d warnings, %d failures\n' "$PASS" "$WARN" "$FAIL"
[ "$FAIL" -eq 0 ]
