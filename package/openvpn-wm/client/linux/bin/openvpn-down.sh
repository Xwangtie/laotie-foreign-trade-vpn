#!/bin/bash
# openvpn-down.sh — route-pre-down 钩子
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-openvpn-wm.sh
source "$SCRIPT_DIR/lib-openvpn-wm.sh"

MODE="$(get_meta FAILMODE)"
restore_dns || true
if [[ "$MODE" == "open" ]]; then
  /bin/rm -f "$STATE_DIR/fail-watch-seen" 2>/dev/null || true
fi
log_info "route-pre-down 完成"
