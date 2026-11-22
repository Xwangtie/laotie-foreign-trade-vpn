#!/bin/bash
# unlock-network.sh — 紧急逃生门（Linux）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-openvpn-wm.sh
source "$SCRIPT_DIR/lib-openvpn-wm.sh"

if [[ $(id -u) -ne 0 ]]; then
  exec /usr/bin/sudo "$0" "$@"
fi

"$SCRIPT_DIR/killswitch.sh" disable
restore_dns || true
log_info "网络已紧急解除封锁"
