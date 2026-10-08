# References

Every external document cited by the guides, grouped by the page that cites it. Each link was opened and checked when its page was written, except where a line says otherwise. Sites change; if a link is dead, search for its title.

## Start here

### [From nothing to a full deployment](start-here/build-from-nothing.md)

- [gnuton/asuswrt-merlin.ng releases](https://github.com/gnuton/asuswrt-merlin.ng/releases): GNUton firmware files for the RT-AX95Q, with `.md5` checksums.
- [Asuswrt-Merlin wiki: Installation](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Installation): flashing from stock, when to reset, recovery mode.
- [Asuswrt-Merlin wiki: Reverting](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Reverting): going back to ASUS stock firmware.
- [Asuswrt-Merlin wiki: AiMesh](https://github.com/RMerl/asuswrt-merlin.ng/wiki/AiMesh): which firmware a node may run and how Merlin nodes are updated.
- [Asuswrt-Merlin wiki: Entware](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Entware): installing Entware with amtm and the disk format it needs.
- [Asuswrt-Merlin wiki: AMTM](https://github.com/RMerl/asuswrt-merlin.ng/wiki/AMTM): what amtm is and how to start it.
- [OpenWrt sysupgrade data for the Archer A7 v5](https://sysupgrade.openwrt.org/json/v1/releases/25.12.5/targets/ath79/generic/tplink_archer-a7-v5.json): the exact factory and sysupgrade image names for 25.12.5.
- [Raspberry Pi documentation: Install an operating system](https://raw.githubusercontent.com/raspberrypi/documentation/master/documentation/asciidoc/computers/getting-started/install.adoc): Imager steps, customisation and Network Install.
- [Raspberry Pi documentation: bootloader configuration](https://raw.githubusercontent.com/raspberrypi/documentation/master/documentation/asciidoc/computers/raspberry-pi/eeprom-bootloader.adoc): `BOOT_ORDER` and `PCIE_PROBE`.
- [Helm: Installing Helm](https://helm.sh/docs/intro/install/): the install script and package options.

## Hardware

### [Second XT8 as an AiMesh node](hardware/asus-aimesh-node.md)

- [Asuswrt-Merlin wiki: AiMesh](https://github.com/RMerl/asuswrt-merlin.ng/wiki/AiMesh): what Merlin supports on a node, and the firmware update limits for nodes.
- [Asuswrt-Merlin wiki: User scripts](https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts): `services-start`, and enabling `jffs2_scripts` on an AiMesh node over SSH.
- [Asuswrt-Merlin wiki: Scheduled tasks (cron jobs)](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Scheduled-tasks-(cron-jobs)): the `cru` command and why jobs must be re-created at boot.
- [ASUS: How to set up an AiMesh system (Web GUI)](https://www.asus.com/support/faq/1035087/): adding a node to the main router.
- [gnuton/asuswrt-merlin.ng](https://github.com/gnuton/asuswrt-merlin.ng): the firmware builds for the XT8.

### [ASUS ZenWiFi XT8 router on Asuswrt-Merlin](hardware/asus-zenwifi-xt8.md)

- [gnuton/asuswrt-merlin.ng](https://github.com/gnuton/asuswrt-merlin.ng): GNUton's builds of Asuswrt-Merlin for extra models, including the ZenWiFi XT8 (RT-AX95Q).
- [Asuswrt-Merlin wiki: User scripts](https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts): when `services-start`, `firewall-start` and `service-event-end` run, and how to enable JFFS scripts.
- [Asuswrt-Merlin wiki: Custom config files](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Custom-config-files): postconf scripts and the `pc_append` helper used by `dnsmasq.postconf`.
- [Asuswrt-Merlin wiki: DNS Director](https://github.com/RMerl/asuswrt-merlin.ng/wiki/DNS-Director): global redirection, per-device rules, user-defined servers.
- [Asuswrt-Merlin wiki: Entware](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Entware): the package manager the add-ons need, and its USB disk requirement.
- [amtm](https://github.com/decoderman/amtm): the terminal menu used to install the add-ons.
- [Skynet (IPSet_ASUS)](https://github.com/Adamm00/IPSet_ASUS): the firewall add-on and its USB requirement.
- [YazDHCP](https://github.com/AMTM-OSR/YazDHCP): the DHCP reservation add-on (the earlier `jackyaz/YazDHCP` repository is archived).
- [scribe](https://github.com/AMTM-OSR/scribe): the syslog-ng and logrotate installer.
- [dnsmasq manual page](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html): every dnsmasq option the postconf script appends.

### [An Apple-silicon Mac as a k3s server in a Lima VM](hardware/mac-lima-vm.md)

- [Lima documentation](https://lima-vm.io/docs/): what Lima is and how instances, templates and `limactl` work.
- [Lima: VMNet networks](https://lima-vm.io/docs/config/network/vmnet/): `socket_vmnet`, the root-owned install location, `limactl sudoers`, the `bridged` network in `networks.yaml`, `lima0` and `macAddress`.
- [socket_vmnet on GitHub](https://github.com/lima-vm/socket_vmnet): the helper itself, and why a Homebrew-installed binary is not trusted for running as root.
- [limactl autostart](https://lima-vm.io/docs/reference/limactl_autostart/): the `enable` and `disable` subcommands for starting an instance automatically.
- [limactl start-at-login](https://lima-vm.io/docs/reference/limactl_start-at-login/): the older command for the same job.
- [K3s server CLI reference](https://docs.k3s.io/cli/server): `--node-name`, `--flannel-iface`, `--node-ip` and the other options used in the config file.
- [K3s uninstalling](https://docs.k3s.io/installation/uninstall): the `k3s-uninstall.sh` and `k3s-agent-uninstall.sh` scripts.
- [MetalLB troubleshooting](https://metallb.io/troubleshooting/): mentions the `node.kubernetes.io/exclude-from-external-load-balancers` label.

### [Preparing a Raspberry Pi to be a k3s server](hardware/raspberry-pi.md)

- [Raspberry Pi computer hardware](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html): boot EEPROM, bootloader configuration and USB mass storage boot for every model.
- [Raspberry Pi getting started](https://www.raspberrypi.com/documentation/computers/getting-started.html): Raspberry Pi Imager, OS customisation (hostname, user, SSH) and the recommended power supply per model.
- [Raspberry Pi configuration](https://www.raspberrypi.com/documentation/computers/configuration.html): `raspi-config`, networking and static addresses with `nmcli`, and the kernel command line.
- [K3s requirements](https://docs.k3s.io/installation/requirements): minimum CPU and memory for servers and agents, and the advice to use an SSD because etcd is write intensive.
- [K3s high availability embedded etcd](https://docs.k3s.io/datastore/ha-embedded): notes that embedded etcd performs poorly on slow disks such as SD cards.
- [nm-settings-nmcli reference](https://networkmanager.dev/docs/api/latest/nm-settings-nmcli.html): every connection property that `nmcli con mod` can set.

### [TP-Link Archer A7 v5 on OpenWrt as a bridged access point](hardware/tp-link-archer-a7-openwrt.md)

- [OpenWrt Firmware Selector](https://firmware-selector.openwrt.org/): finds the right firmware image for the Archer A7 v5 and links to the device's page with flashing instructions.
- [openwrt/openwrt on GitHub](https://github.com/openwrt/openwrt): the OpenWrt source. The board file `target/linux/ath79/generic/base-files/etc/board.d/02_network` is where the A7 v5 switch port numbers (CPU 0, WAN 1, LAN 2 to 5) are defined.
- [openwrt/odhcpd on GitHub](https://github.com/openwrt/odhcpd): README for OpenWrt's DHCPv6 and router-advertisement daemon, including the `ra`, `dhcpv6` and `ndp` options this page disables.
- [RFC 4193: Unique Local IPv6 Unicast Addresses](https://www.rfc-editor.org/rfc/rfc4193): what a ULA prefix is, which explains both the static address and why OpenWrt's own `ula_prefix` is removed.
- [OpenWrt Table of Hardware: TP-Link Archer A7 v5](https://openwrt.org/toh/tp-link/archer_a7_v5): the device page, with flashing instructions. Not opened while writing this page: openwrt.org blocks automated checks, so confirm the link in a browser.
- [OpenWrt wiki: VLAN configuration with the switch (swconfig)](https://openwrt.org/docs/guide-user/network/vlan/switch): background for the Switch page. Not opened while writing, for the same reason.

### [TP-Link Archer AX21 on stock firmware as an access point](hardware/tp-link-archer-ax21.md)

- [Archer - Configure Access Point Mode](https://community.tp-link.com/us/home/kb/detail/390): TP-Link's step-by-step for switching an Archer router to Access Point mode, and what is unavailable in that mode.
- [Download for Archer AX21](https://www.tp-link.com/us/support/download/archer-ax21/): TP-Link's support page with the user guide and firmware for each hardware version.

## Network

### [IP address plan, DHCP reservations and roaming exclusions](network/address-plan.md)

- [dnsmasq manual page](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html): `--dhcp-range` and `--dhcp-host`, including the sentence that a reserved address need not be inside the range but must be in the same subnet as one, and the default lease time.
- [ASUS FAQ: How to manually assign LAN IP around the DHCP list](https://www.asus.com/support/faq/1000906/): the LAN > DHCP Server manual-assignment list, its entry limit, and ASUS's statement that the address must be inside the pool.
- [YazDHCP on GitHub](https://github.com/jackyaz/YazDHCP): the Asuswrt-Merlin add-on that moves reservations into files under `/jffs/addons/YazDHCP.d/` to raise the limit.
- [Asuswrt-Merlin wiki: Custom config files](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Custom-config-files): `dnsmasq.conf.add` and `dnsmasq.postconf`, for adding dnsmasq lines the web interface does not offer.
- [ASUS FAQ: What is Roaming Block list? How does it work?](https://www.asus.com/support/faq/1039647/): what the list exempts (AiMesh-triggered roaming) and how to add devices.
- [ASUS FAQ: How to bind my device to one specific AiMesh router or AiMesh node](https://www.asus.com/support/FAQ/1046957): binding in AiMesh > Topology and in the app, its firmware requirement and its limits.
- [ASUS FAQ: How to enable the Roaming Assistant](https://www.asus.com/support/faq/1036730/): where the threshold is set and the -70 dBm default.
- [Apple: Use private Wi-Fi addresses on Apple devices](https://support.apple.com/en-us/102509): Off, Fixed and Rotating, per network, and how to change it.
- [Android: MAC randomization behavior](https://source.android.com/docs/core/connect/wifi-mac-randomization-behavior): persistent and non-persistent randomised addresses and the per-network setting.

### [DNS design](network/dns-design.md)

- [Asuswrt-Merlin wiki: DNS Director](https://github.com/RMerl/asuswrt-merlin.ng/wiki/DNS-Director): global redirection, "No Redirection" client rules and the three user-defined servers.
- [Pi-hole documentation](https://docs.pi-hole.net/): what Pi-hole is and how it resolves and blocks.
- [Pi-hole documentation: ASUS router](https://docs.pi-hole.net/routers/asus/): pointing an ASUS router's clients at Pi-hole.
- [Cloudflare: DNS over TLS](https://developers.cloudflare.com/1.1.1.1/dns-over-tls/): Cloudflare's addresses and port 853 for DoT.
- [Stubby](https://dnsprivacy.org/dns_privacy_daemon_-_stubby/): the DNS-over-TLS stub resolver the router runs when DoT is on.
- [Quad9: service addresses and features](https://www.quad9.net/service/service-addresses-and-features/): what `9.9.9.9` provides.
- [DNS leak test](https://www.dnsleaktest.com/): the public test used in the checks.
- [k3s: networking services](https://docs.k3s.io/networking/networking-services): CoreDNS as shipped with k3s.

### [Isolated IoT network](network/isolated-iot-network.md)

- [ASUS FAQ: How to configure the guest network to deny wireless devices access to the internal network](https://www.asus.com/support/faq/1009857): what the Access Intranet setting does, on both older and newer ASUS firmware.
- [ASUS FAQ: How to set up Guest Network on ASUS Router](https://www.asus.com/us/support/FAQ/1042732): creating a guest network in the web UI and the app, and its documented limits.
- [Asuswrt-Merlin wiki: User scripts](https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts): when `firewall-start` and `service-event-end` run and what arguments they receive.
- [Asuswrt-Merlin wiki: Iptables tips](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Iptables-tips): examples of adding `iptables` rules from the firewall scripts.
- [ebtables-legacy(8) manual page](https://manpages.debian.org/bookworm/ebtables/ebtables-legacy.8.en.html): the `broute` table and `BROUTING` chain, and the special meaning of DROP and ACCEPT there.
- [gnuton/asuswrt-merlin.ng](https://github.com/gnuton/asuswrt-merlin.ng): the Asuswrt-Merlin fork for the ZenWiFi XT8 that this page was done on.
- [openwrt/openwrt on GitHub](https://github.com/openwrt/openwrt): the OpenWrt source; the board file `target/linux/ath79/generic/base-files/etc/board.d/02_network` defines the Archer A7 v5 switch port numbers used for `UPLINK_PORT`.
- [OpenWrt Firmware Selector](https://firmware-selector.openwrt.org/): finds the firmware and device page for the access point.

### [Local-only IPv6 when the ISP provides none](network/local-only-ipv6.md)

- [RFC 4193: Unique Local IPv6 Unicast Addresses](https://www.rfc-editor.org/rfc/rfc4193): defines ULA prefixes and the requirement to generate the 40-bit global ID randomly.
- [RFC 4861: Neighbor Discovery for IP version 6](https://www.rfc-editor.org/rfc/rfc4861): router advertisements; section 4.2 states that a router lifetime of zero means "not a default router".
- [RFC 4862: IPv6 Stateless Address Autoconfiguration](https://www.rfc-editor.org/rfc/rfc4862): how clients build their own addresses from an advertised prefix (SLAAC).
- [dnsmasq manual page](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html): `--enable-ra`, `--ra-param`, the `ra-stateless` and `constructor:` forms of `--dhcp-range`, `--dhcp-option` with `option6:`, and `--quiet-ra`.
- [Asuswrt-Merlin wiki: Custom config files](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Custom-config-files): postconf scripts such as `dnsmasq.postconf`, and the `pc_append` helper from `helper.sh`.
- [Asuswrt-Merlin wiki: User scripts](https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts): how to enable JFFS scripts and when `firewall-start` and the other hooks run.
- [gnuton/asuswrt-merlin.ng](https://github.com/gnuton/asuswrt-merlin.ng): the Asuswrt-Merlin fork that supports the ZenWiFi XT8, the firmware this page was done on.
- [openwrt/odhcpd](https://github.com/openwrt/odhcpd): the `ra`, `dhcpv6` and `ndp` options disabled on the OpenWrt access point.

### [Router logging](network/router-logging.md)

- [scribe](https://github.com/AMTM-OSR/scribe): the syslog-ng and logrotate installer for Asuswrt-Merlin, and its Entware requirement.
- [logrotate(8) manual page](https://man7.org/linux/man-pages/man8/logrotate.8.html): the state file and the `--state` option that explain the "stub state file" error.
- [logrotate source repository](https://github.com/logrotate/logrotate): the tool itself.
- [syslog-ng source repository](https://github.com/syslog-ng/syslog-ng): the logger Scribe installs.
- [dnsmasq manual page](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html): `quiet-ra` ("suppress logging of the routine operation") and the router advertisement options.
- [ip-neighbour(8) manual page](https://man7.org/linux/man-pages/man8/ip-neighbour.8.html): the `ip neigh` command used in place of the blank IPv6 log page.
- [Asuswrt-Merlin wiki: Entware](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Entware): where `/opt` comes from and why it needs a USB disk.
- [Skynet (IPSet_ASUS)](https://github.com/Adamm00/IPSet_ASUS): the source of the `[BLOCKED - INBOUND]` lines.

## Kubernetes

### [CoreDNS on k3s: replicas, dual-stack and host-network pods](kubernetes/coredns.md)

- [Kubernetes: DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/): pod DNS policies, `dnsConfig`, search domains and `ndots`.
- [Kubernetes: Debugging DNS resolution](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/): the upstream checklist for DNS problems in a cluster.
- [Kubernetes: IPv4/IPv6 dual-stack](https://kubernetes.io/docs/concepts/services-networking/dual-stack/): how pods and Services get an address per family.
- [K3s: networking services](https://docs.k3s.io/networking/networking-services): CoreDNS is deployed automatically by k3s on server start.
- [K3s: basic network options](https://docs.k3s.io/networking/basic-network-options): dual-stack service ranges and the statement that dual-stack is meant to be set at cluster creation.
- [CoreDNS: forward plugin](https://coredns.io/plugins/forward/): forwarding outside names to the resolvers in `/etc/resolv.conf`.

### [Highly available k3s on embedded etcd](kubernetes/k3s-ha-cluster.md)

- [K3s: High availability embedded etcd](https://docs.k3s.io/datastore/ha-embedded): `cluster-init`, joining servers, quorum, and converting an existing SQLite server by restarting it with `--cluster-init`.
- [K3s: Configuration options](https://docs.k3s.io/installation/configuration): the `/etc/rancher/k3s/config.yaml` file and how it relates to command-line flags.
- [K3s: Basic network options](https://docs.k3s.io/networking/basic-network-options): dual-stack `cluster-cidr` and `service-cidr`, `flannel-ipv6-masq`, and the statement that dual-stack must be configured when the cluster is created.
- [K3s: server CLI reference](https://docs.k3s.io/cli/server): every server option, including `--cluster-reset`, `--tls-san`, `--node-name`, `--flannel-iface` and `--disable`.
- [K3s: token](https://docs.k3s.io/cli/token): token types and `k3s token rotate`.
- [K3s: etcd-snapshot](https://docs.k3s.io/cli/etcd-snapshot): taking, listing and restoring snapshots.
- [K3s: Backup and restore](https://docs.k3s.io/datastore/backup-restore): what to back up, including the token file.
- [K3s: Manual upgrades](https://docs.k3s.io/upgrades/manual): upgrading with the install script, servers first and one at a time.
- [K3s: Uninstalling](https://docs.k3s.io/installation/uninstall): the uninstall scripts.
- [etcd FAQ](https://etcd.io/docs/v3.5/faq/): the failure-tolerance table and why an even number of members adds nothing.

### [Load balancers: MetalLB, kube-vip and Traefik's address](kubernetes/load-balancers.md)

- [MetalLB: installation](https://metallb.io/installation/): installing by manifest, including the native-mode manifest used here.
- [MetalLB: configuration](https://metallb.io/configuration/): `IPAddressPool` and `L2Advertisement`.
- [MetalLB: advanced AddressPool configuration](https://metallb.io/configuration/_advanced_ipaddresspool_configuration/): `autoAssign: false` and other pool controls.
- [MetalLB: usage](https://metallb.io/usage/): requesting a specific address with `metallb.io/loadBalancerIPs`, sharing an address, dual-stack Services.
- [MetalLB in layer 2 mode](https://metallb.io/concepts/layer2/): how one node announces an address, how failover works, and its limits.
- [MetalLB: issues with K3s](https://metallb.io/configuration/k3s/): why Klipper (ServiceLB) must be disabled.
- [K3s: networking services](https://docs.k3s.io/networking/networking-services): how ServiceLB works, `--disable=servicelb`, and how the bundled Traefik is managed.
- [K3s: Helm](https://docs.k3s.io/add-ons/helm): the `HelmChart` and `HelmChartConfig` resources and `valuesContent`.
- [kube-vip: K3s](https://kube-vip.io/docs/usage/k3s/): a control-plane address on k3s and the matching `tls-san` requirement.
- [kube-vip Helm charts](https://github.com/kube-vip/helm-charts): the chart installed by the `HelmChart` object.
- [Traefik: RedirectScheme middleware](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/redirectscheme/): the `scheme` and `permanent` options.

### [A host firewall on k3s nodes that does not break k3s](kubernetes/node-firewall.md)

- [ufw manual page](https://manpages.ubuntu.com/manpages/noble/en/man8/ufw.8.html): `default … routed`, `allow from`, `deny`, `comment`, `reset` and `disable`.
- [Ubuntu community help: UFW](https://help.ubuntu.com/community/UFW): basics, and how to read the `UFW BLOCK` log lines.
- [K3s requirements](https://docs.k3s.io/installation/requirements): the inbound port table for k3s nodes (6443, 2379-2380, 8472, 10250) and its notes on running with `ufw` or `firewalld`.
- [K3s basic network options](https://docs.k3s.io/networking/basic-network-options): the pod and service ranges the firewall has to allow.
- [MetalLB in layer 2 mode](https://metallb.io/concepts/layer2/): the speakers use memberlist to detect a failed node, which is what a blocked port 7946 would disturb.
- [nm-settings-nmcli reference](https://networkmanager.dev/docs/api/latest/nm-settings-nmcli.html): the NetworkManager connection properties, including the IPv6 address-generation settings used for the IPv6 gap.

## Apps

### [Client devices: VPN laptops, per-device DNS and browsers](apps/client-devices.md)

- [hosts(5) Linux manual page](https://man7.org/linux/man-pages/man5/hosts.5.html): the hosts file format (one address, then names; no wildcards). macOS uses the same format.
- [Asuswrt-Merlin wiki: DNS Director](https://github.com/RMerl/asuswrt-merlin.ng/wiki/DNS-Director): forcing devices to specific DNS servers, globally and per device.
- [K3s: Cluster access](https://docs.k3s.io/cluster-access): copying `k3s.yaml` to another machine and changing the `server` address.
- [Traefik: Kubernetes Ingress routing configuration](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/ingress/): the sticky-cookie annotation behind the `pihole_pod` cookie.

### [Cameras in HomeKit with camera-ffmpeg: Axis and Wyze](apps/homebridge-cameras.md)

- [homebridge-plugins/homebridge-camera-ffmpeg](https://github.com/homebridge-plugins/homebridge-camera-ffmpeg): the plugin; every `videoConfig` option, and the `unbridge` default and warning.
- [FFmpeg protocols documentation](https://ffmpeg.org/ffmpeg-protocols.html): the RTSP options, including `rtsp_transport`.
- [homebridge/docker-homebridge](https://github.com/homebridge/docker-homebridge): the container image and its `startup.sh` hook, used here to install ffmpeg.
- [Camera configurations collected for homebridge-camera-ffmpeg](https://sunoo.github.io/homebridge-camera-ffmpeg/configs/): community-tested configs by camera make, from the plugin's earlier maintainer.

### [Kasa devices on an isolated IoT network, driven from Homebridge on the LAN](apps/homebridge-kasa-across-networks.md)

- [ZeliardM/homebridge-kasa-python](https://github.com/ZeliardM/homebridge-kasa-python): the plugin; `manualDevices`, `enableCredentials` and `waitTimeUpdate`.
- [python-kasa/python-kasa](https://github.com/python-kasa/python-kasa): the library underneath; discovery by broadcast to `255.255.255.255` and which devices need credentials.
- [jfarmer08/homebridge-wyze-smart-home](https://github.com/jfarmer08/homebridge-wyze-smart-home): the cloud-driven Wyze plugin and its API key fields.
- [homebridge/docker-homebridge](https://github.com/homebridge/docker-homebridge): why the Homebridge container uses the host network, which decides the source address your router rules must allow.

### [Homebridge on k3s](apps/homebridge.md)

- [homebridge/docker-homebridge](https://github.com/homebridge/docker-homebridge): the container image; host network requirement and the `startup.sh` custom startup script.
- [Homebridge wiki: mDNS options](https://github.com/homebridge/homebridge/wiki/mDNS-Options): the Bonjour-HAP, Ciao, Avahi and systemd-resolved advertisers.
- [k8s-at-home/charts](https://github.com/k8s-at-home/charts): the archived chart repository this install uses.
- [Kubernetes: DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/): pod DNS policies, `dnsPolicy: None` and `dnsConfig`.
- [K3s: Volumes and storage](https://docs.k3s.io/add-ons/storage): the local-path provisioner and where its data lives on a node.
- [Traefik: Kubernetes Ingress routing configuration](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/ingress/): the `router.middlewares` annotation used for the redirect.
- [homebridge-plugins/homebridge-resideo](https://github.com/homebridge-plugins/homebridge-resideo): the Resideo plugin; needs a free Resideo developer account.
- [jfarmer08/homebridge-wyze-smart-home](https://github.com/jfarmer08/homebridge-wyze-smart-home): the Wyze plugin and its required API key and key ID fields.

### [Pi-hole on k3s: three replicas behind one address](apps/pihole.md)

- [MoJo2600/pihole-kubernetes](https://github.com/MoJo2600/pihole-kubernetes): the Helm chart used here, with its values reference.
- [Pi-hole Docker configuration](https://docs.pi-hole.net/docker/configuration/): how `FTLCONF_` environment variables map to Pi-hole v6 settings.
- [MetalLB usage](https://metallb.io/usage/): requesting specific addresses, IP address sharing between Services, and what `externalTrafficPolicy` does in layer 2 mode.
- [Kubernetes: Pod topology spread constraints](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/): `maxSkew`, `whenUnsatisfiable` and `matchLabelKeys`.
- [Traefik: Kubernetes Ingress routing configuration](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/ingress/): the sticky-cookie Service annotations and the `router.middlewares` Ingress annotation.
- [Cloudflare changelog: cloudflared proxy-dns command will be removed starting February 2, 2026](https://developers.cloudflare.com/changelog/post/2025-11-11-cloudflared-proxy-dns/): why the sidecar image is pinned.
- [Pi-hole forum: Pi-hole not working after updating cloudflared](https://discourse.pi-hole.net/t/pi-hole-not-working-after-updating-cloudflared/85149): the same removal seen on a plain install, with dnscrypt-proxy and Unbound as replacements.

### [Seerr behind a Cloudflare tunnel through Traefik](apps/seerr-cloudflare-tunnel.md)

- [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/): overview of tunnels and the `cloudflared` connector.
- [Cloudflare Tunnel: routing to a tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/routing-to-tunnel/): publishing an application under a public host name and the DNS record behind it.
- [Cloudflare: run cloudflared as a service on Linux](https://developers.cloudflare.com/tunnel/advanced/local-management/as-a-service/linux/): `cloudflared service install` and managing the systemd service.
- [Cloudflare Tunnel: Kubernetes deployment guide](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/deployment-guides/kubernetes/): running the connector inside a cluster.
- [Seerr documentation](https://docs.seerr.dev/): installation, setup wizard and settings.
- [seerr-team/seerr](https://github.com/seerr-team/seerr): source, container image and the project's own chart directory.
- [Traefik: Kubernetes Ingress routing configuration](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/ingress/): how Traefik turns an Ingress into a route.
- [K3s: Volumes and storage](https://docs.k3s.io/add-ons/storage): the local-path provisioner and the folder backed up above.

## Operations

### [Backups and secrets](operations/backups-and-secrets.md)

- [k3s: etcd-snapshot](https://docs.k3s.io/cli/etcd-snapshot): on-demand and scheduled snapshots, defaults, and why a restore needs the original token.
- [k3s: Backup and restore](https://docs.k3s.io/datastore/backup-restore): what to back up for each k3s datastore type.
- [k3s: token](https://docs.k3s.io/cli/token): what the server token protects and how `k3s token rotate` works.
- [k3s: certificate](https://docs.k3s.io/cli/certificate): checking and rotating k3s certificates.
- [Homebridge wiki: Backup and Restore](https://github.com/homebridge/homebridge/wiki/Backup-and-Restore): the UI backup archive and manual alternatives.
- [Git: gitignore](https://git-scm.com/docs/gitignore): pattern syntax, and why ignoring does not affect files already tracked.
- [GitHub Docs: Removing sensitive data from a repository](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository): rewriting history, and why rotating the secret comes first.
- [Asuswrt-Merlin wiki: User scripts](https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts): what lives in `/jffs/scripts`, which the JFFS backup protects.

### [Maintenance](operations/maintenance.md)

- [k3s: Manual upgrades](https://docs.k3s.io/upgrades/manual): upgrading with the install script, servers first and one at a time.
- [k3s: etcd-snapshot](https://docs.k3s.io/cli/etcd-snapshot): the snapshot to take before an upgrade, and the default schedule.
- [k3s: token](https://docs.k3s.io/cli/token): `k3s token rotate`.
- [k3s: certificate](https://docs.k3s.io/cli/certificate): checking expiry and `k3s certificate rotate`.
- [k3s: Networking services](https://docs.k3s.io/networking/networking-services): the bundled CoreDNS, Traefik and ServiceLB that an upgrade redeploys.
- [Asuswrt-Merlin wiki: Scheduled tasks (cron jobs)](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Scheduled-tasks-(cron-jobs)): the `cru` command and why jobs must be re-added at boot.
- [Asuswrt-Merlin wiki: User scripts](https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts): `services-start` and the other `/jffs/scripts` hooks.

### [Reviewing a home network like this one](operations/security-review.md)

- [Asuswrt-Merlin changelog](https://www.asuswrt-merlin.net/changelog): UPnP off by default from 388.10, AiCloud removed in 388.11, WireGuard and hardware NAT, OpenVPN changes in 388.12.
- [Asuswrt-Merlin wiki: DNS Director](https://github.com/RMerl/asuswrt-merlin.ng/wiki/DNS-Director): what the per-device DNS rules do, for reviewing them.
- [gnuton/asuswrt-merlin.ng releases](https://github.com/gnuton/asuswrt-merlin.ng/releases): the current firmware to compare against.
- [OpenWrt dropbear default configuration](https://raw.githubusercontent.com/openwrt/openwrt/main/package/network/services/dropbear/files/dropbear.config): the `PasswordAuth` and `RootPasswordAuth` options and their defaults.
- [OpenWrt uhttpd default configuration](https://raw.githubusercontent.com/openwrt/openwrt/main/package/network/services/uhttpd/files/uhttpd.config): the `redirect_https` option and the HTTP and HTTPS listeners.
- [OpenWrt 25.12.5 service release](https://forum.openwrt.org/t/openwrt-25-12-5-service-release/251479): the security fixes, and known issues such as 802.11r with WPA3.
- [Cloudflare: cloudflared proxy-dns deprecation](https://developers.cloudflare.com/changelog/post/2025-11-11-cloudflared-proxy-dns/): why the DNS-over-HTTPS sidecar needs replacing.
- [crazy-max/docker-cloudflared](https://github.com/crazy-max/docker-cloudflared): the archived sidecar image.
- [k8s-at-home/charts](https://github.com/k8s-at-home/charts): the archived chart repository the Homebridge chart comes from.
- [K3s: Manual upgrades](https://docs.k3s.io/upgrades/manual): the one-minor-at-a-time rule behind the version drift item.

### [Software and firmware: where to get it and how to update it](operations/software-and-firmware.md)

- [gnuton/asuswrt-merlin.ng releases](https://github.com/gnuton/asuswrt-merlin.ng/releases): GNUton firmware for the RT-AX95Q and its changelogs.
- [Asuswrt-Merlin changelog](https://www.asuswrt-merlin.net/changelog): the upstream changes GNUton builds inherit.
- [Asuswrt-Merlin wiki: AiMesh](https://github.com/RMerl/asuswrt-merlin.ng/wiki/AiMesh): firmware rules and manual updates for nodes.
- [amtm](https://diversion.ch/amtm.html): the current amtm version and its update features.
- [AMTM-OSR on GitHub](https://github.com/AMTM-OSR): the new home of scribe, YazDHCP, uiScribe and scMerlin.
- [OpenWrt 25.12.5 service release](https://forum.openwrt.org/t/openwrt-25-12-5-service-release/251479): what the release fixes and why to upgrade.
- [OpenWrt 25.12 released with apk replacing opkg](https://linuxiac.com/openwrt-25-12-released-with-apk-package-manager-replacing-opkg/): the package manager change and upgrade paths.
- [TP-Link: How to update the firmware](https://www.tp-link.com/us/support/faq/2796/): manual firmware upgrade on TP-Link routers.
- [Raspberry Pi documentation: updating the bootloader](https://raw.githubusercontent.com/raspberrypi/documentation/master/documentation/asciidoc/computers/raspberry-pi/boot-eeprom.adoc): `rpi-eeprom-update` and release streams.
- [K3s: Manual upgrades](https://docs.k3s.io/upgrades/manual): re-running the installer, version pinning and the no-skipping rule.
- [K3s: Automated upgrades](https://docs.k3s.io/upgrades/automated): the system-upgrade-controller and `Plan` objects.
- [K3s: etcd-snapshot](https://docs.k3s.io/cli/etcd-snapshot): snapshot defaults and restore.
- [MetalLB release notes](https://metallb.io/release-notes/): the 0.16 FRR-K8s default and other breaking changes.
- [Cloudflare: cloudflared proxy-dns deprecation](https://developers.cloudflare.com/changelog/post/2025-11-11-cloudflared-proxy-dns/): the removal date and the support window.
- [Pi-hole: upgrading the Docker image](https://docs.pi-hole.net/docker/upgrading/): why `pihole -up` is disabled in containers.
- [Lima: VMNet networks](https://lima-vm.io/docs/config/network/vmnet/): installing socket_vmnet securely and the sudoers file.

### [Troubleshooting](operations/troubleshooting.md)

- [Kubernetes: Debug Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/): reading `describe pod` output and pod states such as Pending and CrashLoopBackOff.
- [Kubernetes: Troubleshooting clusters](https://kubernetes.io/docs/tasks/debug/debug-cluster/): node and control-plane level debugging.
- [Kubernetes: Debugging DNS resolution](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/): the upstream method for CoreDNS and pod `resolv.conf` problems.
- [MetalLB: Troubleshooting](https://metallb.io/troubleshooting/): why an address is not assigned or not announced, and how to read the speaker logs.
- [k3s: Networking services](https://docs.k3s.io/networking/networking-services): the bundled CoreDNS, Traefik and ServiceLB, and how ServiceLB is disabled.
- [k3s: Backup and restore](https://docs.k3s.io/datastore/backup-restore): read before attempting a cluster reset after lost quorum.
- [ufw manual page](https://manpages.ubuntu.com/manpages/noble/en/man8/ufw.8.html): the `ufw status`, `allow from`, `disable` and `enable` commands used in the firewall section.
- [Asuswrt-Merlin wiki: User scripts](https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts): the `service-event-end`, `firewall-start` and `dnsmasq.postconf` hooks referred to above.
- [Pi-hole documentation](https://docs.pi-hole.net/): the query log, allow lists and FTL database used in the DNS sections.

### [Verification](operations/verification.md)

- [k3s: Networking services](https://docs.k3s.io/networking/networking-services): what CoreDNS, Traefik and ServiceLB do in k3s and how ServiceLB is disabled, which the load balancer checks rely on.
- [k3s: etcd-snapshot](https://docs.k3s.io/cli/etcd-snapshot): take a snapshot before the failover tests.
- [MetalLB: Troubleshooting](https://metallb.io/troubleshooting/): how to find out why an address is not assigned or announced.
- [Kubernetes: Debugging DNS resolution](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/): the upstream method behind the CoreDNS checks.
- [DNS leak test: what is a DNS leak](https://www.dnsleaktest.com/what-is-a-dns-leak.html): what test 10 measures.
- [Pi-hole documentation](https://docs.pi-hole.net/): the query log and blocking behaviour used in tests 6 and 7.
