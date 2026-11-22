#!/bin/bash
# openvpn-up.sh — route-up 钩子
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-openvpn-wm.sh
source "$SCRIPT_DIR/lib-openvpn-wm.sh"

DEV="${dev:-${1:-}}"
MODE="$(get_meta FAILMODE)"
if [[ "$MODE" == "close-all" || "$MODE" == "close-foreign" ]]; then
  "$SCRIPT_DIR/killswitch.sh" enable --dev "$DEV" --mode "$MODE"
fi
set_vpn_dns
log_info "route-up 完成 dev=$DEV mode=$MODE"
