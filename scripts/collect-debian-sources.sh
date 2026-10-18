#!/bin/bash
# Run as root in a disposable release-image container with /sources mounted.
set -euo pipefail
if [ "$(id -u)" != 0 ] || [ ! -d /sources ]; then
    echo "Run as root in a disposable container with an output directory mounted at /sources." >&2
    exit 1
fi
cd /sources
dpkg-query -W '-f=${binary:Package}\t${Version}\t${source:Package}\t${source:Version}\n' \
    > binary-packages.tsv
dpkg-query -W '-f=${source:Package}=${source:Version}\n' | sort -u > source-packages.txt
sed 's/^Types: deb$/Types: deb-src/' /etc/apt/sources.list.d/debian.sources \
    > /etc/apt/sources.list.d/release-sources.sources
apt-get update
while IFS= read -r source; do
    apt-get source --download-only "$source"
done < source-packages.txt
find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 \
    | sort -z | xargs -0 sha256sum > SHA256SUMS
