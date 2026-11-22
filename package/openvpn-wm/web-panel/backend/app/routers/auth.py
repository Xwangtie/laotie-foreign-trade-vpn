"""认证：登录、TOTP 绑定/校验、刷新。"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import JSONResponse
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..audit import write_audit
from ..config import get_settings
from ..db import get_db
from ..deps import client_ip, get_current_admin
from ..models import Admin
from ..rate_limit import rate_limiter
from ..schemas import (
    ApiMessage,
    ConfirmTOTPRequest,
    LoginRequest,
    RefreshRequest,
    TOTPSetupResponse,
)
from ..security import (
    create_access_token,
    create_refresh_token,
    create_setup_token,
    decode_token,
    hash_password,
    new_totp_secret,
    totp_provisioning_uri,
    utcnow,
    verify_password,
    verify_totp,
)


router = APIRouter(prefix="/api/auth", tags=["auth"])


@router.post("/login")
def login(
    body: LoginRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    settings = get_settings()
    ip = client_ip(request)
    admin = db.execute(
        select(Admin).where(Admin.username == body.username.strip())
    ).scalar_one_or_none()

    allowed, lock_left = rate_limiter.check(
        body.username,
        ip,
        max_attempts=settings.login_max_attempts,
        window=settings.login_window_seconds,
        lock_seconds=settings.login_lock_seconds,
    )
    if not allowed:
        write_audit(
            db,
            admin,
            "admin.login_locked",
            target_type="admin",
            target_id=admin.id if admin else None,
            detail={"username": body.username, "ip": ip},
            ip=ip,
        )
        raise HTTPException(
            status_code=status.HTTP_423_LOCKED,
            detail=f"尝试次数过多，请 {lock_left} 秒后再试",
        )

    if admin is None or not verify_password(body.password, admin.password_hash):
        rate_limiter.record_failure(
            body.username, ip, window=settings.login_window_seconds
        )
        write_audit(
            db,
            admin,
            "admin.login_failed",
            target_type="admin",
            target_id=admin.id if admin else None,
            detail={"username": body.username, "ip": ip},
            ip=ip,
        )
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "用户名或密码错误")

    if not admin.is_active:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "账号已停用，请联系超级管理员")

    if admin.totp_confirmed:
        if not body.code:
            return JSONResponse(
                status_code=status.HTTP_428_PRECONDITION_REQUIRED,
                content={"detail": "请输入 TOTP 动态验证码", "requires_totp": True},
            )
        if not verify_totp(admin.totp_secret, body.code):
            rate_limiter.record_failure(
                body.username, ip, window=settings.login_window_seconds
            )
            write_audit(
                db,
                admin,
                "admin.totp_failed",
                target_type="admin",
                target_id=admin.id,
                detail={"username": body.username},
                ip=ip,
            )
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "动态验证码错误")
    else:
        if settings.require_totp:
            if not admin.totp_secret:
                admin.totp_secret = new_totp_secret()
                db.commit()
            secret = admin.totp_secret
            return JSONResponse(
                content=TOTPSetupResponse(
                    setup_token=create_setup_token(admin.id),
                    otpauth_uri=totp_provisioning_uri(secret, admin.username),
                    manual_key=secret,
                ).model_dump()
            )
        # REQUIRE_TOTP=false：第一阶段先放行，不强制扫码

    rate_limiter.clear(body.username, ip)
    admin.last_login_at = utcnow()
    admin.last_login_ip = ip
    write_audit(
        db,
        admin,
        "admin.login_success",
        target_type="admin",
        target_id=admin.id,
        detail={"username": admin.username, "ip": ip},
        ip=ip,
        commit=False,
    )
    db.commit()
    return {
        "access_token": create_access_token(admin.id, admin.auth_version),
        "refresh_token": create_refresh_token(admin.id, admin.auth_version),
        "token_type": "bearer",
        "username": admin.username,
        "role": admin.role,
        "requires_totp_setup": False,
    }


@router.post("/totp/confirm", response_model=None)
def confirm_totp(
    body: ConfirmTOTPRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    try:
        payload = decode_token(body.setup_token, "totp_setup")
    except Exception:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "绑定令牌无效或已过期")
    admin = db.get(Admin, int(payload["sub"]))
    if admin is None or not admin.is_active:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "账号不可用")
    if not verify_totp(admin.totp_secret, body.code):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "动态验证码错误")
    admin.totp_enabled = True
    admin.totp_confirmed = True
    admin.auth_version += 1
    write_audit(
        db,
        admin,
        "admin.totp_bound",
        target_type="admin",
        target_id=admin.id,
        detail={"username": admin.username},
        ip=client_ip(request),
        commit=False,
    )
    db.commit()
    return {
        "access_token": create_access_token(admin.id, admin.auth_version),
        "refresh_token": create_refresh_token(admin.id, admin.auth_version),
        "token_type": "bearer",
        "username": admin.username,
        "role": admin.role,
    }


@router.post("/refresh")
def refresh(body: RefreshRequest, db: Session = Depends(get_db)):
    try:
        payload = decode_token(body.refresh_token, "refresh")
    except Exception:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "刷新令牌无效或已过期")
    admin = db.get(Admin, int(payload["sub"]))
    if (
        admin is None
        or not admin.is_active
        or not admin.totp_confirmed
        or int(payload.get("ver", -1)) != admin.auth_version
    ):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "请重新登录")
    return {
        "access_token": create_access_token(admin.id, admin.auth_version),
        "refresh_token": create_refresh_token(admin.id, admin.auth_version),
        "token_type": "bearer",
    }


@router.get("/me")
def me(admin: Admin = Depends(get_current_admin)):
    return {
        "id": admin.id,
        "username": admin.username,
        "role": admin.role,
        "totp_confirmed": admin.totp_confirmed,
    }


@router.post("/logout", response_model=ApiMessage)
def logout(admin: Admin = Depends(get_current_admin)):
    # 前端丢弃令牌即可；如需强制全端下线可在管理页重置 auth_version
    return ApiMessage(message="已退出登录")
