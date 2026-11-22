"""密码哈希、JWT、TOTP 与随机令牌。"""

from __future__ import annotations

import base64
import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any

import jwt
import pyotp
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError

from .config import get_settings


_ph = PasswordHasher()


def utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def hash_password(password: str) -> str:
    return _ph.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return _ph.verify(password_hash, password)
    except (VerifyMismatchError, Exception):
        return False


def hash_vpn_password(password: str) -> str:
    """客户 VPN 连接密码：PBKDF2，服务器端原生脚本可直接校验。"""
    iterations = 200_000
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt.encode("ascii"), iterations
    ).hex()
    return f"pbkdf2_sha256${iterations}${salt}${digest}"


def verify_vpn_password(password: str, encoded: str | None) -> bool:
    if not encoded:
        return False
    try:
        algo, iterations_s, salt, expected = encoded.split("$", 3)
        if algo != "pbkdf2_sha256":
            return False
        iterations = int(iterations_s)
        actual = hashlib.pbkdf2_hmac(
            "sha256", password.encode("utf-8"), salt.encode("ascii"), iterations
        ).hex()
    except (ValueError, TypeError):
        return False
    return secrets.compare_digest(actual, expected)


def _vpn_fernet():
    from cryptography.fernet import Fernet

    digest = hashlib.sha256(
        get_settings().jwt_secret.encode("utf-8")
    ).digest()
    return Fernet(base64.urlsafe_b64encode(digest))


def encrypt_vpn_password(password: str) -> str:
    """用于在配置生成时恢复明文；密钥由服务器 JWT_SECRET 派生。"""
    return _vpn_fernet().encrypt(password.encode("utf-8")).decode("ascii")


def decrypt_vpn_password(encoded: str | None) -> str | None:
    if not encoded:
        return None
    try:
        return _vpn_fernet().decrypt(encoded.encode("ascii")).decode("utf-8")
    except Exception:
        return None


def _token(payload: dict[str, Any], expires_delta: timedelta) -> str:
    settings = get_settings()
    data = dict(payload)
    data["exp"] = utcnow() + expires_delta
    data["iat"] = utcnow()
    return jwt.encode(data, settings.jwt_secret, algorithm="HS256")


def create_access_token(admin_id: int, auth_version: int) -> str:
    settings = get_settings()
    return _token(
        {"sub": str(admin_id), "type": "access", "ver": auth_version},
        timedelta(minutes=settings.access_token_minutes),
    )


def create_refresh_token(admin_id: int, auth_version: int) -> str:
    settings = get_settings()
    return _token(
        {"sub": str(admin_id), "type": "refresh", "ver": auth_version},
        timedelta(days=settings.refresh_token_days),
    )


def create_setup_token(admin_id: int) -> str:
    settings = get_settings()
    return _token(
        {"sub": str(admin_id), "type": "totp_setup"},
        timedelta(minutes=10),
    )


def decode_token(token: str, expected_type: str | None = None) -> dict[str, Any]:
    settings = get_settings()
    payload = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
    if expected_type and payload.get("type") != expected_type:
        raise jwt.InvalidTokenError("token type mismatch")
    return payload


def new_totp_secret() -> str:
    return pyotp.random_base32()


def totp_provisioning_uri(secret: str, username: str) -> str:
    settings = get_settings()
    return pyotp.TOTP(secret).provisioning_uri(name=username, issuer_name=settings.totp_issuer)


def verify_totp(secret: str | None, code: str) -> bool:
    if not secret:
        return False
    return pyotp.TOTP(secret).verify(code, valid_window=1)


def new_download_token() -> str:
    return secrets.token_urlsafe(48)


def stable_secret_fingerprint(value: str) -> str:
    """SMTP 密码等敏感值只允许以指纹形式进入审计日志。"""
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:12]
