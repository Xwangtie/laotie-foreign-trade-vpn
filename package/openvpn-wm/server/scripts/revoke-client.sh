#!/bin/bash
# revoke-client.sh - 吊销用户证书并更新 CRL
# 用法: revoke-client.sh <username>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-common.sh
source "$SCRIPT_DIR/lib-common.sh"

USER="${1:-}"
require_username "$USER"
EASYRSA="$EASYRSA_DIR"
[[ -x "$EASYRSA/easyrsa" ]] || { ovpn_err "easyrsa 不存在"; exit 1; }

if [[ -f "$EASYRSA/pki/issued/$USER.crt" ]]; then
  (cd "$EASYRSA" && ./easyrsa --batch revoke "$USER")
  (cd "$EASYRSA" && ./easyrsa gen-crl)
  cp "$EASYRSA/pki/crl.pem" "$OPENVPN_DIR/crl.pem"
  chmod 644 "$OPENVPN_DIR/crl.pem"
  # 吊销后移除 CCD，避免同名账号重新开户时残留旧静态 IP
  rm -f "$CCD_DIR/$USER"
  systemctl restart openvpn@server 2>/dev/null || true
  ovpn_info "已吊销并更新 CRL: $USER"
else
  ovpn_warn "证书不存在，跳过吊销: $USER"
fi
