#!/bin/bash
# install-client.sh — macOS/Linux 通用安装器
# 用法: sudo ./install-client.sh <xxx.ovpn>
set -euo pipefail

usage() {
  echo "用法: sudo $0 <xxx.ovpn>" >&2
  exit 1
}

OVPN="${1:-}"
if [[ -z "$OVPN" || ! -f "$OVPN" ]]; then
  echo "错误: 缺少 .ovpn 文件或文件不存在" >&2
  usage
fi

# 解析 S1 契约头
PROFILE="$(awk -F= '/^# PROFILE=/{print $2; exit}' "$OVPN" | tr -d '[:space:]' || true)"
FAILMODE="$(awk -F= '/^# FAILMODE=/{print $2; exit}' "$OVPN" | tr -d '[:space:]' || true)"
SPLIT="$(awk -F= '/^# SPLIT=/{print $2; exit}' "$OVPN" | tr -d '[:space:]' || true)"
SERVER="$(awk -F= '/^# SERVER=/{print $2; exit}' "$OVPN" | tr -d '[:space:]' || true)"
PORT="$(awk -F= '/^# PORT=/{print $2; exit}' "$OVPN" | tr -d '[:space:]' || true)"

missing=0
for k in PROFILE FAILMODE SPLIT SERVER PORT; do
  if [[ -z "${!k}" ]]; then
    echo "错误: .ovpn 文件头缺少 # $k= 行（S1 契约），拒绝安装" >&2
    missing=1
  fi
done
[[ "$missing" -eq 0 ]] || exit 1

case "$FAILMODE" in
  close-all|close-foreign|open) ;;
  *) echo "错误: 未知 FAILMODE=$FAILMODE" >&2; exit 1 ;;
esac

if [[ $(id -u) -ne 0 ]]; then
  echo "请用 sudo 执行: sudo $0 $OVPN" >&2
  exit 1
fi

OS="$(uname -s)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OVPN PROFILE FAILMODE SPLIT SERVER PORT SCRIPT_DIR

case "$OS" in
  Darwin)  exec "$SCRIPT_DIR/macos/install-macos.sh" ;;
  Linux)   exec "$SCRIPT_DIR/linux/install-linux.sh" ;;
  *) echo "错误: 不支持的平台 $OS（Windows 请用 install-client.ps1）" >&2; exit 1 ;;
esac
