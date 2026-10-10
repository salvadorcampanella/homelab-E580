# Casita Homelab — Agent and Docker Standards Guide

> Reference document for AI agents and human administrators.
> All modifications or additions of services **must** follow these rules.
> **Mandatory Rule**: All code comments and technical documentation within files MUST be in English.

---

## 1. Overview

| Concept        | Value                                                   |
|----------------|---------------------------------------------------------|
| **Hardware**   | Lenovo ThinkPad E580                                    |
| **OS**         | Ubuntu Server (LTS recommended)                         |
| **Engine**     | Docker Engine + Docker Compose v2                       |
| **Proxy**      | Nginx Proxy Manager (NPM)                               |
| **Access**     | Via Wireguard only (installed on homelab router)        |
| **Local DNS**  | Pi-hole                                                 |
| **DDNS**       | DuckDNS (`casitaogrove.duckdns.org`) + Cloudflare CNAME (`*.salvador512.com`) |

### Network Diagram

```
Internet
   │
   ▼
[Router + Wireguard VPN]
   │
   ├── Remote clients (via WG tunnel)
   │
   ▼
[Lenovo E580 — Docker Host]
   │
   ├── port 53   → Pi-hole (DNS)
   ├── port 80   → NPM (HTTP)
   ├── port 81   → NPM (Admin UI)
   ├── port 443  → NPM (HTTPS)
   ├── port 6881 → qBittorrent (torrents)
   │
   └── [Internal Network: proxy-nw] ──────────────────────┐
       │                                                  │
       ├── pihole              (internal web :80)         │
       ├── portainer           (internal web :9443)       │
       ├── radarr              (internal web :7878)       │
       ├── sonarr              (internal web :8989)       │
       ├── prowlarr            (internal web :9696)       │
       ├── bazarr              (internal web :6767)       │
       ├── qbittorrent         (internal web :8080)       │
       ├── jellyfin            (internal web :8096)       │
       ├── flaresolverr        (internal api :8191)       │
       ├── homepage            (internal web :3000)       │
       ├── glances             (internal api+web :61208)  │
       ├── photoprism-personal (internal web :2342)       │
       ├── photoprism-compartido (internal web :2342)     │
       ├── tdarr               (internal web :8265)       │
       └── ...other services                              │
                                                          │
       NPM reverse proxies to all ◄───────────────────────┘

[duckdns] — uses network_mode: host to detect public IP
```

---

## 2. Project Structure

```
casita-dockercompose/
├── docker-compose.yml           # Root orchestrator (uses 'include')
├── .env.template                # Environment variables template
├── .env                         # Real variables (⚠️ DO NOT commit to Git)
├── .gitignore                   # Protects .env and sensitive files
├── README.md                    # Human-readable instructions
├── agents.md                    # This file — guide for AI agents
│
├── proxy/                       # 🔒 Nginx Proxy Manager + MariaDB
│   ├── docker-compose.yml
│   └── setup-npm-hosts.sh       # Automated host configuration script
├── pihole/                      # 🛡️ DNS + Ad-blocker
│   └── docker-compose.yml
├── portainer/                   # 📦 Visual Docker management
│   └── docker-compose.yml
├── duckdns/                     # 🌐 Dynamic DNS
│   └── docker-compose.yml
├── arr/                         # 🎬 Media stack
│   └── docker-compose.yml       #    Radarr, Sonarr, Prowlarr, Bazarr, qBit, Jellyfin, FlareSolverr

├── homepage/                    # 🏠 Homelab Dashboard + System monitor
│   ├── docker-compose.yml       #    Homepage + Glances
│   └── config/                  #    settings, services, widgets, docker, bookmarks
└── <new-service>/               # Each service in its own folder
    └── docker-compose.yml
```

### Persistent Host Data

```
/home/casita/docker-data/       # ${DOCKER_DATA_PATH}
├── npm/
│   ├── config/
│   ├── letsencrypt/
│   └── mysql/
├── pihole/
│   ├── config/
│   └── dnsmasq/
├── portainer/
├── duckdns/
│   ├── config/
│   └── config/
├── arr/
│   ├── radarr/
│   ├── sonarr/
│   ├── prowlarr/
│   ├── bazarr/
│   ├── qbittorrent/
│   ├── jellyfin/
│   └── downloads/              # ← shared between qBit, Radarr and Sonarr
├── media/
│   ├── movies/                 # ← shared between Radarr, Bazarr and Jellyfin
│   └── tv/                     # ← shared between Sonarr, Bazarr and Jellyfin

├── homepage/
│   └── config/                 # settings, services, widgets, docker, bookmarks
└── <new-service>/
```

---

## 3. Mandatory Conventions

### 3.1 One service = one folder = one docker-compose.yml

- Each service (or logical group) must live in its own folder.
- Folder names must be descriptive and lowercase: `my-service/`.
- Only one `docker-compose.yml` per folder.
- **Comments must be in English.**

### 3.2 Shared Network: `proxy-nw`

- `proxy-nw` is **created** by the `proxy/` compose. All other services must declare it as `external: true`.
- **No web service exposes ports to the host** except NPM (80, 81, 443).
- Services are accessible **only** through NPM using the container name as internal hostname.
- **Documented Exceptions**: Pi-hole (53) and qBittorrent (6881). Any other exception must be documented with a comment.

```yaml
# ✅ CORRECT — in any service other than proxy/
networks:
  proxy-nw:
    external: true

# ❌ INCORRECT — do not redefine the network
networks:
  proxy-nw:
    name: proxy-nw
    driver: bridge
```

### 3.3 Environment Variables

- **Never hardcode passwords** in `docker-compose.yml` files.
- All sensitive variables must be defined in `.env` (root).
- `.env.template` must document all required variables with placeholders.
- Use `${VARIABLE:-default_value}` for non-sensitive values only.

```yaml
# ✅ CORRECT
environment:
  PASSWORD: ${MY_SERVICE_PASSWORD}
  TZ: ${TZ:-Europe/Madrid}

# ❌ INCORRECT
environment:
  PASSWORD: 'myPassword123'
```

### 3.4 Volumes and Persistence

- **Do not use Docker named volumes** for app data. Use bind mounts.
- Base path is `${DOCKER_DATA_PATH}` (defined in `.env`, value: `/home/casita/docker-data`).
- Structure: `${DOCKER_DATA_PATH}/<service-name>/<subdir>`.
- Mount as **read-only** (`:ro`) when write access is not needed.

```yaml
# ✅ CORRECT
volumes:
  - ${DOCKER_DATA_PATH}/my-service/config:/app/config
  - ${DOCKER_DATA_PATH}/media/movies:/movies:ro   # read-only where applicable

# ❌ INCORRECT — named volume
volumes:
  my_data:
    name: my_data

# ❌ INCORRECT — relative path
volumes:
  - ./data:/app/data
```

### 3.5 Container Names

- Always use explicit `container_name`.
- Lowercase, dash-separated: `my-service`.
- For internal databases, prefix with the service name: `my-service-db`.

### 3.6 Restart Policy

- Always use `restart: unless-stopped`.

### 3.7 Images

- Prefer specific tags (`:lts`, `:v6`) over `:latest` in production.
- For the *arr* stack and Jellyfin, always use **linuxserver.io** images.

### 3.8 Registration in Orchestrator and NPM Script

When adding a new service, update **two** places:

**1. `docker-compose.yml` (root):**
```yaml
include:
  - path: ./new-service/docker-compose.yml
```

**2. `proxy/setup-npm-hosts.sh` (or `proxy/setup_https_and_301_redirects.py`):**
Add service entry to `SERVICES` list:
```bash
"new-service|new-service|PORT|http|"
```
This automatically configures:
- Primary HTTPS Proxy Host: `https://new-service.salvador512.com` (SSL forced).
- Local 301 Redirection Host: `http://new-service.casita.local` -> `301` -> `https://new-service.salvador512.com`.

### 3.9 Hardware Acceleration (Intel QuickSync)

Services requiring GPU access for transcoding or processing (like Jellyfin or PhotoPrism) must use a reusable YAML anchor `x-gpu-access` defined at the top of their respective `docker-compose.yml`. This maps `/dev/dri/renderD128` and `/dev/dri/card1` to the container and adds the `video` (44) and `render` (992) groups.

---

## 4. How to Add a New Service — Checklist

1. Create folder and `docker-compose.yml` (follow standard template).
2. Add variables to `.env.template`.
3. Register in root `docker-compose.yml`.
4. Add to `proxy/setup-npm-hosts.sh`.
5. Create host data directories (`mkdir -p`).
6. Update `README.md` services table.
7. Deploy and verify (`docker compose up -d`).

---

## 5. Active Services — Implementation Notes

### 5.1 Nginx Proxy Manager + Setup Script 🔒

- Main entry point via Wireguard.
- `proxy-nw` network creator.
- `proxy/setup-npm-hosts.sh` configures hosts via NPM REST API.
- Idempotent: detects existing hosts.

### 5.2 DuckDNS 🌐

- Updates public IP.
- Uses `network_mode: host`.

### 5.3 Stack *arr* + Jellyfin 🎬

| Service     | Container     | Internal Port |
|-------------|---------------|---------------|
| Radarr      | `radarr`      | 7878          |
| Sonarr      | `sonarr`      | 8989          |
| Prowlarr    | `prowlarr`    | 9696          |
| Bazarr      | `bazarr`      | 6767          |
| qBittorrent | `qbittorrent` | 8080 (web)    |
| Jellyfin    | `jellyfin`    | 8096          |
| Tdarr       | `tdarr`       | 8265          |

- **Jellyfin**: Uses Intel QuickSync (VAAPI) for hardware transcoding via the `x-gpu-access` anchor.
- **Tdarr**: Automated batch transcoding. Re-encodes files >8 GB to H.264 (AVC) using Intel QuickSync (VAAPI) and applies HDR→SDR tone mapping. Uses the `x-gpu-access` anchor. See `arr/TDARR_SETUP.md` for post-deploy configuration.


### 5.4 FlareSolverr 🔥

- HTTP Proxy to bypass Cloudflare protection for Prowlarr indexers.
- Internal use only — no NPM Proxy Host needed.

### 5.5 Homepage + Glances 🏠

Homelab dashboard with real-time system metrics.

| Parameter     | Homepage                        | Glances                         |
|---------------|---------------------------------|---------------------------------|
| Image         | `ghcr.io/gethomepage/homepage`  | `nicolargo/glances:latest-full` |
| Internal Port | `3000`                          | `61208`                         |
| Access        | `homepage.casita.local`         | `glances.casita.local`          |

### 5.6 PhotoPrism 📸

Two separate instances of PhotoPrism running side-by-side using a single MariaDB database container with two schemas.

| Instance    | Container Name          | Database Schema        | Mounted Directory                           | Domain                 |
|-------------|-------------------------|------------------------|---------------------------------------------|------------------------|
| Personal    | `photoprism-personal`   | `photoprism_personal`  | `/mnt/ev_deluxe/originals` (Full access)    | `fotos.casita.local`   |
| Shared      | `photoprism-compartido` | `photoprism_compartido`| `/mnt/ev_deluxe/originals/0-compartido`     | `familia.casita.local` |

* **Database (`photoprism-db`)**: MariaDB container initializing both schemas via `init-db.sql`.
* **UID/GID**: Both instances run as UID/GID 1000 to match host permissions in `/home/casita/docker-data`.
* **Hardware Acceleration**: Both instances use Intel QuickSync for faster video transcoding and thumbnail generation via the `x-gpu-access` anchor.

### 5.7 Monitoring Stack 📊

Comprehensive system and container monitoring stack.

| Service       | Container       | Domain                 | Port  | Notes                                                              |
|---------------|-----------------|------------------------|-------|--------------------------------------------------------------------|
| Grafana       | `grafana`       | `grafana.casita.local` | 3000  | Visual Dashboards. Pre-loaded with SRE Docker Monitoring Dashboard. |
| Prometheus    | `prometheus`    | (Internal)             | 9090  | Metrics TSDB (15d retention, `--web.enable-admin-api` enabled).    |
| Node Exporter | `node-exporter` | (Internal)             | 9100  | Host metrics. Mounts `/`, `/home`, `/mnt` as read-only.            |
| cAdvisor      | `cadvisor`      | (Internal)             | 8080  | Container metrics (cgroup, memory working set, container restarts).|

#### Dashboard Location & Management
* **Host Dashboard JSON**: [`monitoring/dashboards/host_hardware_monitoring.json`](monitoring/dashboards/host_hardware_monitoring.json) (UID: `homelab-host`)
* **Docker Dashboard JSON**: [`monitoring/dashboards/docker_containers_monitoring.json`](monitoring/dashboards/docker_containers_monitoring.json) (UID: `homelab-docker`)
* **Automated Sync**: Python script using Grafana v2 Scenes API (reads credentials from `.env`):
  ```bash
  python3 monitoring/upload_dashboards.py
  ```
* **Alerting**: 10 production SRE rules declaratively defined in [`monitoring/alerting/homelab_alerts.json`](monitoring/alerting/homelab_alerts.json) covering Storage, Host RAM/Swap/Temp, and Container crashes, routed to `Telegram-Alerts`.

### 5.8 n8n Workflow Automation 🤖

Workflow automation platform integrated with Telegram bots and AI pipelines.

| Service | Container | HTTPS Domain | HTTP Redirection Domain | Port | Notes |
|---------|-----------|--------------|-------------------------|------|-------|
| n8n     | `n8n`     | `https://n8n.salvador512.com` | `http://n8n.casita.local` | 5678 | Requires `user: root` and `WEBHOOK_URL=https://n8n.salvador512.com/` |

#### Key Settings:
* **User**: `user: root` is required in `n8n/docker-compose.yml` to prevent `EACCES` permission denied errors on SQLite database volume mount.
* **Volume Mount**: `${DOCKER_DATA_PATH}/n8n:/root/.n8n`.
* **Webhook & SSL**: `WEBHOOK_URL=https://n8n.salvador512.com/` and `N8N_PROTOCOL=https` allow instant Telegram bot webhook registration over SSL.

---

## 6. Security

- **Minimum Privilege**: Do not expose ports unless necessary.
- **No root**: Use `PUID`/`PGID` where supported.
- **Credentials**: Stored in `.env` only (protected by `.gitignore`).
- **Backups**: Regular backup of `${DOCKER_DATA_PATH}`.

---

## 7. Common Operations

```bash
# Start the whole lab
docker compose up -d

# Start individual service
docker compose -f <service>/docker-compose.yml --env-file .env up -d

# Check logs
docker logs -f <container_name>

# Update a service
docker compose -f <service>/docker-compose.yml --env-file .env pull
docker compose -f <service>/docker-compose.yml --env-file .env up -d
```

---

## 8. Migrating System Data (Docker & Containerd)

If the root partition (`/`) is full, the Docker Engine and Containerd data directories should be moved to a larger partition (e.g., `/home`).

**1. Move Docker Engine:**
```bash
sudo systemctl stop docker docker.socket containerd
sudo mkdir -p /home/casita/docker-engine
sudo rsync -aqxP /var/lib/docker/ /home/casita/docker-engine/
```
Update `/etc/docker/daemon.json` to include `"data-root": "/home/casita/docker-engine"`.

**2. Move Containerd:**
```bash
sudo mkdir -p /home/casita/containerd-engine
sudo rsync -aqxP /var/lib/containerd/ /home/casita/containerd-engine/
```
Update `/etc/containerd/config.toml` by setting `root = "/home/casita/containerd-engine"`.

**3. Apply & Clean:**
```bash
sudo systemctl start containerd docker
# Verify: docker info | grep "Docker Root Dir"
# If everything is working, delete the old data:
sudo rm -rf /var/lib/docker/ /var/lib/containerd/
```

---

## 9. Port Quick Reference

| Port   | Protocol | Service          | Exposed |
|--------|----------|------------------|---------|
| 53     | TCP/UDP  | Pi-hole DNS      | ✅ Yes  |
| 80     | TCP      | NPM HTTP         | ✅ Yes  |
| 81     | TCP      | NPM Admin UI     | ✅ Yes  |
| 443    | TCP      | NPM HTTPS        | ✅ Yes  |
| 6881   | TCP/UDP  | qBittorrent      | ✅ Yes  |
| Others | TCP      | Web Interfaces   | ❌ No   |
