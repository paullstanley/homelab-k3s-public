# Cameras in HomeKit with camera-ffmpeg: Axis and Wyze

You end up with RTSP cameras (two Axis cameras and one Wyze camera in this build) showing live video and still images in Apple's Home app, through the `@homebridge-plugins/homebridge-camera-ffmpeg` plugin. The page records which ffmpeg settings worked on a Raspberry Pi and which did not.

Example addresses and names are explained in [Conventions](../start-here/conventions.md); substitute your own.

| | |
| --- | --- |
| **Applies to** | `@homebridge-plugins/homebridge-camera-ffmpeg` 4.1.0 on Homebridge v2.4.0, running on a Raspberry Pi (arm64), ffmpeg installed with `apt-get` at container start. Axis network cameras (RTSP `axis-media/media.amp`) and a Wyze camera with RTSP enabled (`/live`) |
| **Also works for** | Any camera with an RTSP stream. Settings for other makes are not tested by the author |
| **Time** | 30 minutes per camera model, mostly trial and error |
| **You need first** | [Homebridge on k3s](homebridge.md) or any Homebridge install with ffmpeg available |

## How it works

When you open a camera in the Home app, HomeKit asks the plugin for a stream of a certain size and bit rate. The plugin starts ffmpeg, which reads the camera's RTSP stream (`source`) and sends H.264 video to the phone. Two choices decide whether this works well:

- **Copy or transcode.** `vcodec: copy` passes the camera's video through untouched, which costs almost no CPU, but only works if the camera's stream is already in a form HomeKit accepts. `vcodec: libx264` re-encodes the video in software, which works with any input but loads the CPU; on a Raspberry Pi the resolution and frame rate must be kept modest.
- **Still images.** The tile in the Home app shows a snapshot. The plugin takes it from `stillImageSource` if set, otherwise it grabs one frame from `source`.

## Before you start

- Each camera needs a fixed or reserved address.
- Create a viewer login on each camera for Homebridge. Give each camera its own password.
- On a Wyze camera, enable RTSP in the Wyze app or firmware so that it serves `rtsp://<user>:<password>@<address>/live`.
- ffmpeg must exist in the Homebridge environment. In the k3s setup here, the startup script installs it ([Homebridge on k3s](homebridge.md), "The startup script").

> **Pitfall:** the camera logins sit in plain text in `source` inside `config.json`. Never commit that file or paste it into a chat, forum or issue. Replace credentials with placeholders before sharing a config. If it has been shared, change every camera password. See [Backups and secrets](../operations/backups-and-secrets.md).

## Steps

### Step 1. Install the right plugin

In the Homebridge UI, **Plugins**, install `@homebridge-plugins/homebridge-camera-ffmpeg`.

> **Pitfall: the duplicate old plugin.** The unscoped `homebridge-camera-ffmpeg` (3.1.4) is the old package. If both are installed, two camera plugins sit side by side registering the same platform. This happened here because a container startup script ran `npm install homebridge-camera-ffmpeg` on every start. Remove any such line from the startup script, and uninstall the old plugin in the UI if it is listed.

### Step 2. Add the cameras

The working config is [`files/homebridge/config-examples/camera-ffmpeg.json`](../../files/homebridge/config-examples/camera-ffmpeg.json). Paste it into the plugin's JSON config and replace addresses, names and the `<...>` placeholders. Paste the whole block; a cut-off paste gives a config "verification warning".

An Axis camera, transcoded:

```json
{
  "name": "Living Room Camera",
  "videoConfig": {
    "source": "-rtsp_transport tcp -i rtsp://<AXIS_USER>:<AXIS_PASSWORD>@192.168.50.127/axis-media/media.amp?Axis-Orig-Sw=true",
    "maxStreams": 2,
    "vcodec": "libx264",
    "maxWidth": 1280,
    "maxHeight": 720,
    "maxFPS": 15,
    "maxBitrate": 2000,
    "forceMax": false,
    "packetSize": 564,
    "audio": false
  }
}
```

A Wyze camera, copied:

```json
{
  "name": "Backyard",
  "videoConfig": {
    "source": "-rtsp_transport tcp -i rtsp://<WYZE_RTSP_USER>:<WYZE_RTSP_PASSWORD>@192.168.50.69/live",
    "stillImageSource": "-rtsp_transport tcp -i rtsp://<WYZE_RTSP_USER>:<WYZE_RTSP_PASSWORD>@192.168.50.69/live -vframes 1 -r 1",
    "maxStreams": 1,
    "maxWidth": 1280,
    "maxHeight": 720,
    "maxFPS": 15,
    "vcodec": "copy",
    "audio": true
  }
}
```

| Setting | Axis | Wyze | Meaning |
| --- | --- | --- | --- |
| `source` | `-rtsp_transport tcp -i rtsp://.../axis-media/media.amp?Axis-Orig-Sw=true` | `-rtsp_transport tcp -i rtsp://.../live` | ffmpeg input. `-rtsp_transport tcp` carries the stream over TCP, which avoids the picture corruption that lost UDP packets cause |
| `stillImageSource` | not set (one frame from `source`) | same stream with `-vframes 1 -r 1` | Where the snapshot comes from. `-vframes 1` takes a single frame |
| `vcodec` | `libx264` | `copy` | Transcode or pass through |
| `maxWidth` × `maxHeight` | 1280 × 720 | 1280 × 720 | Upper limit of what is sent |
| `maxFPS` | 15 | 15 | Upper frame rate |
| `maxBitrate` | 2000 (kbps) | not set | Upper bit rate |
| `forceMax` | `false` | not set | When `true`, your maximums override what HomeKit asks for |
| `packetSize` | 564 | not set | Smaller packets can help choppy video. Must be a multiple of 188; the default is 1316 |
| `maxStreams` | 2 | 1 | Simultaneous viewers |
| `audio` | `false` | `true` | Send audio |

### Step 3. Restart and view

Restart Homebridge, open the Home app and tap each camera.

## What was tried on the Axis cameras

| Attempt | Result |
| --- | --- |
| Extra Axis URL parameters and a separate snapshot URL | ffmpeg exited with code 8; no picture. Use the plain `axis-media/media.amp` URL |
| `vcodec: copy` | Picture, but very slow and mostly buffering |
| `libx264` at 1920 × 1080, 20 fps, `maxBitrate` 150000, `forceMax` true, `videoFilter` none, `mapvideo` 0 (the original settings) | Streams started ("1920 x 1080, 20 fps, 150000 kbps" in the log), with "Failed to fetch snapshot" errors on both Axis cameras |
| `libx264` at 1280 × 720, 15 fps, `maxBitrate` 2000, `forceMax` false, `packetSize` 564 (current) | The snapshot errors stopped after this change |

> **Not verified:** the picture quality of the current 720p settings was not assessed. The snapshot errors stopped, and that is all that is confirmed. If the 720p settings do not suit your cameras, the fallback is the original: 1920 × 1080, 20 fps, `maxBitrate` 150000, `forceMax` true, `videoFilter` none, `mapvideo` 0, accepting the snapshot errors.

Why the Wyze camera is different: its stream is already in a format HomeKit takes, so copying it costs the Pi almost nothing.

## Bridged or unbridged

In this build the cameras are **bridged** on the main bridge (`unbridge` set off or absent in an older config), so they did not need pairing again when the plugin changed.

The plugin's authors recommend **unbridged** cameras for performance; the current plugin defaults `unbridge` to `true` and warns that bridged cameras can slow the whole Homebridge instance. If you switch a camera to unbridged:

1. Remove its old tile from the Home app first.
2. Add the camera to the Home app separately (Add Accessory → More options), using the bridge's PIN.

Check which mode you are in before upgrading the plugin: a config with no `unbridge` line follows the plugin's default.

## Check it

- Each camera shows a live picture within a few seconds in the Home app.
- Each tile shows a recent still image.
- The Homebridge log has no "Failed to fetch snapshot" and no "ffmpeg exited with code" lines for the cameras.

Test a stream outside HomeKit to separate camera problems from plugin problems.

**Run on: the Homebridge UI terminal**

```bash
ffmpeg -rtsp_transport tcp -i 'rtsp://<AXIS_USER>:<AXIS_PASSWORD>@192.168.50.127/axis-media/media.amp' -vframes 1 -y /tmp/test.jpg && ls -l /tmp/test.jpg
```

A JPEG file of non-zero size means the camera, the login and ffmpeg are fine. (This test is a general ffmpeg check and is not from the tested build.)

## Pitfalls

| What happens | Why | Avoid or recover |
| --- | --- | --- |
| Two camera plugins listed | Old unscoped plugin reinstalled by a startup script | Step 1 |
| No picture, ffmpeg exit code 8 | Unsupported parameters on the Axis URL | Plain `axis-media/media.amp` URL |
| Endless buffering on Axis | `vcodec: copy` on the Axis stream | `libx264` settings above |
| "Failed to fetch snapshot" | Seen with the 1080p / 150000 kbps settings | 720p settings. If it returns, turn on `debug` for that camera in the plugin settings so the log shows the real ffmpeg error |
| No ffmpeg, or an old one | The startup script's `apt-get` failed (no DNS or no package servers) and the pod started with whatever the image has | Check the start of the pod log for "apt-get failed"; fix DNS and restart |
| A Wyze camera on the isolated IoT network cannot be streamed | Unlike other Wyze devices, the camera is reached directly, not through the cloud | Keep it on the main LAN, or open the path as in [Kasa devices across networks](homebridge-kasa-across-networks.md) |
| High CPU on the node while someone watches | `libx264` software encoding | Lower `maxWidth`/`maxHeight`/`maxFPS`, or reduce `maxStreams` |

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Axis cameras show no picture, ffmpeg exit code 8 | Unsupported URL parameters | Use the plain `axis-media/media.amp` URL |
| Axis cameras buffer endlessly | `vcodec: copy` | `libx264`, 1280 × 720, 15 fps, 2000 kbps |
| Camera "Failed to fetch snapshot" | Old 1080p settings, or the camera is unreachable | Current settings; enable the camera's `debug` |
| Two camera plugins listed | Duplicate old plugin | Uninstall `homebridge-camera-ffmpeg` (unscoped) |
| Config "verification warning" | The pasted JSON was cut off | Paste the whole block |
| Camera tile says "No Response" | Homebridge down, or the camera moved address | Pod status; reserve the camera's address |
| Camera shows twice or not at all after switching bridged/unbridged | Old tile not removed, or camera not added separately | See "Bridged or unbridged" |

## Undo

Remove the camera entries (or uninstall the plugin) and restart Homebridge. Remove unbridged cameras from the Home app by hand.

## References

- [homebridge-plugins/homebridge-camera-ffmpeg](https://github.com/homebridge-plugins/homebridge-camera-ffmpeg): the plugin; every `videoConfig` option, and the `unbridge` default and warning.
- [FFmpeg protocols documentation](https://ffmpeg.org/ffmpeg-protocols.html): the RTSP options, including `rtsp_transport`.
- [homebridge/docker-homebridge](https://github.com/homebridge/docker-homebridge): the container image and its `startup.sh` hook, used here to install ffmpeg.
- [Camera configurations collected for homebridge-camera-ffmpeg](https://sunoo.github.io/homebridge-camera-ffmpeg/configs/): community-tested configs by camera make, from the plugin's earlier maintainer.
