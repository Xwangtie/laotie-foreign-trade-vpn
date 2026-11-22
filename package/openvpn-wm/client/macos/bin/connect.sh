#!/bin/bash
# connect.sh — 前台连接 OpenVPN（Ctrl-C 断开）
set -euo pipefail
ETC_DIR="/etc/openvpn-wm"
if [[ ! -f "$ETC_DIR/client.ovpn" ]]; then
  echo "未找到 $ETC_DIR/client.ovpn，请先运行 install-client.sh" >&2
  exit 1
fi
exec /usr/local/bin/openvpn --config "$ETC_DIR/client.ovpn"
