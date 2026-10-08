#!/bin/sh
# =============================================================================
# xt8-node-setup.sh - configure an XT8 AiMesh NODE over SSH. Today that is one
#                     thing: a weekly reboot.
#
# Run on YOUR COMPUTER, from the root of this repo. It logs in to the node and does
# the work there in a single SSH session:
#
#     sh files/xt8/node/xt8-node-setup.sh NODE_IP [USER] [PORT]
#     sh files/xt8/node/xt8-node-setup.sh 192.168.50.117
#     sh files/xt8/node/xt8-node-setup.sh 192.168.50.117 admin 22
#
#   NODE_IP   the node's address (main router > AiMesh shows it). Required.
#   USER      SSH user. Default: admin. A node uses the main router's login.
#   PORT      SSH port. Default: 22.
#
# The password: ssh asks for it once. It is deliberately NOT a command-line
# argument, because arguments are saved in your shell history and visible to
# other programs while the command runs. For an unattended run, install sshpass
# and put the password in the SSHPASS environment variable instead:
#
#     read -s SSHPASS && export SSHPASS        # type the password, press Return
#     sh files/xt8/node/xt8-node-setup.sh 192.168.50.117
#
# Change the schedule with REBOOT_AT (cron fields: minute hour day month weekday):
#     REBOOT_AT="0 4 * * 0" sh files/xt8/node/xt8-node-setup.sh 192.168.50.117
#
# Safe to run again. Lines already in the node's services-start are kept.
# Explanation: docs/hardware/asus-aimesh-node.md
# =============================================================================
NODE_IP="$1"
NODE_USER="${2:-admin}"
NODE_PORT="${3:-22}"
REBOOT_AT="${REBOOT_AT:-30 3 * * 3}"       # Wednesday 03:30
MAIN_IP="192.168.50.1"

usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
[ -n "$NODE_IP" ] || usage
case "$NODE_IP" in -h|--help) usage ;; esac
case "$NODE_IP" in *[!0-9.]*|"") echo "ERROR: NODE_IP must be an IPv4 address, got: $NODE_IP"; exit 1 ;; esac
case "$NODE_PORT" in *[!0-9]*|"") echo "ERROR: PORT must be a number, got: $NODE_PORT"; exit 1 ;; esac
case "$NODE_USER" in *[!A-Za-z0-9._-]*|"") echo "ERROR: USER has unexpected characters: $NODE_USER"; exit 1 ;; esac
case "$REBOOT_AT" in *[!0-9\ \*,/-]*|"") echo "ERROR: REBOOT_AT must be five cron fields, got: $REBOOT_AT"; exit 1 ;; esac
[ "$NODE_IP" != "$MAIN_IP" ] || { echo "ERROR: $MAIN_IP is the main router. Give the node's address."; exit 1; }

SSH="ssh"
if [ -n "$SSHPASS" ]; then
  command -v sshpass >/dev/null 2>&1 || { echo "ERROR: SSHPASS is set but sshpass is not installed."; exit 1; }
  SSH="sshpass -e ssh"
fi

echo "[node] connecting to $NODE_USER@$NODE_IP port $NODE_PORT ..."
# Everything between the two REMOTE lines runs on the node.
$SSH -p "$NODE_PORT" -o ConnectTimeout=10 "$NODE_USER@$NODE_IP" \
  "REBOOT_AT='$REBOOT_AT' MAIN_IP='$MAIN_IP' JFFS=\"\${JFFS:-/jffs}\" sh -s" <<'REMOTE'
F="$JFFS/scripts/services-start"
LAN="$(nvram get lan_ipaddr 2>/dev/null)"
[ "$LAN" != "$MAIN_IP" ] || { echo "ERROR: this device is the main router ($MAIN_IP), not a node. Nothing changed."; exit 1; }
[ -d "$JFFS" ] || { echo "ERROR: $JFFS not found. Is this an Asuswrt-Merlin device?"; exit 1; }

# The firmware's own scheduler (Administration > System) is switched off so the node
# is never asked to reboot twice. It runs from the watchdog and never shows in "cru l".
nvram set reboot_schedule_enable=0
# Without this the firmware ignores /jffs/scripts at boot.
nvram set jffs2_scripts=1
nvram commit

mkdir -p "$JFFS/scripts"
[ -f "$F" ] || printf '#!/bin/sh\n\n' > "$F"
cp -p "$F" "$F.bak"
grep -v 'cru a WeeklyReboot ' "$F.bak" > "$F"
echo "cru a WeeklyReboot \"$REBOOT_AT /sbin/reboot\"" >> "$F"
chmod +x "$F"

# "cru" jobs do not survive a reboot; services-start re-adds this one at every boot.
cru d WeeklyReboot 2>/dev/null
cru a WeeklyReboot "$REBOOT_AT /sbin/reboot"

echo "---- on $(nvram get lan_hostname 2>/dev/null) ($LAN) ----"
echo "jffs2_scripts (expect 1): $(nvram get jffs2_scripts)"
echo "cron (expect one WeeklyReboot line):"; cru l | grep WeeklyReboot
echo "services-start:"; cat "$F"
REMOTE
RC=$?
[ "$RC" = 0 ] && echo "[node] done." || echo "[node] FAILED (exit $RC). If it never connected: check the address, the port, and that SSH is enabled."
exit $RC
