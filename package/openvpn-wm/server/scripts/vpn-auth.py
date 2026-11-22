#!/usr/bin/env python3
# vpn-auth.py - OpenVPN 认证与账号状态校验
# 用法：
#   1) auth-user-pass-verify via-file: 校验 用户名+密码（密码=开户时设置）
#   2) client-connect:                校验账号状态/到期/吊销
# 成功与失败都会写入 panel.db 的 vpn_auth_log 表
import datetime as _dt
import hashlib
import hmac
import os
import sqlite3
import sys

AUTH_DB = "/var/lib/openvpn-wm/panel.db"
LOG_FILE = "/var/log/openvpn/vpn-auth.log"


def utcnow_iso() -> str:
    return _dt.datetime.now(_dt.timezone.utc).replace(microsecond=0).isoformat()


def note(username: str, msg: str) -> None:
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(f"{utcnow_iso()} {username} {msg}\n")
    except OSError:
        pass


def db_connect(read_only: bool = False) -> sqlite3.Connection:
    if read_only:
        return sqlite3.connect(f"file:{AUTH_DB}?mode=ro", uri=True, timeout=5)
    return sqlite3.connect(AUTH_DB, timeout=5)


def verify_pbkdf2(password: str, encoded: str | None) -> bool:
    if not encoded:
        return False
    try:
        algo, it_s, salt, expected = encoded.split("$", 3)
        if algo != "pbkdf2_sha256":
            return False
        actual = hashlib.pbkdf2_hmac(
            "sha256", password.encode("utf-8"), salt.encode("ascii"), int(it_s)
        ).hex()
    except (ValueError, TypeError):
        return False
    return hmac.compare_digest(actual, expected)


def write_auth_log(
    username: str,
    success: bool,
    reason: str | None = None,
    real_ip: str | None = None,
    virtual_ip: str | None = None,
) -> None:
    user_id = None
    try:
        con = db_connect(read_only=True)
        try:
            row = con.execute(
                "SELECT id FROM users WHERE username=? LIMIT 1", (username,)
            ).fetchone()
            user_id = row[0] if row else None
        finally:
            con.close()
        con = db_connect()
        try:
            con.execute(
                "INSERT INTO vpn_auth_log"
                "(user_id, username, success, reason, real_ip, virtual_ip, created_at)"
                " VALUES (?,?,?,?,?,?,?)",
                (
                    user_id,
                    username,
                    1 if success else 0,
                    reason,
                    real_ip,
                    virtual_ip,
                    _dt.datetime.utcnow().isoformat(sep=" "),
                ),
            )
            con.commit()
        finally:
            con.close()
    except Exception:
        pass  # 表尚未迁移/数据库不可写时不阻塞 OpenVPN 决策


def expired(expire_at: object) -> bool:
    if not expire_at:
        return False
    try:
        exp = _dt.datetime.fromisoformat(str(expire_at).replace("Z", "+00:00"))
        if exp.tzinfo is not None:
            exp = exp.astimezone(_dt.timezone.utc).replace(tzinfo=None)
    except ValueError:
        return False
    return exp <= _dt.datetime.utcnow()


def verify_login(username: str, password: str) -> int:
    real_ip = os.environ.get("trusted_ip") or os.environ.get("untrusted_ip")
    if not os.path.exists(AUTH_DB):
        note(username, "deny (db-not-initialized)")
        return 1
    try:
        con = db_connect(read_only=True)
        try:
            row = con.execute(
                "SELECT status, expire_at, password_hash FROM users"
                " WHERE username=? LIMIT 1",
                (username,),
            ).fetchone()
        finally:
            con.close()
    except sqlite3.Error as exc:
        note(username, f"deny (db-error {exc!r})")
        write_auth_log(username, False, "db-error", real_ip=real_ip)
        return 1
    if row is None:
        note(username, "deny (unknown-user)")
        write_auth_log(username, False, "unknown-user", real_ip=real_ip)
        return 1
    status, expire_at, password_hash = row
    if status != "active":
        note(username, f"deny (status={status})")
        write_auth_log(username, False, f"status-{status}", real_ip=real_ip)
        return 1
    if expired(expire_at):
        note(username, "deny (expired)")
        write_auth_log(username, False, "expired", real_ip=real_ip)
        return 1
    if not verify_pbkdf2(password, password_hash):
        note(username, "deny (bad-password)")
        write_auth_log(username, False, "bad-password", real_ip=real_ip)
        return 1
    common_name = os.environ.get("common_name", "")
    if common_name and common_name != username:
        note(username, f"deny (cert-cn-mismatch cn={common_name})")
        write_auth_log(username, False, "cert-cn-mismatch", real_ip=real_ip)
        return 1
    note(username, "allow (password)")
    write_auth_log(username, True, "password-ok", real_ip=real_ip)
    return 0


def check_status(username: str) -> int:
    if not os.path.exists(AUTH_DB):
        note(username, "allow (db-not-initialized test mode)")
        return 0
    try:
        con = db_connect(read_only=True)
        try:
            row = con.execute(
                "SELECT status, expire_at FROM users WHERE username=? LIMIT 1",
                (username,),
            ).fetchone()
        finally:
            con.close()
    except sqlite3.Error as exc:
        note(username, f"allow (db-error {exc!r})")
        return 0
    if row is None:
        note(username, "deny (unknown-user)")
        return 1
    status, expire_at = row
    if status != "active":
        note(username, f"deny (status={status})")
        return 1
    if expired(expire_at):
        note(username, "deny (expired)")
        return 1
    note(username, "allow (status)")
    return 0


def main() -> int:
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    script_type = os.environ.get("script_type", "")
    if script_type == "user-pass-verify":
        try:
            with open(arg, "r", encoding="utf-8") as f:
                lines = f.read().splitlines()
            username = (lines[0] if lines else "").strip()
            password = lines[1] if len(lines) > 1 else ""
        except OSError as exc:
            note("?", f"auth-file-error {exc!r}")
            return 1
        if not username:
            note("?", "deny (empty-username)")
            return 1
        return verify_login(username, password)
    username = sys.argv[2] if len(sys.argv) > 2 else arg
    if not username:
        note("?", "missing common_name")
        return 0
    return check_status(username)


if __name__ == "__main__":
    sys.exit(main())
