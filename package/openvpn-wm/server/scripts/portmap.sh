#!/bin/bash
# portmap.sh - 后台 NAT 端口转发（供面板 openvpnwm 用户经 sudo 白名单调用）
# 用法:
#   portmap.sh add <ext_port> <tcp|udp|tcpudp> <dest_ip> <int_port>
#   portmap.sh del <ext_port> <tcp|udp|tcpudp> <dest_ip> <int_port>
#   portmap.sh reload <rules-file>   # 按文件全量重建：每行 "ext proto ip int"
#   portmap.sh list
set -euo pipefail

NAT_CHAIN="OVPN-WM-DNAT"
FWD_CHAIN="OVPN-WM-PORTFWD"
IFACE="$(ip route show default | awk '/^default/ {print $5; exit}')"
IFACE="${IFACE:-eth0}"

log() { echo "[portmap] $*" >&2; }

protox() {
  case "$1" in
    tcp) echo tcp ;;
    udp) echo udp ;;
    tcpudp) echo -e "tcp\nudp" ;;
    *) echo "协议仅支持 tcp/udp/tcpudp: $1" >&2; exit 2 ;;
  esac
}

ensure_chains() {
  iptables -t nat -N "$NAT_CHAIN" 2>/dev/null || true
  iptables -N "$FWD_CHAIN" 2>/dev/null || true
  iptables -t nat -C PREROUTING -j "$NAT_CHAIN" 2>/dev/null || \
    iptables -t nat -I PREROUTING 1 -j "$NAT_CHAIN"
  iptables -C FORWARD -j "$FWD_CHAIN" 2>/dev/null || \
    iptables -I FORWARD 1 -j "$FWD_CHAIN"
}

persist() {
  mkdir -p /etc/iptables
  iptables-save > /etc/iptables/rules.v4
}

add_one() {
  local proto="$1" ext="$2" ip="$3" int="$4"
  iptables -t nat -C "$NAT_CHAIN" -p "$proto" --dport "$ext" \
    -j DNAT --to-destination "$ip:$int" 2>/dev/null || \
    iptables -t nat -A "$NAT_CHAIN" -p "$proto" --dport "$ext" \
      -j DNAT --to-destination "$ip:$int"
  iptables -C "$FWD_CHAIN" -i "$IFACE" -o tun+ -p "$proto" \
    --dport "$int" -d "$ip" -m state --state NEW,ESTABLISHED,RELATED \
    -j ACCEPT 2>/dev/null || \
    iptables -A "$FWD_CHAIN" -i "$IFACE" -o tun+ -p "$proto" \
      --dport "$int" -d "$ip" -m state --state NEW,ESTABLISHED,RELATED \
      -j ACCEPT
}

del_one() {
  local proto="$1" ext="$2" ip="$3" int="$4"
  iptables -t nat -D "$NAT_CHAIN" -p "$proto" --dport "$ext" \
    -j DNAT --to-destination "$ip:$int" 2>/dev/null || true
  iptables -D "$FWD_CHAIN" -i "$IFACE" -o tun+ -p "$proto" \
    --dport "$int" -d "$ip" -m state --state NEW,ESTABLISHED,RELATED \
    -j ACCEPT 2>/dev/null || true
}

flush_rules() {
  iptables -t nat -F "$NAT_CHAIN" 2>/dev/null || true
  iptables -F "$FWD_CHAIN" 2>/dev/null || true
}

case "${1:-}" in
  add)
    [[ $# -eq 5 ]] || { echo "用法: $0 add <ext> <tcp|udp|tcpudp> <ip> <int>" >&2; exit 2; }
    ensure_chains
    while read -r p; do
      add_one "$p" "$2" "$4" "$5"
    done < <(protox "$3")
    persist
    log "added ext=$2 -> $4:$5 ($3)"
    ;;
  del)
    [[ $# -eq 5 ]] || { echo "用法: $0 del <ext> <tcp|udp|tcpudp> <ip> <int>" >&2; exit 2; }
    ensure_chains
    while read -r p; do
      del_one "$p" "$2" "$4" "$5"
    done < <(protox "$3")
    persist
    log "deleted ext=$2"
    ;;
  reload)
    [[ -f "${2:-}" ]] || { echo "用法: $0 reload <rules-file>" >&2; exit 2; }
    ensure_chains
    flush_rules
    while read -r ext proto ip int; do
      [[ -n "${ext:-}" && "$ext" != "#"* ]] || continue
      while read -r p; do
        add_one "$p" "$ext" "$ip" "$int"
      done < <(protox "$proto")
    done < "$2"
    persist
    log "reloaded from $2"
    ;;
  list)
    ensure_chains
    iptables -t nat -S "$NAT_CHAIN"
    ;;
  *)
    echo "用法: $0 {add|del|reload|list}" >&2
    exit 2
    ;;
esac
