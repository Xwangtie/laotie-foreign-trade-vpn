"""端口映射：把面板记录同步成服务器 NAT 转发规则。"""

from __future__ import annotations

import logging
import os
import subprocess

from ..config import get_settings

logger = logging.getLogger("openvpn-wm.portmap")

PROTO_EXPAND = {
    "tcp": ["tcp"],
    "udp": ["udp"],
    "tcpudp": ["tcp", "udp"],
}


def _run(args: list[str], timeout: int = 30) -> subprocess.CompletedProcess[str]:
    settings = get_settings()
    if settings.s1_use_sudo and os.geteuid() != 0:
        args = ["sudo", "-n"] + args
    logger.info("portmap exec: %s", " ".join(args))
    return subprocess.run(
        args, capture_output=True, text=True, timeout=timeout, check=False
    )


def script_ready() -> bool:
    return get_settings().portmap_script.exists()


def add_rule(
    ext_port: int,
    protocol: str,
    dest_ip: str,
    int_port: int,
) -> None:
    if not script_ready():
        logger.warning("portmap 脚本不存在，跳过 add ext=%s", ext_port)
        return
    proc = _run(
        [
            str(get_settings().portmap_script),
            "add",
            str(ext_port),
            protocol,
            dest_ip,
            str(int_port),
        ]
    )
    if proc.returncode != 0:
        raise RuntimeError(f"端口映射添加失败: {proc.stderr or proc.stdout}")


def remove_rule(
    ext_port: int,
    protocol: str,
    dest_ip: str,
    int_port: int,
) -> None:
    if not script_ready():
        logger.warning("portmap 脚本不存在，跳过 del ext=%s", ext_port)
        return
    proc = _run(
        [
            str(get_settings().portmap_script),
            "del",
            str(ext_port),
            protocol,
            dest_ip,
            str(int_port),
        ]
    )
    if proc.returncode != 0:
        logger.warning(
            "端口映射删除失败 ext=%s: %s", ext_port, proc.stderr or proc.stdout
        )


def sync_all(rules: list[dict]) -> str:
    """开发/运维用：按现有 DB 规则重建 iptables（脚本 reload 全量）。"""
    if not script_ready():
        return "script missing"
    payload = "\n".join(
        f"{r['ext_port']} {r['protocol']} {r['dest_ip']} {r['int_port']}"
        for r in rules
    )
    import tempfile

    with tempfile.NamedTemporaryFile("w", suffix=".portmap", delete=False) as f:
        f.write(payload)
        path = f.name
    try:
        proc = _run([str(get_settings().portmap_script), "reload", path])
        if proc.returncode != 0:
            raise RuntimeError(f"端口映射重建失败: {proc.stderr or proc.stdout}")
        return proc.stdout or ""
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass
