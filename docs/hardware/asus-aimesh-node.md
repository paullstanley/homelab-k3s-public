# Second XT8 as an AiMesh node

A second ZenWiFi XT8 joined to the main router as an AiMesh node (a satellite unit the main router manages), with one addition of your own: a weekly reboot you can see and check. This page also covers what a node cannot do, so you do not spend time trying.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | ASUS ZenWiFi XT8 (RT-AX95Q) as AiMesh node, wired backhaul, GNUton Asuswrt-Merlin.ng 3004.388.10_2, managed by a main XT8 on the same firmware |
| **Also works for** | Other AiMesh nodes running Asuswrt-Merlin or GNUton's builds. Not tested by the author. A node on stock ASUS firmware has no `/jffs/scripts` support, so the script does not apply |
| **Time** | 10 minutes |
| **You need first** | [ASUS ZenWiFi XT8 router](asus-zenwifi-xt8.md) set up, with SSH enabled, and the node added under AiMesh |

## How it works

A node has almost no web UI of its own. The main router pushes Wi-Fi settings to it. But a node running Merlin still has SSH, nvram (the firmware's settings store), a JFFS partition (small persistent flash storage) and `cru` (the firmware's cron command), so a script can configure it.

Facts that shape everything below:

- The node gets its address from the main router by DHCP. In the examples it is `192.168.50.117`.
- It **accepts the main router's SSH login on the same port**.
- It has no USB drive in this setup, so no Entware (the add-on package manager) and no Scribe. Its log lives in memory, limits its own size, and is lost at every reboot.
- `cru` jobs are lost at reboot. The file `/jffs/scripts/services-start` runs at every boot and can add them back, but only if the nvram value `jffs2_scripts` is `1`. On the main router you tick a box for that; on a node there is no box.

The script [`files/xt8/node/xt8-node-setup.sh`](../../files/xt8/node/xt8-node-setup.sh) runs on your computer, logs in to the node once, and does the work there in a single SSH session.

## Before you start

- **Find the node's address.** On the main router's web UI, open AiMesh and select the node; or look for it in the client list (its hostname looks like `ZenWiFi_XT8-XXXX`). Consider giving it a DHCP reservation so the address stays put.
- Decide the reboot time. The default is Wednesday 03:30. Pick a time different from the main router's own scheduled reboot.
- Know the SSH user and port of the main router. The examples use `admin` and `22`; write your own port where you see `<SSH_PORT>`.

> **Note:** the script defaults to user `admin` and port `22`. Pass your own user and port as the second and third arguments if they differ.

> **Not verified:** the script has been syntax-checked and run against stand-in commands, not against a real node. The same commands were entered by hand on a real node and worked. Whether the job survives a reboot by itself had not been observed when this was written; the check is under [Check it](#check-it).

## Steps

### Step 1. Confirm you can log in to the node

**Run on: your computer**

```sh
ssh -p 22 admin@192.168.50.117 'nvram get lan_ipaddr; nvram get lan_hostname'
```

It must print the node's own address (not `192.168.50.1`) and its hostname. The password is the main router's.

### Step 2. Run the node script

**Run on: your computer**, from the root of this repo

```sh
sh files/xt8/node/xt8-node-setup.sh 192.168.50.117 admin 22
```

Arguments:

| Argument | Meaning |
| --- | --- |
| `NODE_IP` | The node's IPv4 address. Required |
| `USER` | SSH user. Optional; pass `admin` |
| `PORT` | SSH port. Optional; pass `22` or your `<SSH_PORT>` |

`ssh` asks for the password once. The password is deliberately not an argument: arguments are saved in shell history and are visible to other programs while the command runs.

For an unattended run, install `sshpass` and put the password in the `SSHPASS` environment variable:

**Run on: your computer**

```sh
read -s SSHPASS && export SSHPASS
sh files/xt8/node/xt8-node-setup.sh 192.168.50.117 admin 22
```

Type the password after the first line and press Return. If `SSHPASS` is set but `sshpass` is not installed, the script stops with an error.

For a different time, set `REBOOT_AT` to five cron fields (minute, hour, day of month, month, weekday). This example is Sunday 04:00:

**Run on: your computer**

```sh
REBOOT_AT="0 4 * * 0" sh files/xt8/node/xt8-node-setup.sh 192.168.50.117 admin 22
```

What the script does on the node:

| Step | Why |
| --- | --- |
| Refuses if you pass `192.168.50.1`, and again if the device's own LAN address is `192.168.50.1` | So it can never put the job on the main router by mistake |
| Refuses if `/jffs` does not exist | The device is not running Asuswrt-Merlin |
| `nvram set reboot_schedule_enable=0` | Turns the firmware's own scheduler off so the node is not rebooted twice |
| `nvram set jffs2_scripts=1`, then `nvram commit` | Without it the firmware ignores `/jffs/scripts` at boot |
| Copies `/jffs/scripts/services-start` to `services-start.bak`, removes any old `cru a WeeklyReboot` line, appends `cru a WeeklyReboot "30 3 * * 3 /sbin/reboot"` and makes the file executable | `services-start` runs at every boot and adds the job back. Lines already in the file, such as amtm's, are kept |
| `cru d WeeklyReboot`, then the same `cru a` once | So the job exists now, without a reboot |
| Prints the hostname, `jffs2_scripts`, the cron line and the file | So you can see the result |

It is safe to run again. A reference copy of the resulting file is [`files/xt8/node/services-start`](../../files/xt8/node/services-start).

## Check it

**Run on: the node** (`ssh -p 22 admin@192.168.50.117`)

```sh
cru l
nvram get jffs2_scripts
uptime
```

Expected: one line ending `#WeeklyReboot#`, then `1`.

After the first scheduled day has passed, run them again. `uptime` must show under a week **and** `cru l` must still list the job. That second part proves `services-start` ran by itself at boot.

## Pitfalls

| What happens | Why | Avoid or recover |
| --- | --- | --- |
| `cru l` is empty although a reboot is scheduled in the GUI | The firmware's own scheduler never appears in `cru l`. It is run by the watchdog process, not by cron | An empty `cru l` says nothing about it. Read it with `nvram get reboot_schedule_enable` and `nvram get reboot_schedule`. The cron job is used here because it can be seen |
| You want to set the firmware scheduler by hand | Its nvram format is seven day flags, Sunday to Saturday, then HHMM | `nvram set reboot_schedule=00010000330` with `nvram set reboot_schedule_enable=1` is Wednesday 03:30. Do not use it together with the cron job |
| `grep: /jffs/addons/custom_settings.txt: No such file or directory` when running `services-start` by hand | It comes from amtm's line in that file | Harmless |
| The job is gone after the main router restarts | AiMesh sync might overwrite node settings. Not seen so far | Run the script again |
| The job is gone after a node reboot | `jffs2_scripts` is not `1`, or `services-start` is not executable | Run the script again and repeat the check after the next reboot |
| The node's log is empty after a problem | The log is in memory and is lost at every reboot | Read it before rebooting, or rely on the main router's log |
| You try to install Scribe on the node | It would need a second USB drive and Entware, for a log that is mostly Wi-Fi association chatter the main router already records | Do not. See [Router logging](../network/router-logging.md) |

### If you also have the isolated IoT network

The `ebtables` rules that let IoT devices answer chosen LAN hosts ([Isolated IoT network](../network/isolated-iot-network.md)) are installed on the main router only. IoT devices that the client list showed as connected through the node were observed answering normally, so nothing extra is installed on the node. If one device stops answering after it roams to the node, look here first.

There is no script in this repo for pushing a wireless device from one unit to the other. To make a device reconnect, use the main router's AiMesh client view to bind it to a unit, or turn its Wi-Fi off and on.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `[node] FAILED (exit 255)` and it never connected | Wrong address, wrong port, or SSH not enabled on the main router | Check the address under AiMesh; check Administration > System > Enable SSH on the main router |
| `Permission denied` | Wrong user or password | The node uses the main router's login |
| `ERROR: this device is the main router` | You gave the main router's address, or the node is not in node mode | Give the node's address |
| `ERROR: NODE_IP must be an IPv4 address` | A hostname or IPv6 address was passed | Pass the IPv4 address |
| `ERROR: REBOOT_AT must be five cron fields` | Characters other than digits, spaces, `*`, `,`, `/`, `-` | For example `"0 4 * * 0"` |
| `cru l` on the node shows no reboot job | `services-start` did not run at boot, or AiMesh sync reset it | Run the script again |
| Node rebooted twice in a week | The firmware scheduler is also on | `nvram get reboot_schedule_enable` must print `0` |

## Undo

**Run on: the node**

```sh
cru d WeeklyReboot
sed -i '/cru a WeeklyReboot /d' /jffs/scripts/services-start
cru l
```

The last command must print no `WeeklyReboot` line. `jffs2_scripts` can stay at `1`; it is harmless.

## References

- [Asuswrt-Merlin wiki: AiMesh](https://github.com/RMerl/asuswrt-merlin.ng/wiki/AiMesh): what Merlin supports on a node, and the firmware update limits for nodes.
- [Asuswrt-Merlin wiki: User scripts](https://github.com/RMerl/asuswrt-merlin.ng/wiki/User-scripts): `services-start`, and enabling `jffs2_scripts` on an AiMesh node over SSH.
- [Asuswrt-Merlin wiki: Scheduled tasks (cron jobs)](https://github.com/RMerl/asuswrt-merlin.ng/wiki/Scheduled-tasks-(cron-jobs)): the `cru` command and why jobs must be re-created at boot.
- [ASUS: How to set up an AiMesh system (Web GUI)](https://www.asus.com/support/faq/1035087/): adding a node to the main router.
- [gnuton/asuswrt-merlin.ng](https://github.com/gnuton/asuswrt-merlin.ng): the firmware builds for the XT8.
