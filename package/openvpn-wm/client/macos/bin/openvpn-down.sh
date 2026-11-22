#!/bin/bash
# openvpn-down.sh — OpenVPN route-pre-down 钩子
# close-*：保持 kill-switch 生效（断线即断网）；open：还原 DNS
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-openvpn-wm.sh
source "$SCRIPT_DIR/lib-openvpn-wm.sh"

MODE="$(get_meta FAILMODE)"

if [[ "$MODE" == "open" ]]; then
  restore_dns || true
  /bin/rm -f "$STATE_DIR/fail-watch-seen"
else
  # 保持防火墙阻断；DNS 还原为 DHCP，便于用户手动重连
  restore_dns || true
fi
log_info "route-pre-down 完成 mode=$MODE"
