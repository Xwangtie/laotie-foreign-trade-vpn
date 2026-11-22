"""P0 主流程接口测试。"""

from __future__ import annotations

from datetime import datetime, timedelta

import pyotp


def test_health(client):
    resp = client.get("/api/health")
    assert resp.status_code == 200
    assert resp.json()["app"] == "老铁外贸网络管理系统"


def test_profiles(client, admin_headers):
    resp = client.get("/api/profiles", headers=admin_headers)
    assert resp.status_code == 200
    ids = {item["profile_id"] for item in resp.json()}
    assert ids == {"trade-global", "trade-strict", "game-open"}


def _create_user(client, admin_headers, username="testclient01"):
    resp = client.post(
        "/api/users",
        headers=admin_headers,
        json={
            "username": username,
            "profile": "trade-strict",
            "customer_name": "张三",
            "phone": "13900000000",
            "company": "测试贸易公司",
            "email": "zhangsan@example.com",
            "quota_bytes": 10 * 1024**3,
        },
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


def test_user_full_lifecycle(client, admin_headers):
    created = _create_user(client, admin_headers)
    assert created["status"] == "active"
    assert created["profile"] == "trade-strict"
    token = created["download_token"]

    # 下载 .ovpn 无需管理员登录，凭一次性 token
    ovpn = client.get(f"/api/users/{created['id']}/ovpn?token={token}")
    assert ovpn.status_code == 200
    assert "# PROFILE=trade-strict" in ovpn.text
    assert "# FAILMODE=close-foreign" in ovpn.text
    assert "vpn.example.com" in ovpn.text
    # token 一次性
    again = client.get(f"/api/users/{created['id']}/ovpn?token={token}")
    assert again.status_code == 404

    # 非法用户名必须被拒
    bad = client.post(
        "/api/users",
        headers=admin_headers,
        json={
            "username": "rm -rf /",
            "profile": "game-open",
            "customer_name": "x",
            "phone": "1",
            "company": "x",
            "email": "x@x.com",
        },
    )
    assert bad.status_code == 422

    # 续期
    renew = client.post(
        f"/api/users/{created['id']}/renew",
        headers=admin_headers,
        json={"months": 2},
    )
    assert renew.status_code == 200
    assert renew.json()["status"] == "active"

    # 暂停/恢复/吊销
    assert client.post(
        f"/api/users/{created['id']}/suspend", headers=admin_headers
    ).status_code == 200
    assert client.post(
        f"/api/users/{created['id']}/resume", headers=admin_headers
    ).status_code == 200
    revoked = client.post(
        f"/api/users/{created['id']}/revoke", headers=admin_headers
    )
    assert revoked.status_code == 200
    assert revoked.json()["status"] == "revoked"


def test_create_user_minimal_info_allowed(client, admin_headers):
    """第一阶段：客户资料允许不全，只填用户名/类型也能开户。"""
    resp = client.post(
        "/api/users",
        headers=admin_headers,
        json={"username": "minimal01", "profile": "game-open"},
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["customer_name"] == ""
    assert body["phone"] == ""
    assert body["company"] == ""
    assert body["email"] == ""


def test_one_char_username(client, admin_headers):
    """用户名 1 位即可；配置为纯证书自动登录，不含 auth-user-pass。"""
    resp = client.post(
        "/api/users",
        headers=admin_headers,
        json={"username": "x", "profile": "game-open"},
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["username"] == "x"
    ovpn = client.get(f"/api/users/{body['id']}/ovpn?token={body['download_token']}")
    assert ovpn.status_code == 200
    assert "auth-user-pass" not in ovpn.text


def test_expired_user_sweep(client, admin_headers):
    created = _create_user(client, admin_headers, username="expireme01")
    from sqlalchemy import update

    from app.db import SessionLocal
    from app.models import User
    from app.services.jobs import sweep_expired

    db = SessionLocal()
    try:
        db.execute(
            update(User)
            .where(User.id == created["id"])
            .values(expire_at=datetime.utcnow() - timedelta(minutes=1))
        )
        db.commit()
        count = sweep_expired(db)
        assert count == 1
        db.expire_all()
        from sqlalchemy import select

        user = db.execute(
            select(User).where(User.id == created["id"])
        ).scalar_one()
        assert user.status == "expired"
    finally:
        db.close()


def test_admin_management_guard(client, admin_headers):
    # 不能停用自己
    me = client.get("/api/auth/me", headers=admin_headers).json()
    resp = client.patch(
        f"/api/admins/{me['id']}",
        headers=admin_headers,
        json={"is_active": False},
    )
    assert resp.status_code == 400

    # 创建第二个管理员后列表可见
    created = client.post(
        "/api/admins",
        headers=admin_headers,
        json={
            "username": "admin2",
            "password": "Admin-2-password",
            "role": "admin",
        },
    )
    assert created.status_code == 201, created.text
    admins = client.get("/api/admins", headers=admin_headers).json()
    assert admins["total"] >= 2


def _login_admin(client, username: str, password: str) -> dict:
    resp = client.post(
        "/api/auth/login",
        json={"username": username, "password": password},
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["setup_token"]
    code = pyotp.TOTP(data["manual_key"]).now()
    confirm = client.post(
        "/api/auth/totp/confirm",
        json={"setup_token": data["setup_token"], "code": code},
    )
    assert confirm.status_code == 200, confirm.text
    tokens = confirm.json()
    return {"Authorization": f"Bearer {tokens['access_token']}"}


def test_admin_password_minimum_six(client, admin_headers):
    """普通管理员初始密码最低 6 位即可，不做复杂度强校验。"""
    resp = client.post(
        "/api/admins",
        headers=admin_headers,
        json={"username": "operator6", "password": "abc123", "role": "admin"},
    )
    assert resp.status_code == 201, resp.text


def test_normal_admin_only_customer_accounts(client, admin_headers):
    """普通管理员（admin）：只能访问客户账号相关 API，其余一律 403。"""
    created = client.post(
        "/api/admins",
        headers=admin_headers,
        json={"username": "operator01", "password": "abc123", "role": "admin"},
    )
    assert created.status_code == 201, created.text
    headers = _login_admin(client, "operator01", "abc123")

    assert client.get("/api/auth/me", headers=headers).status_code == 200
    assert client.get("/api/profiles", headers=headers).status_code == 200
    assert client.get("/api/users", headers=headers).status_code == 200

    for path in (
        "/api/admins",
        "/api/nodes",
        "/api/audit",
        "/api/dashboard",
        "/api/online",
        "/api/port-mappings",
    ):
        resp = client.get(path, headers=headers)
        assert resp.status_code == 403, f"{path} -> {resp.status_code}"


def test_blocked_domains_global_and_per_user(client, admin_headers):
    created = _create_user(client, admin_headers, username="blockme01")
    uid = created["id"]

    # 全局
    g = client.post(
        "/api/blocked-domains/global",
        headers=admin_headers,
        json={"domain": "bad-site.example.com"},
    )
    assert g.status_code == 201, g.text
    assert client.get("/api/blocked-domains/global", headers=admin_headers).json()[0]["domain"] == "bad-site.example.com"

    # 按账号
    u = client.post(
        f"/api/users/{uid}/blocked-domains",
        headers=admin_headers,
        json={"domain": "game-cheat.example.net", "remark": "作弊站"},
    )
    assert u.status_code == 201, u.text
    rows = client.get(
        f"/api/users/{uid}/blocked-domains", headers=admin_headers
    ).json()
    assert len(rows) == 1
    assert rows[0]["username"] == "blockme01"

    # 删除
    assert (
        client.delete(
            f"/api/users/{uid}/blocked-domains",
            headers=admin_headers,
            params={"domain": "game-cheat.example.net"},
        ).status_code
        == 200
    )
    assert (
        client.delete(
            "/api/blocked-domains/global",
            headers=admin_headers,
            params={"domain": "bad-site.example.com"},
        ).status_code
        == 200
    )


def test_delete_user_requires_revoked_first(client, admin_headers):
    created = _create_user(client, admin_headers, username="delete01")
    uid = created["id"]

    # 未吊销直接删除 -> 400
    resp = client.delete(f"/api/users/{uid}", headers=admin_headers)
    assert resp.status_code == 400
    assert "吊销" in resp.json()["detail"]

    # 吊销完成后删除 -> 200，随后查询 404
    revoked = client.post(f"/api/users/{uid}/revoke", headers=admin_headers)
    assert revoked.status_code == 200
    assert revoked.json()["status"] == "revoked"
    deleted = client.delete(f"/api/users/{uid}", headers=admin_headers)
    assert deleted.status_code == 200, deleted.text
    assert client.get(f"/api/users/{uid}", headers=admin_headers).status_code == 404


def test_vpn_group_membership_and_static_ips(client, admin_headers):
    a = _create_user(client, admin_headers, username="groupa01")
    b = _create_user(client, admin_headers, username="groupb01")
    c = _create_user(client, admin_headers, username="groupc01")

    resp = client.get("/api/settings/vpn-groups", headers=admin_headers)
    assert resp.status_code == 200, resp.text
    initial = resp.json()
    assert initial["global_enabled"] is False
    assert initial["groups"][0]["members"] == []
    assert initial["groups"][1]["members"] == []

    saved = client.put(
        "/api/settings/vpn-groups",
        headers=admin_headers,
        json={"group1": [a["username"], b["username"]], "group2": [c["username"]]},
    )
    assert saved.status_code == 200, saved.text

    data = client.get("/api/settings/vpn-groups", headers=admin_headers).json()
    by_group = {g["id"]: g["members"] for g in data["groups"]}
    assert by_group["group1"] == ["groupa01", "groupb01"]
    assert by_group["group2"] == ["groupc01"]
    ips = {u["username"]: u["vpn_ip"] for u in data["users"]}
    assert ips[a["username"]] == "10.8.0.201"
    assert ips[b["username"]] == "10.8.0.202"
    assert ips[c["username"]] == "10.8.0.203"

    # 同一账号不能同时加入两个分组
    overlap = client.put(
        "/api/settings/vpn-groups",
        headers=admin_headers,
        json={"group1": [a["username"]], "group2": [a["username"]]},
    )
    assert overlap.status_code == 400


def test_audit_visible(client, admin_headers):
    rows = client.get("/api/audit", headers=admin_headers)
    assert rows.status_code == 200
    assert rows.json()["total"] >= 1


def test_login_requires_totp_after_bind(client):
    resp = client.post(
        "/api/auth/login",
        json={"username": "admin", "password": "Admin-test-123456"},
    )
    assert resp.status_code == 428
    assert resp.json()["requires_totp"] is True
