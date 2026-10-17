#!/usr/bin/env bash
# ==============================================================================
# SRE BREAK-GLASS: Emergency script to toggle OAuth perimeter authentication
# Usage:
#   ./proxy/emergency-bypass-oauth.sh disable  # Removes auth_request from all hosts
#   ./proxy/emergency-bypass-oauth.sh enable   # Restores auth_request on all hosts
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

ACTION="${1:-help}"

case "${ACTION}" in
  disable)
    echo "⚠️  [EMERGENCY] Disabling OAuth perimeter authentication on all hosts..."
    python3 proxy/setup_https_and_301_redirects.py --disable-oauth
    echo "✅ OAuth perimeter disabled. All services are now directly accessible."
    ;;
  enable)
    echo "🔒 [SECURITY] Restoring OAuth perimeter authentication on all hosts..."
    python3 proxy/setup_https_and_301_redirects.py
    echo "✅ OAuth perimeter restored."
    ;;
  *)
    echo "Usage: $0 {disable|enable}"
    echo ""
    echo "  disable - Removes Nginx auth_request in case Google OAuth is down"
    echo "  enable  - Restores full OAuth2 Proxy perimeter authentication"
    exit 1
    ;;
esac
