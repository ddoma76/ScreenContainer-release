# ScreenContainer 0.1.0

## Image

- Registry: `ghcr.io/ddoma76/screencontainer`
- Tags: `0.1.0`, `latest`
- Platform: `linux/amd64`
- Registry manifest digest:
  `sha256:f0048405fa3791948fa5d93b48353118276c8f00d6ae8d1c8e738734ebacac18`
- Build source: clean public repository revision `56031c6`.
- Built from the Dockerfile, not from a running desktop or its persistent data.

For immutable deployment, replace the Compose `image` reference with:

```yaml
image: ghcr.io/ddoma76/screencontainer@sha256:f0048405fa3791948fa5d93b48353118276c8f00d6ae8d1c8e738734ebacac18
```

## Verified on TrueNAS

Tested on 2026-10-18, TrueNAS 25.04.2.6, Linux
`6.12.15-production+truenas`, amd64, Intel modesetting GPU.
The final image was started using fresh, separate desktop-home and X11 volumes.

- Physical-display Xorg startup on VT 7.
- XFCE session, window manager, panel and desktop startup.
- Default desktop UID/GID 1000 and passwordless sudo disabled.
- PulseAudio daemon startup.
- Firefox window launch through `screen-run`.
- Home-file persistence across container stop/start.
- Clean shutdown with exit status 0, twice.
- Original desktop restored using the same container ID and image.

These are startup/smoke tests, not certification for every TrueNAS release or GPU.
Audible output, Bluetooth pairing/audio, input-device and monitor hotplug were
not tested. The test host lacks Bluetooth driver support.

## Installation and trust

Use `compose.ghcr.yaml` and configure `.env` before starting. The physical-display
container is privileged/root-equivalent and allows trusted local X11 clients.
Do not use on an untrusted multi-user host. See the README for requirements.
The existing Omarchy windowed launcher is a separate, non-privileged test mode.

## License and corresponding source

ScreenContainer code is MIT licensed. Bundled Debian packages retain their own
licenses and notices under `/usr/share/doc/`.

The matching GitHub release provides:

- Clean project source (`screencontainer-0.1.0-source.tar.gz`).
- Pull-only Compose configuration and generic `.env`.
- Binary and source package version manifests.
- Matching Debian source packages, including Debian patches/build instructions,
  in a split tar stream (`debian-sources.tar.part-*`).
- `SHA256SUMS` for the downloadable assets.

After downloading **all** parts and checksum files into an empty directory:

```sh
sha256sum -c SHA256SUMS
cat debian-sources.tar.part-* | tar -xf -
```

Each Debian source package has a `.dsc` file and its referenced source archives.
Use Debian's standard source-package tools to unpack/build the desired package.
The archive also contains the exact installed binary/source version manifests.
