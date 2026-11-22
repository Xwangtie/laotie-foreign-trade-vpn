"""审计日志查询。"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..db import get_db
from ..deps import require_roles
from ..models import Admin, AuditLog
from ..schemas import AuditListPage, AuditOut


router = APIRouter(prefix="/api/audit", tags=["audit"])
superadmin_only = require_roles("superadmin")


@router.get("", response_model=AuditListPage)
def list_audit(
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=50, ge=1, le=200),
    action: str | None = None,
    admin_id: int | None = None,
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    stmt = select(AuditLog)
    if action:
        stmt = stmt.where(AuditLog.action == action)
    if admin_id is not None:
        stmt = stmt.where(AuditLog.admin_id == admin_id)
    total = db.execute(select(func.count()).select_from(stmt.subquery())).scalar_one()
    rows = (
        db.execute(
            stmt.order_by(AuditLog.id.desc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
        .scalars()
        .all()
    )
    return AuditListPage(total=total, items=[AuditOut.model_validate(r) for r in rows])
