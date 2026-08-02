# System Architecture

## System Overview

A fully self-hosted homelab running on a Lenovo ThinkPad E580 with Ubuntu Server. All services run as Docker containers orchestrated via Docker Compose, accessible exclusively through a Wireguard VPN tunnel. Nginx Proxy Manager acts as the central reverse proxy. All services share a single internal Docker bridge network (proxy-nw).

## Architecture Diagram

`mermaid
graph TB
    subgraph External["External Access"]
        Internet["🌐 Internet"]
        RemoteClient["💻 Remote Client\n(Wireguard)"]
    end

    subgraph Router["Home Router"]
        Wireguard["🔒 Wireguard VPN\nServer"]
        DuckDNS["🌐 DuckDNS\nDDNS Client"]
    end

    subgraph Host["Lenovo ThinkPad E580 — Docker Host"]
        subgraph ProxyNW["Docker Network: proxy-nw"]
            NPM["nginx-proxy-manager\n:80 :81 :443"]
            NPMDB["npm-db\nMariaDB"]

            Pihole["pihole\n:53 DNS :8080"]
            Portainer["portainer"]
            Homepage["homepage\n:3000"]
            Glances["glances\n:61208"]

            subgraph ArrStack["Media Stack (arr/)"]
                Radarr["radarr\n:7878"]
                Sonarr["sonarr\n:8989"]
                Prowlarr["prowlarr\n:9696"]
                Bazarr["bazarr\n:6767"]
                qBit["qbittorrent\n:8080 :6881"]
                Jellyfin["jellyfin\n:8096\n(Intel QSV)"]
                Flare["flaresolverr\n:8191"]
            end

            subgraph PhotoStack["photoprism/"]
                PPDb["photoprism-db\nMariaDB"]
                PPPersonal["photoprism-personal\n:2342\n(Intel QSV)"]
                PPShared["photoprism-compartido\n:2342\n(Intel QSV)"]
            end

            subgraph MonStack["monitoring/"]
                Grafana["grafana\n:3000"]
                Prometheus["prometheus\n:9090"]
                NodeExp["node-exporter\n:9100"]
                CAdvisor["cadvisor\n:8080"]
            end
        end

        subgraph GPU["Intel UHD 620"]
            DRI["/dev/dri/renderD128\n/dev/dri/card1"]
        end

        subgraph Storage["Host Storage"]
            DockerData["/home/casita/docker-data"]
            Media["/mnt/ev_deluxe\n(External Drive)"]
        end
    end

    Internet --> Wireguard
    RemoteClient --> Wireguard
    Wireguard --> NPM
    NPM --> NPMDB
    NPM --> Pihole
    NPM --> Portainer
    NPM --> Homepage
    NPM --> Jellyfin
    NPM --> Radarr
    NPM --> Sonarr
    NPM --> Prowlarr
    NPM --> Bazarr
    NPM --> qBit
    NPM --> Glances
    NPM --> PPPersonal
    NPM --> PPShared
    NPM --> Grafana
    Prowlarr --> Flare
    PPPersonal --> PPDb
    PPShared --> PPDb
    Prometheus --> NodeExp
    Prometheus --> CAdvisor
    Grafana --> Prometheus
    Homepage --> Glances
    Jellyfin --> DRI
    PPPersonal --> DRI
    PPShared --> DRI
    DuckDNS -.- Host
`

## Component Descriptions

### proxy/
- **Purpose**: Reverse proxy and SSL termination for all services.
- **Responsibilities**: Routing, SSL certificates (Let's Encrypt), network creation.
- **Dependencies**: MariaDB (
pm-db) for configuration storage.
- **Type**: Infrastructure

### pihole/
- **Purpose**: Local DNS resolver and ad-blocker.
- **Dependencies**: None (standalone).
- **Type**: Infrastructure

### duckdns/
- **Purpose**: DDNS client to keep the public DuckDNS subdomain updated.
- **Dependencies**: Internet access via 
etwork_mode: host.
- **Type**: Infrastructure

### portainer/
- **Purpose**: Visual Docker management interface.
- **Dependencies**: Docker socket (/var/run/docker.sock).
- **Type**: Infrastructure

### arr/
- **Purpose**: Full media automation stack.
- **Dependencies**: proxy-nw, host storage (/home/casita/docker-data/arr, /home/casita/docker-data/media), Intel GPU devices.
- **Type**: Application

### photoprism/
- **Purpose**: Photo gallery with AI-powered indexing.
- **Dependencies**: proxy-nw, MariaDB (photoprism-db), external drive (/mnt/ev_deluxe), Intel GPU devices.
- **Type**: Application

### monitoring/
- **Purpose**: Full observability stack for host and containers.
- **Dependencies**: proxy-nw, Docker socket (cAdvisor), host filesystem mounts.
- **Type**: Infrastructure/Application

### homepage/
- **Purpose**: Unified homelab dashboard.
- **Dependencies**: proxy-nw, Docker socket (read-only), Glances API.
- **Type**: Application

## Data Flow

`mermaid
sequenceDiagram
    participant RC as Remote Client
    participant WG as Wireguard VPN
    participant NPM as Nginx Proxy Manager
    participant SVC as Service Container
    participant DB as Database/Storage

    RC->>WG: HTTPS Request
    WG->>NPM: Forward to :443
    NPM->>SVC: Route to container (proxy-nw)
    SVC->>DB: Read/Write data
    DB-->>SVC: Data response
    SVC-->>NPM: HTTP Response
    NPM-->>WG: HTTPS Response
    WG-->>RC: Encrypted response
`

## Integration Points

- **External APIs**: DuckDNS API (IP updates), torrent indexers via Prowlarr
- **Databases**: MariaDB (NPM config, PhotoPrism data)
- **Third-party Services**: Let's Encrypt (SSL), Cloudflare-protected indexers (via FlareSolverr)

## Infrastructure Components

- **Deployment Model**: Single-node Docker Compose with include directives for modular composition
- **Networking**: Single Docker bridge network proxy-nw created by the proxy service
- **Hardware Acceleration**: Intel UHD 620 via VAAPI/QuickSync (x-gpu-access YAML anchor)
- **Storage**: Bind mounts only — no Docker named volumes
