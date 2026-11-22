#!/bin/bash
# update-data.sh - 每月更新国内 IP 段 + 国内域名表，失败回滚上一版
set -uo pipefail

DATA_DIR="${DATA_DIR:-/etc/openvpn/data}"
DOMAIN_DST="${DOMAIN_DST:-/etc/dnsmasq.d/china-domains.conf}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

URL_CN4=( "https://raw.githubusercontent.com/misakaio/chnroutes2/master/chnroutes.txt"
          "https://cdn.jsdelivr.net/gh/misakaio/chnroutes2@master/chnroutes.txt" )
URL_DOM=( "https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/accelerated-domains.china.conf"
          "https://cdn.jsdelivr.net/gh/felixonmars/dnsmasq-china-list@master/accelerated-domains.china.conf" )

fetch_ok() { # $1 out $2 min $3...url
  local out="$1" min="$2"; shift 2
  local tmp; tmp="$(mktemp)"
  for u in "$@"; do
    if curl -fsSL --connect-timeout 15 --max-time 180 "$u" -o "$tmp" 2>/dev/null; then
      local n; n=$(grep -vc '^#\|^$' "$tmp" 2>/dev/null || echo 0)
      if (( n >= min )); then
        [[ -f "$out" ]] && cp "$out" "$out.prev"
        mv "$tmp" "$out"
        echo "ok $out ($n)"
        return 0
      fi
    fi
  done
  rm -f "$tmp"
  echo "fail $out" >&2
  return 1
}

mkdir -p "$DATA_DIR"
fetch_ok "$DATA_DIR/cn-ipv4.txt" 3000 "${URL_CN4[@]}"
CN_OK=$?
fetch_ok "$DATA_DIR/accelerated-domains.china.conf" 50000 "${URL_DOM[@]}"
DOM_OK=$?

if (( CN_OK != 0 || DOM_OK != 0 )); then
  echo "更新失败，保留上一版 .prev" >&2
  exit 1
fi

# 国内域名上游统一指向本机 ECS DNS 代理（127.0.0.1#5354），
# 该代理带中国客户端子网查询 223.5.5.5/119.29.29.29，
# 避免海外 VPS 查询公共 DNS 时被 GEO 返回海外 CDN 节点。
[[ -f "$DOMAIN_DST" ]] && cp "$DOMAIN_DST" "$DOMAIN_DST.prev"
sed 's#/114\.114\.114\.114#/127.0.0.1#5354#g' \
  "$DATA_DIR/accelerated-domains.china.conf" > "$DOMAIN_DST"

# 重建所有客户 CCD（保留各自 profile）
for ccd in /etc/openvpn/ccd/*; do
  [[ -f "$ccd" ]] || continue
  user="$(basename "$ccd")"
  profile="$(grep -m1 '^# profile=' "$ccd" | sed 's/^# profile=//' | awk '{print $1}')"
  static_ip="$(grep -m1 '^ifconfig-push ' "$ccd" | awk '{print $2}')"
  if [[ -n "$profile" ]]; then
    bash "$SCRIPT_DIR/gen-ccd.sh" "$user" "$profile" "$static_ip"
  fi
done

systemctl restart dnsmasq 2>/dev/null || systemctl reload dnsmasq 2>/dev/null || true
echo "数据更新完成 $(date -u)"
