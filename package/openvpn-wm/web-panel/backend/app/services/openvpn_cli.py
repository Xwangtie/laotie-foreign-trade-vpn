"""与 S1 CLI 的桥接。S1 未就绪时自动回退 MOCK，保证面板可独立联调。"""

from __future__ import annotations

import logging
import os
import subprocess
from pathlib import Path

from ..config import get_settings


logger = logging.getLogger("openvpn-wm.cli")


def _profile_values(profile_id: str) -> dict[str, str]:
    settings = get_settings()
    conf = settings.profiles_dir / profile_id / "profile.conf"
    values: dict[str, str] = {
        "PROFILE_ID": profile_id,
        "PROFILE_NAME": profile_id,
        "SPLIT": "none",
        "FAILMODE": "close-all",
        "DESC": "",
    }
    if conf.exists():
        for line in conf.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def _use_mock() -> bool:
    settings = get_settings()
    if settings.mock_easy_rsa:
        return True
    required = [
        settings.gen_ccd_script,
        settings.gen_client_script,
        settings.revoke_client_script,
    ]
    if any(not p.exists() or not os.access(p, os.X_OK) for p in required):
        logger.warning("S1 脚本未就绪，自动使用 MOCK easyrsa 模式")
        return True
    return False


def _run(
    args: list[str],
    *,
    timeout: int = 90,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    logger.info("exec: %s", " ".join(args))
    if get_settings().s1_use_sudo and os.geteuid() != 0:
        args = ["sudo", "-n"] + args
    run_env = os.environ.copy()
    if env:
        run_env.update(env)
    return subprocess.run(
        args,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
        env=run_env,
    )


def _mock_ovpn(username: str, profile_id: str, remote_domain: str, remote_port: int) -> str:
    v = _profile_values(profile_id)
    header = "\n".join(
        [
            f"# PROFILE={profile_id}",
            f"# FAILMODE={v.get('FAILMODE', 'close-all')}",
            f"# SPLIT={v.get('SPLIT', 'none')}",
            f"# SERVER={remote_domain}",
            f"# PORT={remote_port}",
        ]
    )
    body = f"""\
{header}

# 老铁外贸网络管理系统 - 示例 MOCK .ovpn（S1 上线前仅用于流程联调）
client
dev tun
proto udp
remote {remote_domain} {remote_port}
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
data-ciphers AES-256-GCM
auth SHA256
verb 3
mute 20
max-routes 8192
script-security 2

<ca>
-----BEGIN CERTIFICATE-----
MOCK_CA
-----END CERTIFICATE-----
</ca>
<cert>
-----BEGIN CERTIFICATE-----
MOCK_CERT_{username}
-----END CERTIFICATE-----
</cert>
<key>
-----BEGIN PRIVATE KEY-----
MOCK_KEY_{username}
-----END PRIVATE KEY-----
</key>

# 客服电话: 13905394878
# 客服邮箱: ymwww@qq.com
"""
    return body


def gen_ccd(username: str, profile_id: str, static_ip: str | None = None) -> None:
    settings = get_settings()
    if _use_mock():
        return
    args = [str(settings.gen_ccd_script), username, profile_id]
    if static_ip:
        args.append(static_ip)
    proc = _run(args)
    if proc.returncode != 0:
        raise RuntimeError(f"gen-ccd 失败: {proc.stderr or proc.stdout}")


def gen_client_ovpn(
    username: str, profile_id: str, remote_domain: str, remote_port: int
) -> str:
    settings = get_settings()
    if _use_mock():
        return _mock_ovpn(username, profile_id, remote_domain, remote_port)
    proc = _run(
        [
            str(settings.gen_client_script),
            username,
            profile_id,
            "",  # outdir 占位（stdout 输出）
            remote_domain,
            str(remote_port),
        ],
    )
    if proc.returncode != 0 or not proc.stdout.strip():
        raise RuntimeError(f"gen-client 失败: {proc.stderr or proc.stdout}")
    return proc.stdout


def revoke_user(username: str) -> None:
    settings = get_settings()
    if _use_mock():
        return
    proc = _run([str(settings.revoke_client_script), username])
    if proc.returncode != 0:
        raise RuntimeError(f"revoke-client 失败: {proc.stderr or proc.stdout}")


def kill_user(username: str) -> None:
    settings = get_settings()
    if _use_mock() or not settings.vpn_kill_script.exists():
        logger.info("MOCK kill user=%s", username)
        return
    proc = _run([str(settings.vpn_kill_script), username], timeout=20)
    if proc.returncode != 0:
        logger.warning("vpn-kill 非零退出: %s", proc.stderr or proc.stdout)


def suspend_user(username: str) -> None:
    """暂停 = 通过受控脚本移走 CCD 文件（吊销更重，仅用于彻底停用）。"""
    settings = get_settings()
    if _use_mock():
        return
    script = settings.suspend_ccd_script
    if not script.exists() or not os.access(script, os.X_OK):
        raise RuntimeError(f"暂停脚本不存在或不可执行: {script}")
    proc = _run([str(script), username], timeout=20)
    if proc.returncode != 0:
        raise RuntimeError(f"suspend-client 失败: {proc.stderr or proc.stdout}")


def resume_user(username: str, profile_id: str, static_ip: str | None = None) -> None:
    gen_ccd(username, profile_id, static_ip)


def apply_lan_rules(mode: str = "sync", *, raise_on_error: bool = False) -> None:
    """调用服务端 set-lan-mode.sh 同步“全部互访 / 分组互访”防火墙规则。

    mode: on=全部互访开（重启 OpenVPN）；off=全部互访关（重启）；
          sync=只按当前状态重建规则（分组增删/定时刷新用，不重启）。
    """
    settings = get_settings()
    if _use_mock():
        logger.info("MOCK lan rules mode=%s", mode)
        return
    script = settings.lan_mode_script
    if not script.exists() or not os.access(script, os.X_OK):
        logger.warning("set-lan-mode.sh 不存在或不可执行，跳过: %s", script)
        return
    proc = _run([str(script), mode], timeout=30)
    if proc.returncode != 0:
        msg = f"LAN 规则同步失败({mode}): {proc.stderr or proc.stdout}"
        if raise_on_error:
            raise RuntimeError(msg)
        logger.warning(msg)


def is_mock_mode() -> bool:
    return _use_mock()
