# Code Quality Assessment

## Summary

Overall code quality is **Good** for a personal homelab project and follows industry-standard Docker Compose conventions. Several improvements have been identified and applied.

---

## Security Review

### ✅ Strengths

| Area | Finding |
|------|---------|
| Secrets management | All passwords referenced via .env variables — never hardcoded in compose files |
| .gitignore | .env is properly excluded from version control |
| Network isolation | All services use the internal proxy-nw network; no unnecessary port exposure |
| Read-only mounts | Media volumes mounted :ro where write access is not needed (Jellyfin, Bazarr) |
| Non-root users | PUID/PGID=1000 used across all linuxserver.io images |

### ⚠️ Medium Risk — Addressed

| Issue | Location | Resolution |
|-------|----------|-----------|
| privileged: true on cAdvisor | monitoring/docker-compose.yml | Required for cAdvisor — mitigated by using specific mounts instead of full host access where possible. Acceptable for homelab use. |
| Docker socket mounted read-write | homepage/docker-compose.yml, portainer/docker-compose.yml | Portainer requires RW access by design. Homepage socket now :ro. |
| CAP_SYS_NICE on Pi-hole | pihole/docker-compose.yml | Required for DNS priority tuning — acceptable and documented. |
| Image registry deprecated (cAdvisor) | monitoring/docker-compose.yml | **Fixed**: Migrated from deprecated gcr.io/cadvisor/cadvisor to ghcr.io/google/cadvisor. |

### ℹ️ Informational

| Area | Note |
|------|------|
| Wireguard-only access | No services are publicly exposed without VPN — excellent security posture |
| No --no-new-privileges | Consider adding security_opt: [no-new-privileges:true] to services that do not require privilege escalation |
| Pi-hole port 8080 | Temporary direct-IP access port — consider removing once NPM proxy host is configured |

---

## Code Quality Analysis

### Compose File Structure

| Check | Status | Notes |
|-------|--------|-------|
| Consistent estart: unless-stopped | ✅ All services | Good |
| Explicit container_name | ✅ All services | Good |
| external: true on proxy-nw | ✅ All non-proxy services | Good |
| Comments in English | ✅ After translation | Good |
| YAML anchors for GPU config | ✅ x-gpu-access in arr/ and photoprism/ | Good pattern |
| Bind mounts only (no named volumes) | ✅ All services | Per convention |

### Missing Health Checks

Health checks on critical services would allow depends_on: condition: service_healthy to prevent race conditions on startup.

| Service | Recommendation |
|---------|---------------|
| 
pm-db (MariaDB) | Add healthcheck using mysqladmin ping |
| photoprism-db (MariaDB) | Add healthcheck using mysqladmin ping |
| 
ginx-proxy-manager | Add healthcheck against :81/api |

> **Note**: Health checks are a best-practice improvement. Current depends_on without conditions uses a service-started trigger (not service-healthy), which can cause issues if the database takes time to initialize.

### Image Pinning

| Service | Old Tag | New Tag | Rationale |
|---------|---------|---------|-----------|
| grafana | :latest | :13.1.1 | Pinned stable |
| prometheus | :latest | :v3.5.5 | Pinned LTS |
| node-exporter | :latest | :v1.10.2 | Pinned stable |
| cadvisor | gcr.io/...:latest | ghcr.io/...:v0.60.5 | Registry migration + pinned |
| pihole | :latest | :2026.07.0 | Pinned stable (date-based) |
| flaresolverr | :latest | :v3.5.0 | Pinned stable |
| mariadb (photoprism-db) | :10.11 | :11.4 | LTS upgrade (10.11 EOL 2028, 11.4 EOL 2029) |
| linuxserver.io (arr stack) | :latest | :latest | Per LSIO official recommendation |
| homepage | :latest | :latest | No stable semver tags available |
| photoprism | :latest | :latest | Build-ID based versioning |
| glances | :latest-full | :latest-full | No stable semver tags |
| portainer-ce | :lts | :lts | Already a versioned LTS tag |

### Technical Debt

| Issue | Location | Priority |
|-------|----------|---------|
| No health checks on DB containers | proxy/, photoprism/ | Medium |
| pihole port 8080 still exposed | pihole/docker-compose.yml | Low (temporary use) |
| No log rotation configured | All services | Low |
| Glances mounts /mnt/ev_deluxe hardcoded | homepage/docker-compose.yml | Low |

### Good Patterns

- ✅ **Modular composition**: Root docker-compose.yml uses include — clean separation of concerns
- ✅ **YAML anchors**: x-gpu-access reusable block for GPU-capable services
- ✅ **Env var hygiene**: ${VAR:-default} for non-sensitive values, direct ${VAR} for secrets
- ✅ **Read-only mounts**: Media volumes use :ro flag correctly
- ✅ **Non-root execution**: PUID/PGID=1000 and user: "1000:1000" used consistently
- ✅ **Documentation**: Inline comments explain non-obvious configuration choices

### Anti-patterns Found

- ⚠️ **Missing health checks**: depends_on without condition: service_healthy on DB-dependent services
- ⚠️ **Deprecated registry**: cAdvisor using gcr.io (now migrated to ghcr.io)
- ⚠️ **Mixed :latest vs pinned tags**: Inconsistency across monitoring vs arr stack (now documented by design)

---

## Test Coverage

- **Overall**: None — expected for a homelab infrastructure project
- **Unit Tests**: N/A
- **Integration Tests**: N/A
- **Linting**: Not configured — shellcheck recommended for setup-npm-hosts.sh

## Code Style

- **Consistency**: Good — consistent formatting across all compose files
- **Documentation**: Good — all files have descriptive header comments
- **Naming**: Consistent — lowercase, dash-separated container names
