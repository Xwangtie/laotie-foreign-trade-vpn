#!/bin/bash
# OpenVPN client-connect：退出码 0=允许，非 0=拒绝连接
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-common.sh" 2>/dev/null || true
export AUTH_DB="${AUTH_DB:-/var/lib/openvpn-wm/panel.db}"
USER="${common_name:-}"
if [[ -z "$USER" ]]; then
  echo "$(date -u) client-connect missing common_name" >> /var/log/openvpn/client-connect.log
  exit 0
fi
echo "$(date -u) connect user=$USER real_ip=${trusted_ip:-?} dev=${dev:-?}" >> /var/log/openvpn/client-connect.log
exec python3 "$SCRIPT_DIR/vpn-auth.py" "$AUTH_DB" "$USER"
