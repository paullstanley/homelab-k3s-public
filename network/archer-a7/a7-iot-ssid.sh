#!/bin/sh
# =============================================================================
# a7-iot-ssid.sh - add the isolated 2.4 GHz IoT SSID to the Archer A7 (OpenWrt
#                  25.12.x, swconfig switch). Run AFTER a7-ap-setup.sh.
#
# The XT8 sends its guest/IoT network (192.168.101.0/24) out of every LAN port as
# tagged VLAN 501. This script bridges that VLAN to a second SSID on the 2.4 GHz
# radio. The A7 gets no address on that network and serves no DHCP: the XT8 does.
#
# Run ON the A7, with the Wi-Fi password and the uplink switch port:
#     scp -O a7-iot-ssid.sh root@192.168.50.3:/tmp/
#     ssh root@192.168.50.3 'IOT_KEY="the-guest-password" UPLINK_PORT=1 sh /tmp/a7-iot-ssid.sh'
#
# UPLINK_PORT is the switch port cabled towards the XT8:
#     WAN port = 1,  LAN1 = 2,  LAN2 = 3,  LAN3 = 4,  LAN4 = 5
# On the live A7 the uplink is the WAN port: UPLINK_PORT=1 (read from LuCI, 8 Oct 2026).
# After a rebuild with a7-ap-setup.sh alone the uplink is a LAN port instead.
#
# Safe to run again: it replaces its own sections instead of adding duplicates.
# Full explanation: docs/03-access-points.md
# =============================================================================
IOT_SSID="${IOT_SSID:-Home-IoT}"   # must match the XT8 guest network name exactly
IOT_VLAN="${IOT_VLAN:-501}"            # check on the XT8: brctl show  (members of br1 end in .501)
RADIO="${RADIO:-radio1}"               # the 2.4 GHz radio

[ -n "$IOT_KEY" ]     || { echo "ERROR: set IOT_KEY to the guest network password"; exit 1; }
[ -n "$UPLINK_PORT" ] || { echo "ERROR: set UPLINK_PORT (WAN=1, LAN1=2 ... LAN4=5)"; exit 1; }
case "$UPLINK_PORT" in 1|2|3|4|5) ;; *) echo "ERROR: UPLINK_PORT must be 1 to 5"; exit 1 ;; esac
[ "$(uci -q get wireless.$RADIO.band)" = "2g" ] || { echo "ERROR: $RADIO is not the 2.4 GHz radio"; exit 1; }

sysupgrade -b "/tmp/a7-before-iot-$(date +%Y%m%d-%H%M%S).tar.gz"

# --- remove what an earlier run (or the LuCI steps) created -------------------
i=0
while uci -q get "network.@switch_vlan[$i]" >/dev/null; do
  if [ "$(uci -q get "network.@switch_vlan[$i].vid")" = "$IOT_VLAN" ]; then
    uci delete "network.@switch_vlan[$i]"
  else
    i=$((i+1))
  fi
done
i=0
while uci -q get "network.@device[$i]" >/dev/null; do
  if [ "$(uci -q get "network.@device[$i].name")" = "br-iot" ]; then
    uci delete "network.@device[$i]"
  else
    i=$((i+1))
  fi
done
uci -q delete network.iot
i=0
while uci -q get "wireless.@wifi-iface[$i]" >/dev/null; do
  if [ "$(uci -q get "wireless.@wifi-iface[$i].network")" = "iot" ]; then
    uci delete "wireless.@wifi-iface[$i]"
  else
    i=$((i+1))
  fi
done

# --- switch: VLAN 501 tagged on the CPU port and the uplink only --------------
uci add network switch_vlan >/dev/null
uci set network.@switch_vlan[-1].device='switch0'
uci set network.@switch_vlan[-1].vlan='3'
uci set network.@switch_vlan[-1].vid="$IOT_VLAN"
uci set network.@switch_vlan[-1].ports="0t ${UPLINK_PORT}t"

# --- bridge and an address-less interface ------------------------------------
uci add network device >/dev/null
uci set network.@device[-1].name='br-iot'
uci set network.@device[-1].type='bridge'
uci add_list network.@device[-1].ports="eth0.$IOT_VLAN"

uci set network.iot=interface
uci set network.iot.proto='none'      # "Unmanaged": the A7 itself stays off the IoT network
uci set network.iot.device='br-iot'

# --- the SSID: plain WPA2, no 802.11w, clients isolated from each other --------
uci set wireless.iot_radio1=wifi-iface
uci set wireless.iot_radio1.device="$RADIO"
uci set wireless.iot_radio1.mode='ap'
uci set wireless.iot_radio1.network='iot'
uci set wireless.iot_radio1.ssid="$IOT_SSID"
uci set wireless.iot_radio1.encryption='psk2+ccmp'
uci set wireless.iot_radio1.key="$IOT_KEY"
uci set wireless.iot_radio1.ieee80211w='0'
uci set wireless.iot_radio1.isolate='1'

uci commit network
uci commit wireless

echo "Restarting network (Wi-Fi drops for a few seconds)..."
/etc/init.d/network restart
sleep 15

echo "---- verify ----"
echo "bridge members (expect eth0.$IOT_VLAN and a phy1-ap interface):"
ls /sys/class/net/br-iot/brif 2>/dev/null
echo "addresses on br-iot (expect none):"
ip -4 addr show br-iot | grep inet
echo "SSID:"
iwinfo 2>/dev/null | grep -B1 -A2 "$IOT_SSID" | head -8
echo "Now join $IOT_SSID from a phone: it must get a 192.168.101.x address."
