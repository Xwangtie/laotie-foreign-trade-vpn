#!/bin/bash
# install-linux.sh — Linux 安装
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./bin/lib-openvpn-wm.sh
source "$SCRIPT_DIR/bin/lib-openvpn-wm.sh"

ensure_dirs

if ! command -v openvpn >/dev/null 2>&1; then
  echo "未安装 OpenVPN，执行 apt-get install -y openvpn ..."
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openvpn
fi

/bin/cp "$OVPN" "$OVPN_FILE"
/bin/chmod 0644 "$OVPN_FILE"
for opt in "script-security 2" "route-up $ETC_DIR/bin/openvpn-up.sh" "route-pre-down $ETC_DIR/bin/openvpn-down.sh"; do
  /usr/bin/grep -qF "$opt" "$OVPN_FILE" || echo "$opt" >> "$OVPN_FILE"
done

cat > "$PROFILE_FILE" <<EOF
PROFILE=${PROFILE}
FAILMODE=${FAILMODE}
SPLIT=${SPLIT}
SERVER=${SERVER}
PORT=${PORT}
SOURCE_OVPN=${OVPN}
EOF
/bin/chmod 0600 "$PROFILE_FILE"

if [[ "$SPLIT" == "cn-bypass" ]]; then
  CN_SRC="$SCRIPT_DIR/../../shared/data/cn-ipv4.txt"
  if [[ -f "$CN_SRC" ]]; then
    /bin/cp "$CN_SRC" "$CN4_FILE"
  else
    : > "$CN4_FILE"
    echo "⚠️  未找到共享 CN 数据，cn-ipv4.txt 为空" >&2
  fi
  /bin/chmod 0644 "$CN4_FILE"
fi

/bin/mkdir -p "$ETC_DIR/bin"
/bin/cp "$SCRIPT_DIR/bin/"*.sh "$ETC_DIR/bin/"
/bin/chmod 0755 "$ETC_DIR/bin/"*.sh

pin_server_hosts

# systemd 服务
/bin/cp "$SCRIPT_DIR/../linux/systemd/openvpnwm-failwatch.service" /etc/systemd/system/
/bin/systemctl daemon-reload
/bin/systemctl enable openvpnwm-failwatch.service

# 用户命令
/bin/mkdir -p /usr/local/bin
/bin/ln -sfn "$ETC_DIR/bin/connect.sh" /usr/local/bin/openvpnwm-connect 2>/dev/null || true
/bin/ln -sfn "$ETC_DIR/bin/disconnect.sh" /usr/local/bin/openvpnwm-disconnect 2>/dev/null || true
/bin/ln -sfn "$ETC_DIR/bin/unlock-network.sh" /usr/local/bin/openvpnwm-unlock 2>/dev/null || true

echo "✅ 安装完成 (FAILMODE=$FAILMODE)"
echo "连接:  sudo openvpnwm-connect"
echo "断开:  sudo openvpnwm-disconnect"
echo "紧急解除: openvpnwm-unlock"
