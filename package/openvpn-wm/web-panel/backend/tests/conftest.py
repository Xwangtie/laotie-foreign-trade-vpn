"""测试环境：使用独立临时 SQLite，S1 全部走 MOCK。"""

from __future__ import annotations

import os
import tempfile

import pytest
from fastapi.testclient import TestClient


_TEST_ROOT = tempfile.mkdtemp(prefix="owm-panel-test-")
os.environ["OPENVPN_WM_DB_PATH"] = os.path.join(_TEST_ROOT, "panel-test.db")
os.environ["LAN_STATE_FILE"] = os.path.join(_TEST_ROOT, "lan-groups.json")
os.environ["MOCK_EASY_RSA"] = "true"
os.environ["ENABLE_SCHEDULER"] = "false"
os.environ["JWT_SECRET"] = "test-only-secret-please-change-0123456789"
os.environ["BOOTSTRAP_ADMIN_PASSWORD"] = "Admin-test-123456"
os.environ["SMTP_HOST"] = ""

from app.main import app  # noqa: E402


@pytest.fixture(scope="session")
def client():
    with TestClient(app) as c:
        yield c


@pytest.fixture(scope="session")
def admin_headers(client: TestClient):
    login = client.post(
        "/api/auth/login",
        json={"username": "admin", "password": "Admin-test-123456"},
    )
    assert login.status_code == 200, login.text
    data = login.json()
    assert data["setup_token"]
    import pyotp

    code = pyotp.TOTP(data["manual_key"]).now()
    confirm = client.post(
        "/api/auth/totp/confirm",
        json={"setup_token": data["setup_token"], "code": code},
    )
    assert confirm.status_code == 200, confirm.text
    tokens = confirm.json()
    return {
        "Authorization": f"Bearer {tokens['access_token']}",
        "refresh": tokens["refresh_token"],
    }
