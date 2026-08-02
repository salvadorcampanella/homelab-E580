# Technology Stack

## Container Orchestration
- **Docker Engine** - Container runtime
- **Docker Compose v2** - Multi-container orchestration with include directives

## Images & Registries

| Service | Image | Registry |
|---------|-------|---------|
| Nginx Proxy Manager | jc21/nginx-proxy-manager:latest | Docker Hub |
| Pi-hole | pihole/pihole:2026.07.0 | Docker Hub |
| Portainer CE | portainer/portainer-ce:lts | Docker Hub |
| DuckDNS | lscr.io/linuxserver/duckdns:latest | LinuxServer.io |
| Radarr | lscr.io/linuxserver/radarr:latest | LinuxServer.io |
| Sonarr | lscr.io/linuxserver/sonarr:latest | LinuxServer.io |
| Prowlarr | lscr.io/linuxserver/prowlarr:latest | LinuxServer.io |
| Bazarr | lscr.io/linuxserver/bazarr:latest | LinuxServer.io |
| qBittorrent | lscr.io/linuxserver/qbittorrent:latest | LinuxServer.io |
| Jellyfin | lscr.io/linuxserver/jellyfin:latest | LinuxServer.io |
| FlareSolverr | ghcr.io/flaresolverr/flaresolverr:v3.5.0 | GitHub Container Registry |
| Homepage | ghcr.io/gethomepage/homepage:latest | GitHub Container Registry |
| Glances | 
icolargo/glances:latest-full | Docker Hub |
| PhotoPrism | photoprism/photoprism:latest | Docker Hub |
| MariaDB (NPM) | jc21/mariadb-aria:latest | Docker Hub |
| MariaDB (PhotoPrism) | mariadb:11.4 | Docker Hub |
| Grafana | grafana/grafana:13.1.1 | Docker Hub |
| Prometheus | prom/prometheus:v3.5.5 | Docker Hub |
| Node Exporter | prom/node-exporter:v1.10.2 | Docker Hub |
| cAdvisor | ghcr.io/google/cadvisor:v0.60.5 | GitHub Container Registry |

## Hardware

- **Host**: Lenovo ThinkPad E580
- **OS**: Ubuntu Server LTS
- **GPU**: Intel UHD 620 (QuickSync / VAAPI) — used for hardware transcoding and thumbnail generation

## Networking

- **VPN**: Wireguard (installed on home router)
- **DDNS**: DuckDNS (casitaogrove.duckdns.org)
- **Reverse Proxy**: Nginx Proxy Manager
- **Internal DNS**: Pi-hole (*.casita.local)
- **Docker Network**: Single bridge network proxy-nw

## Storage

- **Persistent data**: Bind mounts under /home/casita/docker-data/
- **Media library**: /mnt/ev_deluxe/ (external drive)
- **No named Docker volumes** — all data stored on host filesystem

## Languages & Scripts

- **Shell (Bash)**: proxy/setup-npm-hosts.sh — NPM and Pi-hole automation script
- **YAML**: Docker Compose files
- **SQL**: photoprism/init-db.sql — MariaDB initialization

## Access Control

- **Remote access**: Wireguard VPN only
- **User mapping**: PUID/PGID 1000 for all linuxserver.io containers
- **Secrets**: Environment variables in .env (excluded from Git)
