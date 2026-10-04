#!/bin/sh
# =============================================================================
# a7-ap-setup.sh - TP-Link Archer A7 v5 on OpenWrt 25.12.x as a bridged ("dumb")
#                  access point at 192.168.50.3 with local-only IPv6.
#
# Run ON the A7:
#     scp -O a7-ap-setup.sh root@192.168.50.3:/tmp/
#     ssh root@192.168.50.3 'sh /tmp/a7-ap-setup.sh'
# (On a freshly flashed A7 the address is 192.168.1.1 instead; plug a computer
#  straight into a LAN port for the first run. The script moves it to .3.)
#
# It does NOT configure Wi-Fi (SSIDs, keys, 802.11k/v/r, neighbor reports).
# Restore those from your sysupgrade backup - see docs/03-access-points.md.
# Everything here is stored by UCI, so it survives reboots. No startup script.
# =============================================================================
A7_IP="192.168.50.3"
A7_IP6="fd00:1234:5678:50::3/64"
GATEWAY="192.168.50.1"
PIHOLE4="192.168.50.11"

# Find the bridge device section whose name is br-lan
DEV=""
i=0
while uci -q get "network.@device[$i]" >/dev/null; do
  [ "$(uci -q get "network.@device[$i].name")" = "br-lan" ] && DEV="network.@device[$i]"
  i=$((i+1))
done
[ -n "$DEV" ] || { echo "ERROR: no 'br-lan' device section in /etc/config/network"; exit 1; }

# Backup first (lives in RAM - copy it off: scp -O root@192.168.50.3:/tmp/a7-before-*.tar.gz .)
sysupgrade -b "/tmp/a7-before-$(date +%Y%m%d-%H%M%S).tar.gz"

# --- IPv4: static address on the main LAN, XT8 is gateway, Pi-hole is DNS ---
uci set network.lan.proto='static'
uci set network.lan.ipaddr="$A7_IP"
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.gateway="$GATEWAY"
uci -q delete network.lan.dns
uci add_list network.lan.dns="$PIHOLE4"

# --- IPv6: on, one static ULA, nothing advertised, no OpenWrt ULA of its own ---
uci -q delete network.globals.ula_prefix
uci set network.lan.ipv6='1'
uci set "$DEV.ipv6=1"              # without this the bridge itself stays IPv6-off
uci -q delete network.lan.ip6assign
uci -q delete network.lan.ip6addr  # delete first so re-runs never duplicate it
uci set network.lan.ip6addr="$A7_IP6"
uci set network.lan.delegate='0'

# --- The A7 must never hand out addresses or router advertisements ---
uci set dhcp.lan.ignore='1'
uci set dhcp.lan.ra='disabled'
uci set dhcp.lan.dhcpv6='disabled'
uci set dhcp.lan.ndp='disabled'

uci commit network
uci commit dhcp

# --- Services a bridged AP does not need ---
for s in odhcpd dnsmasq firewall; do
  [ -x "/etc/init.d/$s" ] && { /etc/init.d/$s disable; /etc/init.d/$s stop; }
done

# uneighbord only talks to other OpenWrt APs; with one OpenWrt AP it just logs errors
apk del uneighbord 2>/dev/null

echo "Restarting network (your SSH session will drop if the address changed)..."
/etc/init.d/network restart
sleep 8

echo "---- verify ----"
ip -4 addr show br-lan | grep inet
ip -6 addr show br-lan | grep inet6      # expect fe80::... and fd00:1234:5678:50::3/64
echo "IPv6 default routes (expect none):"; ip -6 route | grep '^default'
echo "odhcpd/dnsmasq processes (expect none):"; ps | grep -E 'odhcpd|dnsmasq' | grep -v grep
nslookup openwrt.org "$PIHOLE4" >/dev/null 2>&1 && echo "DNS via Pi-hole: OK" || echo "DNS via Pi-hole: FAILED"
