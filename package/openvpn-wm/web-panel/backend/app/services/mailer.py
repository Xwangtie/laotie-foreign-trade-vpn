"""到期提醒 / 测试邮件。SMTP 未配置时优雅跳过，不把密钥写日志。"""

from __future__ import annotations

import logging
import smtplib
from email.header import Header
from email.mime.text import MIMEText
from email.utils import formataddr

from ..config import get_settings
from ..security import stable_secret_fingerprint


logger = logging.getLogger("openvpn-wm.mailer")


def smtp_configured() -> bool:
    settings = get_settings()
    return bool(settings.smtp_host and settings.smtp_user)


def _send_raw(subject: str, html: str, to_addr: str) -> None:
    settings = get_settings()
    if not smtp_configured():
        raise RuntimeError("SMTP 未配置")
    msg = MIMEText(html, "html", "utf-8")
    msg["Subject"] = Header(subject, "utf-8")
    msg["From"] = formataddr(
        (str(Header(settings.smtp_from_name, "utf-8")), settings.smtp_from)
    )
    msg["To"] = to_addr
    if settings.smtp_use_ssl:
        server: smtplib.SMTP = smtplib.SMTP_SSL(
            settings.smtp_host, settings.smtp_port, timeout=20
        )
    else:
        server = smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=20)
        server.starttls()
    try:
        server.login(settings.smtp_user or "", settings.smtp_password or "")
        server.sendmail(settings.smtp_from, [to_addr], msg.as_string())
    finally:
        server.quit()


def send_reminder(to_addr: str, customer_name: str, days_left: int, expire_text: str) -> None:
    settings = get_settings()
    if days_left == 0:
        title = "您的外贸网络服务已到期"
    else:
        title = f"服务即将到期提醒（剩余 {days_left} 天）"
    html = f"""\
<div style="font-family: sans-serif; max-width:640px;margin:0 auto">
<h2>{settings.app_name}</h2>
<p>{customer_name}，您好：</p>
<p>您的 VPN 账号将在 <b>{expire_text}</b> 到期（剩余 {days_left} 天）。</p>
<p>为避免影响外贸业务，请提前联系续费。</p>
<p>客服电话：{settings.support_phone}<br/>客服邮箱：{settings.support_email}</p>
<p style="color:#999">本邮件由系统自动发送，请勿直接回复。</p>
</div>"""
    _send_raw(title, html, to_addr)


def send_test_mail(to_addr: str) -> None:
    _send_raw("老铁外贸网络管理系统 - 测试邮件", "<p>SMTP 配置测试成功。</p>", to_addr)


def smtp_safety_report() -> str:
    if not smtp_configured():
        return "SMTP 未配置"
    settings = get_settings()
    return (
        f"host={settings.smtp_host}:{settings.smtp_port} "
        f"user={settings.smtp_user} password_sha12={stable_secret_fingerprint(settings.smtp_password or '')}"
    )
