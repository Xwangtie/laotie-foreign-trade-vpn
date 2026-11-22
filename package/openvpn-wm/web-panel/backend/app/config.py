"""应用配置：全部来自环境变量 / web-panel/.env，便于开发与生产共用。"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


WEB_PANEL_DIR = Path(__file__).resolve().parents[2]          # web-panel/
PROJECT_ROOT = WEB_PANEL_DIR.parent                          # 仓库根目录
DEFAULT_ENV_FILE = WEB_PANEL_DIR / ".env"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=DEFAULT_ENV_FILE, env_file_encoding="utf-8", extra="ignore"
    )

    # ---- 品牌信息 ----
    app_name: str = "老铁外贸网络管理系统"
    support_phone: str = "13905394878"
    support_email: str = "ymwww@qq.com"

    # ---- 数据库 ----
    openvpn_wm_db_path: Path = Path("/var/lib/openvpn-wm/panel.db")

    # ---- S1 契约路径 ----
    mock_easy_rsa: bool = False
    openvpn_wm_profiles_dir: Path | None = None
    openvpn_wm_ccd_dir: Path = Path("/etc/openvpn/ccd")
    s1_use_sudo: bool = False
    gen_ccd_script: Path = PROJECT_ROOT / "server" / "scripts" / "gen-ccd.sh"
    gen_client_script: Path = PROJECT_ROOT / "server" / "scripts" / "gen-client.sh"
    revoke_client_script: Path = PROJECT_ROOT / "server" / "scripts" / "revoke-client.sh"
    list_clients_script: Path = PROJECT_ROOT / "server" / "scripts" / "list-clients.sh"
    suspend_ccd_script: Path = PROJECT_ROOT / "server" / "scripts" / "suspend-client.sh"
    vpn_kill_script: Path = PROJECT_ROOT / "server" / "scripts" / "vpn-kill.sh"
    portmap_script: Path = PROJECT_ROOT / "server" / "scripts" / "portmap.sh"
    log_clean_script: Path = PROJECT_ROOT / "server" / "scripts" / "log-clean.sh"
    lan_mode_script: Path = PROJECT_ROOT / "server" / "scripts" / "set-lan-mode.sh"
    lan_state_file: Path = Path("/var/lib/openvpn-wm/lan-groups.json")
    openvpn_status_log: Path = Path("/var/log/openvpn/status.log")

    # ---- 默认节点（第一期 vpn.example.com）----
    default_node_name: str = "节点1"
    default_node_region: str = "中国"
    default_node_domain: str = "vpn.example.com"
    default_node_ip: str = "127.0.0.1"
    default_node_ssh_port: int = 12346
    default_node_openvpn_port: int = 1194

    # ---- JWT / TOTP ----
    jwt_secret: str = "please-change-me-to-a-long-random-string"
    access_token_minutes: int = 15
    refresh_token_days: int = 7
    totp_issuer: str = "老铁外贸网络管理系统"
    bootstrap_admin_password: str | None = None

    # ---- SMTP ----
    smtp_host: str | None = None
    smtp_port: int = 465
    smtp_user: str | None = None
    smtp_password: str | None = None
    smtp_from: str = "ymwww@qq.com"
    smtp_from_name: str = "老铁外贸网络管理系统"
    smtp_use_ssl: bool = True

    # ---- 任务 ----
    enable_scheduler: bool = True
    require_totp: bool = True
    enable_email_reminders: bool = True

    # ---- 安全限制 ----
    username_pattern: str = r"^[a-zA-Z0-9_-]{3,32}$"
    login_max_attempts: int = Field(default=5, ge=1)
    login_window_seconds: int = Field(default=300, ge=10)
    login_lock_seconds: int = Field(default=900, ge=60)

    @property
    def profiles_dir(self) -> Path:
        return self.openvpn_wm_profiles_dir or (PROJECT_ROOT / "profiles")

    @property
    def database_url(self) -> str:
        return f"sqlite:///{self.openvpn_wm_db_path}"

    def ensure_db_parent(self) -> None:
        """确保生产库目录存在（无权限时交由调用方报错）。"""
        self.openvpn_wm_db_path.parent.mkdir(parents=True, exist_ok=True)


@lru_cache
def get_settings() -> Settings:
    return Settings()
