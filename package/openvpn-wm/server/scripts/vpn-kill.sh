#!/bin/bash
# vpn-kill.sh - 通过 management 接口断开指定用户在线会话
# 用法: vpn-kill.sh <username>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-common.sh
source "$SCRIPT_DIR/lib-common.sh"

USER="${1:-}"
require_username "$USER"

MGMT_PASS_FILE="$STATE_DIR/mgmt.pass"
if [[ ! -s "$MGMT_PASS_FILE" ]]; then
  ovpn_warn "management 密码文件不存在: $MGMT_PASS_FILE"
fi

# 从 status 文件找该用户名 common name 与 client 编号；kill 用 common-name 也可（management 支持 "kill <cn>"）
killout=$( { printf 'password "%s"\n' "$(cat "$MGMT_PASS_FILE" 2>/dev/null)"; printf 'kill %s\n' "$USER"; sleep 0.5; } | timeout 5 nc 127.0.0.1 8989 2>/dev/null || true)
if grep -qi 'INFO:kill' <<<"$killout" || grep -qi 'SUCCESS' <<<"$killout"; then
  ovpn_info "已请求断开: $USER"
else
  ovpn_warn "kill 命令未确认成功（用户可能不在线）。mgmt 输出: ${killout:-空}"
fi
