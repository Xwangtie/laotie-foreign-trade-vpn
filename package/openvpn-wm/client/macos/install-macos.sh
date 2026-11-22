#!/bin/bash
# install-macos.sh — macOS 安装
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./bin/lib-openvpn-wm.sh
source "$SCRIPT_DIR/bin/lib-openvpn-wm.sh"

ensure_dirs

# 1. 校验 OpenVPN
if ! command -v openvpn >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "未安装 OpenVPN，尝试 brew install openvpn ..."
    brew install openvpn
  else
    echo "错误: 未安装 openvpn，请先: brew install openvpn" >&2
    exit 1
  fi
fi

# 2. 复制 .ovpn 并追加钩子配置
/bin/cp "$OVPN" "$OVPN_FILE"
/bin/chmod 0644 "$OVPN_FILE"
if ! /usr/bin/grep -q 'script-security 2' "$OVPN_FILE"; then
  printf '\nscript-security 2\n' >> "$OVPN_FILE"
fi
if ! /usr/bin/grep -q 'route-up' "$OVPN_FILE"; then
  printf 'route-up %s/bin/openvpn-up.sh\n' "$ETC_DIR" >> "$OVPN_FILE"
fi
if ! /usr/bin/grep -q 'route-pre-down' "$OVPN_FILE"; then
  printf 'route-pre-down %s/bin/openvpn-down.sh\n' "$ETC_DIR" >> "$OVPN_FILE"
fi

# 3. 元数据
cat > "$PROFILE_FILE" <<EOF
PROFILE=${PROFILE}
FAILMODE=${FAILMODE}
SPLIT=${SPLIT}
SERVER=${SERVER}
PORT=${PORT}
SOURCE_OVPN=${OVPN}
EOF
/bin/chmod 0600 "$PROFILE_FILE"

# 4. CN 表与私有网段
if [[ "$SPLIT" == "cn-bypass" ]]; then
  CN_SRC="$SCRIPT_DIR/../../shared/data/cn-ipv4.txt"
  if [[ -f "$CN_SRC" ]]; then
    /bin/cp "$CN_SRC" "$CN4_FILE"
  else
    : > "$CN4_FILE"
    echo "⚠️  未找到共享 CN 数据，cn-ipv4.txt 为空；close-foreign 将退化为 close-all" >&2
  fi
  /bin/chmod 0644 "$CN4_FILE"
fi

# 5. 安装脚本与模板
/bin/mkdir -p "$ETC_DIR/bin" "$ETC_DIR/pf"
/bin/cp "$SCRIPT_DIR/bin/"*.sh "$ETC_DIR/bin/"
/bin/cp "$SCRIPT_DIR/pf/"*.anchor "$ETC_DIR/pf/"
/bin/chmod 0755 "$ETC_DIR/bin/"*.sh
/bin/chmod 0644 "$ETC_DIR/pf/"*.anchor

# 6. 服务器域名固定到 hosts（kill-switch 生效后可重连）
pin_server_hosts

# 7. 安装 launchd 看门狗（open 模式才需要，其余模式也装上便于通知）
/bin/sed -e "s|__ETC_DIR__|$ETC_DIR|g" "$SCRIPT_DIR/launchd/com.openvpnwm.failwatch.plist" \
  > /Library/LaunchDaemons/com.openvpnwm.failwatch.plist
/usr/sbin/chown root:wheel /Library/LaunchDaemons/com.openvpnwm.failwatch.plist
/bin/chmod 0644 /Library/LaunchDaemons/com.openvpnwm.failwatch.plist
/bin/launchctl bootstrap system /Library/LaunchDaemons/com.openvpnwm.failwatch.plist 2>/dev/null || \
  /bin/launchctl load /Library/LaunchDaemons/com.openvpnwm.failwatch.plist 2>/dev/null || true

# 8. 用户命令软链
/bin/mkdir -p /usr/local/bin
/bin/ln -sfn "$ETC_DIR/bin/connect.sh" /usr/local/bin/openvpnwm-connect
/bin/ln -sfn "$ETC_DIR/bin/disconnect.sh" /usr/local/bin/openvpnwm-disconnect
/bin/ln -sfn "$ETC_DIR/bin/unlock-network.sh" /usr/local/bin/openvpnwm-unlock

echo "✅ 安装完成"
echo "   方案: $PROFILE"
echo "   FAILMODE: $FAILMODE"
echo ""
echo "连接:  sudo openvpnwm-connect"
echo "断开:  sudo openvpnwm-disconnect"
echo "紧急解除(断网自救): openvpnwm-unlock"
