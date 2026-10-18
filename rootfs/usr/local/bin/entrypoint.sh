#!/bin/bash
# Starts a real Xorg server on the host GPU (HDMI/DP output) and an XFCE desktop session.
set -uo pipefail

USER_NAME=${USER_NAME:-screen}
PUID=${PUID:-1000}
PGID=${PGID:-1000}
DISPLAY_NUM=${DISPLAY_NUM:-0}
VT=${VT:-7}
KMS_DEVICE=${KMS_DEVICE:-/dev/dri/card0}
XKB_LAYOUT=${XKB_LAYOUT:-us}
XKB_VARIANT=${XKB_VARIANT:-}
XKB_OPTIONS=${XKB_OPTIONS:-}
SCREEN_BLANK_MINUTES=${SCREEN_BLANK_MINUTES:-0}
ENABLE_SUDO=${ENABLE_SUDO:-false}
export DISPLAY=":${DISPLAY_NUM}"
export USER_NAME PUID

log() { echo "[screen] $*"; }

# ---------------------------------------------------------------- user setup
if ! getent group "$PGID" >/dev/null; then
    groupadd -g "$PGID" "$USER_NAME"
fi
if ! id "$USER_NAME" &>/dev/null; then
    useradd -M -d "/home/$USER_NAME" -u "$PUID" -g "$PGID" -s /bin/bash "$USER_NAME"
fi
HOME_DIR="/home/$USER_NAME"
if [ ! -d "$HOME_DIR" ] || [ -z "$(ls -A "$HOME_DIR" 2>/dev/null)" ]; then
    mkdir -p "$HOME_DIR"
    cp -rT /etc/skel "$HOME_DIR"
    chown -R "$PUID:$PGID" "$HOME_DIR"
fi
chown "$PUID:$PGID" "$HOME_DIR"

usermod -aG bluetooth "$USER_NAME"

# Give the user access to GPU, sound and input devices using the host's group ids.
for dev in /dev/dri/* /dev/snd/* /dev/input/event*; do
    [ -c "$dev" ] || continue
    gid=$(stat -c %g "$dev")
    [ "$gid" = 0 ] && continue
    grp=$(getent group "$gid" | cut -d: -f1)
    if [ -z "$grp" ]; then
        grp="hostgid$gid"
        groupadd -g "$gid" "$grp"
    fi
    usermod -aG "$grp" "$USER_NAME"
done

if [ "$ENABLE_SUDO" = "true" ]; then
    echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/screen-user
else
    rm -f /etc/sudoers.d/screen-user
fi

export XDG_RUNTIME_DIR="/run/user/$PUID"
mkdir -p "$XDG_RUNTIME_DIR"
chown "$PUID:$PGID" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

mkdir -p /run/dbus
rm -f /run/dbus/pid
dbus-daemon --system --fork || log "warning: system dbus failed to start"

(
    if ! /usr/libexec/bluetooth/bluetoothd --nodetach; then
        log "warning: BlueZ failed; check host Bluetooth kernel support"
    fi
) &

# ---------------------------------------------------------------- Xorg config
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/10-gpu.conf <<EOF
Section "ServerFlags"
    Option "AutoAddGPU" "false"
EndSection

Section "Device"
    Identifier "gpu0"
    Driver     "modesetting"
    Option     "kmsdev" "${KMS_DEVICE}"
EndSection
EOF

{
    echo 'Section "InputClass"'
    echo '    Identifier      "keyboard-layout"'
    echo '    MatchIsKeyboard "on"'
    echo "    Option \"XkbLayout\"  \"${XKB_LAYOUT}\""
    [ -n "$XKB_VARIANT" ] && echo "    Option \"XkbVariant\" \"${XKB_VARIANT}\""
    [ -n "$XKB_OPTIONS" ] && echo "    Option \"XkbOptions\" \"${XKB_OPTIONS}\""
    echo 'EndSection'
} > /etc/X11/xorg.conf.d/20-keyboard.conf

# ---------------------------------------------------------------- start Xorg
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix
rm -f "/tmp/.X11-unix/X${DISPLAY_NUM}" "/tmp/.X${DISPLAY_NUM}-lock"

log "starting Xorg on ${DISPLAY} (vt${VT}, ${KMS_DEVICE})"
Xorg "$DISPLAY" "vt${VT}" -nolisten tcp -noreset -keeptty \
    -logfile /var/log/Xorg.log -verbose 3 &
XPID=$!

for _ in $(seq 1 60); do
    xdpyinfo >/dev/null 2>&1 && break
    kill -0 "$XPID" 2>/dev/null || { log "Xorg exited, see log:"; tail -n 50 /var/log/Xorg.log; exit 1; }
    sleep 0.5
done
xdpyinfo >/dev/null 2>&1 || { log "Xorg did not come up"; tail -n 50 /var/log/Xorg.log; exit 1; }
log "Xorg is up"

# Any local process (other containers sharing the socket / host network) may draw on this screen.
xhost +local: >/dev/null

if [ "$SCREEN_BLANK_MINUTES" = "0" ]; then
    xset s off -dpms
else
    secs=$((SCREEN_BLANK_MINUTES * 60))
    xset s "$secs" "$secs" +dpms
    xset dpms "$secs" "$secs" "$secs"
fi

# ---------------------------------------------------------------- monitor hotplug
# Re-probe outputs whenever a connector changes state so newly attached monitors light up.
(
    prev=""
    while kill -0 "$XPID" 2>/dev/null; do
        cur=$(cat /sys/class/drm/card*-*/status 2>/dev/null | tr '\n' ' ')
        if [ "$cur" != "$prev" ]; then
            [ -n "$prev" ] && log "display connectors changed: $cur"
            # With nothing connected, keep the current framebuffer instead of shrinking it.
            if [[ "$cur" == *" connected"* || "$cur" == connected* ]]; then
                xrandr --auto >/dev/null 2>&1
            fi
            prev="$cur"
        fi
        sleep 3
    done
) &

# ---------------------------------------------------------------- session
STOPPING=0
SPID=""
shutdown() {
    STOPPING=1
    log "stopping"
    [ -n "$SPID" ] && kill "$SPID" 2>/dev/null
    pkill -TERM -u "$USER_NAME" 2>/dev/null
    sleep 1
    kill "$XPID" 2>/dev/null
    wait "$XPID" 2>/dev/null
    exit 0
}
trap shutdown TERM INT

while kill -0 "$XPID" 2>/dev/null && [ "$STOPPING" = 0 ]; do
    log "starting desktop session for $USER_NAME"
    runuser -u "$USER_NAME" -- env -i \
        HOME="$HOME_DIR" USER="$USER_NAME" LOGNAME="$USER_NAME" SHELL=/bin/bash \
        PATH=/usr/local/bin:/usr/bin:/bin LANG="$LANG" TZ="${TZ:-}" \
        DISPLAY="$DISPLAY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
        XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=XFCE \
        AUTOSTART="${AUTOSTART:-}" \
        dbus-run-session -- startxfce4 &
    SPID=$!
    wait "$SPID"
    SPID=""
    [ "$STOPPING" = 1 ] && break
    log "session ended, restarting in 2s"
    sleep 2
done

kill -0 "$XPID" 2>/dev/null || log "Xorg exited"
exit 1
