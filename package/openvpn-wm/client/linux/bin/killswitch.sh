#!/bin/bash
# killswitch.sh — Linux 断线策略（nftables 优先，ipset+iptables 兜底）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-openvpn-wm.sh
source "$SCRIPT_DIR/lib-openvpn-wm.sh"

if [[ $(id -u) -ne 0 ]]; then
  exec /usr/bin/sudo "$0" "$@"
fi

DEV=""
MODE=""
ACTION="${1:-status}"
if [[ "$ACTION" == "enable" ]]; then
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dev) DEV="${2:-}"; shift 2 ;;
      --mode) MODE="${2:-}"; shift 2 ;;
      *) echo "未知参数: $1" >&2; exit 1 ;;
    esac
  done
  MODE="${MODE:-$(get_meta FAILMODE)}"
  [[ -n "$MODE" ]] || { log_error "无法确定 FAILMODE"; exit 1; }
fi

use_nft() {
  command -v nft >/dev/null 2>&1
}

do_nft_enable() {
  local server port utun_line cn_extra=""
  server="$(resolve_server_ip "$(get_meta SERVER)")"
  port="$(get_meta PORT)"
  [[ -n "$server" ]] || { log_error "无法解析服务器地址"; exit 1; }
  if [[ -n "$DEV" ]]; then
    utun_line="    oifname \"$DEV\" accept"
  fi
  local cn_count=0
  if [[ "$MODE" == "close-foreign" && -f "$CN4_FILE" ]]; then
    cn_count="$(awk 'NF && $1 !~ /^#/ {n++} END {print n+0}' "$CN4_FILE")"
  fi
  if [[ "$MODE" == "close-foreign" && "$cn_count" -gt 0 ]]; then
    cn_extra="    ip daddr @cn4 accept"
  fi
  {
    echo 'table inet openvpn_wm {'
    if [[ -n "$cn_extra" ]]; then
      echo '  set cn4 {'
      echo '    type ipv4_addr'
      echo '    flags interval'
      echo '    elements = {'
      awk 'NF && $1 !~ /^#/ { printf "      %s,\n", $1 }' "$CN4_FILE"
      echo '    }'
      echo '  }'
    fi
    echo '  chain output {'
    echo '    type filter hook output priority 0; policy drop;'
    echo '    oifname "lo" accept'
    echo "    ip daddr $server udp dport $port accept"
    echo "    ip daddr $server tcp dport $port accept"
    echo '    udp dport { 67, 68 } accept'
    echo '    ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } accept'
    if [[ -n "$cn_extra" ]]; then
      echo "$cn_extra"
    fi
    if [[ -n "$utun_line" ]]; then
      echo "$utun_line"
    fi
    echo '  }'
    echo '}'
  } > "$NFTRULES_FILE"
  nft -f "$NFTRULES_FILE"
  save_state KILLSWITCH "$MODE"
  log_info "nft kill-switch 已启用（$MODE）dev=${DEV:-未指定}"
}

do_ipset_enable() {
  local server port
  server="$(resolve_server_ip "$(get_meta SERVER)")"
  port="$(get_meta PORT)"
  ipset destroy openvpn_wm_cn4 2>/dev/null || true
  local cn_count=0
  if [[ "$MODE" == "close-foreign" && -f "$CN4_FILE" ]]; then
    cn_count="$(awk 'NF && $1 !~ /^#/ {n++} END {print n+0}' "$CN4_FILE")"
  fi
  if [[ "$MODE" == "close-foreign" && "$cn_count" -gt 0 ]]; then
    {
      echo 'create openvpn_wm_cn4 hash:net family inet hashsize 16384 maxelem 20000'
      awk 'NF && $1 !~ /^#/ { printf "add openvpn_wm_cn4 %s\n", $1 }' "$CN4_FILE"
    } | ipset restore -exist
  fi
  iptables -N OPENVPN_WM 2>/dev/null || true
  iptables -F OPENVPN_WM
  if ! iptables -C OUTPUT -j OPENVPN_WM 2>/dev/null; then
    iptables -I OUTPUT 1 -j OPENVPN_WM
  fi
  iptables -A OPENVPN_WM -o lo -j ACCEPT
  iptables -A OPENVPN_WM -d "$server" -p udp --dport "$port" -j ACCEPT
  iptables -A OPENVPN_WM -d "$server" -p tcp --dport "$port" -j ACCEPT
  iptables -A OPENVPN_WM -p udp --dport 67:68 -j ACCEPT
  iptables -A OPENVPN_WM -d 10.0.0.0/8 -j ACCEPT
  iptables -A OPENVPN_WM -d 172.16.0.0/12 -j ACCEPT
  iptables -A OPENVPN_WM -d 192.168.0.0/16 -j ACCEPT
  if [[ "$MODE" == "close-foreign" ]]; then
    iptables -A OPENVPN_WM -m set --match-set openvpn_wm_cn4 dst -j ACCEPT
  fi
  if [[ -n "$DEV" ]]; then
    iptables -A OPENVPN_WM -o "$DEV" -j ACCEPT
  fi
  iptables -A OPENVPN_WM -j DROP
  save_state KILLSWITCH "$MODE"
  log_info "iptables kill-switch 已启用（$MODE）dev=${DEV:-未指定}"
}

do_nft_disable() {
  nft delete table inet openvpn_wm 2>/dev/null || true
  /bin/rm -f "$NFTRULES_FILE"
}

do_ipset_disable() {
  iptables -D OUTPUT -j OPENVPN_WM 2>/dev/null || true
  iptables -F OPENVPN_WM 2>/dev/null || true
  iptables -X OPENVPN_WM 2>/dev/null || true
  ipset destroy openvpn_wm_cn4 2>/dev/null || true
}

do_enable() {
  ensure_dirs
  do_disable
  if use_nft; then
    do_nft_enable
  else
    do_ipset_enable
  fi
}

do_disable() {
  if use_nft; then
    do_nft_disable
  fi
  do_ipset_disable
  /bin/sed -i '/^KILLSWITCH=/d' "$STATE_FILE" 2>/dev/null || true
  log_info "kill-switch 已解除"
}

do_status() {
  if use_nft && nft list table inet openvpn_wm >/dev/null 2>&1; then
    echo "kill-switch: nft 已启用 ($(load_state KILLSWITCH || true))"
    nft list chain inet openvpn_wm output 2>/dev/null | head -20
  elif iptables -L OPENVPN_WM -n >/dev/null 2>&1; then
    echo "kill-switch: iptables 已启用 ($(load_state KILLSWITCH || true))"
    iptables -L OPENVPN_WM -n 2>/dev/null | head -20
  else
    echo "kill-switch: 未启用"
  fi
}

case "$ACTION" in
  enable)  do_enable ;;
  disable) do_disable ;;
  status)  do_status ;;
  *) echo "用法: $0 {enable|disable|status}" >&2; exit 1 ;;
esac
