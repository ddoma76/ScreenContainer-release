#!/bin/bash
# Copies the project to the NAS and (re)builds/starts the container.
#   ./deploy.sh <ssh-host> [remote-directory]
set -euo pipefail
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ -z "$1" ]; then
    echo "usage: ./deploy.sh <ssh-host> [remote-directory]" >&2
    exit 2
fi
HOST=$1
REMOTE_DIR=${2:-/opt/screen/app}
printf -v REMOTE_DIR_QUOTED '%q' "$REMOTE_DIR"
cd "$(dirname "$0")"

ssh "$HOST" "sudo mkdir -p $REMOTE_DIR_QUOTED && sudo chown \$(id -u):\$(id -g) $REMOTE_DIR_QUOTED"
tar --exclude=.vscode --exclude=data -czf - . | ssh "$HOST" "tar -xzf - -C $REMOTE_DIR_QUOTED"
ssh "$HOST" "cd $REMOTE_DIR_QUOTED && sudo docker compose up -d --build && sudo docker compose ps"
