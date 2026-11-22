#!/bin/bash
# fail-watch.sh - VPN 断线守护
# 周期 ping VPN 网关，失败 N 次自动 split-down
#
# 用法:
#   ./fail-watch.sh start     # 守护模式（后台）
#   ./fail-watch.sh foreground # 前台运行（调试）
#   ./fail-watch.sh stop      # 停止
#   ./fail-watch.sh status    # 状态
#
# 环境变量:
#   VPN_GATEWAY       - VPN 对端 IP（必填或通过 state.env）
#   PING_INTERVAL     - 间隔秒数（默认 5）
#   PING_FAIL_MAX     - 连续失败次数触发回退（默认 3）
#   SPLIT_DOWN_SCRIPT - 回退时执行的脚本路径（默认本目录/../macos/bin/split-down.sh）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

STATE_FILE="$STATE_DIR/state.env"
PID_FILE="$STATE_DIR/fail-watch.pid"

cmd="${1:-status}"
SPLIT_DOWN_SCRIPT="${SPLIT_DOWN_SCRIPT:-$SCRIPT_DIR/../../方案A_纯客户端侧/macos/bin/split-down.sh}"

# 从 state.env 读 VPN_GATEWAY（如果没显式给）
if [[ -z "${VPN_GATEWAY:-}" && -f "$STATE_FILE" ]]; then
  VPN_GATEWAY="$(load_state VPN_GATEWAY || true)"
fi

is_running() {
  [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

do_foreground() {
  [[ -n "${VPN_GATEWAY:-}" ]] || { log_error "VPN_GATEWAY 未设置"; exit 1; }
  log_info "守护启动: gateway=$VPN_GATEWAY interval=${PING_INTERVAL:-5}s fail_max=${PING_FAIL_MAX:-3}"
  ensure_state_dir
  echo $$ > "$PID_FILE"
  trap 'rm -f "$PID_FILE"; log_info "守护退出"' EXIT INT TERM

  local fail=0
  while true; do
    if ping -c 1 -W "${PING_TIMEOUT:-3}" "$VPN_GATEWAY" >/dev/null 2>&1; then
      fail=0
    else
      fail=$((fail + 1))
      log_warn "ping VPN gateway 失败 ($fail/${PING_FAIL_MAX:-3})"
      if [[ $fail -ge "${PING_FAIL_MAX:-3}" ]]; then
        log_error "VPN 连续 ${PING_FAIL_MAX:-3} 次无响应，触发 fail-open（回退到本地）"
        if [[ -x "$SPLIT_DOWN_SCRIPT" ]]; then
          "$SPLIT_DOWN_SCRIPT" 2>&1 | tee -a "$LOG_FILE" || log_error "split-down 失败"
        else
          log_warn "split-down 脚本不存在或不可执行: $SPLIT_DOWN_SCRIPT"
        fi
        # 桌面通知（macOS / Linux 通用）
        if [[ "$(uname -s)" == "Darwin" ]]; then
          osascript -e 'display notification "VPN 断开，已回退到本地网络" with title "OpenVPN 分流"' 2>/dev/null || true
        elif command -v notify-send >/dev/null 2>&1; then
          notify-send "OpenVPN 分流" "VPN 断开，已回退到本地网络" 2>/dev/null || true
        fi
        # 退出循环，让用户重新连接
        rm -f "$PID_FILE"
        exit 0
      fi
    fi
    sleep "${PING_INTERVAL:-5}"
  done
}

do_start() {
  if is_running; then
    log_warn "守护已在运行 (pid=$(cat "$PID_FILE"))"
    return 0
  fi
  nohup "$0" foreground > "$LOG_FILE" 2>&1 &
  disown
  sleep 1
  if is_running; then
    log_info "守护已启动 (pid=$(cat "$PID_FILE"))"
  else
    log_error "守护启动失败，看日志: $LOG_FILE"
    return 1
  fi
}

do_stop() {
  if is_running; then
    local pid; pid=$(cat "$PID_FILE")
    kill "$pid" 2>/dev/null || true
    sleep 1
    if is_running; then kill -9 "$pid" 2>/dev/null || true; fi
    rm -f "$PID_FILE"
    log_info "守护已停止 (was pid=$pid)"
  else
    log_info "守护未在运行"
  fi
}

do_status() {
  if is_running; then
    echo "running (pid=$(cat "$PID_FILE"))"
    [[ -n "${VPN_GATEWAY:-}" ]] && echo "  gateway: $VPN_GATEWAY"
    return 0
  else
    echo "stopped"
    return 3
  fi
}

case "$cmd" in
  start)      do_start ;;
  foreground) do_foreground ;;
  stop)       do_stop ;;
  status)     do_status ;;
  restart)    do_stop; do_start ;;
  *)
    echo "Usage: $0 {start|foreground|stop|status|restart}" >&2
    exit 1
    ;;
esac
