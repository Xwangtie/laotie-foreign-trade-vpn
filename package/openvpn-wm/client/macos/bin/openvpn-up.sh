#!/bin/bash
# openvpn-up.sh — OpenVPN route-up 钩子：启用断线策略 + 设置 VPN DNS
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-openvpn-wm.sh
source "$SCRIPT_DIR/lib-openvpn-wm.sh"

DEV="${dev:-${2:-}}"
MODE="$(get_meta FAILMODE)"

if [[ "$MODE" == "close-all" || "$MODE" == "close-foreign" ]]; then
  "$SCRIPT_DIR/killswitch.sh" enable --utun "$DEV" --mode "$MODE"
fi

# DNS 一律指向 VPN 内 DNS
set_vpn_dns || true
log_info "route-up 完成 dev=$DEV mode=$MODE"
