#!/usr/bin/env bash
#
# export-live-config.sh - copy the cluster's LIVE configuration into ./live-export/ so you can
# compare it with this repo and commit what changed.
#
# Run on server-1, from the root of this repo:
#     bash scripts/export-live-config.sh
#
# It only reads. It changes nothing on the cluster.
# Secrets are replaced with placeholders before anything is written:
#   - the k3s token in config.yaml
#   - any line whose key contains password, passwd, token, secret, apikey, api_key or psk
# Still read the output before you commit it.
#
set -euo pipefail

OUT="live-export/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

redact() {
  sed -E \
    -e 's/^([[:space:]]*token:[[:space:]]*).*/\1<K3S_TOKEN>/' \
    -e 's/^([[:space:]]*[A-Za-z0-9_.-]*(password|passwd|token|secret|api_?key|psk)[A-Za-z0-9_.-]*:[[:space:]]*).+/\1<REDACTED>/I'
}

echo "==> k3s config on this node"
sudo cat /etc/rancher/k3s/config.yaml | redact > "$OUT/k3s-config-$(hostname).yaml"

echo "==> nodes, labels, services"
sudo kubectl get nodes -o wide --show-labels          > "$OUT/nodes.txt"
sudo kubectl get svc -A -o wide                       > "$OUT/services.txt"
sudo kubectl get ingress -A                           > "$OUT/ingresses.txt"
sudo kubectl get pods -A -o wide                      > "$OUT/pods.txt"

echo "==> helm releases and their values"
sudo helm list -A --kubeconfig /etc/rancher/k3s/k3s.yaml > "$OUT/helm-releases.txt" 2>/dev/null \
  || helm list -A > "$OUT/helm-releases.txt"
while read -r name ns _; do
  [ "$name" = "NAME" ] && continue
  [ -z "$name" ] && continue
  ( sudo helm get values "$name" -n "$ns" -o yaml --kubeconfig /etc/rancher/k3s/k3s.yaml 2>/dev/null \
      || helm get values "$name" -n "$ns" -o yaml ) | redact > "$OUT/helm-values-$ns-$name.yaml"
done < "$OUT/helm-releases.txt"

echo "==> MetalLB, kube-vip, Traefik middlewares"
sudo kubectl get ipaddresspools,l2advertisements -n metallb-system -o yaml > "$OUT/metallb-live.yaml"
sudo kubectl -n kube-system get helmchart kube-vip -o yaml                 > "$OUT/kube-vip-helmchart.yaml" 2>/dev/null || true
sudo kubectl get middlewares.traefik.io -A -o yaml                         > "$OUT/traefik-middlewares.yaml" 2>/dev/null || true

echo "==> host network settings and firewall"
nmcli -t -f NAME,DEVICE con show --active             > "$OUT/nmcli-active.txt" 2>/dev/null || true
ip -br addr                                           > "$OUT/ip-addr.txt"
cat /etc/resolv.conf                                  > "$OUT/resolv.conf.txt"
sudo ufw status verbose                               > "$OUT/ufw-status.txt" 2>/dev/null || true
systemctl is-active cloudflared                       > "$OUT/cloudflared-state.txt" 2>/dev/null || true

echo
echo "Written to $OUT"
echo "live-export/ is in .gitignore on purpose. Compare, then copy what you want into the repo by hand:"
echo "    diff <(grep -v '^#' files/pihole/values.yaml) $OUT/helm-values-pihole-pihole.yaml | less"
