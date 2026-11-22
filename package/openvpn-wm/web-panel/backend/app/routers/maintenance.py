"""服务维护：日志清理。"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from ..audit import write_audit
from ..db import get_db
from ..deps import client_ip, require_roles
from ..models import Admin
from ..schemas import ApiMessage
from ..services import logclean


router = APIRouter(prefix="/api/maintenance", tags=["maintenance"])
superadmin_only = require_roles("superadmin")


@router.post("/logs/clean", response_model=ApiMessage)
def clean_all_logs(
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    msg = logclean.clean_logs()
    write_audit(
        db,
        admin,
        "maintenance.logs.clean",
        detail={"result": msg},
        ip=client_ip(request),
    )
    return ApiMessage(message=msg)


@router.post("/logs/retain30", response_model=ApiMessage)
def retain_30_days_logs(
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    msg = logclean.retain_30_days()
    write_audit(
        db,
        admin,
        "maintenance.logs.retain30",
        detail={"result": msg},
        ip=client_ip(request),
    )
    return ApiMessage(message=msg)
