"""域名封锁规则 + OpenVPN 连接/认证日志。"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..audit import write_audit
from ..db import get_db
from ..deps import client_ip, get_current_admin, require_roles
from ..models import (
    Admin,
    BlockedDomain,
    Session as VpnSession,
    User,
    VpnAuthLog,
)
from ..schemas import (
    ApiMessage,
    BlockedDomainIn,
    BlockedDomainOut,
    VpnAuthLogOut,
    VpnAuthLogPage,
)


router = APIRouter(prefix="/api", tags=["security"])
superadmin_only = require_roles("superadmin")


def _user_or_404(db: Session, user_id: int) -> User:
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "客户不存在")
    return user


def _to_out(rule: BlockedDomain) -> BlockedDomainOut:
    out = BlockedDomainOut.model_validate(rule)
    out.username = rule.user.username if rule.user else None
    return out


def _add_rule(
    db: Session,
    admin: Admin,
    request: Request,
    domain: str,
    user_id: int | None,
    remark: str | None,
) -> BlockedDomain:
    stmt = select(BlockedDomain).where(BlockedDomain.domain == domain)
    if user_id is None:
        stmt = stmt.where(BlockedDomain.user_id.is_(None))
    else:
        stmt = stmt.where(BlockedDomain.user_id == user_id)
    if db.execute(stmt).scalar_one_or_none() is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, f"域名 {domain} 已在封锁列表")
    rule = BlockedDomain(
        user_id=user_id,
        domain=domain,
        remark=remark,
        created_by_admin_id=admin.id,
    )
    db.add(rule)
    db.flush()
    write_audit(
        db,
        admin,
        "blocked_domain.add",
        target_type="blocked_domain",
        target_id=rule.id,
        detail={"user_id": user_id, "domain": domain},
        ip=client_ip(request),
        commit=False,
    )
    db.commit()
    db.refresh(rule)
    return rule


@router.get("/blocked-domains/global", response_model=list[BlockedDomainOut])
def list_global_blocks(
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    rows = db.execute(
        select(BlockedDomain)
        .where(BlockedDomain.user_id.is_(None))
        .order_by(BlockedDomain.id)
    ).scalars().all()
    return [_to_out(r) for r in rows]


@router.post("/blocked-domains/global", response_model=BlockedDomainOut, status_code=201)
def add_global_block(
    body: BlockedDomainIn,
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    return _add_rule(db, admin, request, body.domain, None, body.remark)


@router.delete("/blocked-domains/global", response_model=ApiMessage)
def delete_global_block(
    domain: str = Query(min_length=1),
    request: Request = None,
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    rule = db.execute(
        select(BlockedDomain).where(
            BlockedDomain.domain == domain.strip().lower().rstrip("."),
            BlockedDomain.user_id.is_(None),
        )
    ).scalar_one_or_none()
    if rule is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "该全局封锁规则不存在")
    db.delete(rule)
    write_audit(
        db,
        admin,
        "blocked_domain.remove",
        detail={"user_id": None, "domain": domain},
        ip=client_ip(request),
        commit=False,
    )
    db.commit()
    return ApiMessage(message=f"已解除全局封锁 {domain}")


@router.get("/users/{user_id}/blocked-domains", response_model=list[BlockedDomainOut])
def list_user_blocks(
    user_id: int,
    db: Session = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    _user_or_404(db, user_id)
    rows = db.execute(
        select(BlockedDomain)
        .where(BlockedDomain.user_id == user_id)
        .order_by(BlockedDomain.id)
    ).scalars().all()
    return [_to_out(r) for r in rows]


@router.post(
    "/users/{user_id}/blocked-domains",
    response_model=BlockedDomainOut,
    status_code=201,
)
def add_user_block(
    user_id: int,
    body: BlockedDomainIn,
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    _user_or_404(db, user_id)
    return _add_rule(db, admin, request, body.domain, user_id, body.remark)


@router.delete("/users/{user_id}/blocked-domains", response_model=ApiMessage)
def delete_user_block(
    user_id: int,
    domain: str = Query(min_length=1),
    request: Request = None,
    db: Session = Depends(get_db),
    admin: Admin = Depends(get_current_admin),
):
    _user_or_404(db, user_id)
    rule = db.execute(
        select(BlockedDomain).where(
            BlockedDomain.user_id == user_id,
            BlockedDomain.domain == domain.strip().lower().rstrip("."),
        )
    ).scalar_one_or_none()
    if rule is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "该账号封锁规则不存在")
    db.delete(rule)
    write_audit(
        db,
        admin,
        "blocked_domain.remove",
        detail={"user_id": user_id, "domain": domain},
        ip=client_ip(request),
        commit=False,
    )
    db.commit()
    return ApiMessage(message=f"已解除账号 {user_id} 的封锁 {domain}")


@router.get("/vpn-auth-logs", response_model=VpnAuthLogPage)
def list_vpn_auth_logs(
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=30, ge=1, le=200),
    username: str | None = None,
    success: bool | None = None,
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    stmt = select(VpnAuthLog)
    if username:
        stmt = stmt.where(VpnAuthLog.username.like(f"%{username}%"))
    if success is not None:
        stmt = stmt.where(VpnAuthLog.success == success)
    total = db.execute(select(func.count()).select_from(stmt.subquery())).scalar_one()
    rows = (
        db.execute(
            stmt.order_by(VpnAuthLog.id.desc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
        .scalars()
        .all()
    )
    return VpnAuthLogPage(
        total=int(total),
        items=[VpnAuthLogOut.model_validate(r) for r in rows],
    )


@router.get("/vpn-sessions")
def list_vpn_sessions(
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=30, ge=1, le=200),
    online: bool | None = None,
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    stmt = select(VpnSession, User).join(User, User.id == VpnSession.user_id)
    if online is not None:
        stmt = stmt.where(
            VpnSession.disconnected_at.is_(None)
            if online
            else VpnSession.disconnected_at.is_not(None)
        )
    rows = (
        db.execute(
            stmt.order_by(VpnSession.id.desc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
        .all()
    )
    return [
        {
            "id": s.id,
            "user_id": s.user_id,
            "username": u.username,
            "real_ip": s.real_ip,
            "virtual_ip": s.virtual_ip,
            "connected_at": s.connected_at.isoformat(),
            "disconnected_at": s.disconnected_at.isoformat() if s.disconnected_at else None,
            "online": s.disconnected_at is None,
            "rx_bytes": int(s.rx_bytes or 0),
            "tx_bytes": int(s.tx_bytes or 0),
        }
        for s, u in rows
    ]
