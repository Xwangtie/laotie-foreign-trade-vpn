#!/bin/bash
# unlock-network.sh — 紧急逃生门：一键恢复本地网络（不依赖网络/下载）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-openvpn-wm.sh
source "$SCRIPT_DIR/lib-openvpn-wm.sh"

if [[ $(id -u) -ne 0 ]]; then
  exec /usr/bin/sudo "$0" "$@"
fi

"$SCRIPT_DIR/killswitch.sh" disable
restore_dns || true
# 不强删 hosts 固定条目（避免误删导致无法重连）；如需彻底卸载请运行 uninstall
log_info "网络已紧急解除封锁。如需恢复 OpenVPN 策略请重新连接。"
