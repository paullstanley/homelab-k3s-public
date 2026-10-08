# Router logging

Persistent, rotated logs on an Asuswrt-Merlin router, and a method for reading them. You end up with a log that survives reboots, does not grow without limit, and that you can sweep for real problems in a few minutes without drowning in noise.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | ASUS ZenWiFi XT8 (RT-AX95Q), GNUton Asuswrt-Merlin.ng 3004.388.10_2, Scribe (syslog-ng and logrotate from Entware) on a USB drive, with an AiMesh node and wired access points |
| **Also works for** | Other Asuswrt-Merlin routers with Scribe. Not tested by the author. The review method works on any syslog-style file |
| **Time** | 10 minutes to fix rotation; 15 minutes for a log review |
| **You need first** | [ASUS ZenWiFi XT8 router](../hardware/asus-zenwifi-xt8.md) with Scribe installed through amtm, and SSH access |

## How it works

Without add-ons the router keeps its log in memory, at a limited size, and loses it at every reboot. Scribe is an add-on that installs two Entware packages on the USB drive:

- **syslog-ng** receives every log message and writes it to files.
- **logrotate** runs nightly, renames the current file to `messages-<date>` and starts a new one.

| Path | What |
| --- | --- |
| `/opt/var/log/messages` | The main log. `/opt` is the Entware folder on the USB drive |
| `/opt/var/log/messages-<date>` | Rotated logs |
| `/opt/var/log/logrotate.log` | What logrotate did, or why it failed |
| `/opt/etc/logrotate.conf` | logrotate's configuration |
| `/opt/var/lib/logrotate.status` | logrotate's state file: when each log was last rotated |

logrotate must be able to write its state file. **Nothing creates the folder `/opt/var/lib`.** If it is missing, every nightly run fails before rotating anything, and `messages` grows until the drive is full.

## Before you start

- You need SSH on the router: `ssh -p <SSH_PORT> admin@192.168.50.1`.
- A log review reads tens of megabytes. Run it on the router with the commands below, or copy the file to your computer first: `scp -O -P 22 admin@192.168.50.1:/opt/var/log/messages ./router-messages`.

## Steps

### Step 1. Check whether rotation is working

**Run on: the router**

```sh
ls -la /opt/var/log/messages*
tail -5 /opt/var/log/logrotate.log
ls -ld /opt/var/lib
```

| You see | Meaning |
| --- | --- |
| `messages` of a few hundred kB and dated `messages-<date>` files | Rotation works. Skip to Step 3 |
| `messages` of many MB and no dated files | Rotation is failing |
| `error creating stub state file /opt/var/lib/logrotate.status: No such file or directory`, repeated once a night (at 00:05 on this setup) | The state folder is missing. Step 2 |
| `ls: /opt/var/lib: No such file or directory` | The same |

A `messages` file of 25 MB was the result of this failure going unnoticed for about three weeks.

### Step 2. Fix the logrotate state folder

**Run on: the router**

```sh
mkdir -p /opt/var/lib
/opt/sbin/logrotate /opt/etc/logrotate.conf
```

The first line creates the folder. The second runs a rotation now. The bootstrap script in [ASUS ZenWiFi XT8 router](../hardware/asus-zenwifi-xt8.md) also creates the folder on every `install` or `scripts-only` run, and its `verify` checks for it.

Now prove that logging resumed into the new file:

**Run on: the router**

```sh
logger "rotation test"; sleep 2; ls -la /opt/var/log/messages*
```

Expected: `messages` is small and its size is above zero, and the old log sits beside it as `messages-<date>`.

> **Pitfall:** right after a rotation the new `messages` file can be 0 bytes simply because nothing has been logged yet. That is not a fault. The `logger` line above writes one message so you can tell the difference.

Only if the **old** file grew instead of the new one, syslog-ng is still holding the old file open. Tell it to reopen its files:

**Run on: the router**

```sh
killall -HUP syslog-ng
logger "rotation test 2"; sleep 2; ls -la /opt/var/log/messages*
```

The rotated file stays on the USB drive. Delete it when you have reviewed it, or let logrotate age it out.

### Step 3. Review a log

Work from coarse to fine: who is talking, when, which alarming words appear, and only then which exact messages. Reading the file top to bottom does not work; a few programs produce most of the lines.

The commands assume the usual line shape, `Mon DD HH:MM:SS hostname program[pid]: message`, so the program is field 5. If your lines differ, adjust the field numbers. Set the file once:

**Run on: the router** (or your computer, with the path of your copy)

```sh
LOG=/opt/var/log/messages
wc -l "$LOG"; head -1 "$LOG"; tail -1 "$LOG"
```

That prints the number of lines and the first and last line, so you know the period covered.

**1. Count by program.** Which programs produce the volume.

```sh
awk '{print $5}' "$LOG" | sed -e 's/\[[0-9]*\]//' -e 's/:$//' | sort | uniq -c | sort -rn | head -30
```

**2. Count by day.** A day that is ten times louder than the rest is where something happened.

```sh
awk '{print $1, $2}' "$LOG" | uniq -c
```

To see which program made a loud day loud (replace the date; two spaces before a single-digit day):

```sh
grep '^Oct  4 ' "$LOG" | awk '{print $5}' | sed -e 's/\[[0-9]*\]//' -e 's/:$//' | sort | uniq -c | sort -rn | head
```

**3. Keyword sweep.** Count the lines containing each alarming word, then look at the ones with a count.

```sh
for W in error fail crash panic oops 'signal 11' segfault 'out of memory' reboot buggy radar DHCPNAK 'own address' 'error -110' 'Link DOWN' 'Link Up' CRC restart login; do
  printf '%8s  %s\n' "$(grep -ci -- "$W" "$LOG")" "$W"
done
printf '%8s  %s\n' "$(grep -ciw oom "$LOG")" "oom (whole word)"
```

> **Pitfall:** search for `oom` only as a whole word (`grep -w`). Otherwise it matches every line containing "room".

**4. Group by pattern.** Strip the timestamp, the process ID, and everything that varies (MAC addresses, IP addresses, numbers), then count identical shapes. This turns a hundred thousand lines into a list of a few dozen distinct messages.

```sh
awk '{$1=$2=$3=$4=""; print}' "$LOG" | sed -E -e 's/^ +//' -e 's/\[[0-9]+\]//' -e 's/([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/MAC/g' -e 's/[0-9]{1,3}(\.[0-9]{1,3}){3}/IP/g' -e 's/[0-9]+/N/g' | sort | uniq -c | sort -rn | head -60
```

**5. Look at one pattern in time.** For anything in the list you do not recognize, see when it happened and whether it is still happening:

```sh
grep -c 'roamast' "$LOG"
grep 'fatal signal' "$LOG" | awk '{print $1, $2}' | uniq -c
grep 'fatal signal' "$LOG" | head -1; grep 'fatal signal' "$LOG" | tail -1
```

A message that ran for some days and stopped needs no action. One that is still running today, or that lines up with a symptom you noticed, does. Then look it up in the table below.

## Common log lines and what they mean

Counts and durations are what was observed on this hardware over about three weeks. "Noise" means no action is needed.

| Log line | What it is | Noise or action |
| --- | --- | --- |
| `protocol 0000 is buggy, dev archer` | A kernel complaint about a packet with no protocol type on `archer`, an internal device of the Broadcom packet accelerator | Noise. Appeared tens of thousands of times for about a week, then stopped by itself. No functional impact observed |
| `not mesh client, can't update it's ip` | The AiMesh software noting that a device is not one of its own nodes | Noise. If most of them name stationary devices, see roaming exclusions in [Address plan](address-plan.md) |
| `received packet on ethN with own address as source address` | The bridge saw a frame arrive carrying the router's own MAC address, meaning something reflected or looped it back | Usually noise. 20 to 60 a day on the Wi-Fi interfaces (`eth4`, `eth5`, `eth6` on the XT8) is common with AiMesh plus an extra wired access point. Thousands a day, or on a wired port, suggests a real loop: check cabling |
| `roamast: ... disconnect weak signal strength station [MAC]` | The roaming assistant kicked a client whose signal was below the threshold, so that it reconnects to a nearer unit | Action if frequent. About 250 in three weeks was seen with the threshold at -70 dBm; at -55 dBm it was about 25 a day and users noticed. Set -70 dBm (2.4 GHz -72 to -75) in Wireless > Professional |
| `potentially unexpected fatal signal 11` with `Comm: roamast` | The roaming assistant process crashed (signal 11 is a segmentation fault). The firmware restarts it automatically | Noise unless it persists. Thousands of crashes over three days coincided with heavy network reconfiguration and stopped by itself |
| `Radar detected` | The 5 GHz radio heard radar on a DFS channel and must leave it; clients on that band drop briefly | Action only if frequent: choose a non-DFS channel. A 160 MHz channel at the low end of 5 GHz includes DFS channels |
| `DHCPNAK(br0) ...` | The router refused the address a client asked to keep, for example after the client changed network or its reservation changed. The client then asks afresh | Noise when occasional. A steady stream from one MAC means a reservation or address conflict |
| `not giving name X to the DHCP lease of ... because the name exists in ... .hostnames with address ...` | A device asked for an address other than the one reserved for its name (YazDHCP keeps reservations in that file) | Noise if brief. Otherwise make the reservation match, or wait for the lease to renew |
| `DHCPSOLICIT(br0)` repeating with no reply | One device asking for a DHCPv6 address. In a SLAAC-only setup nothing answers | Noise |
| `WPA: group key handshake failed (RSN) after 4 tries` | A Wi-Fi client did not answer the periodic group key update, typically because it was asleep. It is disconnected and rejoins | Noise for sleeping phones and IoT devices. Action if one device does it constantly: weak signal or a poor Wi-Fi stack |
| `usb X-Y: device descriptor read/64, error -110` | The USB drive timed out (-110 is a timeout) | **Action.** Back the drive up; replace it if it repeats. Entware, Skynet, Scribe and the logs live on it |
| `ethN ... Link DOWN` / `Link Up at 100 mbps` / `Link Up at 1000 mbps`, repeating on one LAN port | The port keeps renegotiating its speed: a marginal cable or a failing device on that port | **Action**, unless you were replugging it. Swap the cable |
| `[BLOCKED - INBOUND] IN=... SRC=...` | Skynet dropping an unsolicited connection from the internet | Noise. This is Skynet working. It is usually the largest share of the log |
| `kernel:` crash dump followed by a boot sequence, with AiProtection on | The Trend Micro engine crashed the kernel and the router rebooted | **Action.** Turn AiProtection off, or at least Two-Way IPS and Infected Device Prevention |
| Hundreds of `dnsmasq` start and exit lines in a day | Something keeps restarting dnsmasq. dnscrypt-proxy's manager did this about 550 times in one day | **Action.** [Remove dnscrypt-proxy](../hardware/asus-zenwifi-xt8.md#removing-dnscrypt-proxy) |
| `stubby` starting | DNS-over-TLS is enabled on the WAN page | Information. See [DNS design](dns-design.md) |
| JFFS `CRC error` lines | Trouble on the flash partition that holds your scripts | Watch. Seen for a few days, then stopped. If they return: back up JFFS, format it at next boot, restore |
| UPnP notify timeouts naming a LAN device | A device that does not answer UPnP event notifications | Noise |
| Web UI `login successful` from an address you do not expect | Someone logged in to the router | **Action**: confirm it was you. Logins through a VPN show the VPN side's address |
| `RTR-ADVERT(br0)`, `RTR-SOLICIT(br0)` | IPv6 router advertisements; see the next section | Noise, kept on purpose |
| `guest bridge (192.168.101.x) not found; Homebridge->Kasa rules skipped` (tag `firewall-start`) | The bootstrap script's firewall hook ran before the guest network existed | **Action**: create the guest network, then `service restart_firewall` |

## IPv6 router advertisement logging

This applies if the router advertises a local IPv6 prefix through dnsmasq, as in [Local-only IPv6](local-only-ipv6.md).

dnsmasq has an option, `quiet-ra`, that suppresses routine logging of router advertisements. The bootstrap script's `dnsmasq.postconf` block leaves it **out** on purpose, so the log shows that advertisements are really being sent:

| Line | Meaning |
| --- | --- |
| `RTR-ADVERT(br0) fd00:1234:5678:50::` | The router announced the prefix. A burst after each dnsmasq restart, then one every few minutes |
| `RTR-SOLICIT(br0)` | A client asked for an advertisement, usually on joining or waking |

Watch them live:

**Run on: the router**

```sh
tail -f /opt/var/log/messages | grep -e RTR- -e SLAAC
```

The lines name the interface, not the client. For "which device has which address" use `ip -6 neigh` (below).

No `RTR-ADVERT` lines at all means either advertisements are not being sent (run `sh /jffs/xt8-bootstrap.sh verify`) or a `quiet-ra` line is present in `/jffs/scripts/dnsmasq.postconf` outside the script's marked block. Check:

**Run on: the router**

```sh
grep -n quiet-ra /jffs/scripts/dnsmasq.postconf /etc/dnsmasq.conf
```

To get the logging, comment that line out and run `service restart_dnsmasq`. To silence the logging, add this line **below** the `# <<< homenet END` marker in `/jffs/scripts/dnsmasq.postconf`, then `service restart_dnsmasq`:

```sh
pc_append "quiet-ra" "$CONFIG"
```

### Why System Log > IPv6 stays blank

**System Log > IPv6 says "IPv6 Not enabled" and always will** in a script-driven setup. That page only fills in when IPv6 is enabled on the IPv6 page of the web UI, and that page must stay on Disable for the local-only design. The same information over SSH:

**Run on: the router**

```sh
ip -6 addr show dev br0
ip -6 neigh show dev br0
ip -6 route
```

The first prints the router's own addresses. The second prints every client's IPv6 address with its MAC address. The third must have no `default` line.

## Check it

**Run on: the router**

```sh
ls -ld /opt/var/lib
tail -3 /opt/var/log/logrotate.log
logger "log check"; sleep 2; tail -1 /opt/var/log/messages
```

Expected: the folder exists; the logrotate log has no `error creating stub state file` line dated after your fix; the last line of `messages` ends with `log check`. The morning after, `ls -la /opt/var/log/messages*` must show a new dated file if the log was large enough to rotate.

## Pitfalls

| What happens | Why | Avoid or recover |
| --- | --- | --- |
| `messages` grows to tens of MB | `/opt/var/lib` is missing, so logrotate fails every night | Step 2 |
| `/opt/var/lib` disappears again | The USB drive was reformatted, or it is failing | Recreate it; check the log for `error -110`; replace the drive |
| New `messages` is 0 bytes after rotation | Nothing logged yet | `logger` test in Step 2 |
| The old file keeps growing after rotation | syslog-ng still has it open | `killall -HUP syslog-ng` |
| Searching for "oom" matches everything | "room" | `grep -w` |
| A scary-looking message with a huge count | Counts mislead; many loud messages are harmless and stop by themselves | Step 3, part 5: check whether it is still happening and whether it lines up with a symptom |
| No log from the AiMesh node | The node logs to memory only and loses it at reboot | Expected. Do not install Scribe on the node: it would need its own USB drive and Entware for a log that is mostly Wi-Fi association chatter the main router already records. See [AiMesh node](../hardware/asus-aimesh-node.md) |
| An empty `cru l` is read as "no reboot scheduled" | The firmware's reboot scheduler is run by the watchdog, not cron, so it never shows there | `nvram get reboot_schedule_enable` |

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `/opt/var/log/messages` is tens of MB; `logrotate.log` says `error creating stub state file /opt/var/lib/logrotate.status` | No state folder | `mkdir -p /opt/var/lib; /opt/sbin/logrotate /opt/etc/logrotate.conf` |
| `messages` is 0 bytes right after a rotation | Nothing has been logged yet | `logger test; sleep 2; ls -la /opt/var/log/messages*`. Only if the old file grew instead: `killall -HUP syslog-ng` |
| `/opt/var/log` does not exist | The USB drive is not mounted, or Scribe is not installed | Check the drive in the web UI; reinstall Scribe through `amtm` |
| System Log > IPv6 says "IPv6 Not enabled" | Expected; IPv6 is set up by script, not the UI | `ip -6 neigh show dev br0` |
| No `RTR-ADVERT` lines in the log | A `quiet-ra` line is in `dnsmasq.postconf`, or advertisements are not being sent | Comment it out, `service restart_dnsmasq`; run `verify` |
| `DHCPSOLICIT(br0)` repeating with no reply | One device wants DHCPv6; the router only does SLAAC | Nothing |
| Random Wi-Fi drops; many `disconnect weak signal strength station` lines | Roaming assistant threshold too strict | -70 dBm |
| Router reboots every few days | AiProtection engine crash | Turn AiProtection off |

## Undo

The folder fix needs no undo. To stop the advertisement logging, add the `quiet-ra` line as shown above. To remove Scribe, use its entry in `amtm`; the router goes back to its in-memory log.

## References

- [scribe](https://github.com/AMTM-OSR/scribe): the syslog-ng and logrotate installer for Asuswrt-Merlin, and its Entware requirement.
- [logrotate(8) manual page](https://man7.org/linux/man-pages/man8/logrotate.8.html): the state file and the `--state` option that explain the "stub state file" error.
- [logrotate source repository](https://github.com/logrotate/logrotate): the tool itself.
- [syslog-ng source repository](https://github.com/syslog-ng/syslog-ng): the logger Scribe installs.
- [dnsmasq manual page](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html): `quiet-ra` ("suppress logging of the routine operation") and the router advertisement options.
- [ip-neighbour(8) manual page](https://man7.org/linux/man-pages/man8/ip-neighbour.8.html): the `ip neigh` command used in place of the blank IPv6 log page.
- [Asuswrt-Merlin wiki: Entware](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Entware): where `/opt` comes from and why it needs a USB disk.
- [Skynet (IPSet_ASUS)](https://github.com/Adamm00/IPSet_ASUS): the source of the `[BLOCKED - INBOUND]` lines.
