#!/bin/bash
# fail-watch.sh — 断线守护（macOS）
# open 模式: 连续失败 → 主动断开 OpenVPN，让流量回落本地
# close 模式: 连续失败 → 桌面通知（可配置 AUTO_UNLOCK_AFTER_MIN 自动解除）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-openvpn-wm.sh
source "$SCRIPT_DIR/lib-openvpn-wm.sh"

LOG_FILE="$LOG_DIR/fail-watch.log"
PID_FILE="$STATE_DIR/fail-watch.pid"
SEEN_FILE="$STATE_DIR/fail-watch-seen"
INTERVAL="${WATCH_INTERVAL:-5}"
FAIL_MAX="${WATCH_FAIL_MAX:-3}"
AUTO_UNLOCK="${AUTO_UNLOCK_AFTER_MIN:-0}"

MODE="$(get_meta FAILMODE)"

notify() {
  local title="$1" msg="$2"
  /usr/bin/osascript -e "display notification \"$msg\" with title \"$title\"" 2>/dev/null || true
  echo "[$(date '+%F %T')] $title: $msg" >> "$LOG_FILE"
}

openvpn_alive() {
  /usr/bin/pgrep -f '/etc/openvpn-wm/client.ovpn' >/dev/null 2>&1
}

do_foreground() {
  ensure_dirs
  echo $$ > "$PID_FILE"
  trap 'rm -f "$PID_FILE"; exit 0' TERM INT EXIT
  local fail=0 started_at
  started_at="$(date +%s)"
  log_info "fail-watch 启动 mode=$MODE interval=${INTERVAL}s max=${FAIL_MAX} auto_unlock=${AUTO_UNLOCK}min"
  while true; do
    if openvpn_alive && /sbin/ping -c 1 -W 3 10.8.0.1 >/dev/null 2>&1; then
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
        "$SCRIPT_DIR/disconnect.sh" || true
        /bin/rm -f "$SEEN_FILE"
      else
        notify "老铁外贸网络管理系统" "VPN 断开超过 ${FAIL_MAX} 次检测，当前处于断网保护。紧急恢复请运行 openvpnwm-unlock"
      fi
      if [[ "$AUTO_UNLOCK" -gt 0 && $((down_secs / 60)) -ge $AUTO_UNLOCK ]]; then
        notify "老铁外贸网络管理系统" "达到自动解除时间，正在恢复本地网络"
        "$SCRIPT_DIR/unlock-network.sh" || true
      fi
      fail=0
    fi
    sleep "$INTERVAL"
  done
}

is_running() {
  [[ -f "$PID_FILE" ]] && /bin/kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

case "${1:-status}" in
  foreground)
    do_foreground
    ;;
  start)
    if is_running; then
      echo "已在运行 (pid=$(cat "$PID_FILE"))"
    else
      /bin/launchctl bootstrap system /Library/LaunchDaemons/com.openvpnwm.failwatch.plist 2>/dev/null \
        || /bin/launchctl load /Library/LaunchDaemons/com.openvpnwm.failwatch.plist 2>/dev/null || true
      sleep 1
      echo "fail-watch 已启动"
    fi
    ;;
  stop)
    /bin/launchctl bootout system /Library/LaunchDaemons/com.openvpnwm.failwatch.plist 2>/dev/null || true
    /bin/launchctl unload /Library/LaunchDaemons/com.openvpnwm.failwatch.plist 2>/dev/null || true
    rm -f "$PID_FILE"
    echo "fail-watch 已停止"
    ;;
  status)
    if is_running; then
      echo "fail-watch: 运行中 (pid=$(cat "$PID_FILE"))"
    else
      echo "fail-watch: 未运行"
    fi
    ;;
  *)
    echo "用法: $0 {start|stop|status|foreground}" >&2
    exit 1
    ;;
esac
