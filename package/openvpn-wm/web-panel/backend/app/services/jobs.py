"""后台任务：到期扫描/邮件提醒/在线状态与流量同步。"""

from __future__ import annotations

import logging
import json
from datetime import datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..audit import write_audit
from ..config import get_settings
from ..db import SessionLocal
from ..models import (
    EmailNotification,
    Session as VpnSession,
    SystemSetting,
    TrafficDaily,
    User,
)
from ..security import utcnow
from . import mailer, openvpn_cli, status_parser


logger = logging.getLogger("openvpn-wm.jobs")


def sweep_expired(db: Session) -> int:
    now = utcnow()
    rows = (
        db.execute(
            select(User).where(User.status == "active", User.expire_at <= now)
        )
        .scalars()
        .all()
    )
    for user in rows:
        user.status = "expired"
        write_audit(
            db,
            admin=None,
            action="user.auto_expire",
            target_type="user",
            target_id=user.id,
            detail={"username": user.username, "expire_at": user.expire_at.isoformat()},
            commit=False,
        )
        db.flush()
        try:
            openvpn_cli.kill_user(user.username)
        except Exception as exc:  # 踢线失败不能阻塞状态落库
            logger.warning("kick expired user %s failed: %s", user.username, exc)
    db.commit()
    return len(rows)


def _process_reminder_queue(db: Session) -> None:
    settings = get_settings()
    rows = (
        db.execute(
            select(EmailNotification).where(
                EmailNotification.status.in_(["pending", "deferred", "failed"]),
                EmailNotification.retry_count < 5,
            )
        )
        .scalars()
        .all()
    )
    if not rows:
        return
    if not mailer.smtp_configured():
        # 未配置 SMTP：保持 pending 状态，等待配置后统一补发，不打日志风暴
        return
    for row in rows:
        user = db.get(User, row.user_id)
        if user is None:
            row.status = "failed"
            row.error_message = "user not found"
            continue
        try:
            mailer.send_reminder(
                user.email,
                user.customer_name,
                _days_left_from_key(row.reminder_key, user.expire_at),
                user.expire_at.strftime("%Y-%m-%d %H:%M"),
            )
            row.status = "sent"
            row.sent_at = utcnow()
            row.error_message = None
        except Exception as exc:
            row.status = "failed"
            row.retry_count += 1
            row.error_message = str(exc)[:500]
            logger.warning("reminder mail failed user=%s key=%s err=%s", user.username, row.reminder_key, exc)
    db.commit()


def _days_left_from_key(key: str, expire_at: datetime) -> int:
    return {"d7": 7, "d3": 3, "d1": 1, "due": 0}.get(key, 0)


def dispatch_expiry_emails(db: Session) -> int:
    if not get_settings().enable_email_reminders:
        return 0  # ENABLE_EMAIL_REMINDERS=false：暂停到期邮件提醒
    today = datetime.utcnow().date()
    active = (
        db.execute(
            select(User).where(User.status == "active", User.expire_at >= datetime.combine(today, datetime.min.time()))
        )
        .scalars()
        .all()
    )
    created = 0
    for user in active:
        if not user.email or "@" not in user.email:
            continue
        days_left = (user.expire_at.date() - today).days
        key_map = {7: "d7", 3: "d3", 1: "d1", 0: "due"}
        if days_left not in key_map:
            continue
        reminder_key = key_map[days_left]
        exists = db.execute(
            select(EmailNotification).where(
                EmailNotification.user_id == user.id,
                EmailNotification.reminder_key == reminder_key,
            )
        ).first()
        if exists:
            continue
        db.add(
            EmailNotification(
                user_id=user.id,
                reminder_key=reminder_key,
                scheduled_for=today.isoformat(),
                status="pending",
            )
        )
        created += 1
    db.commit()
    _process_reminder_queue(db)
    return created


def sync_status_log(db: Session) -> None:
    settings = get_settings()
    if not settings.openvpn_status_log.exists():
        return  # 服务端未运行时不误判离线
    now = utcnow()
    online = status_parser.parse_status_file(settings.openvpn_status_log)
    users = {
        u.username: u
        for u in db.execute(
            select(User).where(User.username.in_(list(online.keys())))
        )
        .scalars()
        .all()
    }

    open_sessions = {
        s.user_id: s
        for s in db.execute(
            select(VpnSession).where(VpnSession.disconnected_at.is_(None))
        )
        .scalars()
        .all()
    }

    # 当前在线用户名集合
    seen_user_ids: set[int] = set()
    for username, info in online.items():
        user = users.get(username)
        if user is None:
            continue
        seen_user_ids.add(user.id)
        rx = int(info["rx_bytes"])
        tx = int(info["tx_bytes"])
        session = open_sessions.get(user.id)
        delta_rx, delta_tx = rx, tx
        if session is not None:
            delta_rx = max(0, rx - (session.rx_bytes or 0))
            delta_tx = max(0, tx - (session.tx_bytes or 0))
            session.rx_bytes = rx
            session.tx_bytes = tx
            session.real_ip = str(info["real_ip"])
            session.virtual_ip = str(info.get("virtual_ip") or "") or session.virtual_ip
        else:
            session = VpnSession(
                user_id=user.id,
                node_id=user.node_id,
                connected_at=now,
                real_ip=str(info["real_ip"]),
                virtual_ip=str(info.get("virtual_ip") or "") or None,
                rx_bytes=rx,
                tx_bytes=tx,
                is_openvpn_active=True,
            )
            db.add(session)
        date_key = now.strftime("%Y-%m-%d")
        daily = db.execute(
            select(TrafficDaily).where(
                TrafficDaily.user_id == user.id, TrafficDaily.date == date_key
            )
        ).scalar_one_or_none()
        if daily is None:
            daily = TrafficDaily(user_id=user.id, date=date_key, rx_bytes=0, tx_bytes=0)
            db.add(daily)
        daily.rx_bytes = (daily.rx_bytes or 0) + delta_rx
        daily.tx_bytes = (daily.tx_bytes or 0) + delta_tx
        user.used_bytes = (user.used_bytes or 0) + delta_rx + delta_tx
        # 配额超限自动暂停
        if user.quota_bytes is not None and user.used_bytes >= user.quota_bytes:
            if user.status != "suspended":
                user.status = "suspended"
                write_audit(
                    db,
                    admin=None,
                    action="user.auto_suspend_quota",
                    target_type="user",
                    target_id=user.id,
                    detail={"username": user.username, "used_bytes": user.used_bytes},
                    commit=False,
                )
                openvpn_cli.kill_user(user.username)

    # 关闭已不在状态文件中的会话
    for user_id, session in open_sessions.items():
        if user_id not in seen_user_ids:
            session.disconnected_at = now
            session.is_openvpn_active = False
    db.commit()
    try:
        refresh_lan_rules(db)
    except Exception:
        logger.exception("refresh lan rules failed")


def refresh_lan_rules(db: Session) -> None:
    """按当前在线状态刷新“全部互访/分组互访”防火墙规则。"""
    groups_nonempty = False
    for key in ("vpn_group1_members", "vpn_group2_members"):
        row = db.get(SystemSetting, key)
        if row and row.value.strip():
            try:
                if json.loads(row.value):
                    groups_nonempty = True
                    break
            except ValueError:
                pass
    global_on = False
    row = db.get(SystemSetting, "vpn_lan_access")
    if row:
        global_on = row.value.lower() in ("1", "true", "on")
    if not global_on and not groups_nonempty:
        return
    openvpn_cli.apply_lan_rules("sync")


def run_job(name: str, fn) -> None:
    db = SessionLocal()
    try:
        fn(db)
    except Exception:
        logger.exception("job %s failed", name)
    finally:
        db.close()


def start_background_scheduler() -> object | None:
    from apscheduler.schedulers.background import BackgroundScheduler

    settings = get_settings()
    if not settings.enable_scheduler:
        return None
    scheduler = BackgroundScheduler(timezone="Asia/Shanghai")
    scheduler.add_job(
        lambda: run_job("status", sync_status_log),
        "interval",
        seconds=10,
        id="sync-status",
        max_instances=1,
        coalesce=True,
    )
    scheduler.add_job(
        lambda: run_job("expire", sweep_expired),
        "interval",
        seconds=60,
        id="sweep-expired",
        max_instances=1,
        coalesce=True,
    )
    scheduler.add_job(
        lambda: run_job("remind", dispatch_expiry_emails),
        "interval",
        hours=6,
        id="expiry-emails",
        max_instances=1,
        coalesce=True,
    )
    scheduler.start()
    return scheduler
