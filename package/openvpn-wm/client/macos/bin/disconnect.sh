#!/bin/bash
# disconnect.sh — 断开 OpenVPN
set -euo pipefail
PIDS="$(/usr/bin/pgrep -f '/etc/openvpn-wm/client.ovpn' || true)"
if [[ -n "$PIDS" ]]; then
  /bin/kill $PIDS 2>/dev/null || true
  echo "已发送断开信号"
else
  echo "OpenVPN 未在运行"
fi
