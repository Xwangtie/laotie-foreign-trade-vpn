#!/bin/bash
# update-cn-ip.sh - 拉取中国大陆 IP 段（IPv4 + IPv6）
# 数据源：
#   IPv4: misakaio/chnroutes2 (BGP 聚合, 每小时更新)
#   IPv6: gaoyifan/china-operator-ip china6.txt (BGP, 每日更新)
#
# 用法:
#   ./update-cn-ip.sh                # 拉取默认数据
#   ./update-cn-ip.sh --ipv4-only    # 只拉 IPv4
#   ./update-cn-ip.sh --ipv6-only    # 只拉 IPv6
#   ./update-cn-ip.sh --verify       # 拉完校验
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 颜色
RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YEL=$'\033[0;33m'; NC=$'\033[0m'
log()  { echo -e "${GRN}[$(date '+%H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YEL}[$(date '+%H:%M:%S')]${NC} $*" >&2; }
err()  { echo -e "${RED}[$(date '+%H:%M:%S')]${NC} $*" >&2; }

# 中国镜像优先（GFW 内访问 GitHub 不稳）
CHN_MIRROR_IPV4="https://china-operator-ip.yfgao.com/china.txt"
GLOBAL_IPV4="https://raw.githubusercontent.com/misakaio/chnroutes2/master/chnroutes.txt"
CHN_MIRROR_IPV6="https://china-operator-ip.yfgao.com/china6.txt"
GLOBAL_IPV6="https://gaoyifan.github.io/china-operator-ip/china6.txt"

IPV4_ONLY=0
IPV6_ONLY=0
DO_VERIFY=0
for arg in "$@"; do
  case "$arg" in
    --ipv4-only) IPV4_ONLY=1 ;;
    --ipv6-only) IPV6_ONLY=1 ;;
    --verify)    DO_VERIFY=1 ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0 ;;
  esac
done

# 备份旧的
backup() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  cp "$f" "${f}.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || sudo cp "$f" "${f}.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || { warn "无法备份 $f (可能 root 拥有)"; sudo chown $(whoami) "$f" 2>/dev/null; }
  # 只保留最近 5 个备份
  ls -1t "${f}".bak.* 2>/dev/null | tail -n +6 | xargs -I{} rm -f {} 2>/dev/null || true
}

# 拉一个文件（带 3 次重试 + 国内镜像优先）
fetch() {
  local url="$1"; local out="$2"
  local max=3
  for i in $(seq 1 $max); do
    log "下载 [$i/$max] $url"
    if curl -fsSL --connect-timeout 10 --max-time 60 "$url" -o "$out.tmp"; then
      # 检查是不是 HTML 错误页
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

# 拉 IPv4
fetch_ipv4() {
  log "==> 拉取 国内 IPv4 (chnroutes2)"
  backup cn-ipv4.txt
  # 先试国内镜像
  if fetch "$CHN_MIRROR_IPV4" cn-ipv4.txt; then
    log "✅ 走国内镜像"
  elif fetch "$GLOBAL_IPV4" cn-ipv4.txt; then
    warn "⚠️  走了 GitHub raw，国内访问可能慢"
  else
    err "❌ IPv4 拉取失败"
    return 1
  fi
  local n; n=$(wc -l < cn-ipv4.txt | tr -d ' ')
  log "   $n 条 CIDR"
}

# 拉 IPv6
fetch_ipv6() {
  log "==> 拉取 国内 IPv6 (china-operator-ip china6.txt)"
  backup cn-ipv6.txt
  if fetch "$CHN_MIRROR_IPV6" cn-ipv6.txt; then
    log "✅ 走国内镜像"
  elif fetch "$GLOBAL_IPV6" cn-ipv6.txt; then
    warn "⚠️  走了 GitHub Pages"
  else
    err "❌ IPv6 拉取失败"
    return 1
  fi
  local n; n=$(wc -l < cn-ipv6.txt | tr -d ' ')
  log "   $n 条 CIDR"
}

# 校验
verify() {
  local f="$1"
  [[ -f "$f" ]] || { err "不存在: $f"; return 1; }
  # 检查每行是合法 CIDR
  local bad
  bad=$(grep -vE '^[0-9a-fA-F:.]+/[0-9]+$' "$f" || true)
  if [[ -n "$bad" ]]; then
    err "$f 含有非法行:"
    echo "$bad" | head -5
    return 1
  fi
  # 去重并排序
  local orig; orig=$(wc -l < "$f" | tr -d ' ')
  sort -u "$f" -o "$f"
  local uniq; uniq=$(wc -l < "$f" | tr -d ' ')
  if [[ "$orig" != "$uniq" ]]; then
    warn "去重: $orig -> $uniq"
  fi
  log "✅ $f 校验通过 ($uniq 条)"
}

main() {
  log "==== update-cn-ip 开始 ===="
  if [[ $IPV6_ONLY -eq 0 ]]; then fetch_ipv4; fi
  if [[ $IPV4_ONLY -eq 0 ]]; then fetch_ipv6; fi
  if [[ $DO_VERIFY -eq 1 ]]; then
    log "==> 校验"
    [[ $IPV6_ONLY -eq 0 ]] && verify cn-ipv4.txt
    [[ $IPV4_ONLY -eq 0 ]] && verify cn-ipv6.txt
  fi
  log "==== 完成 ===="
}

main "$@"
