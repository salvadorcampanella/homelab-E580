# Business Overview

## Business Context Diagram

`mermaid
graph TD
    Internet["🌐 Internet"] --> Router["🔒 Router + Wireguard VPN"]
    Router --> |VPN Tunnel| RemoteClients["💻 Remote Clients"]
    Router --> Host["🖥️ Lenovo ThinkPad E580\nUbuntu Server LTS"]
    Host --> DuckDNS["🌐 DuckDNS\nPublic IP Update"]
    Host --> NPM["🔒 Nginx Proxy Manager\nReverse Proxy + SSL"]
    NPM --> MediaStack["🎬 Media Stack\nJellyfin, Radarr, Sonarr, Prowlarr, Bazarr, qBittorrent"]
    NPM --> Infra["🏗️ Infrastructure\nPi-hole, Portainer, Homepage"]
    NPM --> Photos["📸 PhotoPrism\nPersonal + Shared Gallery"]
    NPM --> Monitoring["📊 Monitoring\nGrafana + Prometheus"]
`

## Business Description

- **Business Description**: A self-hosted home server (homelab) running on a Lenovo ThinkPad E580 that provides a complete private media, photo management, monitoring, and infrastructure management platform. All services are accessible exclusively via a Wireguard VPN tunnel, ensuring full privacy and security.

- **Business Transactions**:
  - **Media consumption**: Browse and stream movies/series via Jellyfin, with automatic download management through Radarr/Sonarr and torrent downloads via qBittorrent.
  - **Content discovery**: Prowlarr manages indexers, FlareSolverr bypasses Cloudflare protections, Bazarr handles subtitle downloads.
  - **Photo management**: PhotoPrism provides two instances — a personal gallery and a shared family gallery — backed by a shared MariaDB database.
  - **Infrastructure management**: Portainer provides visual Docker management; Nginx Proxy Manager handles all reverse proxy routing with SSL.
  - **DNS management**: Pi-hole acts as a local DNS server and ad-blocker. DuckDNS keeps the public IP updated for the external domain.
  - **System monitoring**: Grafana dashboards display metrics collected by Prometheus, Node Exporter, and cAdvisor.
  - **Homelab dashboard**: Homepage provides a unified web dashboard for all services with live status and API widgets.

- **Business Dictionary**:
  - **proxy-nw**: The shared Docker bridge network that all services join to communicate internally.
  - **DOCKER_DATA_PATH**: /home/casita/docker-data — the host directory where all persistent service data is stored.
  - **casita.local**: The local DNS domain used for all internal service URLs, resolved by Pi-hole.
  - **casitaogrove.duckdns.org**: The public DuckDNS subdomain used for external DDNS.
  - **NPM**: Nginx Proxy Manager — the reverse proxy that routes all traffic to the correct container.
  - **Wireguard**: VPN solution installed on the home router, providing secure remote access.

## Component Level Business Descriptions

### proxy (Nginx Proxy Manager + MariaDB)
- **Purpose**: Routes all HTTP/HTTPS traffic to the correct service containers.
- **Responsibilities**: SSL termination, reverse proxy routing, creates the proxy-nw Docker network.

### pihole
- **Purpose**: Local DNS server and network-wide ad blocker.
- **Responsibilities**: Resolves *.casita.local domains, blocks ad/tracker domains.

### duckdns
- **Purpose**: Dynamic DNS — keeps the public DuckDNS subdomain pointed to the current public IP.

### portainer
- **Purpose**: Visual management interface for all Docker containers.

### arr (Media Stack)
- **Purpose**: Automates the download and management of movies and TV series.
- **Responsibilities**: Radarr (movies), Sonarr (TV), Prowlarr (indexers), Bazarr (subtitles), qBittorrent (downloads), Jellyfin (streaming), FlareSolverr (Cloudflare bypass).

### photoprism
- **Purpose**: Photo gallery management for personal and shared photo collections.

### monitoring
- **Purpose**: Comprehensive system and container observability.
- **Responsibilities**: Grafana (visualization), Prometheus (metrics), Node Exporter (host metrics), cAdvisor (container metrics).

### homepage
- **Purpose**: Central dashboard for all homelab services with live widgets.
