"""端口映射管理（后台 NAT 转发）。"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import select
from sqlalchemy.orm import Session, joinedload

from ..audit import write_audit
from ..db import get_db
from ..deps import client_ip, require_roles
from ..models import Admin, Node, PortMapping, User
from ..schemas import ApiMessage, PortMappingCreate, PortMappingOut
from ..services import portmap


router = APIRouter(prefix="/api/port-mappings", tags=["port-mappings"])
superadmin_only = require_roles("superadmin")

# 系统/面板自身已占用的公网端口，禁止再映射
RESERVED_PORTS = {
    22,
    53,
    80,
    443,
    1194,
    8000,
    8989,
    12346,
}


def _node(db: Session) -> Node:
    node = db.execute(
        select(Node).where(Node.status == "active").order_by(Node.id).limit(1)
    ).scalar_one_or_none()
    if node is None:
        raise HTTPException(400, "尚未配置可用节点")
    return node


def _to_out(m: PortMapping) -> PortMappingOut:
    d = PortMappingOut.model_validate(m)
    d.username = m.user.username if m.user else None
    return d


@router.get("", response_model=list[PortMappingOut])
def list_port_mappings(
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    rows = db.execute(
        select(PortMapping)
        .options(joinedload(PortMapping.user))
        .order_by(PortMapping.id.desc())
    ).scalars().all()
    return [_to_out(m) for m in rows]


@router.post("", response_model=PortMappingOut, status_code=201)
def create_port_mapping(
    body: PortMappingCreate,
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    if body.ext_port in RESERVED_PORTS:
        raise HTTPException(400, "该公网端口被系统服务占用，请换一个")
    exists = db.execute(
        select(PortMapping).where(PortMapping.ext_port == body.ext_port)
    ).scalar_one_or_none()
    if exists:
        raise HTTPException(409, f"公网端口 {body.ext_port} 已被其它映射占用")

    user = None
    if body.user_id is not None:
        user = db.get(User, body.user_id)
        if user is None:
            raise HTTPException(404, "所选账号不存在")

    node = _node(db)
    mapping = PortMapping(
        user_id=user.id if user else None,
        dest_ip=body.dest_ip,
        ext_port=body.ext_port,
        int_port=body.int_port,
        protocol=body.protocol,
        status="active",
        remark=body.remark,
    )
    try:
        portmap.add_rule(body.ext_port, body.protocol, body.dest_ip, body.int_port)
    except Exception as exc:
        raise HTTPException(502, str(exc)) from exc
    db.add(mapping)
    db.flush()
    write_audit(
        db,
        admin,
        "portmap.create",
        target_type="port_mapping",
        target_id=mapping.id,
        detail={
            "dest_ip": mapping.dest_ip,
            "ext_port": mapping.ext_port,
            "int_port": mapping.int_port,
            "protocol": mapping.protocol,
            "public": f"{node.public_domain}:{mapping.ext_port}",
        },
        ip=client_ip(request),
        commit=False,
    )
    db.commit()
    db.refresh(mapping)
    return _to_out(mapping)


@router.delete("/{mapping_id}", response_model=ApiMessage)
def delete_port_mapping(
    mapping_id: int,
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    mapping = db.get(PortMapping, mapping_id)
    if mapping is None:
        raise HTTPException(404, "映射不存在")
    portmap.remove_rule(
        mapping.ext_port,
        mapping.protocol,
        mapping.dest_ip,
        mapping.int_port,
    )
    ext = mapping.ext_port
    dest = mapping.dest_ip
    db.delete(mapping)
    write_audit(
        db,
        admin,
        "portmap.delete",
        target_type="port_mapping",
        target_id=mapping_id,
        detail={"ext_port": ext, "dest_ip": dest},
        ip=client_ip(request),
        commit=False,
    )
    db.commit()
    return ApiMessage(message=f"已删除端口映射 {ext} -> {dest}")


@router.post("/sync", response_model=ApiMessage)
def sync_port_mappings(
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    """按数据库全量重建 NAT 规则（服务器迁移/故障恢复后使用）。"""
    rows = db.execute(
        select(PortMapping).where(PortMapping.status == "active")
    ).scalars().all()
    rules = [
        {
            "ext_port": m.ext_port,
            "protocol": m.protocol,
            "dest_ip": m.dest_ip,
            "int_port": m.int_port,
        }
        for m in rows
    ]
    out = portmap.sync_all(rules)
    return ApiMessage(message=f"已重建 {len(rules)} 条映射。{out}".strip())
