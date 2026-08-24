#!/usr/bin/env bash
# =============================================================================
# update-services-keys.sh — Auto-fills API keys in Homepage services.yaml
# =============================================================================

set -euo pipefail

SERVICES_YAML="/home/casita/docker-data/homepage/config/services.yaml"

# --- Logging ---
log_ok()     { echo -e "\033[0;32m[OK]\033[0m    $*"; }
log_info()   { echo -e "\033[0;34m[INFO]\033[0m  $*"; }
log_warn()   { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
log_error()  { echo -e "\033[0;31m[ERROR]\033[0m $*"; }
log_manual() { echo -e "\033[0;36m[MANUAL]\033[0m $*"; }

echo ""
echo "============================================"
echo "  Homepage — API Keys Setup Script"
echo "============================================"
echo ""

if [[ ! -f "$SERVICES_YAML" ]]; then
  log_error "services.yaml not found at: $SERVICES_YAML"
  exit 1
fi

log_info "Target file: $SERVICES_YAML"
echo ""

# Helper to extract XML ApiKey using native grep
get_xml_key() {
  docker exec "$1" cat /config/config.xml 2>/dev/null | grep -oP '(?<=<ApiKey>)[^<]+' || true
}

# --- 1. Extract *arr API Keys ---
echo "--- Extracting API keys from running containers ---"

RADARR_KEY=$(get_xml_key radarr)
[[ -n "$RADARR_KEY" ]] && log_ok "Radarr key: ${RADARR_KEY:0:8}..." || log_warn "Radarr key not found"

SONARR_KEY=$(get_xml_key sonarr)
[[ -n "$SONARR_KEY" ]] && log_ok "Sonarr key: ${SONARR_KEY:0:8}..." || log_warn "Sonarr key not found"

PROWLARR_ID=$(docker ps --format "{{.Names}}" | grep prowlarr | head -1)
PROWLARR_KEY=""
[[ -n "$PROWLARR_ID" ]] && PROWLARR_KEY=$(get_xml_key "$PROWLARR_ID")
[[ -n "$PROWLARR_KEY" ]] && log_ok "Prowlarr key: ${PROWLARR_KEY:0:8}..." || log_warn "Prowlarr key not found"

BAZARR_KEY=$(docker exec bazarr python3 -c "
import yaml
with open('/config/config/config.yaml') as f:
    print(yaml.safe_load(f).get('auth',{}).get('apikey',''))
" 2>/dev/null || true)
[[ -n "$BAZARR_KEY" ]] && log_ok "Bazarr key: ${BAZARR_KEY:0:8}..." || log_warn "Bazarr key not found"

# --- 2. Jellyfin API Key ---
echo ""
echo "--- Jellyfin API key ---"
JELLYFIN_IP=$(docker inspect jellyfin --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || true)
JELLYFIN_KEY=""

if [[ -n "$JELLYFIN_IP" ]]; then
  for jf_user in "admin" "casita"; do
    for jf_pass in "" "thisisus" "!!.eaEClla512" "admin"; do
      AUTH_RESP=$(curl -s -X POST "http://$JELLYFIN_IP:8096/Users/AuthenticateByName" \
        -H 'Authorization: MediaBrowser Client="SetupScript", Device="server", DeviceId="setup001", Version="10.8.0"' \
        -H "Content-Type: application/json" \
        -d "{\"Username\":\"$jf_user\",\"Pw\":\"$jf_pass\"}" 2>/dev/null || true)
      JF_TOKEN=$(echo "$AUTH_RESP" | jq -r '.AccessToken // empty' 2>/dev/null || true)
      if [[ -n "$JF_TOKEN" ]]; then
        KEYS_RESP=$(curl -s "http://$JELLYFIN_IP:8096/Auth/Keys" -H "Authorization: MediaBrowser Token=\"$JF_TOKEN\"" 2>/dev/null || true)
        JELLYFIN_KEY=$(echo "$KEYS_RESP" | jq -r '.Items[] | select(.AppName != "Jellyfin Web") | .AccessToken' 2>/dev/null | head -1 || true)
        if [[ -z "$JELLYFIN_KEY" ]]; then
          curl -s -X POST "http://$JELLYFIN_IP:8096/Auth/Keys?app=Homepage" -H "Authorization: MediaBrowser Token=\"$JF_TOKEN\"" -H "Content-Length: 0" >/dev/null 2>&1 || true
          KEYS_RESP=$(curl -s "http://$JELLYFIN_IP:8096/Auth/Keys" -H "Authorization: MediaBrowser Token=\"$JF_TOKEN\"" 2>/dev/null || true)
          JELLYFIN_KEY=$(echo "$KEYS_RESP" | jq -r '.Items[] | select(.AppName == "Homepage") | .AccessToken' 2>/dev/null | head -1 || true)
        fi
        [[ -n "$JELLYFIN_KEY" ]] && log_ok "Jellyfin key: ${JELLYFIN_KEY:0:8}..." && break 2
      fi
    done
  done
fi
[[ -z "$JELLYFIN_KEY" ]] && log_warn "Jellyfin API key could not be retrieved automatically"

# --- 3. Replace Keys in services.yaml ---
echo ""
echo "--- Updating services.yaml ---"
cp "$SERVICES_YAML" "${SERVICES_YAML}.bak.$(date +%Y%m%d-%H%M%S)"

replace_key() {
  local placeholder="$1" key="$2"
  if [[ -n "$key" ]]; then
    sed -i "s|${placeholder}|${key}|g" "$SERVICES_YAML"
    log_ok "Replaced ${placeholder}"
  fi
}

replace_key "<RADARR_API_KEY>" "$RADARR_KEY"
replace_key "<SONARR_API_KEY>" "$SONARR_KEY"
replace_key "<PROWLARR_API_KEY>" "$PROWLARR_KEY"
replace_key "<BAZARR_API_KEY>" "$BAZARR_KEY"
replace_key "<JELLYFIN_API_KEY>" "$JELLYFIN_KEY"

# --- 4. Manual Steps Notice ---
echo ""
echo "============================================"
echo "  MANUAL STEPS REQUIRED"
echo "============================================"
echo ""
log_manual "1. PORTAINER API KEY"
echo "   Generate token in Portainer > Account > Access Tokens"
echo "   Run: sed -i 's/<PORTAINER_API_KEY>/YOUR_TOKEN/g' \"$SERVICES_YAML\""
echo ""
log_manual "2. QBITTORRENT PASSWORD"
echo "   Set password in \"$SERVICES_YAML\" under qBittorrent widget"
echo ""
echo "============================================"
log_ok "Done! Restart Homepage to apply changes: docker restart homepage"
echo "============================================"
