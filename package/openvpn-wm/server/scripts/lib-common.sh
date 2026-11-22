#!/bin/bash
# lib-common.sh - S1 服务端公共函数与路径（被 server/scripts 与 deploy 引用）

[[ -n "${_OVPNWM_LIB_COMMON:-}" ]] && return 0
_OVPNWM_LIB_COMMON=1

OPENVPN_DIR="${OPENVPN_DIR:-/etc/openvpn}"
PROFILE_DIR="${PROFILE_DIR:-$OPENVPN_DIR/profiles}"
CCD_DIR="${CCD_DIR:-$OPENVPN_DIR/ccd}"
DATA_DIR="${DATA_DIR:-$OPENVPN_DIR/data}"
EASYRSA_DIR="${EASYRSA_DIR:-$OPENVPN_DIR/easy-rsa}"
SCRIPT_DIR_REPO="${SCRIPT_DIR_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

STATE_DIR="${STATE_DIR:-/var/lib/openvpn-wm}"
AUTH_DB="${AUTH_DB:-$STATE_DIR/panel.db}"
LOG_DIR="${LOG_DIR:-/var/log/openvpn}"
MGMT_ADDR="${MGMT_ADDR:-127.0.0.1}"
MGMT_PORT="${MGMT_PORT:-8989}"

VPN_SERVER_HOST="${VPN_SERVER_HOST:-vpn.example.com}"
VPN_PORT="${VPN_PORT:-1194}"
USERNAME_RE='^[a-zA-Z0-9_-]{1,32}$'

_c_green=$'\033[0;32m'; _c_red=$'\033[0;31m'; _c_yellow=$'\033[0;33m'; _c_reset=$'\033[0m'

ovpn_info()  { echo -e "${_c_green}[S1]${_c_reset} $*" >&2; }
ovpn_warn()  { echo -e "${_c_yellow}[S1][warn]${_c_reset} $*" >&2; }
ovpn_err()   { echo -e "${_c_red}[S1][error]${_c_reset} $*" >&2; }

validate_username() {
  [[ "$1" =~ $USERNAME_RE ]]
}

require_username() {
  [[ -n "$1" ]] || { ovpn_err "用法: $0 <username> [<profile>]"; exit 2; }
  validate_username "$1" || { ovpn_err "用户名不合法（仅允许 a-zA-Z0-9_-，长度 3-32）: $1"; exit 2; }
}

load_profile() {
  local profile_id="$1" conf required missing=0 v
  conf="$PROFILE_DIR/$profile_id/profile.conf"
  [[ -f "$conf" ]] || { ovpn_err "找不到 profile: $conf"; return 1; }
  # 重置上次 source 的变量
  unset PROFILE_ID PROFILE_NAME SPLIT FAILMODE IPV6 DNS_MODE LAN_ACCESS EGRESS_ACL DESC 2>/dev/null || true
  # shellcheck disable=SC1090
  source "$conf"
  required=(PROFILE_ID PROFILE_NAME SPLIT FAILMODE)
  for v in "${required[@]}"; do
    if [[ -z "${!v:-}" ]]; then
      ovpn_err "profile $profile_id 缺少必填字段: $v"
      missing=1
    fi
  done
  [[ $missing -eq 0 ]]
}

ensure_dirs() {
  mkdir -p "$CCD_DIR" "$STATE_DIR"
  mkdir -p "$LOG_DIR" 2>/dev/null || true
}
