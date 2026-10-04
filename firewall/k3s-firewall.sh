#!/usr/bin/env bash
#
# k3s-firewall.sh - host firewall (ufw) for one k3s server node.
#
# Run on ONE node at a time:   sudo bash k3s-firewall.sh
#
# What it does
#   - Other cluster nodes and the pod/service networks: allowed in full (k3s needs this).
#   - etcd, kubelet, flannel and MetalLB's internal ports: blocked for everything else.
#   - Your home ranges (192.168.0.0/16, which covers the main LAN 192.168.50.x, the VPN
#     subnet 192.168.0.x and the IoT network; plus the LAN's IPv6 range): allowed for everything else
#     (SSH, kubectl, Pi-hole, Traefik, Homebridge and HomeKit discovery keep working).
#   - The guest/IoT network 192.168.101.0/24 is inside that /16, so Kasa and Wyze devices can
#     answer Homebridge. They still cannot reach the cluster-internal ports. (The separate IoT
#     rule for the Homebridge node is kept so narrowing LAN4 later does not break Kasa.)
#   - Everything else: blocked inbound.
#
# Safety net
#   A timer switches the firewall OFF again after 10 minutes. If everything checks out,
#   cancel the timer to keep the firewall on:
#       sudo systemctl stop ufw-safety.timer
#   If you get locked out, wait 10 minutes and the node opens up again by itself.
#
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo: sudo bash $0" >&2
  exit 1
fi

# ---- Your network. Edit here if addresses change. ---------------------------------------------
# /16, not /24: you also reach the Pis from 192.168.0.x when on VPN. This range includes the
# main LAN (192.168.50.x) and the IoT network (192.168.101.x). Cluster-internal ports stay
# blocked for all of it (rule 3 comes before rule 4).
LAN4="192.168.0.0/16"
LAN6="fd00:1234:5678:50::/64"

# Guest / IoT network (Kasa and Wyze devices) and the node that runs Homebridge.
IOT4="192.168.101.0/24"
HOMEBRIDGE_NODE="k3sprimary"

NODES="
192.168.50.5
192.168.50.6
192.168.50.7
192.168.50.146
fd00:1234:5678:50::5
fd00:1234:5678:50::6
fd00:1234:5678:50::7
fd00:1234:5678:50:5055:55ff:fe15:f169
"

# Pod and service networks, from /etc/rancher/k3s/config.yaml
CLUSTER_NETS="
10.42.0.0/16
10.43.0.0/16
fd00:1234:5678:4200::/56
fd00:1234:5678:4300::/112
"
# -----------------------------------------------------------------------------------------------

echo "==> Installing ufw"
apt-get update -qq
apt-get install -y -qq ufw

echo "==> Arming the 10-minute safety timer"
systemctl stop ufw-safety.timer 2>/dev/null || true
systemctl reset-failed ufw-safety.service 2>/dev/null || true
systemd-run --quiet --unit=ufw-safety --on-active=10m /usr/sbin/ufw --force disable

echo "==> Resetting ufw and setting defaults"
ufw --force reset >/dev/null
sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw
ufw default deny incoming  >/dev/null
ufw default allow outgoing >/dev/null
# REQUIRED for Kubernetes: traffic to pods and services is forwarded, not delivered to the host.
ufw default allow routed   >/dev/null

echo "==> 1. Cluster nodes: allow everything"
for n in $NODES; do
  ufw allow from "$n" comment 'k3s node' >/dev/null
done

echo "==> 2. Pod and service networks: allow everything"
for c in $CLUSTER_NETS; do
  ufw allow from "$c" comment 'k3s pods/services' >/dev/null
done
for i in cni0 flannel.1 flannel-v6.1; do
  ufw allow in on "$i" comment 'k3s pod interface' >/dev/null
done

echo "==> 3. Cluster-internal ports: block for everyone else"
ufw deny 2379:2380/tcp comment 'etcd - nodes only'             >/dev/null
ufw deny 10250/tcp     comment 'kubelet - nodes only'          >/dev/null
ufw deny 8472/udp      comment 'flannel vxlan - nodes only'    >/dev/null
ufw deny 7946          comment 'metallb memberlist - nodes only' >/dev/null

echo "==> 4. Main LAN: allow everything else"
ufw allow from "$LAN4"   comment 'main LAN'            >/dev/null
ufw allow from "$LAN6"   comment 'main LAN IPv6'       >/dev/null
ufw allow from fe80::/10 comment 'IPv6 link-local (HomeKit, mDNS)' >/dev/null

# Homebridge host only: the Kasa/Wyze devices live on the guest/IoT network and must be able to
# answer Homebridge (discovery replies and status updates are not always seen as "replies" by a
# firewall). Rule 3 above still keeps them away from etcd, kubelet, flannel and MetalLB.
if [ "$(hostname)" = "$HOMEBRIDGE_NODE" ]; then
  echo "==> 5. Homebridge host: allowing the IoT network $IOT4"
  ufw allow from "$IOT4" comment 'IoT network -> Homebridge' >/dev/null
fi

# Lima VM only: limactl reaches the VM over its private eth0. Without this, "limactl shell" breaks.
if ip link show lima0 >/dev/null 2>&1; then
  echo "==> Lima VM detected: allowing the private eth0 link to the Mac"
  ufw allow in on eth0 comment 'lima host link' >/dev/null
fi

echo "==> Enabling the firewall"
ufw --force enable >/dev/null

echo
ufw status verbose
cat <<'EOF'

------------------------------------------------------------------------------------------
Firewall is ON. It switches itself OFF in 10 minutes unless you cancel the safety timer.

Check now (docs/10-firewall.md, step 3), then keep it with:

    sudo systemctl stop ufw-safety.timer

To turn it off by hand at any time:

    sudo ufw disable
------------------------------------------------------------------------------------------
EOF
