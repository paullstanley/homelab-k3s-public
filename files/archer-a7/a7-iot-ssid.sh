#!/bin/sh
# =============================================================================
# a7-iot-ssid.sh - add the isolated 2.4 GHz IoT SSID to the Archer A7 (OpenWrt
#                  25.12.x, swconfig switch). Run AFTER a7-ap-setup.sh.
#
# An ASUS router on Asuswrt-Merlin 3004.388 sends its guest/IoT network (192.168.101.0/24) out of every LAN port as
# tagged VLAN 501. This script bridges that VLAN to a second SSID on the 2.4 GHz
# radio. The A7 gets no address on that network and serves no DHCP: the router does.
#
# Run ON the A7, with the Wi-Fi password and the uplink switch port:
#     scp -O a7-iot-ssid.sh root@192.168.50.3:/tmp/
#     ssh root@192.168.50.3 'IOT_KEY="the-guest-password" UPLINK_PORT=1 sh /tmp/a7-iot-ssid.sh'
#
# UPLINK_PORT is the switch port cabled towards the main router:
#     WAN port = 1,  LAN1 = 2,  LAN2 = 3,  LAN3 = 4,  LAN4 = 5
# If the WAN port was merged into the LAN VLAN and is your uplink, that is UPLINK_PORT=1.
# With an untouched switch and a LAN-port uplink it is that LAN port's number.
# (Network > Switch in LuCI shows which ports have a link.)
#
# Safe to run again: it replaces its own sections instead of adding duplicates.
# Full explanation: docs/hardware/tp-link-archer-a7-openwrt.md
# =============================================================================
IOT_SSID="${IOT_SSID:-Home-IoT}"   # must match the router's guest network name exactly
IOT_VLAN="${IOT_VLAN:-501}"            # check on the router: brctl show  (members of br1 end in .501)
VLAN_SLOT="${VLAN_SLOT:-3}"            # swconfig table row to use; pick a free one if you already have 3 VLANs
IOT_ENCRYPTION="${IOT_ENCRYPTION:-sae-compat}"  # sae-compat = WPA2/WPA3 compatibility (what the live AP uses);
                                       # psk2+ccmp = plain WPA2 for very old IoT radios
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
uci set network.@switch_vlan[-1].vlan="$VLAN_SLOT"
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

# --- the SSID ------------------------------------------------------------------
uci set wireless.iot_radio1=wifi-iface
uci set wireless.iot_radio1.device="$RADIO"
uci set wireless.iot_radio1.mode='ap'
uci set wireless.iot_radio1.network='iot'
uci set wireless.iot_radio1.ssid="$IOT_SSID"
uci set wireless.iot_radio1.encryption="$IOT_ENCRYPTION"
uci set wireless.iot_radio1.key="$IOT_KEY"
[ "$IOT_ENCRYPTION" = "psk2+ccmp" ] && uci set wireless.iot_radio1.ieee80211w='0'
# bridge_isolate: clients of this SSID cannot reach other ports of br-iot through the AP
# (the live setting). isolate additionally stops clients of this SSID talking to each other.
uci set wireless.iot_radio1.bridge_isolate='1'

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
