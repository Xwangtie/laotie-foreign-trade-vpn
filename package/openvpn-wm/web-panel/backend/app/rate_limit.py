"""轻量内存登录限流（生产多进程可换 Redis，接口不变）。"""

from __future__ import annotations

import threading
import time
from dataclasses import dataclass, field


@dataclass
class _Entry:
    attempts: list[float] = field(default_factory=list)
    locked_until: float = 0.0


class LoginRateLimiter:
    def __init__(self) -> None:
        self._data: dict[str, _Entry] = {}
        self._lock = threading.Lock()

    def _key(self, username: str, ip: str) -> str:
        return f"{username.lower()}|{ip}"

    def check(self, username: str, ip: str, *, max_attempts: int, window: int, lock_seconds: int) -> tuple[bool, int]:
        """返回 (是否允许, 锁定剩余秒数)。"""
        key = self._key(username, ip)
        now = time.time()
        with self._lock:
            entry = self._data.get(key) or _Entry()
            if entry.locked_until > now:
                return False, int(entry.locked_until - now)
            entry.attempts = [t for t in entry.attempts if now - t < window]
            if len(entry.attempts) >= max_attempts:
                entry.locked_until = now + lock_seconds
                entry.attempts.clear()
                self._data[key] = entry
                return False, lock_seconds
            return True, 0

    def record_failure(self, username: str, ip: str, *, window: int) -> None:
        key = self._key(username, ip)
        now = time.time()
        with self._lock:
            entry = self._data.get(key) or _Entry()
            entry.attempts = [t for t in entry.attempts if now - t < window]
            entry.attempts.append(now)
            self._data[key] = entry

    def clear(self, username: str, ip: str) -> None:
        with self._lock:
            self._data.pop(self._key(username, ip), None)


rate_limiter = LoginRateLimiter()
