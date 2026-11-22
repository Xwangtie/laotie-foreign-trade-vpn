"""运维 CLI：python -m app.cli ..."""

from __future__ import annotations

import argparse
import getpass
import sys

from sqlalchemy import func, select

from .config import get_settings
from .db import SessionLocal, init_db
from .models import Admin, Node
from .security import hash_password


def cmd_init_db(_args: argparse.Namespace) -> None:
    init_db()
    settings = get_settings()
    db = SessionLocal()
    try:
        count = db.execute(select(func.count()).select_from(Node)).scalar_one()
        if not count:
            db.add(
                Node(
                    name=settings.default_node_name,
                    region=settings.default_node_region,
                    public_domain=settings.default_node_domain,
                    public_ip=settings.default_node_ip,
                    ssh_port=settings.default_node_ssh_port,
                    openvpn_port=settings.default_node_openvpn_port,
                    status="active",
                )
            )
            db.commit()
    finally:
        db.close()
    print(f"数据库已初始化: {settings.openvpn_wm_db_path}")


def cmd_create_admin(args: argparse.Namespace) -> None:
    init_db()
    db = SessionLocal()
    try:
        exists = db.execute(
            select(Admin).where(Admin.username == args.username)
        ).scalar_one_or_none()
        if exists:
            print(f"管理员 {args.username} 已存在", file=sys.stderr)
            sys.exit(1)
        password = args.password
        if not password:
            password = getpass.getpass("初始密码（至少 6 位）: ")
        if len(password) < 6:
            print("密码至少 6 位", file=sys.stderr)
            sys.exit(1)
        db.add(
            Admin(
                username=args.username,
                password_hash=hash_password(password),
                role=args.role,
                is_active=True,
                totp_enabled=False,
                totp_confirmed=False,
            )
        )
        db.commit()
        print(f"管理员 {args.username} 已创建，首次登录需绑定 TOTP")
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="老铁外贸网络管理系统运维命令")
    sub = parser.add_subparsers(dest="command", required=True)
    p_init = sub.add_parser("init-db", help="初始化数据库与默认节点")
    p_init.set_defaults(func=cmd_init_db)
    p_admin = sub.add_parser("create-admin", help="创建超级管理员")
    p_admin.add_argument("--username", default="admin")
    p_admin.add_argument(
        "--role", default="superadmin", choices=["superadmin", "admin"]
    )
    p_admin.add_argument("--password", default="")
    p_admin.set_defaults(func=cmd_create_admin)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
