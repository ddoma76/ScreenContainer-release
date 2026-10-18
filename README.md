# Screen container for TrueNAS

Turns the TrueNAS box's HDMI/DisplayPort output into a real desktop (XFCE + Firefox),
running entirely inside a Docker container. Other containers and host programs can show
their windows on it.

How it works: the container runs a real **Xorg server** on the host GPU (`/dev/dri/card0`,
KMS/modesetting) on virtual terminal 7, with keyboard/mouse via libinput and audio
(incl. HDMI) via PulseAudio. Devices are bind-mounted, so monitor, keyboard and mouse can
be plugged in after the container starts.

## Deploy / update

### Prebuilt image (Linux amd64)

Public source: <https://github.com/ddoma76/ScreenContainer-release>.
Published releases use `ghcr.io/ddoma76/screencontainer`. On a Linux server with
Docker Engine and the Compose plugin, download `compose.ghcr.yaml` and `.env`
from the same release into an empty directory. Review `.env` before starting:
set `DATA_DIR` to persistent storage, `PUID`/`PGID` to its owner, and check
`KMS_DEVICE`, keyboard layout and timezone.

```sh
sudo docker compose -f compose.ghcr.yaml pull
sudo docker compose -f compose.ghcr.yaml up -d
sudo docker compose -f compose.ghcr.yaml logs -f
```

The default version is `0.1.0`; set `SCREEN_VERSION` to select another published
version or an immutable `sha256` digest by editing the image reference.
Do not point this configuration at an existing deployment's data unless you
intend to upgrade it. Stop any existing desktop using the same GPU/VT first.
This is a Docker Compose deployment, not a TrueNAS app-catalog entry.

Requirements: a compatible Linux DRM/KMS GPU driver, a connected display,
available VT 7, and `/dev/dri`, `/dev/input`, `/dev/snd` and `/run/udev` on the host.
Only Linux amd64 is initially supported. Other GPUs, architectures and TrueNAS
versions are not certified. No host driver is included in this image.

### Build from source

```sh
./deploy.sh user@server                 # copies to /opt/screen/app, builds, starts
./deploy.sh user@server /path/to/app     # uses a custom remote directory
```

Settings are in [.env](./.env) (keyboard layout, timezone, screen blanking, autostart command, ...).
Set the desired host UID/GID, timezone and data directory before deployment. Defaults are
UID/GID 1000, UTC and `./data` relative to the deployed project directory. The SSH target
must be supplied explicitly; no personal host alias is configured.
The container restarts automatically with Docker (`restart: unless-stopped`).

Persistent data under `DATA_DIR` (default `/opt/screen/app/data` when deployed):

- `home/` – the desktop user's home (Firefox profile, settings, downloads), owned by `PUID:PGID`
- `x11/`  – the X11 socket shared with other containers

When updating an existing deployment, pass its existing remote project directory and keep
its original `DATA_DIR`, `PUID` and `PGID` values to preserve access to existing data.

## Using the screen

- **Ctrl+Alt+F1** switches to the TrueNAS console menu, **Ctrl+Alt+F7** back to the desktop.
  Stopping the container also returns the screen to the console.
- Firefox is in *Applications → Internet*. With host networking, `http://localhost` is the TrueNAS UI.

## Showing other programs on the screen

From the NAS shell, start any program installed in the container:

```sh
sudo docker exec screen screen-run firefox-esr https://example.com
sudo docker exec screen screen-run xfce4-terminal
```

From **another container**, mount the shared socket and set `DISPLAY=:0`
(see [examples/client-app.yaml](./examples/client-app.yaml)):

```yaml
    environment:
      DISPLAY: ":0"
    volumes:
      - /path/to/data/x11:/tmp/.X11-unix
```

Use the same data directory as the screen container. The example Compose file defaults to
`../data/x11` relative to `examples/`, matching this project's default `./data`.

Containers using `network_mode: host` and processes on the NAS host itself can also simply use
`DISPLAY=:0` (abstract X socket) without the mount.

Sound (HDMI/analog) is available to programs running inside the screen container; for audio,
launch them with `screen-run`.

## Bluetooth

Blueman (the Bluetooth manager supported by Debian Bookworm) is installed along with
BlueZ and PulseAudio Bluetooth support. Open **Bluetooth Manager** from the applications
menu, or run:

```sh
sudo docker exec screen screen-run blueman-manager
```

BlueZ starts inside the container using its own system D-Bus. The desktop user belongs
to the `bluetooth` group and may use Blueman's privileged operations without a logind
session. Do not run another BlueZ daemon on the host against the same adapter.

The host kernel must provide Bluetooth support, including `bluetooth` and the adapter
driver (usually `btusb` for USB/Intel adapters). A privileged container cannot supply
missing host drivers. Some NAS kernels omit Bluetooth support; if so, the adapter cannot
be used until host kernel support is available. Installing the manager alone does not
resolve this limitation.

## Notes

- The container is `privileged` (required for Xorg to drive the GPU and VTs). Treat it as
  root-equivalent on the NAS; `ENABLE_SUDO=true` gives the desktop user passwordless sudo.
- Logs: `sudo docker logs screen`, Xorg log: `sudo docker exec screen cat /var/log/Xorg.log`.
- Install extra apps by adding them to the `apt-get install` list in the [Dockerfile](./Dockerfile)
  and re-running `./deploy.sh <ssh-host>` (changes made inside a running container are lost on rebuild).
- The X server allows all local clients (`xhost +local:`). Other local processes and
  host-network containers can observe or control the desktop. Use only on a trusted,
  single-purpose host, not an untrusted multi-user server. X11 TCP listening is disabled.
- The Omarchy [windowed launcher](local-omarchy.sh) uses a separate authenticated Xephyr
  window and private desktop volume, not the physical GPU/VT entrypoint. It does not
  pass through Bluetooth or host audio and is not a test of physical GPU compatibility.

## License and releases

Original project code is [MIT licensed](LICENSE). Bundled Debian applications retain
their own licenses; see [third-party notices](THIRD_PARTY_NOTICES.md). Corresponding
Debian sources accompany official releases. Maintainers should follow
[release instructions](RELEASING.md) and never publish personal desktop volumes,
browser profiles, tokens or committed running containers.
