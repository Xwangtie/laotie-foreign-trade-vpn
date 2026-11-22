#!/bin/bash
set -euo pipefail
exec /usr/sbin/openvpn --config /etc/openvpn-wm/client.ovpn "$@"
