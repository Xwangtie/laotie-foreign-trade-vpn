"""开户、用户管理、续期、吊销、暂停、下载 .ovpn。"""

from __future__ import annotations

from datetime import datetime, timedelta
from urllib.parse import quote

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from fastapi.responses import Response
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..audit import write_audit
from ..config import get_settings
from ..dateutils import add_months
from ..db import get_db
from ..deps import client_ip, get_current_admin
from ..models import Admin, DownloadToken, Node, PortMapping, User
from ..schemas import (
    ApiMessage,
    ProfileOut,
    RenewRequest,
    UserCreate,
    UserCreated,
    UserListPage,
    UserOut,
    UserPasswordReset,
    UserUpdate,
)
from ..security import (
    encrypt_vpn_password,
    hash_vpn_password,
    new_download_token,
    utcnow,
)
from ..services import openvpn_cli, portmap, profiles as profile_service


router = APIRouter(prefix="/api", tags=["users"])


def _normalize_dt(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is not None:
        value = value.astimezone().replace(tzinfo=None)
    return value


def _get_user_or_404(db: Session, user_id: int) -> User:
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "用户不存在")
    return user


def _default_node(db: Session) -> Node:
    node = db.execute(
        select(Node).where(Node.status == "active").order_by(Node.id).limit(1)
    ).scalar_one_or_none()
    if node is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "尚未配置可用节点")
    return node


@router.get("/profiles", response_model=list[ProfileOut])
def list_profiles(
    admin: Admin = Depends(get_current_admin),
):
    settings = get_settings()
    return [
        ProfileOut(**item) for item in profile_service.list_profiles(settings.profiles_dir)
    ]


@router.post("/users", response_model=UserCreated, status_code=status.HTTP_201_CREATED)
def create_user(
    body: UserCreate,
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    existing = db.execute(
        select(User).where(User.username == body.username)
    ).scalar_one_or_none()
    if existing:
        raise HTTPException(status.HTTP_409_CONFLICT, "用户名已存在")
    node = db.get(Node, body.node_id) if body.node_id else None
    if node is None:
        node = _default_node(db)
    if node.status != "active":
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "所选节点不可用")

    # 先验证 S1 可生成配置，再落库；失败则整笔回滚
    try:
        openvpn_cli.gen_ccd(body.username, body.profile)
        openvpn_cli.gen_client_ovpn(
            body.username, body.profile, node.public_domain, node.openvpn_port
        )
    except Exception as exc:
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY, f"服务端生成配置失败：{exc}"
        )

    expire_at = _normalize_dt(body.expire_at) or (utcnow() + timedelta(days=30))
    user = User(
        username=body.username,
        profile=body.profile,
        customer_name=(body.customer_name or "").strip(),
        phone=(body.phone or "").strip(),
        company=(body.company or "").strip(),
        email=body.email or "",
        node_id=node.id,
        status="active",
        expire_at=expire_at,
        quota_bytes=body.quota_bytes,
        remark=body.remark,
        embed_password=body.embed_password,
        password_hash=hash_vpn_password(body.connection_password)
        if body.connection_password
        else None,
        password_encrypted=encrypt_vpn_password(body.connection_password)
        if body.connection_password
        else None,
    )
    db.add(user)
    db.flush()
    token = new_download_token()
    db.add(
        DownloadToken(
            token=token,
            user_id=user.id,
            expires_at=utcnow() + timedelta(minutes=5),
        )
    )
    write_audit(
        db,
        admin,
        "user.create",
        target_type="user",
        target_id=user.id,
        detail={
            "username": user.username,
            "profile": user.profile,
            "node": node.public_domain,
            "expire_at": expire_at.isoformat(),
        },
        ip=client_ip(request),
        commit=False,
    )
    db.commit()
    db.refresh(user)
    return UserCreated(
        **UserOut.model_validate(user).model_dump(),
        download_token=token,
        connection_password=body.connection_password,
    )


@router.get("/users", response_model=UserListPage)
def list_users(
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=200),
    q: str | None = None,
    profile: str | None = None,
    user_status: str | None = Query(default=None, alias="status"),
    db: Session = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    stmt = select(User)
    if q:
        like = f"%{q}%"
        stmt = stmt.where(
            (User.username.like(like))
            | (User.customer_name.like(like))
            | (User.phone.like(like))
            | (User.company.like(like))
            | (User.email.like(like))
        )
    if profile:
        stmt = stmt.where(User.profile == profile)
    if user_status:
        stmt = stmt.where(User.status == user_status)
    total = db.execute(select(func.count()).select_from(stmt.subquery())).scalar_one()
    rows = (
        db.execute(
            stmt.order_by(User.id.desc()).offset((page - 1) * page_size).limit(page_size)
        )
        .scalars()
        .all()
    )
    return UserListPage(total=total, items=[UserOut.model_validate(u) for u in rows])


@router.get("/users/{user_id}", response_model=UserOut)
def get_user(
    user_id: int,
    db: Session = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    return _get_user_or_404(db, user_id)


@router.patch("/users/{user_id}", response_model=UserOut)
def update_user(
    user_id: int,
    body: UserUpdate,
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    user = _get_user_or_404(db, user_id)
    changed: dict[str, object] = {}
    for field, value in body.model_dump(exclude_unset=True).items():
        if value is not None:
            setattr(user, field, value)
            if isinstance(value, datetime):
                changed[field] = value.isoformat()
            else:
                changed[field] = value
    write_audit(
        db,
        admin,
        "user.update",
        target_type="user",
        target_id=user.id,
        detail={"username": user.username, "changed": changed},
        ip=client_ip(request),
        commit=False,
    )
    db.commit()
    db.refresh(user)
    return user


@router.post("/users/{user_id}/reset-password", response_model=ApiMessage)
def reset_user_password(
    user_id: int,
    body: UserPasswordReset,
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    user = _get_user_or_404(db, user_id)
    user.password_hash = hash_vpn_password(body.password)
    user.password_encrypted = encrypt_vpn_password(body.password)
    # 密码一改，强制断开当前在线会话，防止旧设备继续使用
    try:
        openvpn_cli.kill_user(user.username)
    except Exception as exc:
        # 踢线失败不阻塞改密
        pass
    write_audit(
        db,
        admin,
        "user.reset_password",
        target_type="user",
        target_id=user.id,
        detail={"username": user.username},
        ip=client_ip(request),
        commit=False,
    )
    db.commit()
    return ApiMessage(message=f"客户 {user.username} 连接密码已重置，旧设备已踢下线")


@router.post("/users/{user_id}/renew", response_model=UserOut)
def renew_user(
    user_id: int,
    body: RenewRequest,
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    user = _get_user_or_404(db, user_id)
    if user.status == "revoked":
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "已吊销账号需重新开户，不能续期")
    base = max(_normalize_dt(user.expire_at) or utcnow(), utcnow())
    new_expire = add_months(base, body.months)
    old_expire = user.expire_at
    user.expire_at = new_expire
    if user.status == "expired":
        user.status = "active"
    write_audit(
        db,
        admin,
        "user.renew",
        target_type="user",
        target_id=user.id,
        detail={
            "username": user.username,
            "months": body.months,
            "old_expire": old_expire.isoformat(),
            "new_expire": new_expire.isoformat(),
        },
        ip=client_ip(request),
        commit=False,
    )
    db.commit()
    db.refresh(user)
    return user


@router.post("/users/{user_id}/suspend", response_model=UserOut)
def suspend_user(
    user_id: int,
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    user = _get_user_or_404(db, user_id)
    if user.status == "revoked":
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "账号已吊销")
    user.status = "suspended"
    try:
        openvpn_cli.suspend_user(user.username)
        openvpn_cli.kill_user(user.username)
    except Exception as exc:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, f"暂停失败：{exc}")
    write_audit(
        db,
        admin,
        "user.suspend",
        target_type="user",
        target_id=user.id,
        detail={"username": user.username},
        ip=client_ip(request),
        commit=False,
    )
    db.commit()
    db.refresh(user)
    return user


@router.post("/users/{user_id}/resume", response_model=UserOut)
def resume_user(
    user_id: int,
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    user = _get_user_or_404(db, user_id)
    if user.status == "revoked":
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "已吊销账号不能恢复")
    try:
        openvpn_cli.resume_user(user.username, user.profile, user.vpn_ip)
    except Exception as exc:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, f"恢复失败：{exc}")
    user.status = "active"
    write_audit(
        db,
        admin,
        "user.resume",
        target_type="user",
        target_id=user.id,
        detail={"username": user.username},
        ip=client_ip(request),
        commit=False,
    )
    db.commit()
    db.refresh(user)
    return user


@router.post("/users/{user_id}/revoke", response_model=UserOut)
def revoke_user(
    user_id: int,
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    user = _get_user_or_404(db, user_id)
    if user.status == "revoked":
        return user
    try:
        openvpn_cli.revoke_user(user.username)
        openvpn_cli.kill_user(user.username)
    except Exception as exc:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, f"吊销失败：{exc}")
    user.status = "revoked"
    write_audit(
        db,
        admin,
        "user.revoke",
        target_type="user",
        target_id=user.id,
        detail={"username": user.username},
        ip=client_ip(request),
        commit=False,
    )
    db.commit()
    db.refresh(user)
    return user


@router.delete("/users/{user_id}", response_model=ApiMessage)
def delete_user(
    user_id: int,
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    """删除客户：仅允许已吊销账号，删除前自动清理该客户的端口映射。"""
    user = _get_user_or_404(db, user_id)
    if user.status != "revoked":
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "客户尚未吊销，必须完成吊销后才能删除",
        )

    # 保险起见再次断开可能残留的在线会话
    openvpn_cli.kill_user(user.username)

    mappings = db.execute(
        select(PortMapping).where(PortMapping.user_id == user.id)
    ).scalars().all()
    for mapping in mappings:
        portmap.remove_rule(
            mapping.ext_port,
            mapping.protocol,
            mapping.dest_ip,
            mapping.int_port,
        )
        db.delete(mapping)

    username = user.username
    profile = user.profile
    db.delete(user)
    write_audit(
        db,
        admin,
        "user.delete",
        target_type="user",
        target_id=user.id,
        detail={
            "username": username,
            "profile": profile,
            "cleaned_port_mappings": len(mappings),
        },
        ip=client_ip(request),
        commit=False,
    )
    db.commit()
    suffix = f"，同时清理其 {len(mappings)} 条端口映射" if mappings else ""
    return ApiMessage(message=f"客户 {username} 已删除{suffix}")


@router.post("/users/{user_id}/download-token")
def new_download_token_endpoint(
    user_id: int,
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    user = _get_user_or_404(db, user_id)
    token = new_download_token()
    db.add(
        DownloadToken(
            token=token,
            user_id=user.id,
            expires_at=utcnow() + timedelta(minutes=5),
        )
    )
    write_audit(
        db,
        admin,
        "user.download_token_issued",
        target_type="user",
        target_id=user.id,
        detail={"username": user.username},
        ip=client_ip(request),
        commit=False,
    )
    db.commit()
    return {"download_url": f"/api/users/{user.id}/ovpn?token={token}"}


@router.get("/users/{user_id}/ovpn")
def download_ovpn(
    user_id: int,
    token: str = Query(min_length=20, max_length=80),
    db: Session = Depends(get_db),
):
    """客户下载 .ovpn：无需管理员登录，凭一次性短令牌。"""
    row = db.get(DownloadToken, token)
    if row is None or row.user_id != user_id or row.used_at is not None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "下载链接不存在或已使用")
    if row.expires_at <= utcnow():
        raise HTTPException(status.HTTP_410_GONE, "下载链接已过期，请联系客服重新获取")
    user = _get_user_or_404(db, user_id)
    node = db.get(Node, user.node_id) if user.node_id else _default_node(db)
    try:
        content = openvpn_cli.gen_client_ovpn(
            user.username, user.profile, node.public_domain, node.openvpn_port
        )
    except Exception as exc:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, f"生成配置文件失败：{exc}")
    row.used_at = utcnow()
    write_audit(
        db,
        None,
        "user.ovpn_downloaded",
        target_type="user",
        target_id=user.id,
        detail={"username": user.username, "profile": user.profile},
        commit=False,
    )
    db.commit()
    display = (user.customer_name or "").strip() or user.username
    safe_name = "".join(ch for ch in display if ch not in '"/\\')
    filename = f"{(safe_name or user.username)}.ovpn"
    fallback = f"laotie-{user.username}.ovpn"
    return Response(
        content=content,
        media_type="application/x-openvpn-profile",
        headers={
            "Content-Disposition": (
                f'attachment; filename="{fallback}"; filename*=UTF-8\'\'{quote(filename)}'
            )
        },
    )
