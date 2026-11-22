"""系统设置：VPN 局域网互访（全部互访 + 分组互访 1/2）。"""

from __future__ import annotations

import ipaddress
import json

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..audit import write_audit
from ..config import get_settings
from ..db import get_db
from ..deps import client_ip, require_roles
from ..models import Admin, SystemSetting, User
from ..services import openvpn_cli


router = APIRouter(prefix="/api/settings", tags=["settings"])
superadmin_only = require_roles("superadmin")

# 分组互访固定两个分组；静态隧道地址从 10.8.0.201-.250 分配，
# server.conf 的 ifconfig-pool 只用到 10.8.0.200，二者不会冲突。
GROUP_KEYS = {
    "group1": "vpn_group1_members",
    "group2": "vpn_group2_members",
}
GROUP_NAMES = {
    "group1": "分组互访1",
    "group2": "分组互访2",
}
STATIC_START = ipaddress.IPv4Address("10.8.0.201")
STATIC_END = ipaddress.IPv4Address("10.8.0.250")


def _get_flag(db: Session, key: str) -> bool:
    row = db.get(SystemSetting, key)
    return bool(row) and row.value.lower() in ("1", "true", "on")


def _set_flag(db: Session, key: str, value: bool) -> None:
    row = db.get(SystemSetting, key)
    if row is None:
        row = SystemSetting(key=key, value="1" if value else "0")
        db.add(row)
    else:
        row.value = "1" if value else "0"


def _get_list(db: Session, key: str) -> list[str]:
    row = db.get(SystemSetting, key)
    if row is None or not row.value.strip():
        return []
    try:
        value = json.loads(row.value)
    except ValueError:
        return []
    if not isinstance(value, list):
        return []
    return [str(item) for item in value if isinstance(item, str)]


def _set_list(db: Session, key: str, items: list[str]) -> None:
    value = json.dumps(items, ensure_ascii=False)
    row = db.get(SystemSetting, key)
    if row is None:
        db.add(SystemSetting(key=key, value=value))
    else:
        row.value = value


def _group_map(db: Session) -> dict[str, list[str]]:
    return {gid: _get_list(db, key) for gid, key in GROUP_KEYS.items()}


def _lan_state_payload(db: Session) -> dict[str, object]:
    return {
        "global_on": _get_flag(db, "vpn_lan_access"),
        "groups": _group_map(db),
    }


def _write_lan_state(db: Session) -> None:
    state_file = get_settings().lan_state_file
    state_file.parent.mkdir(parents=True, exist_ok=True)
    state_file.write_text(
        json.dumps(_lan_state_payload(db), ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


class LanModeBody(BaseModel):
    enabled: bool


class VpnGroupsBody(BaseModel):
    group1: list[str] = Field(default_factory=list, max_length=50)
    group2: list[str] = Field(default_factory=list, max_length=50)


@router.get("/vpn-lan")
def get_vpn_lan(db: Session = Depends(get_db), admin: Admin = Depends(superadmin_only)):
    return {"enabled": _get_flag(db, "vpn_lan_access")}


@router.put("/vpn-lan")
def set_vpn_lan(
    body: LanModeBody,
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    mode = "on" if body.enabled else "off"
    try:
        openvpn_cli.apply_lan_rules(mode, raise_on_error=True)
    except RuntimeError as exc:
        raise HTTPException(status_code=502, detail=str(exc))
    _set_flag(db, "vpn_lan_access", body.enabled)
    write_audit(
        db,
        admin,
        "settings.vpn_lan",
        detail={"enabled": body.enabled},
        ip=client_ip(request),
        commit=False,
    )
    db.commit()
    _write_lan_state(db)
    return {
        "enabled": body.enabled,
        "message": "已开启 VPN 局域网互访" if body.enabled else "已关闭 VPN 局域网互访",
    }


@router.get("/vpn-groups")
def get_vpn_groups(
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    group_map = _group_map(db)
    membership = {
        username: gid for gid, names in group_map.items() for username in names
    }
    users = db.execute(
        select(User).where(User.status != "revoked").order_by(User.username)
    ).scalars().all()
    return {
        "global_enabled": _get_flag(db, "vpn_lan_access"),
        "groups": [
            {
                "id": gid,
                "name": GROUP_NAMES[gid],
                "members": group_map[gid],
            }
            for gid in ("group1", "group2")
        ],
        "users": [
            {
                "username": user.username,
                "customer_name": user.customer_name,
                "status": user.status,
                "vpn_ip": user.vpn_ip,
                "in_group": membership.get(user.username),
            }
            for user in users
        ],
    }


def _next_static_ip(used: set[str]) -> str | None:
    used_ips = {str(ipaddress.IPv4Address(ip)) for ip in used}
    for offset in range(int(STATIC_END) - int(STATIC_START) + 1):
        candidate = str(STATIC_START + offset)
        if candidate not in used_ips:
            return candidate
    return None


@router.put("/vpn-groups")
def set_vpn_groups(
    body: VpnGroupsBody,
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    group1 = list(dict.fromkeys(body.group1))
    group2 = list(dict.fromkeys(body.group2))
    if len(group1) != len(body.group1) or len(group2) != len(body.group2):
        raise HTTPException(status_code=400, detail="同一分组内不能重复选择账号")
    overlap = set(group1) & set(group2)
    if overlap:
        names = "、".join(sorted(overlap))
        raise HTTPException(status_code=400, detail=f"{names} 不能同时加入两个分组")

    usernames = set(group1) | set(group2)
    users = (
        db.execute(select(User).where(User.username.in_(usernames)))
        .scalars()
        .all()
    )
    by_name = {user.username: user for user in users}
    if len(by_name) != len(usernames):
        raise HTTPException(status_code=400, detail="部分客户账号不存在")
    revoked = [user.username for user in users if user.status == "revoked"]
    if revoked:
        raise HTTPException(
            status_code=400,
            detail=f"已吊销账号不能加入分组：{', '.join(revoked)}",
        )

    old_group_map = _group_map(db)
    used_ips = {
        row
        for row in db.execute(
            select(User.vpn_ip).where(User.vpn_ip.is_not(None))
        ).scalars()
        if row
    }
    assigned: dict[str, str] = {}
    # 按 group1 -> group2 顺序分配，固定地址可预期
    for username in [*group1, *group2]:
        user = by_name[username]
        if user.vpn_ip is None:
            ip = _next_static_ip(used_ips)
            if ip is None:
                raise HTTPException(
                    status_code=400,
                    detail="分组静态隧道地址段(10.8.0.201-250)已用完",
                )
            user.vpn_ip = ip
            used_ips.add(ip)
            assigned[username] = ip

    _set_list(db, GROUP_KEYS["group1"], group1)
    _set_list(db, GROUP_KEYS["group2"], group2)
    db.flush()
    write_audit(
        db,
        admin,
        "settings.vpn_groups",
        detail={
            "old": old_group_map,
            "new": {"group1": group1, "group2": group2},
            "assigned_ips": assigned,
        },
        ip=client_ip(request),
        commit=False,
    )

    # 新分配固定 IP 的账号重建 CCD（含 ifconfig-push），重连后地址生效
    for username, ip in assigned.items():
        user = by_name[username]
        try:
            openvpn_cli.gen_ccd(user.username, user.profile, ip)
        except RuntimeError as exc:
            raise HTTPException(status_code=502, detail=f"写入固定IP配置失败：{exc}")

    db.commit()
    _write_lan_state(db)
    try:
        openvpn_cli.apply_lan_rules("sync", raise_on_error=True)
    except RuntimeError as exc:
        # 规则同步失败不撤销已保存分组；后台每 10 秒会自动重试
        raise HTTPException(
            status_code=502,
            detail=f"分组已保存，但防火墙规则同步失败：{exc}",
        )
    return {
        "message": "分组互访已保存",
        "groups": {"group1": group1, "group2": group2},
    }
