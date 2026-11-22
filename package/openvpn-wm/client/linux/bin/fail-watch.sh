#!/bin/bash
# fail-watch.sh — Linux 断线守护
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-openvpn-wm.sh
source "$SCRIPT_DIR/lib-openvpn-wm.sh"

LOG_FILE="$LOG_DIR/fail-watch.log"
SEEN_FILE="$STATE_DIR/fail-watch-seen"
INTERVAL="${WATCH_INTERVAL:-5}"
FAIL_MAX="${WATCH_FAIL_MAX:-3}"
AUTO_UNLOCK="${AUTO_UNLOCK_AFTER_MIN:-0}"
MODE="$(get_meta FAILMODE)"

notify() {
  local title="$1" msg="$2"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$title" "$msg" 2>/dev/null || true
  fi
  echo "[$(date '+%F %T')] $title: $msg" >> "$LOG_FILE"
}

openvpn_alive() {
  /usr/bin/pgrep -f '/etc/openvpn-wm/client.ovpn' >/dev/null 2>&1
}

do_foreground() {
  ensure_dirs
  local fail=0 started_at
  started_at="$(date +%s)"
  while true; do
    if openvpn_alive && /bin/ping -c 1 -W 3 10.8.0.1 >/dev/null 2>&1; then
      /usr/bin/touch "$SEEN_FILE" 2>/dev/null || true
      fail=0
      started_at="$(date +%s)"
    elif [[ -f "$SEEN_FILE" ]]; then
      fail=$((fail + 1))
    fi
    if [[ $fail -ge $FAIL_MAX ]]; then
      local down_secs=$(( $(date +%s) - started_at ))
      if [[ "$MODE" == "open" ]]; then
        notify "老铁外贸网络管理系统" "VPN 已断开，正在回落到本地网络…"
        pkill -f '/etc/openvpn-wm/client.ovpn' 2>/dev/null || true
        /bin/rm -f "$SEEN_FILE"
      else
        notify "老铁外贸网络管理系统" "VPN 断开，当前处于断网保护。紧急恢复: openvpnwm-unlock"
      fi
      if [[ "$AUTO_UNLOCK" -gt 0 && $((down_secs / 60)) -ge $AUTO_UNLOCK ]]; then
        "$SCRIPT_DIR/unlock-network.sh" || true
      fi
      fail=0
    fi
    sleep "$INTERVAL"
  done
}

case "${1:-status}" in
  foreground) do_foreground ;;
  start) systemctl start openvpnwm-failwatch.service ;;
  stop) systemctl stop openvpnwm-failwatch.service ;;
  status) systemctl status openvpnwm-failwatch.service --no-pager 2>/dev/null || echo "未运行" ;;
  *) echo "用法: $0 {start|stop|status|foreground}" >&2; exit 1 ;;
esac
