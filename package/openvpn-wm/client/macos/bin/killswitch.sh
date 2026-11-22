#!/bin/bash
# killswitch.sh — macOS pf 断线策略（close-all / close-foreign）
# 用法:
#   sudo killswitch.sh enable [--utun utunN]
#   sudo killswitch.sh disable
#   sudo killswitch.sh status
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-openvpn-wm.sh
source "$SCRIPT_DIR/lib-openvpn-wm.sh"

if [[ $(id -u) -ne 0 ]]; then
  exec /usr/bin/sudo "$0" "$@"
fi

UTUN=""
MODE=""
ACTION="${1:-status}"
if [[ "$ACTION" == "enable" ]]; then
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --utun) UTUN="${2:-}"; shift 2 ;;
      --mode) MODE="${2:-}"; shift 2 ;;
      *) echo "未知参数: $1" >&2; exit 1 ;;
    esac
  done
  MODE="${MODE:-$(get_meta FAILMODE)}"
  if [[ -z "$MODE" ]]; then
    log_error "无法确定 FAILMODE（$PROFILE_FILE 缺失？）"
    exit 1
  fi
fi

ensure_pf_conf() {
  if [[ ! -f "$PF_CONF" ]]; then
    cat > "$PF_CONF" <<'EOF'
scrub-anchor "com.apple/*"
nat-anchor "com.apple/*"
rdr-anchor "com.apple/*"
dummynet-anchor "com.apple/*"
anchor "com.apple/*"
load anchor "com.apple" from "/etc/pf.anchors/com.apple"
EOF
  fi
  if [[ ! -f "$PF_BACKUP" ]]; then
    /bin/cp -p "$PF_CONF" "$PF_BACKUP"
  fi
  if ! /usr/bin/grep -q '^anchor "openvpn-wm"' "$PF_CONF"; then
    printf '\nanchor "openvpn-wm"\n' >> "$PF_CONF"
  fi
}

build_anchor() {
  local template="$ETC_DIR/pf/killswitch-${MODE}.anchor"
  [[ -f "$template" ]] || { log_error "缺少模板 $template"; exit 1; }
  local server vpn_ips="" ip
  server="$(get_meta SERVER)"
  for ip in $(resolve_server_ip "$server"); do
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    vpn_ips="${vpn_ips:+$vpn_ips,}${ip}"
  done
  if [[ -z "$vpn_ips" ]]; then
    log_error "无法解析 VPN 服务器地址 ${server:-空}"
    exit 1
  fi
  local utun_line=""
  if [[ -n "$UTUN" ]]; then
    utun_line="pass out on ${UTUN} keep state"
  fi
  /usr/bin/sed -e "s|__VPN_IPS__|$vpn_ips|g" \
      -e "s|__VPN_PORT__|$(get_meta PORT)|g" \
      -e "s|__CN4_FILE__|$CN4_FILE|g" \
      -e "s|__UTUN_PASS__|${utun_line}|g" \
      "$template" > "$PF_ANCHOR"
  /bin/chmod 0640 "$PF_ANCHOR"
}

do_enable() {
  ensure_dirs
  ensure_pf_conf
  build_anchor
  # 先清理旧锚点，保证幂等
  /sbin/pfctl -a openvpn-wm -F all 2>/dev/null || true
  # 启用 pf（幂等：已启用则仅重载配置）
  /sbin/pfctl -ef "$PF_CONF" >/dev/null 2>&1 || /sbin/pfctl -f "$PF_CONF" >/dev/null
  /sbin/pfctl -a openvpn-wm -f "$PF_ANCHOR"
  save_state KILLSWITCH "$MODE"
  log_info "kill-switch 已启用（$MODE）utun=${UTUN:-未指定}"
}

do_disable() {
  /sbin/pfctl -a openvpn-wm -F all 2>/dev/null || true
  if [[ -f "$PF_BACKUP" ]]; then
    /bin/cp -p "$PF_BACKUP" "$PF_CONF"
    if /sbin/pfctl -s info 2>/dev/null | /usr/bin/grep -q 'Status: Enabled'; then
      /sbin/pfctl -f "$PF_CONF" >/dev/null 2>&1 || true
    fi
  fi
  /usr/bin/sed -i '' '/^KILLSWITCH=/d' "$STATE_FILE" 2>/dev/null || true
  log_info "kill-switch 已解除"
}

do_status() {
  if anchor_loaded; then
    local mode
    mode="$(load_state KILLSWITCH || true)"
    echo "kill-switch: 启用 (mode=${mode:-unknown})"
    /sbin/pfctl -a openvpn-wm -s rules 2>/dev/null | /usr/bin/head -15
  else
    echo "kill-switch: 未启用"
  fi
  if /sbin/pfctl -s info 2>/dev/null | /usr/bin/grep -q 'Status: Enabled'; then
    echo "pf: 系统级已启用"
  else
    echo "pf: 系统级未启用"
  fi
}

case "$ACTION" in
  enable)  do_enable ;;
  disable) do_disable ;;
  status)  do_status ;;
  *) echo "用法: $0 {enable|disable|status}" >&2; exit 1 ;;
esac
