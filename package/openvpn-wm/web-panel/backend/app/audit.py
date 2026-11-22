"""审计写入助手。"""

from __future__ import annotations

import json
from typing import Any, Optional

from sqlalchemy.orm import Session

from .models import Admin, AuditLog


def write_audit(
    db: Session,
    admin: Optional[Admin],
    action: str,
    target_type: Optional[str] = None,
    target_id: Optional[int] = None,
    detail: Optional[dict[str, Any]] = None,
    ip: Optional[str] = None,
    commit: bool = True,
) -> AuditLog:
    entry = AuditLog(
        admin_id=admin.id if admin else None,
        admin_username=admin.username if admin else None,
        action=action,
        target_type=target_type,
        target_id=target_id,
        detail_json=json.dumps(detail or {}, ensure_ascii=False),
        ip=ip,
    )
    db.add(entry)
    if commit:
        db.commit()
    return entry
