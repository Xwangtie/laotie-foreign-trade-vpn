#!/bin/bash
# convert-domains.sh - 把 dnsmasq-china-list 转 smartdns / dnsmasq / 各种格式
#
# 用法:
#   ./convert-domains.sh smartdns   > cn-names-smartdns.txt
#   ./convert-domains.sh dnsmasq    > cn-names-dnsmasq.conf
#   ./convert-domains.sh unbound     > cn-names-unbound.conf
#   ./convert-domains.sh bind        > cn-names-bind.conf
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${DATA_DIR:-$SCRIPT_DIR/../data}"
SRC="${SRC:-$DATA_DIR/accelerated-domains.china.conf}"

[[ -f "$SRC" ]] || { echo "缺失: $SRC (请先运行 $DATA_DIR/update.sh)" >&2; exit 1; }

fmt="${1:-smartdns}"
CN_DNS="${CN_DNS:-223.5.5.5}"

case "$fmt" in
  smartdns)
    # smartdns 格式: nameserver /domain/ upstream
    # 跳过 server=  / server=/ 这类 dnsmasq 前缀
    grep '^server=' "$SRC" | sed -E 's/^server=\/(.*)\/.*/nameserver \/\1\/ '"$CN_DNS"'/' | sort -u
    ;;
  dnsmasq)
    # dnsmasq 原始格式（直接 copy 即可）
    cat "$SRC"
    ;;
  unbound)
    # unbound local-zone / local-data
    grep '^server=' "$SRC" | sed -E 's/^server=\/(.*)\/.*/local-zone "\1" redirect/' | sort -u
    echo "# nameserver 转发"
    echo 'forward-zone:'
    echo '  name: "."'
    echo "  forward-addr: $CN_DNS"
    ;;
  bind)
    grep '^server=' "$SRC" | sed -E 's/^server=\/(.*)\/.*/zone "\1" { type forward; forwarders { '"$CN_DNS"'; }; }/' | sort -u
    ;;
  *) echo "Usage: $0 {smartdns|dnsmasq|unbound|bind}" >&2; exit 1 ;;
esac
