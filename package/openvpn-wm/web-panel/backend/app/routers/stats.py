"""Dashboard、在线状态与流量统计。"""

from __future__ import annotations

from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..db import get_db
from ..deps import require_roles
from ..models import (
    Admin,
    Session as VpnSession,
    TrafficDaily,
    User,
)
from ..schemas import DashboardOut
from ..security import utcnow


router = APIRouter(prefix="/api", tags=["stats"])
superadmin_only = require_roles("superadmin")


@router.get("/dashboard", response_model=DashboardOut)
def dashboard(
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    now = utcnow()
    today = now.strftime("%Y-%m-%d")
    month_prefix = now.strftime("%Y-%m")
    online = db.execute(
        select(func.count()).select_from(VpnSession).where(
            VpnSession.disconnected_at.is_(None),
            VpnSession.is_openvpn_active.is_(True),
        )
    ).scalar_one()
    active_users = db.execute(
        select(func.count()).select_from(User).where(User.status == "active")
    ).scalar_one()
    expired_today = db.execute(
        select(func.count())
        .select_from(User)
        .where(
            User.status == "expired",
            func.date(User.expire_at) == today,
        )
    ).scalar_one()
    row = db.execute(
        select(
            func.coalesce(func.sum(TrafficDaily.rx_bytes), 0),
            func.coalesce(func.sum(TrafficDaily.tx_bytes), 0),
        ).where(TrafficDaily.date == today)
    ).one()
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    new_month = db.execute(
        select(func.count()).select_from(User).where(User.created_at >= month_start)
    ).scalar_one()
    dist_rows = db.execute(
        select(User.profile, func.count()).group_by(User.profile)
    ).all()
    return DashboardOut(
        online=int(online),
        active_users=int(active_users),
        expired_today=int(expired_today),
        today_rx=int(row[0]),
        today_tx=int(row[1]),
        new_users_this_month=int(new_month),
        profile_distribution={str(p): int(c) for p, c in dist_rows},
    )


@router.get("/online")
def online_users(
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    rows = db.execute(
        select(VpnSession, User)
        .join(User, User.id == VpnSession.user_id)
        .where(
            VpnSession.disconnected_at.is_(None),
            VpnSession.is_openvpn_active.is_(True),
        )
        .order_by(VpnSession.connected_at.desc())
    ).all()
    return [
        {
            "user_id": user.id,
            "username": user.username,
            "profile": user.profile,
            "real_ip": session.real_ip,
            "connected_at": session.connected_at.isoformat(),
            "rx_bytes": session.rx_bytes,
            "tx_bytes": session.tx_bytes,
        }
        for session, user in rows
    ]


@router.get("/traffic")
def traffic(
    days: int = Query(default=30, ge=1, le=93),
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    start = (utcnow() - timedelta(days=days - 1)).strftime("%Y-%m-%d")
    rows = db.execute(
        select(TrafficDaily.date, TrafficDaily.rx_bytes, TrafficDaily.tx_bytes)
        .where(TrafficDaily.date >= start)
        .order_by(TrafficDaily.date)
    ).all()
    return [
        {"date": d, "rx_bytes": int(rx), "tx_bytes": int(tx)} for d, rx, tx in rows
    ]
