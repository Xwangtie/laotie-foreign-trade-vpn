#!/bin/bash
# lib-openvpn-wm.sh — macOS 公共函数（绝对路径，避免 OpenVPN 钩子 PATH 问题）

ETC_DIR="/etc/openvpn-wm"
STATE_DIR="/var/run/openvpn-wm"
LOG_DIR="/var/log/openvpn-wm"
STATE_FILE="$STATE_DIR/state.env"
PROFILE_FILE="$ETC_DIR/profile.env"
OVPN_FILE="$ETC_DIR/client.ovpn"
CN4_FILE="$ETC_DIR/cn-ipv4.txt"
PF_ANCHOR_DIR="/etc/pf.anchors"
PF_ANCHOR="$PF_ANCHOR_DIR/openvpn-wm"
PF_CONF="/etc/pf.conf"
PF_BACKUP="/etc/pf.conf.openvpn-wm.bak"

log_info() { echo "[openvpn-wm] $*"; }
log_error() { echo "[openvpn-wm][ERROR] $*" >&2; }

ensure_dirs() {
  /bin/mkdir -p "$ETC_DIR" "$STATE_DIR" "$LOG_DIR" "$PF_ANCHOR_DIR"
  /usr/sbin/chown root:wheel "$ETC_DIR" "$STATE_DIR" "$LOG_DIR" 2>/dev/null || true
  /bin/chmod 0755 "$ETC_DIR" "$STATE_DIR" "$LOG_DIR"
}

load_profile_env() {
  # 输出到 stdout: KEY=value；未安装时返回 1
  [[ -f "$PROFILE_FILE" ]] || { log_error "未找到 $PROFILE_FILE"; return 1; }
  set -a
  # shellcheck disable=SC1090
  source "$PROFILE_FILE"
  set +a
}

get_meta() {
  # get_meta KEY
  local key="$1" val=""
  if [[ -f "$PROFILE_FILE" ]]; then
    val="$(awk -F= -v k="$key" '$1==k {sub(/^[^=]*=/,""); print; exit}' "$PROFILE_FILE" || true)"
  fi
  printf '%s' "$val"
}

save_state() {
  # save_state KEY VALUE
  ensure_dirs
  local key="$1" val="$2"
  if [[ -f "$STATE_FILE" ]]; then
    /usr/bin/sed -i '' "/^${key}=/d" "$STATE_FILE" 2>/dev/null || true
  fi
  printf '%s=%s\n' "$key" "$val" >> "$STATE_FILE"
}

load_state() {
  local key="$1"
  [[ -f "$STATE_FILE" ]] || return 1
  awk -F= -v k="$key" '$1==k {sub(/^[^=]*=/,""); print; exit}' "$STATE_FILE"
}

resolve_server_ip() {
  # 输入 hostname 或 IP，输出第一个 A 记录（无法解析则原样返回）
  local input="${1:-}"
  [[ -n "$input" ]] || return 1
  if /usr/bin/grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' <<<"$input"; then
    echo "$input"
    return 0
  fi
  /usr/bin/dscacheutil -q host -a name "$input" 2>/dev/null | /usr/bin/awk '/ip_address/{print $2; exit}' || true
}

pin_server_hosts() {
  # 域名 remote 固定到 /etc/hosts，保证 kill-switch 生效后无需 DNS 即可重连
  local server="${SERVER:-$(get_meta SERVER)}" ip=""
  /usr/bin/grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' <<<"$server" && return 0
  ip="$(resolve_server_ip "$server")"
  if [[ -z "$ip" ]]; then
    log_error "无法解析服务器域名 $server；无法固定 hosts，请检查网络后重试"
    return 1
  fi
  ensure_dirs
  /usr/bin/sed -i '' '/# openvpn-wm pinned/d' /etc/hosts 2>/dev/null || true
  printf '%s\t%s # openvpn-wm pinned\n' "$ip" "$server" >> /etc/hosts
  log_info "已将 $server -> $ip 固定到 /etc/hosts（卸载时自动移除）"
}

unpin_server_hosts() {
  /usr/bin/sed -i '' '/# openvpn-wm pinned/d' /etc/hosts 2>/dev/null || true
}

find_active_service() {
  # 找到当前有 IP 的活动网络服务名（不写死 Wi-Fi）
  local ports dev svc ip
  /usr/sbin/networksetup -listallhardwareports 2>/dev/null | \
  awk '/^Hardware Port:/{svc=$0; sub(/^Hardware Port: /,"",svc)} /^Device:/{dev=$2; print dev"\t"svc}' | \
  while IFS=$'\t' read -r dev svc; do
    ip="$(/usr/sbin/ipconfig getifaddr "$dev" 2>/dev/null || true)"
    if [[ -n "$ip" ]]; then
      echo "$svc"
      return 0
    fi
  done
  return 1
}

set_vpn_dns() {
  local svc
  svc="$(find_active_service || true)"
  if [[ -z "$svc" ]]; then
    log_error "找不到活动网络服务，无法设置 DNS"
    return 1
  fi
  # 记录原 DNS 以便还原
  if [[ -z "$(load_state DNS_BACKUP || true)" ]]; then
    local old
    old="$(/usr/sbin/networksetup -getdnsservers "$svc" 2>/dev/null | /usr/bin/grep -E '^[0-9.]' | /usr/bin/paste -sd ',' - || true)"
    save_state DNS_BACKUP "${old:-Empty}"
  fi
  /usr/sbin/networksetup -setdnsservers "$svc" 10.8.0.1 || log_error "设置 DNS 失败"
  log_info "DNS 已指向 10.8.0.1 ($svc)"
}

restore_dns() {
  local svc backup
  svc="$(find_active_service || true)"
  backup="$(load_state DNS_BACKUP || true)"
  [[ -z "$svc" ]] && return 0
  if [[ -n "$backup" && "$backup" != "Empty" ]]; then
    IFS=',' read -r -a arr <<<"$backup"
    /usr/sbin/networksetup -setdnsservers "$svc" "${arr[@]}" 2>/dev/null || true
  else
    /usr/sbin/networksetup -setdnsservers "$svc" Empty 2>/dev/null || true
  fi
  /usr/bin/sed -i '' '/^DNS_BACKUP=/d' "$STATE_FILE" 2>/dev/null || true
  log_info "DNS 已还原"
}

pf_running() {
  /sbin/pfctl -s info 2>/dev/null | /usr/bin/grep -q 'Status: Enabled'
}

anchor_loaded() {
  /sbin/pfctl -a openvpn-wm -s rules 2>/dev/null | /usr/bin/grep -q . 
}
