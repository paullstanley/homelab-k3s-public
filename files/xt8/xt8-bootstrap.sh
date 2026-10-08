#!/bin/sh
# =============================================================================
# xt8-bootstrap.sh  -  put the Asus ZenWiFi XT8 (GNUton/Merlin 3004.388.x)
#                      to a known home-network spec in one run.
#
# Copy to the router and run it there (see docs/hardware/asus-zenwifi-xt8.md):
#     scp -O -P <SSH_PORT> xt8-bootstrap.sh admin@192.168.50.1:/jffs/
#     ssh -p <SSH_PORT> admin@192.168.50.1 'sh /jffs/xt8-bootstrap.sh install'
#
# Commands:
#   install          write the scripts, apply the nvram settings, restart
#                    dnsmasq + firewall, then run verify            (default)
#   scripts-only     write the scripts and restart services; touch no nvram
#   verify           check the live router against the spec; changes nothing
#   backup           save JFFS scripts/configs/addons and the per-device lists
#                    (DNS Director clients, DHCP reservations) to the USB drive
#   restore-lists F  load the per-device lists back from a backup file F
#   uninstall        remove everything this script installed (nvram untouched)
#
# Safe to run repeatedly. Every file it changes is first copied to
# /jffs/homenet-backups/.
#
# What it does NOT do (GUI steps, docs/hardware/asus-zenwifi-xt8.md): LAN IP, Wi-Fi/AiMesh,
# the guest network itself, Skynet/amtm installs, admin and Wi-Fi passwords.
# =============================================================================

# ----------------------------- THE SPEC --------------------------------------
# Change values here, re-run "install", and the router follows.
ULA_NET="fd00:1234:5678:50"          # LAN /64 (first four groups)
ROUTER6="${ULA_NET}::1"              # XT8's own ULA
PIHOLE6="${ULA_NET}::11"             # Pi-hole VIP (IPv6)
PIHOLE4="192.168.50.11"              # Pi-hole VIP (IPv4)
LAN_IP="192.168.50.1"                # expected router LAN address
DOMAIN="home.example.com"          # local domain
WAN_DNS="1.1.1.1"                    # the router's own upstream resolver, first server
WAN_DNS2="1.0.0.1"                   # second server ("" for none)
WAN_DOT="1"                          # 1 = the router is expected to use DNS-over-TLS to those servers.
                                     # DoT itself is switched on in the GUI (WAN > DNS Privacy Protocol);
                                     # this script only checks it. 0 = plain DNS on port 53.
DNSF_CUSTOM2="1.1.1.1"               # DNS Director "User Defined 2"
DNSF_CUSTOM3=""                      # DNS Director "User Defined 3": unused. If you set it, it must be an
                                     # address that really answers DNS, or every device on that rule has none.
GUEST_PREFIX="192.168.101."          # guest/IoT subnet, first three octets + dot
GUEST_NET="192.168.101.0/24"
USB_MOUNT="/tmp/mnt/gateway"         # where the router mounts its USB drive (ls /tmp/mnt); used by "backup"
GUEST_WL="wl0.1"                     # guest Wi-Fi interface carrying the isolation rules
HB_HOSTS="192.168.50.5,192.168.50.6,192.168.50.7"   # k3s nodes that may run Homebridge (today: .5 only)
# -----------------------------------------------------------------------------

JFFS="${JFFS:-/jffs}"                # overridable only for testing
S="$JFFS/scripts"
BK="$JFFS/homenet-backups"
TS="$(date +%Y%m%d-%H%M%S)"
BEGIN="# >>> homenet BEGIN (managed by xt8-bootstrap.sh - do not edit between markers)"
END="# <<< homenet END"

say()  { echo "[homenet] $*"; }
fail() { echo "[homenet] ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# File installers
# ---------------------------------------------------------------------------
backup_file() {
  [ -f "$1" ] || return 0
  mkdir -p "$BK"
  cp -p "$1" "$BK/$(basename "$1").$TS"
}

# install_block FILE BLOCKFILE LEGACY_REGEX
# Puts the contents of BLOCKFILE between the homenet markers at the end of FILE.
# - markers already there  -> the old block is replaced
# - pre-bootstrap hand-made layout (matches LEGACY_REGEX, no markers) -> the file
#   is rebuilt; lines owned by other add-ons (code followed by a "# Tag") are kept
install_block() {
  f="$1"; blk="$2"; legacy="$3"
  backup_file "$f"
  if [ ! -f "$f" ]; then
    echo '#!/bin/sh' > "$f"
  elif grep -q '^# >>> homenet BEGIN' "$f"; then
    sed -i '/^# >>> homenet BEGIN/,/^# <<< homenet END/d' "$f"
  elif [ -n "$legacy" ] && grep -q "$legacy" "$f"; then
    say "$(basename "$f"): hand-made layout found, rebuilding (original saved in $BK)"
    grep -v '^[[:space:]]*#' "$f" | grep -E '[[:space:]]# [A-Za-z][A-Za-z0-9_. -]*$' > "$f.keep"
    if [ -s "$f.keep" ]; then
      say "  kept these add-on lines:"; sed 's/^/    /' "$f.keep"
    fi
    { echo '#!/bin/sh'; cat "$f.keep"; } > "$f"
    rm -f "$f.keep"
  fi
  head -n 1 "$f" | grep -q '^#!' || sed -i '1i #!/bin/sh' "$f"
  [ -n "$(tail -c 1 "$f")" ] && echo >> "$f"
  { echo "$BEGIN"; cat "$blk"; echo "$END"; } >> "$f"
  chmod 755 "$f"
  say "installed block in $f"
}

write_conf() {
  backup_file "$S/homenet.conf"
  cat > "$S/homenet.conf" <<EOF
# /jffs/scripts/homenet.conf - written by xt8-bootstrap.sh on $TS
# Read by dnsmasq.postconf, firewall-start and kasa-guest-allow.sh.
ULA_NET="$ULA_NET"
ROUTER6="$ROUTER6"
PIHOLE6="$PIHOLE6"
DOMAIN="$DOMAIN"
GUEST_PREFIX="$GUEST_PREFIX"
GUEST_NET="$GUEST_NET"
GUEST_WL="$GUEST_WL"
HB_HOSTS="$HB_HOSTS"
EOF
  say "wrote $S/homenet.conf"
}

write_kasa() {
  backup_file "$S/kasa-guest-allow.sh"
  cat > "$S/kasa-guest-allow.sh" <<'EOF'
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
EOF
  chmod 755 "$S/kasa-guest-allow.sh"
  say "wrote $S/kasa-guest-allow.sh"
}

write_blocks() {
  T="/tmp/homenet.$$"; mkdir -p "$T"

  # ---- dnsmasq.postconf: local-only IPv6 (ULA) on br0 ----
  cat > "$T/dnsmasq" <<'EOF'
CONFIG="$1"
. /usr/sbin/helper.sh
. /jffs/scripts/homenet.conf
# Kernel: IPv6 on br0 (the firmware has it off while IPv6 = Disable in the UI),
# and never autoconfigure from anyone else's router advertisements.
echo 0 > /proc/sys/net/ipv6/conf/br0/disable_ipv6
echo 0 > /proc/sys/net/ipv6/conf/br0/accept_ra
echo 0 > /proc/sys/net/ipv6/conf/br0/autoconf
ip -6 addr show dev br0 | grep -q "${ROUTER6}/64" || ip -6 addr add "${ROUTER6}/64" dev br0
# dnsmasq: advertise the ULA /64 with router lifetime 0 (no IPv6 default route),
# SLAAC only, and the Pi-hole as the one and only IPv6 DNS server.
pc_append "enable-ra" "$CONFIG"
pc_append "ra-param=br0,0,0" "$CONFIG"
pc_append "dhcp-range=::,constructor:br0,ra-stateless,64,12h" "$CONFIG"
pc_append "dhcp-option=option6:dns-server,[${PIHOLE6}]" "$CONFIG"
pc_append "dhcp-option=option6:domain-search,${DOMAIN}" "$CONFIG"
EOF

  # ---- firewall-start: IPv6 filtering + Homebridge -> guest network ----
  cat > "$T/firewall" <<'EOF'
. /jffs/scripts/homenet.conf
# --- Local-only IPv6 filtering ---
# With IPv6 = Disable the firmware sets ip6tables INPUT/OUTPUT/FORWARD policy DROP.
# Allow only: ICMPv6 (RA/NDP/ping) and DHCPv6 in from the LAN; refuse DNS to the
# router over IPv6 (clients must use the Pi-hole); let the router talk on br0.
for R in "-p udp --dport 53 -j REJECT" "-p tcp --dport 53 -j REJECT" \
         "-p udp --dport 547 -j ACCEPT" "-p ipv6-icmp -j ACCEPT"; do
  ip6tables -D INPUT -i br0 $R 2>/dev/null
  ip6tables -I INPUT -i br0 $R
done
# Nothing from the LAN is ever routed out another interface over IPv6
ip6tables -D FORWARD -i br0 ! -o br0 -j DROP 2>/dev/null
ip6tables -I FORWARD -i br0 ! -o br0 -j DROP
# Without this the router cannot send RAs or answer pings (OUTPUT policy is DROP)
ip6tables -D OUTPUT -o br0 -j ACCEPT 2>/dev/null
ip6tables -I OUTPUT -o br0 -j ACCEPT
ip6tables -D INPUT -i lo -j ACCEPT 2>/dev/null; ip6tables -I INPUT -i lo -j ACCEPT
ip6tables -D OUTPUT -o lo -j ACCEPT 2>/dev/null; ip6tables -I OUTPUT -o lo -j ACCEPT
# --- Homebridge (k3s nodes) -> Kasa devices on the guest network, one-way ---
GBR=$(ip -4 -o addr show | awk -v p="$GUEST_PREFIX" 'index($4,p)==1 {print $2; exit}')
if [ -n "$GBR" ]; then
  iptables -D FORWARD -i br0 -s $HB_HOSTS -o $GBR -d $GUEST_NET -j ACCEPT 2>/dev/null
  iptables -I FORWARD -i br0 -s $HB_HOSTS -o $GBR -d $GUEST_NET -j ACCEPT
  iptables -D FORWARD -i $GBR -o br0 -d $HB_HOSTS -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
  iptables -I FORWARD -i $GBR -o br0 -d $HB_HOSTS -m state --state ESTABLISHED,RELATED -j ACCEPT
else
  logger -t firewall-start "guest bridge (${GUEST_PREFIX}x) not found; Homebridge->Kasa rules skipped"
fi
sh /jffs/scripts/kasa-guest-allow.sh
EOF

  # ---- service-event-end: a Wi-Fi restart rebuilds ebtables, so re-add our rules ----
  cat > "$T/event" <<'EOF'
case "$2" in wireless|net_and_phy|allnet) sleep 10; sh /jffs/scripts/kasa-guest-allow.sh ;; esac
EOF
}

do_scripts() {
  [ -d "$JFFS" ] || fail "$JFFS not found - is this the router?"
  mkdir -p "$S" "$BK"
  write_conf
  write_kasa
  write_blocks
  install_block "$S/dnsmasq.postconf"   "$T/dnsmasq"  'enable-ra'
  install_block "$S/firewall-start"     "$T/firewall" 'Local-only IPv6 filtering\|kasa-guest-allow'
  install_block "$S/service-event-end"  "$T/event"    'kasa-guest-allow'
  rm -rf "$T"
  fix_logrotate
}

# Scribe's nightly logrotate keeps its state in /opt/var/lib. Entware does not create
# that folder, and without it every run fails ("error creating stub state file") and
# /opt/var/log/messages grows without limit. (25 MB after three weeks in one case).
OPT="${OPT:-/opt}"                   # overridable only for testing
fix_logrotate() {
  [ -x "$OPT/sbin/logrotate" ] || return 0
  [ -d "$OPT/var/lib" ] && return 0
  mkdir -p "$OPT/var/lib" && say "created $OPT/var/lib (logrotate state folder for Scribe)"
}

# ---------------------------------------------------------------------------
# nvram settings (the GUI settings that are safe to script)
# ---------------------------------------------------------------------------
NV_CHANGED=0
nv() {   # nv KEY VALUE "what it is in the GUI"
  cur="$(nvram get "$1" 2>/dev/null)"
  if [ "$cur" = "$2" ]; then
    printf '  ok       %-22s = %s\n' "$1" "$2"
  else
    nvram set "$1=$2"; NV_CHANGED=1
    printf '  CHANGED  %-22s : "%s" -> "%s"   (%s)\n' "$1" "$cur" "$2" "$3"
  fi
}

do_nvram() {
  say "nvram settings:"
  nv jffs2_scripts      1              "Administration > System > Enable JFFS custom scripts"
  nv ipv6_service       disabled       "IPv6 > Connection type = Disable"
  nv ipv6_fw_rulelist   ""             "Firewall > IPv6 Firewall: no inbound rules"
  nv ipv6_dns1_x        "$PIHOLE6"     "IPv6 DNS, only used if native IPv6 is ever enabled"
  nv lan_domain         "$DOMAIN"      "LAN > DHCP Server > Domain Name"
  nv dhcp_dns1_x        "$PIHOLE4"     "LAN > DHCP Server > DNS Server 1"
  nv dhcp_dns2_x        ""             "LAN > DHCP Server > DNS Server 2 (blank)"
  nv dhcpd_dns_router   0              "LAN > DHCP Server > Advertise router's IP = No"
  nv dnsfilter_enable_x 1              "LAN > DNS Director > Enable"
  nv dnsfilter_mode     8              "LAN > DNS Director > Global = User Defined 1"
  nv dnsfilter_custom1  "$PIHOLE4"     "DNS Director > User Defined 1"
  nv dnsfilter_custom61 "$PIHOLE6"     "DNS Director > User Defined 1, IPv6"
  nv dnsfilter_custom2  "$DNSF_CUSTOM2" "DNS Director > User Defined 2"
  nv dnsfilter_custom3  "$DNSF_CUSTOM3" "DNS Director > User Defined 3"
  nv wan0_dnsenable_x   0              "WAN > Connect to DNS Server automatically = No"
  nv wan0_dns1_x        "$WAN_DNS"     "WAN > DNS Server 1"
  nv wan0_dns2_x        "$WAN_DNS2"    "WAN > DNS Server 2"
  nv wan_dnsenable_x    0              "WAN (same, generic key)"
  nv wan_dns1_x         "$WAN_DNS"     "WAN (same, generic key)"
  nv wan_dns2_x         "$WAN_DNS2"    "WAN (same, generic key)"
  if [ "$NV_CHANGED" = 1 ]; then
    nvram commit
    say "nvram committed. REBOOT the router once so every changed setting takes effect."
  fi
}

restart_services() {
  say "restarting dnsmasq and firewall..."
  service restart_dnsmasq  >/dev/null 2>&1
  sleep 5
  service restart_firewall >/dev/null 2>&1
  sleep 10
}

# ---------------------------------------------------------------------------
# verify
# ---------------------------------------------------------------------------
PASS=0; BAD=0
chk() {  # chk "description" command...
  d="$1"; shift
  if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  PASS  $d"
  else BAD=$((BAD+1)); echo "  FAIL  $d"; fi
}
nveq() { [ "$(nvram get "$1")" = "$2" ]; }

do_verify() {
  say "verify:"
  chk "router LAN address is $LAN_IP"                 nveq lan_ipaddr "$LAN_IP"
  chk "JFFS scripts enabled"                          nveq jffs2_scripts 1
  chk "IPv6 connection type is Disable in the UI"     nveq ipv6_service disabled
  chk "DHCP hands out the Pi-hole ($PIHOLE4) as DNS"   nveq dhcp_dns1_x "$PIHOLE4"
  chk "DHCP does not also advertise the router"       nveq dhcpd_dns_router 0
  chk "DNS Director enabled"                          nveq dnsfilter_enable_x 1
  chk "DNS Director global = User Defined 1"          nveq dnsfilter_mode 8
  chk "DNS Director User Defined 1 = $PIHOLE4"        nveq dnsfilter_custom1 "$PIHOLE4"
  chk "br0 has ${ROUTER6}/64"                         sh -c "ip -6 addr show dev br0 | grep -q '${ROUTER6}/64'"
  chk "no IPv6 default route"                         sh -c "! ip -6 route | grep -q '^default'"
  chk "dnsmasq: enable-ra"                            grep -q '^enable-ra' /etc/dnsmasq.conf
  chk "dnsmasq: ra-param=br0,0,0 (no default route)"  grep -q '^ra-param=br0,0,0' /etc/dnsmasq.conf
  chk "dnsmasq: IPv6 DNS = Pi-hole only"              grep -q "option6:dns-server,\[${PIHOLE6}\]" /etc/dnsmasq.conf
  if [ "$WAN_DOT" = 1 ]; then
    # DNS-over-TLS: dnsmasq forwards to stubby on the router, and stubby talks to the servers.
    chk "DNS-over-TLS is switched on (WAN page)"      nveq dnspriv_enable 1
    chk "DNS-over-TLS: stubby is running"             pidof stubby
    chk "DNS-over-TLS: $WAN_DNS is in the server list" sh -c "nvram get dnspriv_rulelist | grep -q -- '$WAN_DNS'"
    [ -z "$WAN_DNS2" ] || chk "DNS-over-TLS: $WAN_DNS2 is in the server list" sh -c "nvram get dnspriv_rulelist | grep -q -- '$WAN_DNS2'"
  else
    chk "dnsmasq: upstream is only $WAN_DNS $WAN_DNS2" sh -c "grep -q '^server=' /tmp/resolv.dnsmasq && ! grep '^server=' /tmp/resolv.dnsmasq | grep -v -x -e 'server=${WAN_DNS}' -e 'server=${WAN_DNS2:-none}' | grep -q ."
  fi
  chk "no dnscrypt-proxy running"                     sh -c "! ps w | grep -q '[d]nscrypt-proxy'"
  chk "ip6tables: LAN IPv6 never forwarded out"       sh -c "ip6tables -S FORWARD | grep -q -- '-i br0 ! -o br0 -j DROP'"
  chk "ip6tables: router may send on br0"             sh -c "ip6tables -S OUTPUT | grep -q -- '-o br0 -j ACCEPT'"
  chk "ip6tables: DNS to the router over IPv6 refused" sh -c "ip6tables -S INPUT | grep -q -- '-i br0 -p udp .*--dport 53 -j REJECT'"
  GBR=$(ip -4 -o addr show | awk -v p="$GUEST_PREFIX" 'index($4,p)==1 {print $2; exit}')
  chk "guest bridge for ${GUEST_PREFIX}x exists"      [ -n "$GBR" ]
  chk "iptables: Homebridge -> guest allowed"         sh -c "iptables -S FORWARD | grep -q -- '-d $GUEST_NET .*-j ACCEPT'"
  n=$(echo "$HB_HOSTS" | tr ',' '\n' | wc -l); want=$((n*2))
  chk "ebtables: $want guest->Homebridge ACCEPT rules" sh -c "[ \"\$(ebtables -t broute -L BROUTING | grep -c -- '-i $GUEST_WL --ip-dst 192.168.50.[0-9]* .*-j ACCEPT')\" = $want ]"
  chk "Pi-hole answers on IPv4"                       nslookup example.com "$PIHOLE4"
  if [ -x "$OPT/sbin/logrotate" ]; then
    chk "Scribe: logrotate state folder exists"       [ -d "$OPT/var/lib" ]
  fi
  # (Pi-hole over IPv6 is tested from a client, not from here: the router's own
  #  ip6tables INPUT policy drops the reply. See docs/operations/verification.md.)
  echo
  say "$PASS passed, $BAD failed."
  [ "$BAD" = 0 ] || say "Look up each FAIL in docs/hardware/asus-zenwifi-xt8.md, section on verify FAILs."
}

# ---------------------------------------------------------------------------
# backup / restore of per-device lists
# ---------------------------------------------------------------------------
LIST_KEYS="dnsfilter_rulelist dhcp_staticlist dhcp_hostnames custom_clientlist"

do_backup() {
  if [ -d "$USB_MOUNT" ]; then D="$USB_MOUNT/homenet-backup"; else D="/tmp/homenet-backup"; fi
  mkdir -p "$D"
  : > "$D/nvram-lists-$TS.txt"
  for k in $LIST_KEYS; do echo "$k=$(nvram get "$k")" >> "$D/nvram-lists-$TS.txt"; done
  ( cd / && tar -czf "$D/jffs-$TS.tar.gz" jffs/scripts jffs/configs jffs/addons 2>/dev/null ) \
    || ( cd / && tar -cf "$D/jffs-$TS.tar" jffs/scripts jffs/configs jffs/addons 2>/dev/null )
  cp -p "$0" "$D/xt8-bootstrap.sh" 2>/dev/null
  say "backup written to $D:"; ls -l "$D" | sed 's/^/    /'
  say "copy it off the router from your computer:"
  echo "    scp -O -P $(nvram get sshd_port) -r $(nvram get http_username)@$LAN_IP:$D ~/homelab-backups/"
  case "$D" in /tmp/homenet-backup) say "NOTE: no USB drive found; /tmp is RAM and is lost on reboot - copy it now." ;; esac
}

do_restore_lists() {
  [ -f "$1" ] || fail "file not found: $1"
  while IFS= read -r line; do
    k="${line%%=*}"
    case " $LIST_KEYS " in *" $k "*) nvram set "$line"; say "restored $k" ;; esac
  done < "$1"
  nvram commit
  say "done. Reboot (or: service restart_dnsmasq; service restart_firewall)."
}

do_uninstall() {
  for f in dnsmasq.postconf firewall-start service-event-end; do
    [ -f "$S/$f" ] || continue
    backup_file "$S/$f"
    sed -i '/^# >>> homenet BEGIN/,/^# <<< homenet END/d' "$S/$f"
  done
  backup_file "$S/kasa-guest-allow.sh"; backup_file "$S/homenet.conf"
  rm -f "$S/kasa-guest-allow.sh" "$S/homenet.conf"
  restart_services
  ip -6 addr del "${ROUTER6}/64" dev br0 2>/dev/null
  echo 1 > /proc/sys/net/ipv6/conf/br0/disable_ipv6 2>/dev/null
  say "removed. nvram settings were left as they are. Backups are in $BK."
}

# ---------------------------------------------------------------------------
case "${1:-install}" in
  install)
    cur="$(nvram get lan_ipaddr)"
    [ "$cur" = "$LAN_IP" ] || fail "router LAN IP is '$cur', spec says $LAN_IP. Set LAN > LAN IP in the GUI first (docs/hardware/asus-zenwifi-xt8.md)."
    do_scripts; do_nvram; restart_services; do_verify ;;
  scripts-only)  do_scripts; restart_services; do_verify ;;
  verify)        do_verify ;;
  backup)        do_backup ;;
  restore-lists) do_restore_lists "${2:-}" ;;
  uninstall)     do_uninstall ;;
  *) sed -n '2,30p' "$0"; exit 1 ;;
esac
