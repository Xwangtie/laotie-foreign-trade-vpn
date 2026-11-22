"""SMTP 状态与测试邮件。"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, EmailStr

from ..audit import write_audit
from ..deps import client_ip, get_current_admin, require_roles
from ..db import get_db
from ..models import Admin
from ..services import mailer
from sqlalchemy.orm import Session


router = APIRouter(prefix="/api/mail", tags=["mail"])
superadmin_only = require_roles("superadmin")


class TestMailBody(BaseModel):
    email: EmailStr


@router.get("/status")
def mail_status(admin: Admin = Depends(superadmin_only)):
    return {"configured": mailer.smtp_configured(), "report": mailer.smtp_safety_report()}


@router.post("/test")
def send_test(
    body: TestMailBody,
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    try:
        mailer.send_test_mail(body.email)
    except Exception as exc:
        write_audit(
            db,
            admin,
            "mail.test_failed",
            target_type="mail",
            detail={"to": body.email, "error": str(exc)[:300]},
            ip=client_ip(request),
        )
        raise HTTPException(status_code=502, detail=f"发送失败：{exc}")
    write_audit(
        db,
        admin,
        "mail.test_sent",
        target_type="mail",
        detail={"to": body.email},
        ip=client_ip(request),
    )
    return {"message": "测试邮件已发送"}
