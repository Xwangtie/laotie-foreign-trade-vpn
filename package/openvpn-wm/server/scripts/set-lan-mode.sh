#!/usr/bin/env bash
# set-lan-mode.sh on|off|sync
#   on    全部互访：写入 client-to-client 并重启 OpenVPN
#   off   关闭全部互访：移除 client-to-client 并重启；之后只放行“分组互访”成员
#   sync  不重启，仅按当前状态重建防火墙分组互访规则（面板定时刷新用）
#
# 规则说明：
#   - 分组互访 1 / 分组互访 2：同组在线客户可互相访问，两组互相隔离；
#   - 未加入任何分组的客户不能访问其它 VPN 客户；
#   - “全部互访”开启时优先级最高（全员互通），分组隔离暂时不生效。
set -euo pipefail

MODE="${1:-}"
CONF="${CONF:-/etc/openvpn/server.conf}"
STATE="${LAN_STATE_FILE:-/var/lib/openvpn-wm/lan-groups.json}"
STATUS_LOG="${STATUS_LOG:-/var/log/openvpn/status.log}"
CHAIN=OVPNWM-LAN
VPN_NET="${LAN_VPN_NET:-10.8.0.0/24}"

case "$MODE" in
  on)
    grep -q "^client-to-client" "$CONF" || echo "client-to-client" >> "$CONF"
    ;;
  off)
    sed -i "/^client-to-client/d" "$CONF"
    ;;
  sync)
    ;;
  *)
    echo "用法: $0 {on|off|sync}" >&2
    exit 2
    ;;
esac

if [[ "$MODE" == "on" || "$MODE" == "off" ]]; then
  systemctl restart openvpn@server.service
fi

# 防火墙规则由 Python 统一重建（root 执行，直接操作 iptables）
python3 - "$STATE" "$STATUS_LOG" "$CHAIN" "$VPN_NET" "$MODE" <<'PY'
import ipaddress
import json
import os
import subprocess
import sys

state_file, status_file, chain, vpn_net, mode = sys.argv[1:6]


def run(args, check=False):
    subprocess.run(args, check=check)


def ipt(*args):
    run(["iptables", *args])


def parse_online_ips(path: str) -> dict[str, str]:
    """从 OpenVPN status v1/v2 的路由表读取 {common_name: 隧道IP}。"""
    result: dict[str, str] = {}
    if not os.path.exists(path):
        return result
    in_route = False
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return result
    for raw in lines:
        line = raw.strip()
        if line.startswith("ROUTING TABLE"):
            in_route = True
            continue
        if line.startswith(("GLOBAL STATS", "END")):
            in_route = False
            continue
        if not in_route or "," not in line:
            continue
        if line.startswith("Virtual Address"):
            continue
        cells = [c.strip() for c in line.split(",")]
        if len(cells) < 2:
            continue
        ip_text, name = cells[0], cells[1]
        if not name:
            continue
        try:
            if ipaddress.ip_address(ip_text).version == 4:
                result[name] = ip_text
        except ValueError:
            continue
    return result


state: dict = {}
try:
    with open(state_file, encoding="utf-8") as fh:
        state = json.load(fh)
except (OSError, ValueError):
    state = {}

# on/off 由操作本身决定优先级；sync 按状态文件
if mode == "on":
    global_on = True
elif mode == "off":
    global_on = False
else:
    global_on = bool(state.get("global_on", False))

groups: dict[str, list[str]] = state.get("groups") or {}

# 先清空自有链与旧跳转，保证幂等
ipt("-N", chain)
ipt("-F", chain)
ipt("-D", "FORWARD", "-i", "tun+", "-o", "tun+", "-j", chain)
ipt("-D", "FORWARD", "-i", "tun+", "-o", "tun+", "-j", "ACCEPT")

if global_on:
    ipt("-A", "FORWARD", "-i", "tun+", "-o", "tun+", "-j", "ACCEPT")
else:
    online = parse_online_ips(status_file)
    group_ips: dict[str, list[str]] = {}
    for gid in ("group1", "group2"):
        group_ips[gid] = [
            online[u] for u in (groups.get(gid) or []) if online.get(u)
        ]

    # 同组在线成员双向放行
    for gid in ("group1", "group2"):
        ips = group_ips.get(gid) or []
        for src in ips:
            for dst in ips:
                if src != dst:
                    ipt("-A", chain, "-s", src, "-d", dst, "-j", "ACCEPT")

    # 未被上方放行的 VPN 客户端互访一律禁止
    ipt("-A", chain, "-s", vpn_net, "-d", vpn_net, "-j", "DROP")
    ipt("-A", chain, "-j", "RETURN")
    ipt("-I", "FORWARD", "1", "-i", "tun+", "-o", "tun+", "-j", chain)

# 保存规则，重启后仍生效
os.makedirs("/etc/iptables", exist_ok=True)
with open("/etc/iptables/rules.v4", "w", encoding="utf-8") as fh:
    subprocess.run(["iptables-save"], stdout=fh, check=True)
subprocess.run(
    ["ip6tables-save"],
    stdout=open("/etc/iptables/rules.v6", "w", encoding="utf-8"),
    check=False,
)
print(f"VPN局域网互访: {mode} (global_on={global_on})")
PY
