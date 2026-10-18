# Third-party software

The [MIT license](LICENSE) covers ScreenContainer's original scripts and
configuration, not all software in its container image.

The image includes Debian Bookworm and packages such as Linux userspace
libraries, Xorg, Mesa, XFCE, Firefox ESR, PulseAudio, BlueZ and Blueman.
These have their own licenses, including GPL, LGPL, MPL and permissive licenses.
Firmware and other non-free components, if added by downstream users, may
have additional redistribution restrictions.

Installed package copyright and license notices are retained inside the image
at `/usr/share/doc/<package>/copyright`. Symlinked documentation directories are
normal for Debian packages. To list installed binary and source versions:

```sh
docker run --rm --entrypoint dpkg-query ghcr.io/ddoma76/screencontainer:0.1.0 \
  -W '-f=${binary:Package}\t${Version}\t${source:Package}\t${source:Version}\n'
```

Official releases must provide the exact corresponding Debian source packages
alongside their binary images, as downloadable assets on the matching GitHub
release. Each source archive includes upstream source and Debian packaging,
patches and build instructions. Original ScreenContainer source is provided in
the same release. See [release instructions](RELEASING.md).

Do not publish a release if its matching source bundle cannot be generated.
Do not strip license notices from the image. Consult each package's license
before distributing modified images; this document does not relicense Debian
packages or replace their terms.
