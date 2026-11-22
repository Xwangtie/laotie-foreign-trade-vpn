#!/bin/bash
set -euo pipefail
PIDS="$(pgrep -f '/etc/openvpn-wm/client.ovpn' || true)"
if [[ -n "$PIDS" ]]; then
  kill $PIDS 2>/dev/null || true
  echo "已发送断开信号"
else
  echo "OpenVPN 未在运行"
fi
