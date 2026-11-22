"""服务端日志清理桥接。"""

from __future__ import annotations

import logging
import os
import subprocess

from ..config import get_settings

logger = logging.getLogger("openvpn-wm.logclean")


def _run(mode: str) -> str:
    settings = get_settings()
    args = [str(settings.log_clean_script), mode]
    if settings.s1_use_sudo and os.geteuid() != 0:
        args = ["sudo", "-n"] + args
    logger.info("logclean exec: %s", " ".join(args))
    proc = subprocess.run(
        args, capture_output=True, text=True, timeout=60, check=False
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr or proc.stdout or "清理命令失败")
    return (proc.stdout or "").strip()


def clean_logs() -> str:
    return _run("clean")


def retain_30_days() -> str:
    return _run("retain30")
