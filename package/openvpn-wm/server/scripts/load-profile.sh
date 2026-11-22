#!/bin/bash
# load-profile.sh - 校验并加载 profile 定义
# 用法: load-profile.sh <profile-id>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-common.sh
source "$SCRIPT_DIR/lib-common.sh"

PROFILE="${1:-}"
[[ -z "$PROFILE" ]] && { echo "用法: $0 <trade-global|trade-strict|game-open>" >&2; exit 2; }
load_profile "$PROFILE" || exit 1
ovpn_info "profile=$PROFILE name=$PROFILE_NAME split=$SPLIT failmode=$FAILMODE"
