#!/usr/bin/env bash
# =============================================================================
# setup-npm-hosts.sh — Automatically configures Proxy Hosts in NPM
#                       and DNS entries in Pi-hole
# =============================================================================
# USAGE:
#   chmod +x proxy/setup-npm-hosts.sh
#   ./proxy/setup-npm-hosts.sh            # Run both NPM and Pi-hole setup
#   ./proxy/setup-npm-hosts.sh --npm-only # Only create NPM proxy hosts
#   ./proxy/setup-npm-hosts.sh --dns-only # Only create Pi-hole DNS entries
#
# REQUIREMENTS:
#   - NPM running on localhost:81
#   - Pi-hole running on localhost:8080 (mapped host port)
#   - NPM_ADMIN_EMAIL, NPM_ADMIN_PASSWORD, PIHOLE_PASSWORD in .env
#   - curl and jq installed on host
#
# DESCRIPTION:
#   This script uses the NPM REST API to create all homelab Proxy Hosts,
#   and the Pi-hole v6 REST API to add matching local DNS entries.
#   It is safe to run multiple times — detects existing entries and skips them.
# =============================================================================

set -euo pipefail

# --- Parse arguments ---
RUN_NPM=true
RUN_DNS=true
for arg in "$@"; do
  case "$arg" in
    --npm-only) RUN_DNS=false ;;
    --dns-only) RUN_NPM=false ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

# --- Load .env if exists ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

# --- NPM Configuration ---
NPM_URL="${NPM_URL:-http://localhost:81}"
NPM_EMAIL="${NPM_ADMIN_EMAIL:-admin@example.com}"
NPM_PASSWORD="${NPM_ADMIN_PASSWORD:-changeme}"

# --- Pi-hole Configuration ---
# Pi-hole v6 web port is mapped to host port 8080 in pihole/docker-compose.yml
PIHOLE_URL="${PIHOLE_URL:-http://localhost:8080}"
PIHOLE_PASS="${PIHOLE_PASSWORD:-}"
# The host IP that Pi-hole DNS entries should resolve to (the Docker host itself)
PIHOLE_HOST_IP="${PIHOLE_HOST_IP:-127.0.0.1}"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_dns()   { echo -e "${CYAN}[DNS]${NC}   $*"; }

# =============================================================================
# NPM SECTION
# =============================================================================

NPM_TOKEN=""

npm_authenticate() {
  log_info "Authenticating to NPM (${NPM_URL})..."

  local response
  response=$(curl -s -X POST "${NPM_URL}/api/tokens" \
    -H "Content-Type: application/json" \
    -d "{\"identity\": \"${NPM_EMAIL}\", \"secret\": \"${NPM_PASSWORD}\"}")

  NPM_TOKEN=$(echo "$response" | jq -r '.token // empty')

  if [[ -z "$NPM_TOKEN" ]]; then
    log_error "Could not obtain NPM token. Check NPM_ADMIN_EMAIL and NPM_ADMIN_PASSWORD."
    log_error "Response: ${response}"
    exit 1
  fi

  log_ok "NPM token obtained successfully."
}

# -----------------------------------------------------------------------------
# create_proxy_host <domain> <forward_host> <forward_port> <scheme>
# -----------------------------------------------------------------------------
create_proxy_host() {
  local domain="$1"
  local fwd_host="$2"
  local fwd_port="$3"
  local scheme="${4:-http}"

  # Check if already exists
  local existing
  existing=$(curl -s -X GET "${NPM_URL}/api/nginx/proxy-hosts" \
    -H "Authorization: Bearer ${NPM_TOKEN}" | \
    jq -r --arg d "$domain" '.[] | select(.domain_names[] == $d) | .id // empty')

  if [[ -n "$existing" ]]; then
    log_warn "NPM: Already exists: ${domain} (id=${existing}) — skipping."
    return
  fi

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${NPM_URL}/api/nginx/proxy-hosts" \
    -H "Authorization: Bearer ${NPM_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"domain_names\": [\"${domain}\"],
      \"forward_scheme\": \"${scheme}\",
      \"forward_host\": \"${fwd_host}\",
      \"forward_port\": ${fwd_port},
      \"block_exploits\": true,
      \"allow_websocket_upgrade\": true,
      \"access_list_id\": 0,
      \"certificate_id\": 0,
      \"ssl_forced\": false,
      \"meta\": {\"letsencrypt_agree\": false, \"dns_challenge\": false},
      \"advanced_config\": \"\",
      \"enabled\": 1,
      \"locations\": [],
      \"http2_support\": false
    }")

  if [[ "$http_code" == "201" ]]; then
    log_ok "NPM: Created: ${domain} → ${scheme}://${fwd_host}:${fwd_port}"
  else
    log_error "NPM: Failed to create ${domain} (HTTP ${http_code})"
  fi
}

# =============================================================================
# PI-HOLE SECTION
# =============================================================================

PIHOLE_SESSION_ID=""

pihole_authenticate() {
  log_info "Authenticating to Pi-hole (${PIHOLE_URL})..."

  if [[ -z "$PIHOLE_PASS" ]]; then
    log_warn "PIHOLE_PASSWORD not set — skipping Pi-hole DNS setup."
    return 1
  fi

  local response
  response=$(curl -s -X POST "${PIHOLE_URL}/api/auth" \
    -H "Content-Type: application/json" \
    -d "{\"password\": \"${PIHOLE_PASS}\"}")

  PIHOLE_SESSION_ID=$(echo "$response" | jq -r '.session.sid // empty')

  if [[ -z "$PIHOLE_SESSION_ID" ]]; then
    log_error "Could not obtain Pi-hole session. Check PIHOLE_PASSWORD."
    log_error "Response: ${response}"
    return 1
  fi

  log_ok "Pi-hole session obtained successfully."
  return 0
}

pihole_logout() {
  if [[ -n "$PIHOLE_SESSION_ID" ]]; then
    curl -s -X DELETE "${PIHOLE_URL}/api/auth" \
      -H "X-FTL-SID: ${PIHOLE_SESSION_ID}" > /dev/null 2>&1 || true
    log_info "Pi-hole session closed."
  fi
}

# -----------------------------------------------------------------------------
# add_pihole_dns <domain> <ip>
# Adds a local DNS A record in Pi-hole via v6 API.
# Skips gracefully if the entry already exists.
# Only call this for *.casita.local domains (not external domains).
# -----------------------------------------------------------------------------
add_pihole_dns() {
  local domain="$1"
  local ip="${2:-${PIHOLE_HOST_IP}}"

  if [[ -z "$PIHOLE_SESSION_ID" ]]; then
    return 0
  fi

  # Check if the DNS entry already exists
  local existing
  existing=$(curl -s -X GET "${PIHOLE_URL}/api/config/dns/hosts" \
    -H "X-FTL-SID: ${PIHOLE_SESSION_ID}" | \
    jq -r --arg d "$domain" --arg ip "$ip" \
      '.config.dns.hosts // [] | .[] | select(. == ($ip + " " + $d)) | .' 2>/dev/null || true)

  if [[ -n "$existing" ]]; then
    log_warn "DNS:  Already exists: ${domain} → ${ip} — skipping."
    return
  fi

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${PIHOLE_URL}/api/config/dns/hosts" \
    -H "X-FTL-SID: ${PIHOLE_SESSION_ID}" \
    -H "Content-Type: application/json" \
    -d "{\"ip\": \"${ip}\", \"domain\": \"${domain}\"}")

  if [[ "$http_code" == "201" || "$http_code" == "200" ]]; then
    log_dns "Created: ${domain} → ${ip}"
  else
    log_error "DNS:  Failed to create ${domain} (HTTP ${http_code})"
  fi
}

# =============================================================================
# MAIN — Setup
# =============================================================================

echo ""
echo "=========================================="
echo "  Casita Homelab — Setup Script"
echo "=========================================="
echo ""

# --- NPM Setup ---
if [[ "$RUN_NPM" == "true" ]]; then
  echo "--- NPM Proxy Hosts ---"
  npm_authenticate

  log_info "Creating NPM Proxy Hosts..."
  echo ""

  # Infrastructure
  create_proxy_host "pihole.casita.local"    "pihole"                "80"    "http"
  create_proxy_host "portainer.casita.local" "portainer"             "9000"  "http"

  # Stack *arr + Jellyfin
  create_proxy_host "radarr.casita.local"    "radarr"                "7878"  "http"
  create_proxy_host "sonarr.casita.local"    "sonarr"                "8989"  "http"
  create_proxy_host "prowlarr.casita.local"  "prowlarr"              "9696"  "http"
  create_proxy_host "bazarr.casita.local"    "bazarr"                "6767"  "http"
  create_proxy_host "qbit.casita.local"      "qbittorrent"           "8080"  "http"
  create_proxy_host "jellyfin.casita.local"  "jellyfin"              "8096"  "http"

  # Homepage + Glances + Grafana
  create_proxy_host "homepage.casita.local"  "homepage"              "3000"  "http"
  create_proxy_host "glances.casita.local"   "glances"               "61208" "http"
  create_proxy_host "grafana.casita.local"   "grafana"               "3000"  "http"

  # PhotoPrism
  create_proxy_host "fotos.casita.local"     "photoprism-personal"   "2342"  "http"
  create_proxy_host "familia.casita.local"   "photoprism-compartido" "2342"  "http"

  echo ""
  log_ok "NPM setup completed!"
  log_info "Access NPM to activate SSL for hosts that need it: ${NPM_URL}"
fi

# --- Pi-hole DNS Setup ---
if [[ "$RUN_DNS" == "true" ]]; then
  echo ""
  echo "--- Pi-hole Local DNS ---"

  if pihole_authenticate; then
    # Trap to ensure session is closed even on error
    trap pihole_logout EXIT

    log_info "Creating Pi-hole DNS entries..."
    log_info "Resolving all *.casita.local domains to: ${PIHOLE_HOST_IP}"
    echo ""

    # Infrastructure
    add_pihole_dns "pihole.casita.local"
    add_pihole_dns "portainer.casita.local"

    # Media stack
    add_pihole_dns "radarr.casita.local"
    add_pihole_dns "sonarr.casita.local"
    add_pihole_dns "prowlarr.casita.local"
    add_pihole_dns "bazarr.casita.local"
    add_pihole_dns "qbit.casita.local"
    add_pihole_dns "jellyfin.casita.local"

    # Dashboard + monitoring
    add_pihole_dns "homepage.casita.local"
    add_pihole_dns "glances.casita.local"
    add_pihole_dns "grafana.casita.local"

    # PhotoPrism
    add_pihole_dns "fotos.casita.local"
    add_pihole_dns "familia.casita.local"

    echo ""
    log_ok "Pi-hole DNS setup completed!"
    log_info "Note: PIHOLE_HOST_IP=${PIHOLE_HOST_IP}"
    log_info "      Set PIHOLE_HOST_IP in your .env if this is not the correct host IP."
  fi
fi

echo ""
log_ok "All done!"
