"""读取 S1 profile.conf 并返回可选账号类型。"""

from __future__ import annotations

from pathlib import Path


def _parse_profile_conf(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        result[key.strip()] = value.strip().strip('"').strip("'")
    return result


def list_profiles(profiles_dir: Path) -> list[dict[str, str]]:
    profiles: list[dict[str, str]] = []
    for sub in sorted(profiles_dir.iterdir()):
        conf = sub / "profile.conf"
        if not sub.is_dir() or not conf.exists():
            continue
        data = _parse_profile_conf(conf)
        profiles.append(
            {
                "profile_id": data.get("PROFILE_ID", sub.name),
                "name": data.get("PROFILE_NAME", sub.name),
                "desc": data.get("DESC", ""),
                "split": data.get("SPLIT", ""),
                "failmode": data.get("FAILMODE", ""),
            }
        )
    return profiles
