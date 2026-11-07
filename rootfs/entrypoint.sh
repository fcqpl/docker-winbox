#!/bin/bash

: "${RESOLUTION:=1600x900}"
: "${DEPTH:=24}"
: "${VNC_PORT:=5900}"
: "${VNC_PASSWORD:=}"
: "${NOVNC:=true}"
: "${NOVNC_PORT:=6080}"
: "${LISTEN:=}"
: "${EXTERNAL_DISPLAY:=false}"
: "${PUID:=1000}"
: "${PGID:=1000}"

# Started as root: match the winbox user to PUID/PGID, then drop privileges
if [ "$(id -u)" = 0 ]; then
    [ "$(id -g winbox)" = "$PGID" ] || groupmod -o -g "$PGID" winbox
    [ "$(id -u winbox)" = "$PUID" ] || usermod -o -u "$PUID" winbox
    chown -R winbox:winbox /data
    exec setpriv --reuid=winbox --regid=winbox --init-groups "$0" "$@"
fi

export HOME=/data
cd "$HOME" || exit 1

if [ "$EXTERNAL_DISPLAY" = true ]; then
    # GNS3 and similar: the X server comes from outside, DISPLAY must point to it
    if [ -z "$DISPLAY" ]; then
        echo "EXTERNAL_DISPLAY=true needs DISPLAY" >&2
        exit 1
    fi
    echo "Using external display $DISPLAY"
else
    export DISPLAY=:0
    vnc_auth=(-SecurityTypes None)
    if [ -n "$VNC_PASSWORD" ]; then
        mkdir -p "$HOME/.vnc"
        printf '%s\n' "$VNC_PASSWORD" | vncpasswd -f > "$HOME/.vnc/passwd"
        chmod 600 "$HOME/.vnc/passwd"
        vnc_auth=(-SecurityTypes VncAuth -rfbauth "$HOME/.vnc/passwd")
    fi
    # Empty LISTEN = all interfaces
    vnc_listen=()
    [ -n "$LISTEN" ] && vnc_listen=(-interface "$LISTEN")

    echo "Xvnc $DISPLAY ${RESOLUTION}x$DEPTH on ${LISTEN:-*}:$VNC_PORT"
    Xvnc "$DISPLAY" -geometry "$RESOLUTION" -depth "$DEPTH" -rfbport "$VNC_PORT" \
        "${vnc_listen[@]}" "${vnc_auth[@]}" -AlwaysShared -nolisten tcp &
    pids+=($!)

    if [ "$NOVNC" = true ]; then
        echo "noVNC on ${LISTEN:-*}:$NOVNC_PORT"
        websockify --web /usr/share/novnc "${LISTEN:+$LISTEN:}$NOVNC_PORT" "${LISTEN:-localhost}:$VNC_PORT" >/dev/null 2>&1 &
        pids+=($!)
    fi
fi

until xdpyinfo >/dev/null 2>&1; do
    sleep 0.2
done

# Not supervised: an external display may already have a window manager
openbox &

# Closing the WinBox window just starts a new one
while true; do
    /opt/winbox/WinBox "$@"
    sleep 1
done &
pids+=($!)

# Xvnc or websockify dying ends the container
wait -n "${pids[@]}"
