#!/bin/sh
# =============================================================================
# a7-backup.sh - pull a settings backup off the Archer A7 (OpenWrt) and check it.
#
# Run on YOUR MAC, from the root of this repo:
#
#     sh network/archer-a7/a7-backup.sh [A7_IP] [USER] [DEST_FOLDER]
#     sh network/archer-a7/a7-backup.sh
#     sh network/archer-a7/a7-backup.sh 192.168.50.3 root ~/Documents/network-rebuild/a7
#
#   A7_IP        default 192.168.50.3
#   USER         default root
#   DEST_FOLDER  default ~/Documents/network-rebuild/a7
#
# ssh asks for the A7 password once (not an argument: arguments land in shell history).
#
# The backup is OpenWrt's own format: restore it in LuCI under
# System > Backup / Flash Firmware > Restore backup. It holds EVERYTHING that makes
# the A7 yours: Wi-Fi names and passwords, the MAC deny lists, the IoT VLAN and SSID,
# the weekly reboot. It contains passwords, so it is never committed (.gitignore
# blocks a7-backup*.tar.gz) and must not go in the public repo.
#
# Run it after every change to the A7. It keeps the newest KEEP files (default 10).
# =============================================================================
A7_IP="${1:-192.168.50.3}"
A7_USER="${2:-root}"
DEST="${3:-$HOME/Documents/network-rebuild/a7}"
KEEP="${KEEP:-10}"

case "$A7_IP" in -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
case "$A7_IP" in *[!0-9.]*|"") echo "ERROR: A7_IP must be an IPv4 address, got: $A7_IP"; exit 1 ;; esac
case "$A7_USER" in *[!A-Za-z0-9._-]*|"") echo "ERROR: USER has unexpected characters: $A7_USER"; exit 1 ;; esac
case "$KEEP" in *[!0-9]*|""|0) echo "ERROR: KEEP must be a number above 0"; exit 1 ;; esac

mkdir -p "$DEST" || { echo "ERROR: cannot create $DEST"; exit 1; }
OUT="$DEST/a7-backup-$(date +%Y%m%d-%H%M%S).tar.gz"

echo "[a7] pulling backup from $A7_USER@$A7_IP ..."
# "sysupgrade -b -" writes the archive to standard output, so nothing is left on the A7.
if ! ssh -o ConnectTimeout=10 "$A7_USER@$A7_IP" 'sysupgrade -b - 2>/dev/null' > "$OUT.part"; then
  rm -f "$OUT.part"; echo "[a7] FAILED: could not connect or sysupgrade failed. Nothing saved."; exit 1
fi

# ---- check it before trusting it ----
BAD=0
chk() { if eval "$2" >/dev/null 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; BAD=$((BAD+1)); fi; }
chk "archive opens"                         'tar -tzf "$OUT.part"'
chk "has etc/config/network"                'tar -tzf "$OUT.part" | grep -q "^etc/config/network$"'
chk "has etc/config/wireless"               'tar -tzf "$OUT.part" | grep -q "^etc/config/wireless$"'
chk "wireless has an SSID on network iot"   'tar -xzOf "$OUT.part" etc/config/wireless | grep -q "option network .iot."'
chk "network has the IoT bridge br-iot"     'tar -xzOf "$OUT.part" etc/config/network | grep -q "br-iot"'
chk "weekly reboot is in etc/crontabs/root" 'tar -xzOf "$OUT.part" etc/crontabs/root | grep -q "reboot"'

if ! tar -tzf "$OUT.part" >/dev/null 2>&1; then
  rm -f "$OUT.part"; echo "[a7] FAILED: the archive is unreadable. Nothing saved."; exit 1
fi
mv "$OUT.part" "$OUT"
chmod 600 "$OUT"

# ---- keep only the newest $KEEP ----
ls -1t "$DEST"/a7-backup-*.tar.gz 2>/dev/null | awk -v k="$KEEP" 'NR>k' | while IFS= read -r old; do rm -f "$old"; done

echo "[a7] saved: $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes)"
echo "[a7] backups kept in $DEST: $(ls -1 "$DEST"/a7-backup-*.tar.gz | wc -l | tr -d ' ')"
if [ "$BAD" = 0 ]; then
  echo "[a7] all checks passed. Copy this file somewhere off this Mac as well."
else
  echo "[a7] $BAD check(s) failed. The file was kept, but the A7 is missing what the FAIL lines name:"
  echo "     IoT lines -> docs/03-access-points.md, IoT network.  Reboot line -> same guide, Weekly reboot."
fi
