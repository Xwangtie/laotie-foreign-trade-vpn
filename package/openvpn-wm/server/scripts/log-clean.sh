#!/bin/bash
# log-clean.sh - 服务端日志清理
# 用法:
#   log-clean.sh clean       立即清空全部运行日志（保留文件本身）
#   log-clean.sh retain30    只保留 30 天内日志（删除更早轮转/压缩日志）
#   log-clean.sh stats       查看日志占用
set -euo pipefail

LOG_FILES=(
  /var/log/openvpn/openvpn.log
  /var/log/openvpn/status.log
  /var/log/openvpn/client-connect.log
  /var/log/openvpn/vpn-auth.log
  /var/log/openvpn/dns-policy.log
  /var/log/nginx/access.log
  /var/log/nginx/error.log
)

clean() {
  for f in "${LOG_FILES[@]}"; do
    if [[ -f "$f" ]]; then
      truncate -s 0 "$f" || true
    fi
  done
  # 立即删除已轮转/压缩的旧日志，等价于“清空所有日志”
  find /var/log/openvpn /var/log/nginx -type f \
    \( -name '*.gz' -o -name '*.1' -o -name '*.old' \) -delete 2>/dev/null || true
  echo "日志已清空"
}

retain30() {
  find /var/log/openvpn /var/log/nginx -type f \
    \( -name '*.gz' -o -name '*.1' -o -name '*.old' \) -mtime +30 -delete 2>/dev/null || true
  # 系统日志只保留 30 天
  journalctl --vacuum-time=30d 2>/dev/null || true
  echo "已清理超过 30 天的日志"
}

stats() {
  du -sh /var/log/openvpn /var/log/nginx 2>/dev/null || true
  echo "--- openvpn ---"
  ls -lh /var/log/openvpn 2>/dev/null || true
  echo "--- nginx ---"
  ls -lh /var/log/nginx/*.log* 2>/dev/null | head -20 || true
}

case "${1:-}" in
  clean) clean ;;
  retain30) retain30 ;;
  stats) stats ;;
  *) echo "用法: $0 {clean|retain30|stats}" >&2; exit 2 ;;
esac
