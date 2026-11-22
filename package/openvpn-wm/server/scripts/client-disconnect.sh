#!/bin/bash
set -uo pipefail
echo "$(date -u) disconnect user=${common_name:-?} bytes_rx=${bytes_received:-0} bytes_tx=${bytes_sent:-0}" >> /var/log/openvpn/client-connect.log
exit 0
