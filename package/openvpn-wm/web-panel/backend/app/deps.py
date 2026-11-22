"""FastAPI 依赖：鉴权、角色、数据库。"""

from __future__ import annotations

from collections.abc import Callable

import jwt
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from .db import get_db
from .models import Admin


bearer = HTTPBearer(auto_error=False)


def _client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def get_current_admin(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
) -> Admin:
    if credentials is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="未登录")
    from .config import get_settings

    try:
        payload = jwt.decode(
            credentials.credentials,
            get_settings().jwt_secret,
            algorithms=["HS256"],
        )
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="登录已过期")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="登录已失效")

    if payload.get("type") != "access":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="令牌类型错误")
    admin = db.get(Admin, int(payload["sub"]))
    if admin is None or not admin.is_active:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="账号已停用")
    if not admin.totp_confirmed and get_settings().require_totp:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="必须先完成 TOTP 绑定")
    if int(payload.get("ver", -1)) != admin.auth_version:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="登录状态已变更，请重新登录")
    return admin


def require_roles(*roles: str) -> Callable:
    def checker(admin: Admin = Depends(get_current_admin)) -> Admin:
        if admin.role not in roles:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="无权限")
        return admin

    return checker


def client_ip(request: Request) -> str:
    return _client_ip(request)
