#!/bin/bash
# gen-routes.sh - 把 cn-ipv4.txt 转成各种格式的路由命令
#
# 用法:
#   ./gen-routes.sh macos         # 生成 macOS route add 命令
#   ./gen-routes.sh linux-ipset   # 生成 Linux ipset restore 格式
#   ./gen-routes.sh linux-route   # 生成 Linux route add 命令
#   ./gen-routes.sh windows       # 生成 Windows route add (PowerShell 友好)
#   ./gen-routes.sh openvpn       # 生成 OpenVPN route 指令块（嵌进 .conf）
#   ./gen-routes.sh pf-table      # 生成 macOS pf table 加载块
#   ./gen-routes.sh ip6-route     # 生成 macOS route add -inet6
#
# 输入:
#   $DATA_DIR/cn-ipv4.txt   (默认 ../data)
#   $DATA_DIR/cn-ipv6.txt
#   $DATA_DIR/private-ranges.txt
#   $DATA_DIR/private-ranges6.txt
#
# 输出 (stdout): 路由命令，注释以 # 开头
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${DATA_DIR:-$SCRIPT_DIR/../data}"

RED=$'\033[0;31m'; GRN=$'\033[0;32m'; NC=$'\033[0m'
log() { echo -e "${GRN}[gen-routes]${NC} $*" >&2; }
err() { echo -e "${RED}[gen-routes]${NC} $*" >&2; }

usage() {
  cat <<EOF
Usage: $0 <format>
  format:
    macos            macOS route add 格式
    linux-route      Linux route add 格式
    linux-ipset      Linux ipset restore 格式
    windows          Windows route add 格式
    openvpn          OpenVPN route 指令块
    pf-table         macOS pf table 加载格式
    ip6-route        macOS IPv6 route add 格式
    all              全部输出到当前目录（生成 route-cmd-*.txt）

环境变量:
  DATA_DIR    数据目录路径 (默认 $DATA_DIR)
  GATEWAY     本地网关 IP（部分格式需要）
  METRIC      路由 metric (默认 100)
EOF
}

[[ $# -lt 1 ]] && { usage; exit 1; }
FMT="$1"

# 加载数据
CN4="$DATA_DIR/cn-ipv4.txt"
CN6="$DATA_DIR/cn-ipv6.txt"
PR4="$DATA_DIR/private-ranges.txt"
PR6="$DATA_DIR/private-ranges6.txt"

for f in "$CN4" "$PR4"; do
  [[ -f "$f" ]] || { err "缺失数据文件: $f (请先运行 $DATA_DIR/update.sh)"; exit 1; }
done

# 把 CIDR 转 "ip mask" 形式（给 macOS route / Windows route 用）
cidr_to_ipmask() {
  awk -F/ '{
    n = $2; split($1, a, ".");
    # 计算 netmask
    if (n == 0) mask = "0.0.0.0"
    else {
      m = 0; for (i=0; i<n; i++) m = m * 2 + 1
      mask = sprintf("%d.%d.%d.%d",
        int(m/16777216), int(m/65536)%256, int(m/256)%256, m%256)
    }
    print a[1]"."a[2]"."a[3]"."a[4], mask
  }'
}

gen_macos_ipv4() {
  echo "# macOS IPv4: 国内 + 私有网段 → 本地网关"
  echo "# 生成时间: $(date)"
  echo "# 共 $(wc -l < "$CN4" | tr -d ' ') 条国内 + $(wc -l < "$PR4" | tr -d ' ') 条私有"
  cat "$CN4" "$PR4" 2>/dev/null | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' | while read -r cidr; do
    cidr_to_ipmask <<< "$cidr" | while read -r ip mask; do
      printf "route add -net %s %s \"\$GATEWAY\"\n" "$ip" "$mask"
    done
  done
}

gen_linux_route() {
  echo "# Linux route add: 国内 → 本地网关"
  echo "# 生成时间: $(date)"
  cat "$CN4" "$PR4" 2>/dev/null | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' | while read -r cidr; do
    printf "ip route add %s via \$GATEWAY metric %s\n" "$cidr" "${METRIC:-100}"
  done
}

gen_linux_ipset() {
  echo "# ipset restore 格式"
  echo "create cn hash:net family inet maxelem 200000 -exist"
  echo "flush cn"
  cat "$CN4" "$PR4" 2>/dev/null | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' | awk '{print "add cn " $1}'
}

gen_windows() {
  echo "REM Windows route add: 国内 → 本地网关"
  echo "REM 生成时间: %date% %time%"
  cat "$CN4" "$PR4" 2>/dev/null | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' | while read -r cidr; do
    cidr_to_ipmask <<< "$cidr" | while read -r ip mask; do
      printf "route add %s mask %s %%gw%% metric %s\n" "$ip" "$mask" "${METRIC:-100}"
    done
  done
}

gen_openvpn() {
  echo "# OpenVPN route 指令块（粘贴到 .ovpn 文件 max-routes NUM 之后）"
  echo "# 生成时间: $(date)"
  echo "# 总路由条数:"
  echo "#   $(cat "$CN4" "$PR4" 2>/dev/null | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ') 条"
  echo ""
  cat "$CN4" "$PR4" 2>/dev/null | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' | while read -r cidr; do
    cidr_to_ipmask <<< "$cidr" | while read -r ip mask; do
      printf "route %s %s net_gateway\n" "$ip" "$mask"
    done
  done
}

gen_pf_table() {
  echo "# macOS pf table 加载块（嵌进 .conf）"
  echo "# 用法: pfctl -a split -f - < pf-table-block.txt"
  echo ""
  echo "table <cn> persist {"
  cat "$CN4" 2>/dev/null | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' | awk '{printf "  %s\n", $1}'
  echo "}"
  if [[ -f "$CN6" ]]; then
    echo ""
    echo "table <cn6> persist {"
    cat "$CN6" 2>/dev/null | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' | awk '{printf "  %s\n", $1}'
    echo "}"
  fi
  if [[ -f "$PR4" ]]; then
    echo ""
    echo "table <private> persist {"
    cat "$PR4" 2>/dev/null | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' | awk '{printf "  %s\n", $1}'
    echo "}"
  fi
}

gen_ip6_route() {
  [[ -f "$CN6" ]] || { err "缺 IPv6 数据: $CN6"; return 1; }
  echo "# macOS route add -inet6: 国内 IPv6 → 本地网关（需要去掉 block-ipv6）"
  echo "# 生成时间: $(date)"
  cat "$CN6" 2>/dev/null | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' | while read -r cidr; do
    printf "route add -inet6 %s \"\$GATEWAY\"\n" "$cidr"
  done
}

case "$FMT" in
  macos)         gen_macos_ipv4 ;;
  linux-route)   gen_linux_route ;;
  linux-ipset)   gen_linux_ipset ;;
  windows)       gen_windows ;;
  openvpn)       gen_openvpn ;;
  pf-table)      gen_pf_table ;;
  ip6-route)     gen_ip6_route ;;
  all)
    gen_macos_ipv4    > route-cmd-macos.txt
    gen_linux_route   > route-cmd-linux.txt
    gen_linux_ipset   > route-cmd-ipset.txt
    gen_windows       > route-cmd-windows.txt
    gen_openvpn       > route-cmd-openvpn.txt
    gen_pf_table      > route-cmd-pf-table.txt
    gen_ip6_route     > route-cmd-ip6.txt 2>/dev/null || true
    log "全部格式已生成到当前目录"
    ls -la route-cmd-*.txt
    ;;
  -h|--help) usage ;;
  *) err "未知格式: $FMT"; usage; exit 1 ;;
esac
