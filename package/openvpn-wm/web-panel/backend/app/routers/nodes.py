"""节点/服务器管理（第一期仅本机，结构支持多机）。"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..audit import write_audit
from ..db import get_db
from ..deps import client_ip, require_roles
from ..models import Admin, Node
from ..schemas import NodeCreate, NodeOut, NodeUpdate


router = APIRouter(prefix="/api/nodes", tags=["nodes"])
superadmin_only = require_roles("superadmin")


@router.get("", response_model=list[NodeOut])
def list_nodes(
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    rows = db.execute(select(Node).order_by(Node.id)).scalars().all()
    return rows


@router.post("", response_model=NodeOut, status_code=status.HTTP_201_CREATED)
def create_node(
    body: NodeCreate,
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    exists = db.execute(select(Node).where(Node.name == body.name)).scalar_one_or_none()
    if exists:
        raise HTTPException(status.HTTP_409_CONFLICT, "节点名称已存在")
    node = Node(**body.model_dump())
    db.add(node)
    db.flush()
    write_audit(
        db,
        admin,
        "node.create",
        target_type="node",
        target_id=node.id,
        detail={"name": node.name, "public_domain": node.public_domain},
        ip=client_ip(request),
        commit=False,
    )
    db.commit()
    db.refresh(node)
    return node


@router.patch("/{node_id}", response_model=NodeOut)
def update_node(
    node_id: int,
    body: NodeUpdate,
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    node = db.get(Node, node_id)
    if node is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "节点不存在")
    changed = {
        k: v for k, v in body.model_dump(exclude_unset=True).items() if v is not None
    }
    for key, value in changed.items():
        setattr(node, key, value)
    write_audit(
        db,
        admin,
        "node.update",
        target_type="node",
        target_id=node.id,
        detail={"name": node.name, "changed": {k: str(v) for k, v in changed.items()}},
        ip=client_ip(request),
        commit=False,
    )
    db.commit()
    db.refresh(node)
    return node


@router.delete("/{node_id}")
def delete_node(
    node_id: int,
    request: Request,
    db: Session = Depends(get_db),
    admin: Admin = Depends(superadmin_only),
):
    node = db.get(Node, node_id)
    if node is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "节点不存在")
    active_count = db.execute(
        select(func.count()).select_from(Node).where(Node.status == "active")
    ).scalar_one()
    if node.status == "active" and active_count <= 1:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "至少保留一个可用节点")
    name = node.name
    db.delete(node)
    write_audit(
        db,
        admin,
        "node.delete",
        target_type="node",
        target_id=node_id,
        detail={"name": name},
        ip=client_ip(request),
        commit=False,
    )
    db.commit()
    return {"message": f"节点 {name} 已删除"}
