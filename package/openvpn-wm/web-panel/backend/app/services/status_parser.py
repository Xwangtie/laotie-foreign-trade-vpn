"""解析 OpenVPN status v1 文件。"""

from __future__ import annotations

from pathlib import Path
from typing import Optional


def parse_status_file(path: Path) -> dict[str, dict[str, object]]:
    """返回 {common_name: {real_ip, virtual_ip, rx_bytes, tx_bytes, connected_since}}。"""
    if not path.exists():
        return {}
    result: dict[str, dict[str, object]] = {}
    header: list[str] = []
    in_v1_clients = False
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    route_lines: list[list[str]] = []
    in_route = False
    for raw in lines:
        line = raw.strip()
        if line.startswith("ROUTING TABLE"):
            in_route = True
            continue
        if line.startswith("GLOBAL STATS") or line.startswith("END"):
            in_route = False
            continue
        if in_route and "," in line:
            cells = [c.strip() for c in line.split(",")]
            if len(cells) >= 2 and not line.startswith("Virtual Address"):
                route_lines.append(cells)
        if line.startswith("HEADER"):
            parts = line.split("\t")
            if len(parts) >= 2:
                header = parts[1:]
            in_v1_clients = False
            continue
        if not line.startswith("CLIENT_LIST"):
            # OpenVPN status v1 格式：Common Name,Real Address,Bytes Received,... 之后每行一个客户端
            if line.startswith("Common Name"):
                header = [h.strip() for h in line.split(",")]
                in_v1_clients = True
                continue
            if in_v1_clients:
                if line.startswith(("ROUTING TABLE", "GLOBAL STATS", "END")):
                    in_v1_clients = False
                    continue
                if not line or line.startswith(("Updated", "Virtual Address")):
                    continue
                cells = [c.strip() for c in line.split(",")]
                if len(cells) >= len(header) and header:
                    data = dict(zip(header, cells))
                    name = data.get("Common Name")
                    if name:
                        result[name] = {
                            "real_ip": data.get("Real Address", ""),
                            "virtual_ip": data.get("Virtual Address", ""),
                            "rx_bytes": int(data.get("Bytes Received") or 0),
                            "tx_bytes": int(data.get("Bytes Sent") or 0),
                            "connected_since": data.get("Connected Since", ""),
                        }
            continue
        cells = line.split("\t")
        if len(cells) < 2:
            continue
        data = dict(zip(header, cells[1:]))
        name = data.get("Common Name")
        if not name:
            continue
        result[name] = {
            "real_ip": data.get("Real Address", ""),
            "virtual_ip": data.get("Virtual Address", ""),
            "rx_bytes": int(data.get("Bytes Received") or 0),
            "tx_bytes": int(data.get("Bytes Sent") or 0),
            "connected_since": data.get("Connected Since", ""),
        }
    # v1 路由段回填虚拟 IP
    for cells in route_lines:
        cn = cells[1] if len(cells) > 1 else ""
        if cn in result and cells:
            result[cn]["virtual_ip"] = cells[0]
    return result
