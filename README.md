## docker-winbox

[![Build Status](https://img.shields.io/github/actions/workflow/status/fcqpl/docker-winbox/docker-publish.yml?branch=main)](https://github.com/fcqpl/docker-winbox/actions/workflows/docker-publish.yml)

MikroTik [WinBox](https://mikrotik.com/download/winbox) 4.x in a container, reachable from a browser (noVNC) or any VNC client.

Inspired by [alexhorner/winbox-dockerised](https://github.com/alexhorner/winbox-dockerised), but:

- native Linux build of WinBox 4, no Wine
- Debian trixie, TigerVNC `Xvnc`, openbox
- noVNC on port 6080: open it in a browser, WinBox fills the tab and follows its size
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
| `LISTEN` | empty | Address to bind VNC and noVNC to, e.g. `127.0.0.1` behind a reverse proxy or SSH tunnel. Empty = all |
| `PUID` / `PGID` | `1000` | UID/GID WinBox runs as, owner of `/data` |
| `EXTERNAL_DISPLAY` | `false` | `true` = no built-in VNC, WinBox goes to the X display in `DISPLAY` (GNS3) |

Without `VNC_PASSWORD` anyone who reaches the ports gets the WinBox screen, including saved sessions. Set a password or `LISTEN` when the host is not on a trusted network.

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
