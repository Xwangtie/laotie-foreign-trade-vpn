#!/bin/bash
# update.sh - 一键更新所有 IP 段 + 域名数据
#
# 用法:
#   ./update.sh               # 拉全部 + 校验
#   ./update.sh --no-verify   # 不校验
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED=$'\033[0;31m'; GRN=$'\033[0;32m'; NC=$'\033[0m'
log() { echo -e "${GRN}[$(date '+%H:%M:%S')]${NC} $*"; }

DO_VERIFY=1
for arg in "$@"; do
  case "$arg" in
    --no-verify) DO_VERIFY=0 ;;
    -h|--help)
      cat <<EOF
update.sh - 一键更新所有 IP 段 + 域名数据
  --no-verify   拉完不校验
EOF
      exit 0 ;;
  esac
done

EXTRA=""
[[ $DO_VERIFY -eq 1 ]] && EXTRA="--verify"

log "==== 更新 国内 IP 段 (IPv4 + IPv6) ===="
./update-cn-ip.sh $EXTRA

log "==== 更新 国内加速域名 ===="
./update-cn-domains.sh $EXTRA

log "==== 当前数据文件 ===="
ls -la *.txt *.conf 2>/dev/null | grep -v '\.bak\.' || true

log "✅ 全部更新完成"
