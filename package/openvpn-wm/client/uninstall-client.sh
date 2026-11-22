#!/bin/bash
# uninstall-client.sh — 卸载客户端策略并尽量恢复安装前状态
# 用法: sudo ./uninstall-client.sh
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "请用 sudo 执行: sudo $0" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"

case "$OS" in
  Darwin)
    "$SCRIPT_DIR/macos/bin/unlock-network.sh" || true
    /bin/launchctl bootout "gui/$(id -u)/com.openvpnwm.failwatch" 2>/dev/null || true
    /bin/launchctl bootout system /Library/LaunchDaemons/com.openvpnwm.failwatch.plist 2>/dev/null || true
    /bin/rm -f /Library/LaunchDaemons/com.openvpnwm.failwatch.plist
    /usr/bin/sed -i '' '/# openvpn-wm pinned/d' /etc/hosts 2>/dev/null || true
    /bin/rm -f /usr/local/bin/openvpnwm-connect /usr/local/bin/openvpnwm-disconnect /usr/local/bin/openvpnwm-unlock
    ;;
  Linux)
    "$SCRIPT_DIR/linux/bin/unlock-network.sh" || true
    /bin/systemctl disable --now openvpnwm-failwatch.service 2>/dev/null || true
    /bin/rm -f /etc/systemd/system/openvpnwm-failwatch.service
    /bin/systemctl daemon-reload 2>/dev/null || true
    /bin/sed -i '/# openvpn-wm pinned/d' /etc/hosts 2>/dev/null || true
    /bin/rm -f /usr/local/bin/openvpnwm-connect /usr/local/bin/openvpnwm-disconnect /usr/local/bin/openvpnwm-unlock
    ;;
  *)
    echo "Windows 请使用 uninstall-client.ps1" >&2
    exit 1
    ;;
esac

# 删除安装目录（含 hosts 固定条目由平台脚本处理）
/bin/rm -rf /etc/openvpn-wm
/bin/rm -f /var/run/openvpn-wm/state.env /var/log/openvpn-wm/*
/usr/bin/rmdir /var/run/openvpn-wm /var/log/openvpn-wm 2>/dev/null || true

echo "✅ 已卸载。若此前修改过 /etc/pf.conf，备份位于 /etc/pf.conf.openvpn-wm.bak"
echo "   Windows 使用 netsh advfirewall reset 已由脚本自动执行。"
