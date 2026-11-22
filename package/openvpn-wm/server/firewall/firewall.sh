#!/bin/bash
# firewall.sh - 老铁外贸网络管理系统服务端防火墙（幂等）
# 用法: firewall.sh {apply|persist|status}
set -euo pipefail

SSH_PORT="${SSH_PORT:-12346}"
VPN_PORT="${VPN_PORT:-1194}"
HTTP_PORT="${HTTP_PORT:-80}"
HTTPS_PORT="${HTTPS_PORT:-443}"
IFACE="$(ip route show default | awk '/^default/ {print $5; exit}')"
IFACE="${IFACE:-eth0}"
CHAIN="OVPN-WM"
CHAIN_IN="OVPN-WM-IN"
CHAIN_NAT="OVPN-WM-NAT"
CHAIN_PM_FWD="OVPN-WM-PORTFWD"
CHAIN_PM_NAT="OVPN-WM-DNAT"

log() { echo "[firewall] $*"; }

ensure_jump() {
  local table="$1" chain="$2" target="$3"
  if [[ "$table" == "nat" ]]; then
    iptables -t nat -C "$chain" -j "$target" 2>/dev/null || iptables -t nat -I "$chain" 1 -j "$target"
  else
    iptables -C "$chain" -j "$target" 2>/dev/null || iptables -I "$chain" 1 -j "$target"
  fi
}

apply() {
  # 清空自有链再重建（不碰系统默认链旧规则，保证幂等）
  iptables -N "$CHAIN" 2>/dev/null || true
  iptables -F "$CHAIN"
  iptables -N "$CHAIN_IN" 2>/dev/null || true
  iptables -F "$CHAIN_IN"
  iptables -t nat -N "$CHAIN_NAT" 2>/dev/null || true
  iptables -t nat -F "$CHAIN_NAT"

  # INPUT：只放行 SSH / VPN / 已建立 / 回环 / ICMP，其余交给 INPUT DROP
  iptables -A "$CHAIN_IN" -p tcp --dport "$SSH_PORT" -j ACCEPT
  iptables -A "$CHAIN_IN" -p udp --dport "$VPN_PORT" -j ACCEPT
  iptables -A "$CHAIN_IN" -p tcp --dport "$HTTP_PORT" -j ACCEPT
  iptables -A "$CHAIN_IN" -p tcp --dport "$HTTPS_PORT" -j ACCEPT
  iptables -A "$CHAIN_IN" -m state --state ESTABLISHED,RELATED -j ACCEPT
  iptables -A "$CHAIN_IN" -i lo -j ACCEPT
  # VPN 客户端访问隧道内 DNS（10.8.0.1:53）与 OpenVPN 服务端口
  iptables -A "$CHAIN_IN" -i tun+ -p udp --dport 53 -j ACCEPT
  iptables -A "$CHAIN_IN" -i tun+ -p tcp --dport 53 -j ACCEPT
  iptables -A "$CHAIN_IN" -p icmp -j ACCEPT
  iptables -A "$CHAIN_IN" -j RETURN
  ensure_jump filter INPUT "$CHAIN_IN"

  # FORWARD：VPN tun <-> 外网（先清一次避免重复）
  iptables -F FORWARD
  # 端口映射专用链（保留规则，不清空；由 portmap.sh 维护）
  iptables -N "$CHAIN_PM_FWD" 2>/dev/null || true
  iptables -A FORWARD -j "$CHAIN_PM_FWD"
  iptables -t nat -N "$CHAIN_PM_NAT" 2>/dev/null || true
  iptables -t nat -C PREROUTING -j "$CHAIN_PM_NAT" 2>/dev/null || \
    iptables -t nat -I PREROUTING 1 -j "$CHAIN_PM_NAT"
  iptables -A FORWARD -o "$IFACE" -j ACCEPT
  iptables -A FORWARD -i "$IFACE" -o tun+ -m state --state ESTABLISHED,RELATED -j ACCEPT
  iptables -A FORWARD -i tun+ -o "$IFACE" -j ACCEPT
  iptables -P FORWARD DROP

  # OUTPUT DNS 策略：国内 DNS 明文放行；DoT 853 放行；其余明文 53 DROP；其它放行
  iptables -A "$CHAIN" -o lo -j ACCEPT
  iptables -A "$CHAIN" -p udp --dport 53 -d 223.5.5.5 -j ACCEPT
  iptables -A "$CHAIN" -p udp --dport 53 -d 119.29.29.29 -j ACCEPT
  iptables -A "$CHAIN" -p udp --dport 53 -d 114.114.114.114 -j ACCEPT
  iptables -A "$CHAIN" -p udp --dport 53 -j DROP
  iptables -A "$CHAIN" -p tcp --dport 53 -j DROP
  iptables -A "$CHAIN" -p tcp --dport 853 -j ACCEPT
  iptables -A "$CHAIN" -j RETURN
  ensure_jump filter OUTPUT "$CHAIN"

  # NAT
  iptables -t nat -A "$CHAIN_NAT" -o "$IFACE" -j MASQUERADE
  ensure_jump nat POSTROUTING "$CHAIN_NAT"

  # 默认策略（顺序陷阱：SSH 已先在 INPUT 链放行）
  iptables -P INPUT DROP
  iptables -P FORWARD DROP
  iptables -P OUTPUT ACCEPT

  # IPv6 全 DROP + 禁用
  ip6tables -P INPUT DROP 2>/dev/null || true
  ip6tables -P FORWARD DROP 2>/dev/null || true
  ip6tables -P OUTPUT DROP 2>/dev/null || true
  sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null || true
  log "apply done (iface=${IFACE} ssh=${SSH_PORT} vpn=${VPN_PORT})"
}

persist() {
  mkdir -p /etc/iptables
  iptables-save > /etc/iptables/rules.v4
  ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
  log "已保存 /etc/iptables"
}

status() {
  echo "== INPUT policy =="; iptables -S INPUT | head -20
  echo "== OVPN-WM 链 =="; iptables -S "$CHAIN" 2>/dev/null || echo "（链不存在）"
  echo "== NAT =="; iptables -t nat -S POSTROUTING | head -10
}

case "${1:-}" in
  apply) apply ;;
  persist) persist ;;
  status) status ;;
  *) echo "用法: $0 {apply|persist|status}"; exit 1 ;;
esac
