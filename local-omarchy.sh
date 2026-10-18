#!/usr/bin/env bash
# Run with: bash local-omarchy.sh
# Starts the project's XFCE desktop in a Xephyr window inside Omarchy/Xwayland.
# This bypasses the physical-display entrypoint: no GPU/VT takeover, privileged
# container, host D-Bus, or Bluetooth adapter access. Audio stays in the container.
set -euo pipefail
cd "$(dirname "$0")"

# 1. Install missing prerequisites from an Omarchy terminal, then rerun:
#    omarchy pkg add docker docker-compose xorg-server-xephyr xorg-xauth xorg-xdpyinfo
#    sudo systemctl enable --now docker
# Run this script as your normal desktop user, not with sudo.
if [ "$(id -u)" -eq 0 ] || [ -z "${DISPLAY:-}" ]; then
    echo "Run as your normal user from an Omarchy terminal with Xwayland available." >&2
    exit 1
fi
for tool in docker Xephyr xauth xdpyinfo mcookie; do
    if ! command -v "$tool" >/dev/null; then
        echo "Missing $tool; follow step 1 in this script." >&2
        exit 1
    fi
done
engine=(docker)
if ! docker info >/dev/null 2>&1; then
    if [ -t 0 ]; then
        echo "Checking Docker with sudo (you may be prompted for your password)."
        engine=(sudo docker)
    else
        echo "Checking Docker with graphical authorization."
        engine=(pkexec docker)
    fi
    "${engine[@]}" info >/dev/null
fi

# 2. Build the existing project image. Do not use the physical-display Compose file.
"${engine[@]}" build -t screen-desktop:omarchy "$PWD"

# 3. Reserve a separate nested display and prepare private X authentication.
display_num=""
for number in $(seq 100 199); do
    if [ ! -e "/tmp/.X11-unix/X$number" ] && [ ! -e "/tmp/.X$number-lock" ]; then
        display_num=$number
        break
    fi
done
if [ -z "$display_num" ]; then
    echo "No unused nested X display found in :100 through :199." >&2
    exit 1
fi
state=$(mktemp -d)
xephyr_pid=""
attach_pid=""
container_name="screen-omarchy-$$"
container_started=false
cleanup() {
    result=$?
    trap - EXIT
    if [ "$container_started" = true ]; then
        if ! "${engine[@]}" stop --time 5 "$container_name" >/dev/null; then
            echo "Could not stop $container_name; check docker ps -a." >&2
        elif ! "${engine[@]}" rm "$container_name" >/dev/null; then
            echo "Could not remove stopped container $container_name." >&2
        fi
    fi
    if [ -n "$xephyr_pid" ] && kill -0 "$xephyr_pid" 2>/dev/null; then
        kill "$xephyr_pid"
        wait "$xephyr_pid" || :
    fi
    if [ -n "$attach_pid" ]; then
        wait "$attach_pid" || :
    fi
    rm -f "$state/Xauthority" "$state/xephyr.log"
    rmdir "$state"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
touch "$state/Xauthority"
xauth -f "$state/Xauthority" add ":$display_num" . "$(mcookie)"

# 4. Open a nested X server as an ordinary window. Never use xhost + or Xephyr -ac.
Xephyr ":$display_num" -screen 1280x800 -resizeable -noreset -nolisten tcp \
    -auth "$state/Xauthority" -title "ScreenContainer - XFCE" \
    >"$state/xephyr.log" 2>&1 &
xephyr_pid=$!
ready=false
for _ in $(seq 1 100); do
    if ! kill -0 "$xephyr_pid" 2>/dev/null; then
        cat "$state/xephyr.log" >&2
        exit 1
    fi
    if DISPLAY=":$display_num" XAUTHORITY="$state/Xauthority" xdpyinfo >/dev/null 2>&1; then
        ready=true
        break
    fi
    sleep 0.1
done
if [ "$ready" != true ]; then
    echo "Xephyr did not become ready." >&2
    cat "$state/xephyr.log" >&2
    exit 1
fi

# 5. Create an isolated container with its own persistent Docker home volume.
# The hostname matches the local Xauthority entry. Only the nested X socket is
# mounted; the container cannot access the main Xwayland socket through this mount.
"${engine[@]}" create --name "$container_name" \
    --hostname "$(hostname)" --shm-size 1g \
    --env DISPLAY=":$display_num" --env XAUTHORITY=/run/nested.Xauthority \
    --env PUID="$(id -u)" --env PGID="$(id -g)" \
    --mount "type=bind,src=/tmp/.X11-unix/X$display_num,dst=/tmp/.X11-unix/X$display_num,readonly" \
    --mount "type=bind,src=$state/Xauthority,dst=/run/nested.Xauthority,readonly" \
    --mount type=volume,src=screen-omarchy-home,dst=/home/screen \
    --entrypoint /bin/bash screen-desktop:omarchy -euc '
        if ! getent group "$PGID" >/dev/null; then
            groupadd -g "$PGID" screen
        fi
        useradd -M -u "$PUID" -g "$PGID" -d /home/screen -s /bin/bash screen
        if [ -z "$(ls -A /home/screen)" ]; then
            cp -rT /etc/skel /home/screen
            chown -R "$PUID:$PGID" /home/screen
        fi
        chown "$PUID:$PGID" /home/screen
        install -d -m 700 -o "$PUID" -g "$PGID" "/run/user/$PUID"
        install -d -m 1777 /tmp/.ICE-unix
        mkdir -p /run/dbus
        dbus-daemon --system --fork
        # This mode deliberately has no Bluetooth adapter.
        rm -f /etc/xdg/autostart/blueman.desktop
        # Copy authentication so the desktop user can read it without exposing
        # the private host-side file to other host users.
        install -m 600 -o "$PUID" -g "$PGID" /run/nested.Xauthority /home/screen/.nested.Xauthority
        exec runuser -u screen -- env HOME=/home/screen USER=screen LOGNAME=screen \
            XAUTHORITY=/home/screen/.nested.Xauthority XDG_RUNTIME_DIR="/run/user/$PUID" \
            XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=XFCE \
            dbus-run-session -- startxfce4
    ' >/dev/null
container_started=true
# Keep an unprivileged wrapper PID: kill -0 cannot probe a root-owned pkexec PID.
(
    "${engine[@]}" start --attach "$container_name"
    exit "$?"
) &
attach_pid=$!

# 6. Wait for the session. Closing the window or pressing Ctrl+C stops the container.
# Desktop files survive in screen-omarchy-home. Run this script again to reopen.
echo "Starting XFCE in the Xephyr window. Close it or press Ctrl+C here to stop."
while kill -0 "$xephyr_pid" 2>/dev/null; do
    if ! kill -0 "$attach_pid" 2>/dev/null; then
        if ! kill -0 "$xephyr_pid" 2>/dev/null; then
            break
        fi
        echo "The desktop container exited; see its output above." >&2
        exit 1
    fi
    sleep 2
done
