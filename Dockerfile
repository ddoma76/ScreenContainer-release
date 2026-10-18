FROM debian:bookworm-slim

ARG VERSION=development
ARG REVISION=unknown
LABEL org.opencontainers.image.title="ScreenContainer" \
      org.opencontainers.image.description="Containerized XFCE desktop for a Linux host's physical display" \
      org.opencontainers.image.source="https://github.com/ddoma76/ScreenContainer-release" \
      org.opencontainers.image.url="https://github.com/ddoma76/ScreenContainer-release" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        xserver-xorg-core xserver-xorg-input-libinput xserver-xorg-input-evdev \
        libgl1-mesa-dri libglx-mesa0 mesa-vulkan-drivers mesa-va-drivers intel-media-va-driver \
        x11-xserver-utils x11-utils x11-apps xauth xdotool udev \
        dbus dbus-x11 at-spi2-core \
        xfce4 xfce4-terminal xfce4-taskmanager xfce4-notifyd xfce4-pulseaudio-plugin \
        thunar mousepad ristretto \
        adwaita-icon-theme elementary-xfce-icon-theme \
        fonts-dejavu fonts-noto-core fonts-noto-color-emoji \
        firefox-esr \
        pulseaudio pulseaudio-module-bluetooth pavucontrol alsa-utils \
        blueman bluez polkitd \
        sudo procps psmisc less nano curl ca-certificates tzdata locales \
    && rm -rf /var/lib/apt/lists/*

COPY rootfs/ /
COPY LICENSE THIRD_PARTY_NOTICES.md /usr/share/doc/screencontainer/
RUN chmod +x /usr/local/bin/*

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
