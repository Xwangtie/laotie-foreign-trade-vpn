#!/usr/bin/env python3
# dns-policy.py - OpenVPN 客户级 DNS 策略网关（域名封锁，无跳转）
# 监听 10.8.0.1:53；按来源隧道 IP 识别客户；命中全局/账号封锁列表 => 返回 0.0.0.0/::；
# 其余 DNS 请求原样转发给本机 dnsmasq(127.0.0.1:53)，继续走国内ECS/国外DoH。
# 用法: dns-policy.py <listen_ip> <upstream_ip> <upstream_port>
import datetime as _dt
import concurrent.futures
import os
import socket
import sqlite3
import struct
import sys
import threading

AUTH_DB = "/var/lib/openvpn-wm/panel.db"
LOG_FILE = "/var/log/openvpn/dns-policy.log"


def log_line(msg: str) -> None:
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(f"{_dt.datetime.now(_dt.timezone.utc).isoformat()} {msg}\n")
    except OSError:
        pass


def normalize_domain(name: str) -> str:
    name = (name or "").strip().lower().rstrip(".")
    if name.startswith("*."):
        name = name[2:]
    return name


def parse_dns_name(packet: bytes, offset: int) -> tuple[str, int]:
    labels: list[str] = []
    jumped = False
    end = offset
    while True:
        if offset >= len(packet):
            break
        length = packet[offset]
        if length == 0:
            offset += 1
            if not jumped:
                end = offset
            break
        if length & 0xC0 == 0xC0:
            if offset + 1 >= len(packet):
                break
            ptr = ((length & 0x3F) << 8) | packet[offset + 1]
            if not jumped:
                end = offset + 2
            offset = ptr
            jumped = True
            continue
        offset += 1
        if offset + length > len(packet):
            break
        labels.append(packet[offset : offset + length].decode("ascii", "ignore"))
        offset += length
    return ".".join(labels), end


def parse_question(packet: bytes) -> tuple[str, int, int]:
    name, off = parse_dns_name(packet, 12)
    if off + 4 > len(packet):
        return name, 1, 1
    qtype, qclass = struct.unpack("!HH", packet[off : off + 4])
    return name, qtype, qclass


def make_block_response(query: bytes, qname: str, qtype: int, qclass: int) -> bytes:
    qid = int.from_bytes(query[:2], "big")
    # question 段原样复制（到 qtype/qclass 结束）
    name, qend = parse_dns_name(query, 12)
    question = query[12 : qend + 4]
    if qtype not in (1, 28):
        header = struct.pack("!HHHHHH", qid, 0x8183, 1, 0, 0, 0)
        return header + question
    flags = 0x8180  # QR + RD + RA
    header = struct.pack("!HHHHHH", qid, flags, 1, 1, 0, 0)
    ttl = 60
    if qtype == 28:  # AAAA
        rdata = b"\x00" * 16
    else:
        rdata = b"\x00\x00\x00\x00"
    answer = (
        struct.pack("!HHHIH", 0xC00C, qtype, qclass, ttl, len(rdata))
        + rdata
    )
    return header + question + answer


def load_policy() -> dict[str, dict]:
    """返回 {'users': {tun_ip: user_id}, 'blocks': {user_id_or_0: [domains...]}}"""
    users: dict[str, int] = {}
    blocks: dict[int, list[str]] = {0: []}
    try:
        con = sqlite3.connect(f"file:{AUTH_DB}?mode=ro", uri=True, timeout=3)
        try:
            for row in con.execute(
                "SELECT virtual_ip, user_id FROM sessions"
                " WHERE disconnected_at IS NULL AND virtual_ip IS NOT NULL"
            ):
                if row[0]:
                    users[str(row[0])] = int(row[1])
            for row in con.execute(
                "SELECT user_id, domain FROM blocked_domains WHERE domain <> ''"
            ):
                key = int(row[0]) if row[0] is not None else 0
                blocks.setdefault(key, []).append(normalize_domain(row[1]))
        finally:
            con.close()
    except sqlite3.Error as exc:
        log_line(f"policy-load-error {exc!r}")
    return {"users": users, "blocks": blocks}


def is_blocked(policy: dict, user_id: int, domain: str) -> bool:
    blocks = policy.get("blocks", {})
    target = normalize_domain(domain)
    if not target:
        return False
    candidates: list[str] = []
    candidates.extend(blocks.get(0, []))
    candidates.extend(blocks.get(user_id, []))
    for rule in candidates:
        if target == rule or target.endswith("." + rule):
            return True
    return False


class PolicyServer:
    def __init__(self, listen_ip: str, upstream_ip: str, upstream_port: int):
        self.listen_ip = listen_ip
        self.upstream = (upstream_ip, upstream_port)
        self.policy: dict[str, dict] = {"users": {}, "blocks": {0: []}}
        self.lock = threading.Lock()
        # Browsers issue many DNS queries concurrently.  Handling them on the
        # receive loop would let one slow upstream lookup block every client.
        self.workers = concurrent.futures.ThreadPoolExecutor(
            max_workers=32, thread_name_prefix="dns-policy"
        )
        self._refresh_policy()

    def _refresh_policy(self) -> None:
        new_policy = load_policy()
        with self.lock:
            self.policy = new_policy

    def reload_loop(self) -> None:
        while True:
            threading.Event().wait(5)
            self._refresh_policy()

    def udp_serve(self) -> None:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind((self.listen_ip, 53))
        sock.settimeout(1.0)
        log_line(f"dns-policy listening {self.listen_ip}:53 -> {self.upstream}")
        while True:
            try:
                query, peer = sock.recvfrom(4096)
            except socket.timeout:
                continue
            except OSError:
                continue
            self.workers.submit(self._handle_udp_safe, sock, query, peer)

    def _handle_udp_safe(self, sock: socket.socket, query: bytes, peer) -> None:
        try:
            self._handle_udp(sock, query, peer)
        except Exception as exc:
            log_line(f"handle-error {exc!r}")

    def _handle_udp(self, sock: socket.socket, query: bytes, peer) -> None:
        if len(query) < 12:
            return
        qname, qtype, qclass = parse_question(query)
        with self.lock:
            policy = self.policy
            users = policy.get("users", {})
            blocks = policy.get("blocks", {})
        tun_ip = peer[0]
        user_id = users.get(tun_ip, -1)
        if user_id >= 0 and is_blocked({"blocks": blocks}, user_id, qname):
            log_line(f"block user={user_id} ip={tun_ip} domain={qname}")
            response = make_block_response(query, qname, qtype, qclass)
            sock.sendto(response, peer)
            return
        if user_id < 0:
            # 未映射到会话的隧道 IP：先按全局规则执行，仍命中就封
            if is_blocked({"blocks": blocks}, -1, qname) and blocks.get(0):
                log_line(f"block global-only ip={tun_ip} domain={qname}")
                sock.sendto(make_block_response(query, qname, qtype, qclass), peer)
                return
        for attempt in range(2):
            up = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            try:
                up.settimeout(2.0)
                up.sendto(query, self.upstream)
                data, _ = up.recvfrom(4096)
                sock.sendto(data, peer)
                return
            except OSError as exc:
                if attempt:
                    log_line(
                        f"upstream-error domain={qname} peer={peer[0]} error={exc!r}"
                    )
            finally:
                up.close()


def main() -> int:
    listen_ip = sys.argv[1] if len(sys.argv) > 1 else "10.8.0.1"
    upstream_ip = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1"
    upstream_port = int(sys.argv[3]) if len(sys.argv) > 3 else 53
    server = PolicyServer(listen_ip, upstream_ip, upstream_port)
    threading.Thread(target=server.reload_loop, daemon=True).start()
    server.udp_serve()
    return 0


if __name__ == "__main__":
    sys.exit(main())
