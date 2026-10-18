# Publishing a release

Only `linux/amd64` is initially supported. Do not advertise other platforms
without building and testing them. Publish an image built from the Dockerfile,
never a committed/exported running desktop or its home volume.

## Authentication

Create a classic GitHub PAT with `write:packages` (`read:packages` is included),
and `public_repo` if pushing public source using the same token. Do not request
`delete:packages`. Authorize organization SSO separately if applicable.
Never paste tokens into issues, chat, source files or shell command arguments.

Authenticate interactively in your own terminal:

```sh
gh auth login --hostname github.com --with-token
gh auth token | docker login ghcr.io --username "$(gh api user --jq .login)" --password-stdin
```

Use a credential helper for Docker if possible. Without one, Docker stores
registry credentials in its configuration; use `docker logout ghcr.io` after
publishing. For a temporary publishing session, use a private temporary
`DOCKER_CONFIG` directory and remove its credential file afterward.

## Build, test and publish

1. Review the build context allowlist in `.dockerignore`. Commit the release
   source, license and documentation. Build with revision and version metadata:

   ```sh
   docker build --platform linux/amd64 \
     --build-arg VERSION=0.1.0 --build-arg REVISION="$(git rev-parse HEAD)" \
     -t ghcr.io/ddoma76/screencontainer:0.1.0 .
   ```

2. Generate the matching Debian source bundle from that image:

   ```sh
   mkdir -p dist/debian-sources
   docker run --rm --user 0 \
     -v "$PWD/dist/debian-sources:/sources" \
     -v "$PWD/scripts/collect-debian-sources.sh:/collect-sources:ro" \
     --entrypoint /bin/bash ghcr.io/ddoma76/screencontainer:0.1.0 /collect-sources
   ```

   This downloads sources in a disposable container, not into the published
   image. It fails if a matching source version is unavailable. For long-term
   reproducibility retain these archives; live Debian mirrors change.

3. Test the exact image on TrueNAS with fresh home and X11 volumes, not existing
   user data. Stop any existing physical-display container only during the test
   and restart that exact container afterward. Verify Xorg, XFCE, Firefox launch,
   PulseAudio, persistent home data and clean stop/restart. Bluetooth needs host
   kernel support and must be reported as untested if that support is absent.
   Do not run two physical-display containers against the same GPU/VT.
4. Package the sources in numbered tar archives smaller than GitHub's per-asset
   limit, keeping each Debian source package's `.dsc` and referenced files.
   Include a binary/source version manifest and SHA-256 checksums. Upload them
   with the original project source to the GitHub release before publication of
   the binary image. Link that release from the package description.
5. Push the tested version tag, tag the same image `latest`, and push `latest`.
   Set the GHCR package visibility to public (new packages may default to private).
   Verify an unauthenticated pull resolves both tags to the tested digest.
6. Verify the downloaded pull-only Compose example with
   `docker compose -f compose.ghcr.yaml config`. Record exact digest, architecture,
   test results and limitations in the release notes. Never replace a versioned
   release tag with a different image.
