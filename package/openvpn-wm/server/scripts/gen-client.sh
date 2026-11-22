#!/bin/bash
# gen-client.sh - 签发（如缺失）并生成 .ovpn（幂等；无证书时自动签发）
# 用法: gen-client.sh <username> <profile> [outdir] [remote_host] [remote_port]
# 环境: EMBED_CN_ROUTES=1 时把 CN 路由内嵌 .ovpn（兜底开关）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-common.sh
source "$SCRIPT_DIR/lib-common.sh"

USER="${1:-}"
PROFILE="${2:-}"
OUTDIR="${3:-}"
REMOTE_HOST_ARG="${4:-}"
REMOTE_PORT_ARG="${5:-}"
require_username "$USER"
[[ -n "$PROFILE" ]] || { echo "用法: $0 <username> <profile> [outdir] [remote_host] [remote_port]" >&2; exit 2; }
load_profile "$PROFILE" || exit 1

EASYRSA="$EASYRSA_DIR"
[[ -x "$EASYRSA/easyrsa" ]] || { ovpn_err "easyrsa 不存在: $EASYRSA/easyrsa"; exit 1; }

# 幂等签发
if [[ -f "$EASYRSA/pki/issued/$USER.crt" ]]; then
  ovpn_info "证书已存在，复用: $USER"
else
  (cd "$EASYRSA" && ./easyrsa --batch build-client-full "$USER" nopass) >&2
fi

emit() {
  local failmode="${FAILMODE:-close-all}" split="${SPLIT:-none}"
  local host="${REMOTE_HOST_ARG:-$VPN_SERVER_HOST}"
  local port="${REMOTE_PORT_ARG:-$VPN_PORT}"
  cat <<EOF
# PROFILE=$PROFILE
# FAILMODE=$failmode
# SPLIT=$split
# SERVER=$host
# PORT=$port

# 老铁外贸网络管理系统
# 客服电话: 13905394878  客服邮箱: ymwww@qq.com
client
dev tun
proto udp
remote $host $port
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
verify-x509-name server name
pull-filter ignore "route-ipv6"
block-ipv6
cipher AES-256-GCM
data-ciphers AES-256-GCM
auth SHA256
tls-version-min 1.3
max-routes 8192
script-security 2
verb 3
mute 20

EOF
  if [[ "${EMBED_CN_ROUTES:-0}" == "1" && "$split" == "cn-bypass" ]]; then
    echo "# 路由内嵌模式（EMBED_CN_ROUTES=1，由 gen-routes 生成）"
    if [[ -x "$SCRIPT_DIR/../common/gen-routes.sh" ]]; then
      DATA_DIR="$DATA_DIR" bash "$SCRIPT_DIR/../common/gen-routes.sh" openvpn 2>/dev/null || true
    else
      ovpn_warn "找不到 gen-routes.sh，路由内嵌跳过"
    fi
  fi
  echo "<ca>"
  cat "$EASYRSA/pki/ca.crt"
  echo "</ca>"
  echo "<cert>"
  cat "$EASYRSA/pki/issued/$USER.crt"
  echo "</cert>"
  echo "<key>"
  cat "$EASYRSA/pki/private/$USER.key"
  echo "</key>"
  if [[ -f /etc/openvpn/tc.key ]]; then
    echo "<tls-crypt>"
    cat /etc/openvpn/tc.key
    echo "</tls-crypt>"
  fi
}

if [[ -n "$OUTDIR" ]]; then
  mkdir -p "$OUTDIR"
  emit > "$OUTDIR/$USER.ovpn"
  ovpn_info "已生成 $OUTDIR/$USER.ovpn"
else
  emit
fi
