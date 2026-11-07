#!/bin/bash

: "${RESOLUTION:=1600x900}"
: "${DEPTH:=24}"
: "${VNC_PORT:=5900}"
: "${VNC_PASSWORD:=}"
: "${NOVNC:=true}"
: "${NOVNC_PORT:=6080}"
: "${LISTEN:=}"
: "${ALLOW:=127.0.0.0/8 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 fc00::/7 fe80::/10}"
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
    # Xvnc and websockify only on unix sockets, nginx in front of them does
    # the TCP ports and the ALLOW list
    run=/tmp/winbox
    mkdir -p "$run/nginx"

    echo "Xvnc $DISPLAY ${RESOLUTION}x$DEPTH"
    Xvnc "$DISPLAY" -geometry "$RESOLUTION" -depth "$DEPTH" -rfbport -1 -rfbunixpath "$run/vnc.sock" \
        "${vnc_auth[@]}" -AlwaysShared -nolisten tcp -nolisten local &
    pids+=($!)

    if [ "$NOVNC" = true ]; then
        websockify --unix-listen="$run/websockify.sock" --unix-target="$run/vnc.sock" >/dev/null 2>&1 &
        pids+=($!)
    fi

    # Empty LISTEN = all interfaces
    listen() {
        local a
        if [ -z "$LISTEN" ]; then
            echo "listen $1;"
            [ -e /proc/net/if_inet6 ] && echo "listen [::]:$1;"
        else
            for a in ${LISTEN//,/ }; do
                [[ $a == *:* ]] && a="[$a]"
                echo "listen $a:$1;"
            done
        fi
    }
    acl=""
    for a in ${ALLOW//,/ }; do
        acl+="allow $a; "
    done
    acl+="deny all;"

    echo "VNC on ${LISTEN:-*}:$VNC_PORT, allowed from: $ALLOW"
    cat > "$run/nginx/nginx.conf" <<EOF
load_module /usr/lib/nginx/modules/ngx_stream_module.so;
daemon off;
pid $run/nginx/nginx.pid;
error_log stderr warn;
worker_processes 1;
events { worker_connections 256; }

stream {
    server {
        $(listen "$VNC_PORT")
        $acl
        proxy_pass unix:$run/vnc.sock;
        proxy_timeout 1d;
    }
}
EOF
    if [ "$NOVNC" = true ]; then
        echo "noVNC on ${LISTEN:-*}:$NOVNC_PORT, allowed from: $ALLOW"
        cat >> "$run/nginx/nginx.conf" <<EOF

http {
    include /etc/nginx/mime.types;
    access_log off;
    client_body_temp_path $run/nginx/body;
    proxy_temp_path $run/nginx/proxy;
    fastcgi_temp_path $run/nginx/fastcgi;
    uwsgi_temp_path $run/nginx/uwsgi;
    scgi_temp_path $run/nginx/scgi;

    server {
        $(listen "$NOVNC_PORT")
        $acl
        root /usr/share/novnc;

        location = /websockify {
            proxy_pass http://unix:$run/websockify.sock;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection upgrade;
            proxy_read_timeout 1d;
            proxy_send_timeout 1d;
        }
    }
}
EOF
    fi
    nginx -e stderr -c "$run/nginx/nginx.conf" &
    pids+=($!)
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

# Xvnc, websockify or nginx dying ends the container
wait -n "${pids[@]}"
