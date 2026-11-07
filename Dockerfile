FROM docker.io/debian:trixie-slim

ARG WINBOX_VERSION=4.5
ARG NOVNC_VERSION=1.7.0

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    QT_QPA_PLATFORM=xcb \
    TINI_SUBREAPER=1

# Xvnc + websockify + nginx (ACL) + openbox, runtime libs of the static Qt build in
# WinBox_Linux.zip, a few network tools for GNS3 topologies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl unzip tini \
        tigervnc-standalone-server tigervnc-tools python3-websockify \
        nginx libnginx-mod-stream \
        openbox xterm x11-utils fonts-dejavu-core \
        libgl1 libegl1 \
        libx11-6 libx11-xcb1 libxcb1 libxcb-glx0 libxcb-icccm4 libxcb-image0 \
        libxcb-keysyms1 libxcb-randr0 libxcb-render0 libxcb-render-util0 \
        libxcb-shape0 libxcb-shm0 libxcb-sync1 libxcb-xfixes0 libxcb-xkb1 \
        libxkbcommon0 libxkbcommon-x11-0 libfreetype6 libfontconfig1 libdbus-1-3 \
        iproute2 iputils-ping udhcpc procps \
    && rm -rf /var/lib/apt/lists/*

# noVNC from upstream, Debian's package drags in nodejs
RUN mkdir -p /usr/share/novnc \
    && curl -fsSL "https://github.com/novnc/noVNC/archive/refs/tags/v${NOVNC_VERSION}.tar.gz" \
        | tar -xz --strip-components=1 -C /usr/share/novnc \
        "noVNC-${NOVNC_VERSION}/app" "noVNC-${NOVNC_VERSION}/core" "noVNC-${NOVNC_VERSION}/vendor" \
        "noVNC-${NOVNC_VERSION}/vnc.html" "noVNC-${NOVNC_VERSION}/vnc_lite.html" \
        "noVNC-${NOVNC_VERSION}/package.json" "noVNC-${NOVNC_VERSION}/LICENSE.txt"

RUN curl -fsSLo /tmp/winbox.zip "https://download.mikrotik.com/routeros/winbox/${WINBOX_VERSION}/WinBox_Linux.zip" \
    && echo "$(curl -fsSL "https://download.mikrotik.com/routeros/winbox/${WINBOX_VERSION}/WinBox_Linux.zip.sha256" | cut -d' ' -f1)  /tmp/winbox.zip" | sha256sum -c - \
    && unzip -q /tmp/winbox.zip -d /opt/winbox \
    && chmod 755 /opt/winbox/WinBox \
    && rm /tmp/winbox.zip \
    && useradd -m -u 1000 -s /bin/bash winbox \
    && mkdir -p /data && chown winbox:winbox /data \
    && mkdir -m 1777 /tmp/.X11-unix

# One desktop, WinBox main windows maximized and undecorated (they follow the
# VNC screen size, noVNC resizes it to the browser window)
RUN sed -i \
        -e 's|<number>4</number>|<number>1</number>|' \
        -e 's|<applications>|<applications>\n  <application class="WinBox" type="normal"><decor>no</decor><maximized>yes</maximized></application>|' \
        -e '\|/var/lib/openbox/debian-menu.xml|d' \
        /etc/xdg/openbox/rc.xml

COPY rootfs/ /

LABEL org.opencontainers.image.title="docker-winbox" \
      org.opencontainers.image.description="MikroTik WinBox ${WINBOX_VERSION} (native Linux) over VNC and noVNC" \
      org.opencontainers.image.source="https://github.com/fcqpl/docker-winbox" \
      com.mikrotik.winbox.version="${WINBOX_VERSION}"

VOLUME /data
EXPOSE 5900 6080
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
