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

# --- Configuration ---
NPM_URL="${NPM_URL:-http://localhost:81}"
NPM_EMAIL="${NPM_ADMIN_EMAIL:-admin@example.com}"
NPM_PASSWORD="${NPM_ADMIN_PASSWORD:-changeme}"
PIHOLE_URL="${PIHOLE_URL:-http://localhost:8080}"
PIHOLE_PASS="${PIHOLE_PASSWORD:-}"
PIHOLE_HOST_IP="${PIHOLE_HOST_IP:-192.168.0.102}"

# --- Logging ---
log_info()  { echo -e "\033[0;34m[INFO]\033[0m  $*"; }
log_ok()    { echo -e "\033[0;32m[OK]\033[0m    $*"; }
log_warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $*"; }
log_dns()   { echo -e "\033[0;36m[DNS]\033[0m   $*"; }

# --- Single Source of Truth for Services ---
# Format: "domain|forward_host|forward_port|scheme|advanced_config"
SERVICES=(
  "pihole.casita.local|pihole|80|http|location = / {\n    return 302 /admin/;\n}"
  "portainer.casita.local|portainer|9443|https|"
  "npm.casita.local|nginx-proxy-manager|81|http|"
  "radarr.casita.local|radarr|7878|http|"
  "sonarr.casita.local|sonarr|8989|http|"
  "prowlarr.casita.local|prowlarr|9696|http|"
  "bazarr.casita.local|bazarr|6767|http|"
  "qbit.casita.local|qbittorrent|8080|http|"
  "jellyfin.casita.local|jellyfin|8096|http|"
  "tdarr.casita.local|tdarr|8265|http|"
  "homepage.casita.local|homepage|3000|http|"
  "glances.casita.local|glances|61208|http|"
  "grafana.casita.local|grafana|3000|http|"
  "fotos.casita.local|photoprism-personal|2342|http|"
  "familia.casita.local|photoprism-compartido|2342|http|"
)

# =============================================================================
# NPM HELPERS
# =============================================================================

NPM_TOKEN=""

npm_authenticate() {
  log_info "Authenticating to NPM (${NPM_URL})..."
  local resp
  resp=$(curl -s -X POST "${NPM_URL}/api/tokens" \
    -H "Content-Type: application/json" \
    -d "{\"identity\": \"${NPM_EMAIL}\", \"secret\": \"${NPM_PASSWORD}\"}")

  NPM_TOKEN=$(echo "$resp" | jq -r '.token // empty')
  if [[ -z "$NPM_TOKEN" ]]; then
    log_error "Could not obtain NPM token. Check NPM_ADMIN_EMAIL and NPM_ADMIN_PASSWORD."
    exit 1
  fi
  log_ok "NPM token obtained successfully."
}

create_proxy_host() {
  local domain="$1" fwd_host="$2" fwd_port="$3" scheme="${4:-http}" adv_cfg="${5:-}"

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
      \"advanced_config\": \"${adv_cfg}\",
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
# PI-HOLE HELPERS
# =============================================================================

PIHOLE_SESSION_ID=""

pihole_authenticate() {
  log_info "Authenticating to Pi-hole (${PIHOLE_URL})..."
  if [[ -z "$PIHOLE_PASS" ]]; then
    log_warn "PIHOLE_PASSWORD not set — skipping Pi-hole DNS setup."
    return 1
  fi

  local resp
  resp=$(curl -s -X POST "${PIHOLE_URL}/api/auth" \
    -H "Content-Type: application/json" \
    -d "{\"password\": \"${PIHOLE_PASS}\"}")

  PIHOLE_SESSION_ID=$(echo "$resp" | jq -r '.session.sid // empty')
  if [[ -z "$PIHOLE_SESSION_ID" ]]; then
    log_error "Could not obtain Pi-hole session. Check PIHOLE_PASSWORD."
    return 1
  fi

  log_ok "Pi-hole session obtained successfully."
  return 0
}

pihole_logout() {
  if [[ -n "$PIHOLE_SESSION_ID" ]]; then
    curl -s -X DELETE "${PIHOLE_URL}/api/auth" \
      -H "X-FTL-SID: ${PIHOLE_SESSION_ID}" > /dev/null 2>&1 || true
  fi
}

add_pihole_dns() {
  local domain="$1" ip="${2:-${PIHOLE_HOST_IP}}"
  [[ -z "$PIHOLE_SESSION_ID" ]] && return 0

  local existing
  existing=$(curl -s -X GET "${PIHOLE_URL}/api/config/dns/hosts" \
    -H "X-FTL-SID: ${PIHOLE_SESSION_ID}" | \
    jq -r --arg d "$domain" --arg ip "$ip" \
      '.config.dns.hosts // [] | .[] | select(. == ($ip + " " + $d)) | .' 2>/dev/null || true)

  if [[ -n "$existing" ]]; then
    log_warn "DNS:  Already exists: ${domain} → ${ip} — skipping."
    return
  fi

  local entry_encoded="${ip}%20${domain}"
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "${PIHOLE_URL}/api/config/dns/hosts/${entry_encoded}" \
    -H "X-FTL-SID: ${PIHOLE_SESSION_ID}")

  if [[ "$http_code" == "201" || "$http_code" == "200" ]]; then
    log_dns "Created: ${domain} → ${ip}"
  else
    log_error "DNS:  Failed to create ${domain} (HTTP ${http_code})"
  fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

echo ""
echo "=========================================="
echo "  Casita Homelab — Setup Script"
echo "=========================================="
echo ""

if [[ "$RUN_NPM" == "true" ]]; then
  echo "--- NPM Proxy Hosts ---"
  npm_authenticate
  for entry in "${SERVICES[@]}"; do
    IFS='|' read -r domain fwd_host fwd_port scheme adv_cfg <<< "$entry"
    create_proxy_host "$domain" "$fwd_host" "$fwd_port" "$scheme" "$adv_cfg"
  done
  echo ""
  log_ok "NPM setup completed!"
fi

if [[ "$RUN_DNS" == "true" ]]; then
  echo ""
  echo "--- Pi-hole Local DNS ---"
  if pihole_authenticate; then
    trap pihole_logout EXIT
    for entry in "${SERVICES[@]}"; do
      IFS='|' read -r domain _ _ _ _ <<< "$entry"
      add_pihole_dns "$domain"
    done
    echo ""
    log_ok "Pi-hole DNS setup completed!"
  fi
fi

echo ""
log_ok "All done!"
