"""管理员管理：CRUD、角色、启停、改密、重置 TOTP。"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..audit import write_audit
from ..db import get_db
from ..deps import client_ip, get_current_admin, require_roles
from ..models import Admin
from ..schemas import (
    AdminCreate,
    AdminListPage,
    AdminOut,
    AdminPasswordChange,
    AdminUpdate,
    ApiMessage,
)
from ..security import hash_password


router = APIRouter(prefix="/api/admins", tags=["admins"])
superadmin_only = require_roles("superadmin")


def _count_active_superadmins(db: Session) -> int:
    return db.execute(
        select(func.count()).select_from(Admin).where(
            Admin.role == "superadmin", Admin.is_active.is_(True)
        )
    ).scalar_one()


def _get_admin_or_404(db: Session, admin_id: int) -> Admin:
    admin = db.get(Admin, admin_id)
    if admin is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "管理员不存在")
    return admin


@router.get("", response_model=AdminListPage)
def list_admins(
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=200),
    q: str | None = None,
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    stmt = select(Admin)
    if q:
        stmt = stmt.where(Admin.username.like(f"%{q}%"))
    total = db.execute(select(func.count()).select_from(stmt.subquery())).scalar_one()
    rows = (
        db.execute(
            stmt.order_by(Admin.id).offset((page - 1) * page_size).limit(page_size)
        )
        .scalars()
        .all()
    )
    return AdminListPage(total=total, items=[AdminOut.model_validate(a) for a in rows])


@router.post("", response_model=AdminOut, status_code=status.HTTP_201_CREATED)
def create_admin(
    body: AdminCreate,
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    exists = db.execute(
        select(Admin).where(Admin.username == body.username)
    ).scalar_one_or_none()
    if exists:
        raise HTTPException(status.HTTP_409_CONFLICT, "用户名已存在")
    new_admin = Admin(
        username=body.username,
        password_hash=hash_password(body.password),
        role=body.role,
        is_active=True,
        totp_enabled=False,
        totp_confirmed=False,
        created_by_id=admin.id,
    )
    db.add(new_admin)
    db.flush()
    write_audit(
        db,
        admin,
        "admin.create",
        target_type="admin",
        target_id=new_admin.id,
        detail={"username": new_admin.username, "role": new_admin.role},
        ip=client_ip(request),
        commit=False,
    )
    db.commit()
    db.refresh(new_admin)
    return new_admin


@router.patch("/{admin_id}", response_model=AdminOut)
def update_admin(
    admin_id: int,
    body: AdminUpdate,
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    target = _get_admin_or_404(db, admin_id)
    changes: dict[str, object] = {}
    if body.role is not None and body.role != target.role:
        if target.id == admin.id and body.role != "superadmin":
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "不能降级自己")
        if (
            target.role == "superadmin"
            and body.role != "superadmin"
            and _count_active_superadmins(db) <= 1
        ):
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "必须保留至少一名超级管理员")
        changes["role"] = body.role
        target.role = body.role
    if body.is_active is not None and body.is_active != target.is_active:
        if target.id == admin.id and body.is_active is False:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "不能停用自己")
        if (
            target.role == "superadmin"
            and target.is_active
            and body.is_active is False
            and _count_active_superadmins(db) <= 1
        ):
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "必须保留至少一名可用超级管理员")
        changes["is_active"] = body.is_active
        target.is_active = body.is_active
        target.auth_version += 1  # 停用/恢复都强制旧令牌失效
    if not changes:
        return target
    write_audit(
        db,
        admin,
        "admin.update",
        target_type="admin",
        target_id=target.id,
        detail={"username": target.username, "changes": {k: str(v) for k, v in changes.items()}},
        ip=client_ip(request),
        commit=False,
    )
    db.commit()
    db.refresh(target)
    return target


@router.delete("/{admin_id}", response_model=ApiMessage)
def delete_admin(
    admin_id: int,
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    target = _get_admin_or_404(db, admin_id)
    if target.id == admin.id:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "不能删除自己")
    if (
        target.role == "superadmin"
        and target.is_active
        and _count_active_superadmins(db) <= 1
    ):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "必须保留至少一名超级管理员")
    username = target.username
    db.delete(target)
    write_audit(
        db,
        admin,
        "admin.delete",
        target_type="admin",
        target_id=target.id,
        detail={"username": username},
        ip=client_ip(request),
        commit=False,
    )
    db.commit()
    return ApiMessage(message=f"管理员 {username} 已删除")


@router.post("/{admin_id}/reset-password", response_model=ApiMessage)
def reset_password(
    admin_id: int,
    body: AdminPasswordChange,
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    target = _get_admin_or_404(db, admin_id)
    target.password_hash = hash_password(body.new_password)
    target.auth_version += 1
    write_audit(
        db,
        admin,
        "admin.reset_password",
        target_type="admin",
        target_id=target.id,
        detail={"username": target.username},
        ip=client_ip(request),
        commit=False,
    )
    db.commit()
    return ApiMessage(message="密码已重置，该管理员需重新登录")


@router.post("/{admin_id}/reset-totp", response_model=ApiMessage)
def reset_totp(
    admin_id: int,
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    target = _get_admin_or_404(db, admin_id)
    target.totp_enabled = False
    target.totp_confirmed = False
    target.totp_secret = None
    target.auth_version += 1
    write_audit(
        db,
        admin,
        "admin.reset_totp",
        target_type="admin",
        target_id=target.id,
        detail={"username": target.username},
        ip=client_ip(request),
        commit=False,
    )
    db.commit()
    return ApiMessage(message="TOTP 已重置，该管理员下次登录需重新绑定")
