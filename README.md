## docker-winbox

[![Build Status](https://img.shields.io/github/actions/workflow/status/fcqpl/docker-winbox/docker-publish.yml?branch=main)](https://github.com/fcqpl/docker-winbox/actions/workflows/docker-publish.yml)

MikroTik [WinBox](https://mikrotik.com/download/winbox) 4.x in a container, reachable from a browser (noVNC) or any VNC client.

Inspired by [alexhorner/winbox-dockerised](https://github.com/alexhorner/winbox-dockerised), but:

- native Linux build of WinBox 4, no Wine
- Debian trixie, TigerVNC `Xvnc`, openbox
- noVNC on port 6080: open it in a browser, WinBox fills the tab and follows its size
- ACL: only private networks get in by default (`ALLOW`)
- settings, saved addresses and workspaces kept in `/data`
- rebuilt every week with the latest stable WinBox

### Quick start

```
docker run -d --name winbox --network host -v ./data:/data ghcr.io/fcqpl/docker-winbox
```

Then open `http://<docker-host>:6080/` or point a VNC client at `<docker-host>:5900`.

Host networking lets WinBox see MikroTik neighbors and connect by MAC address on the host's L2 segments. Without it only IP connections work:

```
docker run -d --name winbox -p 6080:6080 -p 5900:5900 -v ./data:/data ghcr.io/fcqpl/docker-winbox
```

#### docker-compose.yml

```
services:
  winbox:
    image: ghcr.io/fcqpl/docker-winbox:latest
    container_name: winbox
    restart: unless-stopped
    network_mode: host
    environment:
      VNC_PASSWORD: changeme
    volumes:
      - ./data:/data
```

### Environment variables

| Variable | Default | |
|---|---|---|
| `RESOLUTION` | `1600x900` | Initial screen size, noVNC and VNC clients with remote resize change it on the fly |
| `DEPTH` | `24` | Colour depth |
| `VNC_PASSWORD` | empty | VNC (and noVNC) password, VNC auth uses only the first 8 characters. Empty = no password |
| `VNC_PORT` | `5900` | VNC port |
| `NOVNC` | `true` | `false` disables noVNC |
| `NOVNC_PORT` | `6080` | noVNC port |
| `ALLOW` | private ranges | Networks allowed to reach VNC and noVNC, comma or space separated, `all` = anyone. Default: `127.0.0.0/8 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 fc00::/7 fe80::/10` |
| `LISTEN` | empty | Addresses to bind VNC and noVNC to, comma separated, e.g. `127.0.0.1,::1` behind a reverse proxy or SSH tunnel. Empty = all |
| `PUID` / `PGID` | `1000` | UID/GID WinBox runs as, owner of `/data` |
| `EXTERNAL_DISPLAY` | `false` | `true` = no built-in VNC, WinBox goes to the X display in `DISPLAY` (GNS3) |

### Access control

Xvnc and websockify listen only on unix sockets inside the container. The TCP ports are served by nginx, which checks the client address against `ALLOW` (`allow`/`deny` rules, first match wins) and logs refused clients to the container log:

```
[error] access forbidden by rule while initializing session, client: 203.0.113.7, server: 0.0.0.0:5900
```

By default only private, CGNAT, loopback and link-local addresses get in, so a host with a public address does not expose WinBox to the internet. Examples:

```
-e ALLOW="10.105.0.0/16, 2001:db8:100::/48"
-e ALLOW=all
```

nginx sees the address the connection comes from. With `--network host` that is the real client. With published ports (`-p`) IPv4 clients usually keep their address, but connections that go through `docker-proxy` (IPv6 clients of an IPv4-only container, hairpin, hosts with the userland proxy) show up as the Docker gateway, e.g. `172.17.0.1`, which the default list allows. Use host networking or publish on IPv4 only (`-p 0.0.0.0:6080:6080`) if that matters.

`ALLOW` is not a password: without `VNC_PASSWORD` anyone in the allowed networks gets the WinBox screen, including saved sessions.

### Use with GNS3

- Preferences > Docker containers > New > New image: `ghcr.io/fcqpl/docker-winbox:latest`
- Network adapters: 1 (or more)
- Start command: empty
- Console type: VNC
- Environment: `EXTERNAL_DISPLAY=true`

WinBox discovers devices on the node's adapters. Right-click on the desktop opens a menu with a terminal (`ip`, `ping` and `udhcpc` are in the image) and a second WinBox.

### Building

```
docker build -t docker-winbox .
docker build --build-arg WINBOX_VERSION=4.5 -t docker-winbox:4.5 .
```

| Build arg | Default |
|---|---|
| `WINBOX_VERSION` | `4.5` |
| `NOVNC_VERSION` | `1.7.0` |

WinBox is downloaded from download.mikrotik.com at build time and checked against MikroTik's published SHA256. The GitHub workflow builds with the latest stable version listed on mikrotik.com every Monday and tags the image `latest` and `<WinBox version>`.

WinBox's own updater cannot replace the binary inside the image, pull a newer image instead.

### License

Scripts and Dockerfile: MIT, see [LICENSE](LICENSE). WinBox is © MikroTik and is used unmodified, under MikroTik's terms.
