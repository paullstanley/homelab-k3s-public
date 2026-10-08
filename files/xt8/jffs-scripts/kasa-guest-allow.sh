#!/bin/sh
# Asus guest isolation lives in "ebtables -t broute": it drops icmp/tcp from the
# guest Wi-Fi to 192.168.50.0/24, which kills the REPLIES from Kasa devices to
# Homebridge. These ACCEPT rules sit above those DROPs, for the k3s nodes only.
# Idempotent (delete, then insert). Run by firewall-start and service-event-end.
. /jffs/scripts/homenet.conf
for IP in $(echo "$HB_HOSTS" | tr ',' ' '); do
  for PR in icmp tcp; do
    ebtables -t broute -D BROUTING -p IPv4 -i "$GUEST_WL" --ip-dst "$IP" --ip-proto "$PR" -j ACCEPT 2>/dev/null
    ebtables -t broute -I BROUTING -p IPv4 -i "$GUEST_WL" --ip-dst "$IP" --ip-proto "$PR" -j ACCEPT
  done
done
