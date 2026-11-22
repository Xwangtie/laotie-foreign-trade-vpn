#!/bin/bash
# lib.sh - 通用函数库（被 macOS/Linux/Windows 脚本 source）
# 提供: 日志、锁、检测、状态文件、信号处理
#
# 用法:
#   source "$(dirname "$0")/../common/lib.sh"
#
# 提供的变量:
#   STATE_DIR  - 状态目录（默认 /var/run/openvpn-split，可被环境变量覆盖）
#   LOG_FILE   - 日志文件
#
# 提供的函数:
#   log_info / log_warn / log_error
#   lock / unlock
#   detect_vpn_iface / detect_local_gw / detect_dns
#   save_state / load_state / clear_state
#   cleanup_on_exit
#   require_root / require_cmd

# 防止重复 source
[[ -n "${_LIB_SH_LOADED:-}" ]] && return 0
_LIB_SH_LOADED=1

# 严格模式（sourced 时不启用 set -e，让 caller 控制）
# set -euo pipefail

# 路径
STATE_DIR="${STATE_DIR:-/var/run/openvpn-split}"
LOG_FILE="${LOG_FILE:-$STATE_DIR/split.log}"
LOCK_FILE="${LOCK_FILE:-$STATE_DIR/split.lock}"

# 颜色（如果终端支持）
if [[ -t 1 ]]; then
  _RED=$'\033[0;31m'; _GRN=$'\033[0;32m'; _YEL=$'\033[0;33m'; _BLU=$'\033[0;34m'; _NC=$'\033[0m'
else
  _RED=''; _GRN=''; _YEL=''; _BLU=''; _NC=''
fi

_ts() { date '+%Y-%m-%d %H:%M:%S'; }

log_info()  { echo -e "${_GRN}[$(_ts)] [INFO]${_NC}  $*" | tee -a "$LOG_FILE" >&2 ; }
log_warn()  { echo -e "${_YEL}[$(_ts)] [WARN]${_NC}  $*" | tee -a "$LOG_FILE" >&2 ; }
log_error() { echo -e "${_RED}[$(_ts)] [ERROR]${_NC} $*" | tee -a "$LOG_FILE" >&2 ; }
log_debug() { [[ "${DEBUG:-0}" = "1" ]] && echo -e "${_BLU}[$(_ts)] [DEBUG]${_NC} $*" | tee -a "$LOG_FILE" >&2 || true ; }

# 初始化状态目录
ensure_state_dir() {
  if [[ ! -d "$STATE_DIR" ]]; then
    mkdir -p "$STATE_DIR" 2>/dev/null || {
      # 权限不够时回退到用户家目录
      STATE_DIR="$HOME/.openvpn-split"
      LOG_FILE="$STATE_DIR/split.log"
      LOCK_FILE="$STATE_DIR/split.lock"
      mkdir -p "$STATE_DIR"
    }
  fi
  : >> "$LOG_FILE"  # 确保文件存在
}

# 互斥锁（避免 split-up 和 split-watch 抢资源）
lock() {
  ensure_state_dir
  if [[ -f "$LOCK_FILE" ]]; then
    local pid; pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      log_error "已有进程占用锁 (pid=$pid): $LOCK_FILE"
      return 1
    fi
    log_warn "陈旧锁，清理 (pid=$pid)"
    rm -f "$LOCK_FILE"
  fi
  echo $$ > "$LOCK_FILE"
}

unlock() {
  rm -f "$LOCK_FILE" 2>/dev/null || true
}

# 信号处理
cleanup_on_exit() {
  local rc=$?
  unlock
  exit "$rc"
}

# 检测本机默认网关（macOS/Linux）
# 返回: "IP dev IFACE"  形如 "192.168.1.1 dev en0"
detect_local_gw() {
  local os; os=$(uname -s)
  case "$os" in
    Darwin)
      local gw iface
      # 关键: openvpn 钩子 PATH 只有 /usr/bin:/bin, 必须补全
      export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/sbin:/bin:/usr/bin:$PATH"
      # 用绝对路径避免 PATH 问题
      local ROUTE_BIN="/sbin/route"
      [[ -x "$ROUTE_BIN" ]] || ROUTE_BIN="$(command -v route)"
      # 方法1: route -n get default
      gw=$("$ROUTE_BIN" -n get default 2>/dev/null | awk '/gateway:/ {print $2; exit}')
      iface=$("$ROUTE_BIN" -n get default 2>/dev/null | awk '/interface:/ {print $2; exit}')
      if [[ -n "$iface" && "$iface" != "lo0" && "$iface" != utun* ]]; then
        echo "$gw $iface"
        return 0
      fi
      # 方法2: route -n get <vpn_server> (当 default 是 utun 时兜底)
      if [[ -n "${TRUSTED_IP:-}" ]]; then
        gw=$("$ROUTE_BIN" -n get "$TRUSTED_IP" 2>/dev/null | awk '/gateway:/ {print $2; exit}')
        iface=$("$ROUTE_BIN" -n get "$TRUSTED_IP" 2>/dev/null | awk '/interface:/ {print $2; exit}')
        if [[ -n "$gw" && -n "$iface" && "$iface" != "lo0" && "$iface" != utun* ]]; then
          echo "$gw $iface"
          return 0
        fi
      fi
      # 方法3: netstat -nr
      local NETSTAT_BIN="/usr/sbin/netstat"
      [[ -x "$NETSTAT_BIN" ]] || NETSTAT_BIN="$(command -v netstat)"
      gw=$("$NETSTAT_BIN" -nr 2>/dev/null | awk '/^default/ && $2 !~ /:/ {print $2; exit}')
      iface=$("$NETSTAT_BIN" -nr 2>/dev/null | awk '/^default/ && $2 !~ /:/ {print $4; exit}')
      if [[ -n "$gw" && -n "$iface" ]]; then
        echo "$gw $iface"
        return 0
      fi
      log_error "无法检测 macOS 默认网关 (TRUSTED_IP=${TRUSTED_IP:-空})"
      return 1
      ;;
    Linux)
      local gw
      gw=$(/sbin/ip route show default 2>/dev/null | awk '/^default/ {print $3; exit}')
      local iface
      iface=$(/sbin/ip route show default 2>/dev/null | awk '/^default/ {print $5; exit}')
      if [[ -n "$gw" && -n "$iface" ]]; then
        echo "$gw $iface"
        return 0
      fi
      log_error "无法检测 Linux 默认网关"
      return 1
      ;;
    *)
      log_error "不支持的 OS: $os"
      return 1
      ;;
  esac
}

# 检测 VPN 接口（tun0 / utun0 / tap0 / tun1 / utun1）
# 返回: 接口名
detect_vpn_iface() {
  local hint="${1:-}"
  if [[ -n "$hint" ]]; then
    ifconfig "$hint" 2>/dev/null | grep -q "UP" && { echo "$hint"; return 0; }
  fi
  # macOS: utun0..utun9
  for i in 0 1 2 3 4 5 6 7 8 9; do
    if ifconfig "utun$i" 2>/dev/null | grep -q "UP"; then
      echo "utun$i"
      return 0
    fi
  done
  # Linux: tun0..tun3
  for i in 0 1 2 3; do
    if ip link show "tun$i" 2>/dev/null | grep -q "UP"; then
      echo "tun$i"
      return 0
    fi
  done
  # 通用: 任何名字含 tun 的
  ifconfig 2>/dev/null | awk '/^[^ ]+: flags=/ {iface=$1; gsub(":","",iface)} /UP/ && iface ~ /tun/ {print iface; exit}' && return 0
  return 1
}

# 检测系统 DNS
# 返回: 空格分隔的 DNS IP 列表
detect_dns() {
  local os; os=$(uname -s)
  case "$os" in
    Darwin)
      scutil --dns 2>/dev/null | awk '/nameserver\[0\]/ {print $3}' | head -3 | tr '\n' ' '
      ;;
    Linux)
      cat /etc/resolv.conf 2>/dev/null | awk '/^nameserver/ {print $2}' | head -3 | tr '\n' ' '
      ;;
    *)
      echo "1.1.1.1 8.8.8.8"
      ;;
  esac
}

# 状态文件操作 (key=value)
save_state() {
  ensure_state_dir
  local k="$1"; local v="$2"
  local f="$STATE_DIR/state.env"
  # 删旧的
  [[ -f "$f" ]] && grep -v "^$k=" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  echo "$k='$v'" >> "$f"
}

load_state() {
  local k="$1"
  local f="$STATE_DIR/state.env"
  [[ -f "$f" ]] || return 1
  # 用 awk 提取 value (兼容 BSD sed, 避免非贪婪正则)
  awk -F= -v key="$k" '
    $1 == key {
      val = $2
      # 去前后的单引号 (state 用 key='"'"'value'"'"' 存)
      if (val ~ /^'\''/) val = substr(val, 2)
      if (val ~ /'\''$/) val = substr(val, 1, length(val)-1)
      print val
      exit
    }
  ' "$f"
}

clear_state() {
  rm -f "$STATE_DIR/state.env"
}

# 检查 root
require_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "需要 root 权限（请用 sudo）"
    return 1
  fi
}

# 检查命令
require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "缺少命令: $cmd"
    return 1
  fi
}

# 解析 OpenVPN 环境变量（up/down 脚本会被 openvpn 设置很多环境变量）
# 常用:
#   $dev               tun 设备 (e.g. utun0)
#   $ifconfig_local    本地 VPN IP
#   $ifconfig_remote   VPN 网关（对端）
#   $route_vpn_gateway VPN 网关（route-up 特有）
#   $trusted_ip        真实远端 IP
#   $trusted_port      真实远端端口
