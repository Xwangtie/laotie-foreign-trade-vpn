#!/bin/bash
# lib-openvpn-wm.sh — Linux 公共函数

ETC_DIR="/etc/openvpn-wm"
STATE_DIR="/run/openvpn-wm"
LOG_DIR="/var/log/openvpn-wm"
STATE_FILE="$STATE_DIR/state.env"
PROFILE_FILE="$ETC_DIR/profile.env"
OVPN_FILE="$ETC_DIR/client.ovpn"
CN4_FILE="$ETC_DIR/cn-ipv4.txt"
RESOLV_BACKUP="$STATE_DIR/resolv.conf.pre-openvpn-wm"
NFTRULES_FILE="$ETC_DIR/nft-rules.nft"

log_info() { echo "[openvpn-wm] $*"; }
log_error() { echo "[openvpn-wm][ERROR] $*" >&2; }

ensure_dirs() {
  /bin/mkdir -p "$ETC_DIR" "$STATE_DIR" "$LOG_DIR"
}

get_meta() {
  local key="$1" val=""
  if [[ -f "$PROFILE_FILE" ]]; then
    val="$(awk -F= -v k="$key" '$1==k {sub(/^[^=]*=/,""); print; exit}' "$PROFILE_FILE" || true)"
  fi
  printf '%s' "$val"
}

save_state() {
  ensure_dirs
  local key="$1" val="$2"
  /bin/sed -i "/^${key}=/d" "$STATE_FILE" 2>/dev/null || true
  printf '%s=%s\n' "$key" "$val" >> "$STATE_FILE"
}

load_state() {
  local key="$1"
  [[ -f "$STATE_FILE" ]] || return 1
  awk -F= -v k="$key" '$1==k {sub(/^[^=]*=/,""); print; exit}' "$STATE_FILE"
}

resolve_server_ip() {
  local input="${1:-}" out=""
  [[ -n "$input" ]] || return 1
  if /usr/bin/grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' <<<"$input"; then
    echo "$input"
    return 0
  fi
  out="$(/usr/bin/getent ahostsv4 "$input" 2>/dev/null | /usr/bin/awk '{print $1; exit}' || true)"
  echo "$out"
}

pin_server_hosts() {
  local server="${SERVER:-$(get_meta SERVER)}" ip=""
  /usr/bin/grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' <<<"$server" && return 0
  ip="$(resolve_server_ip "$server")"
  [[ -z "$ip" ]] && { log_error "无法解析 $server"; return 1; }
  /bin/sed -i '/# openvpn-wm pinned/d' /etc/hosts 2>/dev/null || true
  printf '%s\t%s # openvpn-wm pinned\n' "$ip" "$server" >> /etc/hosts
  log_info "已固定 $server -> $ip 到 /etc/hosts"
}

unpin_server_hosts() {
  /bin/sed -i '/# openvpn-wm pinned/d' /etc/hosts 2>/dev/null || true
}

set_vpn_dns() {
  ensure_dirs
  if [[ ! -f "$RESOLV_BACKUP" ]]; then
    /bin/cp -p /etc/resolv.conf "$RESOLV_BACKUP" 2>/dev/null || true
  fi
  printf 'nameserver 10.8.0.1\noptions timeout:1 attempts:2\n' > /etc/resolv.conf
  log_info "DNS 已指向 10.8.0.1"
}

restore_dns() {
  if [[ -f "$RESOLV_BACKUP" ]]; then
    /bin/cp -p "$RESOLV_BACKUP" /etc/resolv.conf
    /bin/rm -f "$RESOLV_BACKUP"
  fi
  log_info "DNS 已还原"
}
