#!/bin/bash
# gen-ccd.sh - 生成 CCD：profile 决定推送哪些路由（幂等）
# 用法: gen-ccd.sh <username> <profile> [static_ip]
# static_ip 可选：加入“分组互访”的客户由面板分配 10.8.0.201-.250 固定隧道 IP。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-common.sh
source "$SCRIPT_DIR/lib-common.sh"

USER="${1:-}"
PROFILE="${2:-}"
STATIC_IP="${3:-}"
require_username "$USER"
[[ -n "$PROFILE" ]] || { echo "用法: $0 <username> <profile>" >&2; exit 2; }
load_profile "$PROFILE" || exit 1
ensure_dirs
if [[ -n "$STATIC_IP" ]]; then
  if ! python3 - "$STATIC_IP" <<'PY'
import ipaddress, sys
try:
    ip = ipaddress.ip_address(sys.argv[1])
except ValueError:
    raise SystemExit(f"not an ip: {sys.argv[1]}")
raise SystemExit(0 if ip.version == 4 else 1)
PY
  then
    ovpn_err "static_ip 不是合法 IPv4: $STATIC_IP"
    exit 2
  fi
fi

CN4="$DATA_DIR/cn-ipv4.txt"
PR4="$DATA_DIR/private-ranges.txt"
[[ -f "$CN4" ]] || { ovpn_err "缺少国内 IP 数据: $CN4"; exit 1; }

CCD_FILE="$CCD_DIR/$USER"
mkdir -p "$CCD_DIR"
: > "$CCD_FILE"
{
  echo "# CCD for $USER (老铁外贸网络管理系统)"
  echo "# profile=$PROFILE split=${SPLIT:-none} generated=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ -n "$STATIC_IP" ]]; then
    echo "# static_ip=$STATIC_IP"
    echo "ifconfig-push $STATIC_IP 255.255.255.0"
  fi
} > "$CCD_FILE"

if [[ "${SPLIT:-none}" == "cn-bypass" ]]; then
  python3 - "$CN4" "$CCD_FILE" "${LAN_ACCESS:-0}" "${PR4:-}" "${CN_ROUTE_LIMIT:-1300}" <<'PY'
import ipaddress, sys
cn4, out, lan, pr4 = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
limit = int(sys.argv[5])
cn_nets = []
with open(cn4, encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            n = ipaddress.ip_network(line, strict=False)
        except ValueError:
            continue
        cn_nets.append(n)

# 大网段优先的精简直连表：
# macOS/Windows/iOS 官方 OpenVPN Connect 对一次推送的总字节按“条数+参数”计费，
# 全量 4147 条已超过旧版 256KB / 新版 768KB 的可容纳范围（实测均报 too large）。
# 默认只推前 1300 个最大的国内网段（约覆盖 98.7% 国内 IPv4 地址空间），
# 客户端数量可控、连接稳定；可通过 CN_ROUTE_LIMIT 覆盖。
cn_nets.sort(key=lambda n: n.num_addresses, reverse=True)
cn_nets = cn_nets[:limit]

private_nets = []
if lan == "1" and pr4:
    try:
        with open(pr4, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                n = ipaddress.ip_network(line, strict=False)
                private_nets.append(n)
    except OSError:
        pass

routes = cn_nets + private_nets
total_cn_addr = sum(n.num_addresses for n in cn_nets)
all_cn_addr = 0
for line in open(cn4, encoding="utf-8"):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    try:
        all_cn_addr += ipaddress.ip_network(line, strict=False).num_addresses
    except ValueError:
        pass
coverage = 100.0 * total_cn_addr / all_cn_addr if all_cn_addr else 0.0

with open(out, "a", encoding="utf-8") as f:
    f.write(
        f"# CN bypass push routes: {len(routes)} "
        f"(CN={len(cn_nets)}, coverage~{coverage:.1f}%, private={len(private_nets)})\n"
    )
    for n in routes:
        # OpenVPN Connect 不接受 CIDR 简写（会把整条路由静默丢弃），
        # 必须保持 “IP + 掩码” 形式。net_gateway = 客户端本地网关
        f.write(f'push "route {n.network_address} {n.netmask} net_gateway"\n')
PY
else
  {
    echo "# SPLIT=none: 无 CN 例外路由，全部流量由 server.conf 默认走 VPN"
  } >> "$CCD_FILE"
fi

# DNS：只有“全局代理”强制走 VPN 内网 DNS；分流方案由客户端本地 DNS 解析，
# 否则美国服务器上的 dnsmasq 会把百度/QQ/淘宝等国内域名解析成海外 CDN 节点。
if [[ "${DNS_MODE:-local}" == "vpn-only" ]]; then
  echo 'push "dhcp-option DNS 10.8.0.1"' >> "$CCD_FILE"
fi

COUNT=$(grep -c '^push "route ' "$CCD_FILE" || true)
ovpn_info "已生成 CCD: ${CCD_FILE} (routes=${COUNT})"
