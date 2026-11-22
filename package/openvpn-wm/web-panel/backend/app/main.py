"""FastAPI 应用入口。"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import func, select

from .config import get_settings
from .db import SessionLocal, init_db
from .models import Admin, Node
from .routers import (
    admins,
    audit,
    auth,
    mail,
    maintenance,
    nodes,
    port_mappings,
    security_logs,
    stats,
    system_settings,
    users,
)
from .security import hash_password
from .services import jobs


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("openvpn-wm")


def seed_default_node() -> None:
    db = SessionLocal()
    try:
        exists = db.execute(select(func.count()).select_from(Node)).scalar_one()
        if exists:
            return
        settings = get_settings()
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
        logger.info("已创建默认节点 %s", settings.default_node_domain)
    finally:
        db.close()


def auto_bootstrap_admin() -> None:
    settings = get_settings()
    db = SessionLocal()
    try:
        count = db.execute(select(func.count()).select_from(Admin)).scalar_one()
        if count:
            return
        password = settings.bootstrap_admin_password
        if not password:
            logger.warning(
                "尚未创建管理员：请设置 BOOTSTRAP_ADMIN_PASSWORD 后重启，"
                "或执行 python -m app.cli create-admin"
            )
            return
        db.add(
            Admin(
                username="admin",
                password_hash=hash_password(password),
                role="superadmin",
                is_active=True,
                totp_enabled=False,
                totp_confirmed=False,
            )
        )
        db.commit()
        logger.info("已自动创建初始超级管理员 admin（首次登录需绑定 TOTP）")
    finally:
        db.close()


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    seed_default_node()
    auto_bootstrap_admin()
    scheduler = jobs.start_background_scheduler()
    logger.info("面板启动完成：老铁外贸网络管理系统")
    yield
    if scheduler is not None:
        scheduler.shutdown(wait=False)


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title=settings.app_name,
        description="老铁外贸网络管理系统 Web 管理端",
        version="0.4.0",
        lifespan=lifespan,
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=[
            "http://localhost:5173",
            "http://127.0.0.1:5173",
            "https://vpn.example.com",
        ],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.include_router(auth.router)
    app.include_router(users.router)
    app.include_router(admins.router)
    app.include_router(nodes.router)
    app.include_router(port_mappings.router)
    app.include_router(security_logs.router)
    app.include_router(system_settings.router)
    app.include_router(maintenance.router)
    app.include_router(audit.router)
    app.include_router(stats.router)
    app.include_router(mail.router)

    @app.get("/api/health")
    def health():
        return {"status": "ok", "app": settings.app_name}

    return app


app = create_app()
