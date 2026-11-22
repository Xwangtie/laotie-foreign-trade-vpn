#!/bin/bash
# suspend-client.sh - 暂停客户时安全移除其 CCD 配置
# 用法: suspend-client.sh <username>
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-common.sh
source "$SCRIPT_DIR/lib-common.sh"

USER="${1:-}"
require_username "$USER"

CCD_FILE="$CCD_DIR/$USER"
ARCHIVE_DIR="$STATE_DIR/suspended-ccd"

if [[ ! -e "$CCD_FILE" ]]; then
  ovpn_info "CCD 已不存在，无需暂停: $USER"
  exit 0
fi

install -d -m 700 "$ARCHIVE_DIR"
mv -f "$CCD_FILE" "$ARCHIVE_DIR/$USER"
ovpn_info "已暂停客户 CCD: $USER"
