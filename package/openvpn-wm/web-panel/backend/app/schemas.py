"""API 请求/响应模型。"""

from __future__ import annotations

from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator


PROFILE_CHOICES = ("trade-global", "trade-strict", "game-open")
USER_STATUS_CHOICES = ("active", "expired", "revoked", "suspended")
ROLE_CHOICES = ("superadmin", "admin")
NODE_STATUS_CHOICES = ("active", "maintenance", "offline")
USERNAME_RE = r"^[a-zA-Z0-9_-]{1,32}$"
ADMIN_USERNAME_RE = r"^[a-zA-Z0-9_-]{3,32}$"


class ApiMessage(BaseModel):
    message: str


# ---------------- 认证 ----------------
class LoginRequest(BaseModel):
    username: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=1, max_length=256)
    code: Optional[str] = Field(default=None, min_length=6, max_length=6)


class TOTPSetupResponse(BaseModel):
    setup_token: str
    otpauth_uri: str
    manual_key: str


class ConfirmTOTPRequest(BaseModel):
    setup_token: str
    code: str = Field(min_length=6, max_length=6)


class LoginResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    username: str
    role: str
    requires_totp_setup: bool = False


class RefreshRequest(BaseModel):
    refresh_token: str


class TOTPLoginRequest(BaseModel):
    username: str
    password: str
    code: str = Field(min_length=6, max_length=6)


# ---------------- 节点 ----------------
class NodeBase(BaseModel):
    name: str = Field(min_length=1, max_length=64)
    region: Optional[str] = None
    public_domain: str
    public_ip: str
    ssh_port: int = Field(default=12346, ge=1, le=65535)
    openvpn_port: int = Field(default=1194, ge=1, le=65535)
    status: Literal["active", "maintenance", "offline"] = "active"
    capacity: Optional[int] = Field(default=None, ge=0)


class NodeCreate(NodeBase):
    pass


class NodeUpdate(BaseModel):
    name: Optional[str] = None
    region: Optional[str] = None
    public_domain: Optional[str] = None
    public_ip: Optional[str] = None
    ssh_port: Optional[int] = Field(default=None, ge=1, le=65535)
    openvpn_port: Optional[int] = Field(default=None, ge=1, le=65535)
    status: Optional[Literal["active", "maintenance", "offline"]] = None
    capacity: Optional[int] = Field(default=None, ge=0)


class NodeOut(NodeBase):
    model_config = ConfigDict(from_attributes=True)
    id: int
    created_at: datetime
    updated_at: datetime


# ---------------- 用户 ----------------
class UserCreate(BaseModel):
    username: str
    profile: Literal["trade-global", "trade-strict", "game-open"]
    customer_name: Optional[str] = Field(default="", max_length=128)
    phone: Optional[str] = Field(default="", max_length=32)
    company: Optional[str] = Field(default="", max_length=128)
    email: Optional[EmailStr] = None
    node_id: Optional[int] = None
    expire_at: Optional[datetime] = None
    quota_bytes: Optional[int] = Field(default=None, ge=0)
    remark: Optional[str] = Field(default=None, max_length=2000)
    connection_password: Optional[str] = Field(default=None, min_length=1, max_length=128)
    embed_password: bool = True

    @field_validator("username")
    @classmethod
    def validate_username(cls, v: str) -> str:
        import re

        v = v.strip()
        if not re.fullmatch(USERNAME_RE, v):
            raise ValueError("用户名仅允许 1-32 位字母/数字/下划线/短横线")
        return v

    @field_validator("customer_name", "phone", "company")
    @classmethod
    def allow_blank_customer_fields(cls, v: Optional[str]) -> str:
        return (v or "").strip()


class UserUpdate(BaseModel):
    customer_name: Optional[str] = Field(default=None, min_length=1, max_length=128)
    phone: Optional[str] = Field(default=None, min_length=1, max_length=32)
    company: Optional[str] = Field(default=None, min_length=1, max_length=128)
    email: Optional[EmailStr] = None
    remark: Optional[str] = Field(default=None, max_length=2000)
    quota_bytes: Optional[int] = Field(default=None, ge=0)
    expire_at: Optional[datetime] = None
    embed_password: Optional[bool] = None


class UserPasswordReset(BaseModel):
    password: str = Field(min_length=1, max_length=128)


class RenewRequest(BaseModel):
    months: int = Field(ge=1, le=12)


class ProfileOut(BaseModel):
    profile_id: str
    name: str
    desc: str
    split: str
    failmode: str


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    username: str
    profile: str
    customer_name: str
    phone: str
    company: str
    email: str
    node_id: Optional[int]
    status: str
    expire_at: datetime
    vpn_ip: Optional[str] = None
    quota_bytes: Optional[int]
    used_bytes: int
    embed_password: bool
    remark: Optional[str]
    created_at: datetime
    updated_at: datetime


class UserCreated(UserOut):
    download_token: str
    connection_password: Optional[str] = None


class UserListPage(BaseModel):
    total: int
    items: list[UserOut]


# ---------------- 管理员 ----------------
class AdminCreate(BaseModel):
    username: str = Field(min_length=3, max_length=64)
    password: str = Field(min_length=6, max_length=128)
    role: Literal["superadmin", "admin"] = "admin"

    @field_validator("username")
    @classmethod
    def validate_username(cls, v: str) -> str:
        import re

        v = v.strip()
        if not re.fullmatch(ADMIN_USERNAME_RE, v):
            raise ValueError("管理员用户名仅允许 3-32 位字母/数字/下划线/短横线")
        return v


class AdminUpdate(BaseModel):
    role: Optional[Literal["superadmin", "admin"]] = None
    is_active: Optional[bool] = None


class AdminPasswordChange(BaseModel):
    new_password: str = Field(min_length=6, max_length=128)


class AdminOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    username: str
    role: str
    is_active: bool
    totp_enabled: bool
    totp_confirmed: bool
    created_at: datetime
    last_login_at: Optional[datetime]
    last_login_ip: Optional[str]


class AdminListPage(BaseModel):
    total: int
    items: list[AdminOut]


# ---------------- 端口映射 ----------------
class PortMappingCreate(BaseModel):
    user_id: Optional[int] = Field(default=None)
    dest_ip: str = Field(min_length=7, max_length=64)
    ext_port: int = Field(ge=1, le=65535)
    int_port: int = Field(ge=1, le=65535)
    protocol: Literal["tcp", "udp", "tcpudp"] = "tcp"
    remark: Optional[str] = Field(default=None, max_length=255)

    @field_validator("dest_ip")
    @classmethod
    def valid_ip(cls, v: str) -> str:
        import ipaddress

        try:
            ipaddress.ip_address(v)
        except ValueError as exc:
            raise ValueError("内网目标必须是合法 IPv4/IPv6 地址") from exc
        return v.strip()


class PortMappingOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    user_id: Optional[int]
    username: Optional[str] = None
    dest_ip: str
    ext_port: int
    int_port: int
    protocol: str
    status: str
    remark: Optional[str]
    created_at: datetime
    updated_at: datetime


# ---------------- 审计 / 统计 ----------------
class AuditOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    admin_id: Optional[int]
    admin_username: Optional[str]
    action: str
    target_type: Optional[str]
    target_id: Optional[int]
    detail_json: str
    ip: Optional[str]
    created_at: datetime


class AuditListPage(BaseModel):
    total: int
    items: list[AuditOut]


class DashboardOut(BaseModel):
    online: int
    active_users: int
    expired_today: int
    today_rx: int
    today_tx: int
    new_users_this_month: int
    profile_distribution: dict[str, int]


# ---------------- 域名封锁 / 审计日志 ----------------
class BlockedDomainIn(BaseModel):
    domain: str = Field(min_length=1, max_length=255)
    remark: Optional[str] = Field(default=None, max_length=255)

    @field_validator("domain")
    @classmethod
    def normalize_domain(cls, v: str) -> str:
        v = v.strip().lower().rstrip(".")
        if v.startswith("*."):
            v = v[2:]
        if not v or " " in v or "/" in v:
            raise ValueError("请输入合法域名，例如 example.com")
        return v


class BlockedDomainOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    user_id: Optional[int]
    username: Optional[str] = None
    domain: str
    remark: Optional[str]
    created_at: datetime


class VpnAuthLogOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    user_id: Optional[int]
    username: str
    success: bool
    reason: Optional[str]
    real_ip: Optional[str]
    virtual_ip: Optional[str]
    created_at: datetime


class VpnAuthLogPage(BaseModel):
    total: int
    items: list[VpnAuthLogOut]
