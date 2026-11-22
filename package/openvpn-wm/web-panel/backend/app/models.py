"""SQLAlchemy 2.x 数据模型（SQLite 第一期，结构兼容 PostgreSQL）。"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .db import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=utcnow, onupdate=utcnow
    )


class Admin(Base, TimestampMixin):
    __tablename__ = "admins"
    __table_args__ = (
        CheckConstraint("role IN ('superadmin','admin')", name="ck_admin_role"),
        CheckConstraint("username <> ''", name="ck_admin_username"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    username: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    totp_secret: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    totp_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    totp_confirmed: Mapped[bool] = mapped_column(Boolean, default=False)
    role: Mapped[str] = mapped_column(String(16), default="admin", index=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    auth_version: Mapped[int] = mapped_column(Integer, default=0)
    created_by_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("admins.id", ondelete="SET NULL"), nullable=True
    )
    last_login_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    last_login_ip: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)

    created_by: Mapped[Optional["Admin"]] = relationship(
        remote_side=[id], foreign_keys=[created_by_id]
    )


class Node(Base, TimestampMixin):
    __tablename__ = "nodes"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(64), unique=True)
    region: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    public_domain: Mapped[str] = mapped_column(String(255), index=True)
    public_ip: Mapped[str] = mapped_column(String(64))
    ssh_port: Mapped[int] = mapped_column(Integer, default=12346)
    openvpn_port: Mapped[int] = mapped_column(Integer, default=1194)
    status: Mapped[str] = mapped_column(
        String(16), default="active", index=True
    )  # active|maintenance|offline
    capacity: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)

    users: Mapped[list["User"]] = relationship(back_populates="node")


class User(Base, TimestampMixin):
    __tablename__ = "users"
    __table_args__ = (
        CheckConstraint(
            "profile IN ('trade-global','trade-strict','game-open')",
            name="ck_user_profile",
        ),
        CheckConstraint(
            "status IN ('active','expired','revoked','suspended')",
            name="ck_user_status",
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    username: Mapped[str] = mapped_column(String(32), unique=True, index=True)
    password_hash: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    password_encrypted: Mapped[Optional[str]] = mapped_column(String(512), nullable=True)
    embed_password: Mapped[bool] = mapped_column(Boolean, default=True)
    profile: Mapped[str] = mapped_column(String(32), index=True)
    customer_name: Mapped[str] = mapped_column(String(128))
    phone: Mapped[str] = mapped_column(String(32))
    company: Mapped[str] = mapped_column(String(128))
    email: Mapped[str] = mapped_column(String(255), index=True)
    node_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("nodes.id", ondelete="SET NULL"), nullable=True, index=True
    )
    status: Mapped[str] = mapped_column(String(16), default="active", index=True)
    expire_at: Mapped[datetime] = mapped_column(DateTime, index=True)
    vpn_ip: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    quota_bytes: Mapped[Optional[int]] = mapped_column(BigInteger, nullable=True)
    used_bytes: Mapped[int] = mapped_column(BigInteger, default=0)
    remark: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    node: Mapped[Optional[Node]] = relationship(back_populates="users")


class Session(Base):
    __tablename__ = "sessions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    node_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("nodes.id", ondelete="SET NULL"), nullable=True
    )
    connected_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)
    disconnected_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime, nullable=True
    )
    real_ip: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    virtual_ip: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    rx_bytes: Mapped[int] = mapped_column(BigInteger, default=0)
    tx_bytes: Mapped[int] = mapped_column(BigInteger, default=0)
    is_openvpn_active: Mapped[bool] = mapped_column(Boolean, default=True, index=True)


class TrafficDaily(Base):
    __tablename__ = "traffic_daily"
    __table_args__ = (
        UniqueConstraint("user_id", "date", name="uq_traffic_user_date"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    date: Mapped[str] = mapped_column(String(10), index=True)
    rx_bytes: Mapped[int] = mapped_column(BigInteger, default=0)
    tx_bytes: Mapped[int] = mapped_column(BigInteger, default=0)


class PortMapping(Base, TimestampMixin):
    """端口映射：公网 ext_port -> 客户 VPN 内网 dest_ip:int_port。"""

    __tablename__ = "port_mappings"
    __table_args__ = (
        UniqueConstraint("ext_port", name="uq_portmap_ext_port"),
        CheckConstraint(
            "protocol IN ('tcp','udp','tcpudp')", name="ck_portmap_protocol"
        ),
        CheckConstraint(
            "status IN ('active','disabled')", name="ck_portmap_status"
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    dest_ip: Mapped[str] = mapped_column(String(64))
    ext_port: Mapped[int] = mapped_column(Integer)
    int_port: Mapped[int] = mapped_column(Integer)
    protocol: Mapped[str] = mapped_column(String(8), default="tcp")
    status: Mapped[str] = mapped_column(String(16), default="active")
    remark: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)

    user: Mapped[Optional["User"]] = relationship()


class BlockedDomain(Base, TimestampMixin):
    """网站域名封锁规则：user_id 为空 = 全局规则；非空 = 只对该客户生效。"""

    __tablename__ = "blocked_domains"
    __table_args__ = (
        UniqueConstraint("user_id", "domain", name="uq_blocked_user_domain"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=True, index=True
    )
    domain: Mapped[str] = mapped_column(String(255), index=True)
    remark: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    created_by_admin_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("admins.id", ondelete="SET NULL"), nullable=True
    )

    user: Mapped[Optional["User"]] = relationship()


class VpnAuthLog(Base):
    """OpenVPN 连接/认证记录：成功与失败都留痕，供审计追溯。"""

    __tablename__ = "vpn_auth_log"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    username: Mapped[str] = mapped_column(String(32), index=True)
    success: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    reason: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    real_ip: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    virtual_ip: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=utcnow, index=True
    )


class SystemSetting(Base):
    """面板系统设置（key/value）。"""

    __tablename__ = "system_settings"

    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    value: Mapped[str] = mapped_column(Text, default="")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=utcnow, onupdate=utcnow
    )


class AuditLog(Base):
    __tablename__ = "audit_log"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    admin_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("admins.id", ondelete="SET NULL"), nullable=True, index=True
    )
    admin_username: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    action: Mapped[str] = mapped_column(String(64), index=True)
    target_type: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
    target_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    detail_json: Mapped[str] = mapped_column(Text, default="{}")
    ip: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=utcnow, index=True
    )


class DownloadToken(Base):
    __tablename__ = "download_tokens"

    token: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime, index=True)
    used_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class EmailNotification(Base, TimestampMixin):
    __tablename__ = "email_notifications"
    __table_args__ = (
        UniqueConstraint(
            "user_id", "reminder_key", name="uq_email_user_reminder"
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    reminder_key: Mapped[str] = mapped_column(String(24), index=True)
    scheduled_for: Mapped[Optional[str]] = mapped_column(String(10), nullable=True)
    status: Mapped[str] = mapped_column(
        String(16), default="pending", index=True
    )  # pending|sent|failed|deferred
    retry_count: Mapped[int] = mapped_column(Integer, default=0)
    error_message: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    sent_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
