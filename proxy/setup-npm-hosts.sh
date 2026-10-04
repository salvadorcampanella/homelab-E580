#!/usr/bin/env bash
# =============================================================================
# setup-npm-hosts.sh — HTTPS DuckDNS Proxy Hosts + .casita.local 301 Redirections
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "${SCRIPT_DIR}/setup_https_and_301_redirects.py" "$@"
