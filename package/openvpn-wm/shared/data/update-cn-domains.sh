#!/bin/bash
# update-cn-domains.sh - 拉取中国大陆加速域名列表
# 数据源: felixonmars/dnsmasq-china-list (6000+ 国内域名)
#
# 用法:
#   ./update-cn-domains.sh           # 拉 accelerated-domains.china.conf
#   ./update-cn-domains.sh --verify  # 拉完校验
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YEL=$'\033[0;33m'; NC=$'\033[0m'
log()  { echo -e "${GRN}[$(date '+%H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YEL}[$(date '+%H:%M:%S')]${NC} $*" >&2; }
err()  { echo -e "${RED}[$(date '+%H:%M:%S')]${NC} $*" >&2; }

# 国内镜像（CDN），GitHub raw 经常被 GFW 干扰
CHN_MIRROR="https://cdn.jsdelivr.net/gh/felixonmars/dnsmasq-china-list@master/accelerated-domains.china.conf"
BACKUP_MIRROR="https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/accelerated-domains.china.conf"

DO_VERIFY=0
for arg in "$@"; do
  case "$arg" in
    --verify) DO_VERIFY=1 ;;
    -h|--help)
      sed -n '2,8p' "$0"
      exit 0 ;;
  esac
done

backup() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  cp "$f" "${f}.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || sudo cp "$f" "${f}.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || { warn "无法备份 $f (可能 root 拥有)"; sudo chown $(whoami) "$f" 2>/dev/null; }
  ls -1t "${f}".bak.* 2>/dev/null | tail -n +6 | xargs -I{} rm -f {} 2>/dev/null || true
}

fetch() {
  local url="$1"; local out="$2"
  local max=1
  for i in $(seq 1 $max); do
    log "下载 [$i/$max] $url"
    if curl -fsSL --connect-timeout 10 --max-time 30 "$url" -o "$out.tmp"; then
      if head -c 200 "$out.tmp" | grep -qiE "<html|<!doctype"; then
        warn "返回了 HTML 页面，可能被劫持"
        rm -f "$out.tmp"
        continue
      fi
      mv "$out.tmp" "$out"
      return 0
    fi
    rm -f "$out.tmp"
    sleep 2
  done
  return 1
}

main() {
  log "==== update-cn-domains 开始 ===="
  log "==> 拉取 国内加速域名 (dnsmasq-china-list)"
  backup accelerated-domains.china.conf
  if fetch "$CHN_MIRROR" accelerated-domains.china.conf; then
    log "✅ 走 jsDelivr CDN 镜像"
  elif fetch "$BACKUP_MIRROR" accelerated-domains.china.conf; then
    warn "⚠️  走了 GitHub raw"
  else
    err "❌ 域名列表拉取失败"
    return 1
  fi
  local n; n=$(grep -cE '^(server=|server/)' accelerated-domains.china.conf 2>/dev/null || echo 0)
  log "   $n 条 server 规则"

  if [[ $DO_VERIFY -eq 1 ]]; then
    log "==> 校验格式"
    local bad
    bad=$(grep -vE '^(server=|server/|#|$)' accelerated-domains.china.conf || true)
    if [[ -n "$bad" ]]; then
      warn "发现 $(echo "$bad" | wc -l) 行非标准格式（前 3 行）:"
      echo "$bad" | head -3
    fi
  fi

  log "==== 完成 ===="
}

main "$@"
