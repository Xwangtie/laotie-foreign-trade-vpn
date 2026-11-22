# openvpn-wm 技术架构设计

> 配套阅读：`REQUIREMENTS.md`（需求）、`ROADMAP.md`（分期计划）
> 范围：三种方案 ① 全局 ② 分流+断网不走本地 ③ 分流+断网走本地 + Web 管理端
> 最后更新：2026-09-03

---

## 1. 顶层拓扑

```
                ┌─────────────────────────────────────────┐
                │           Web 管理端                     │
                │  FastAPI + Vue3 + SQLite                │
                │  开户 → 选 profile ①②③ → 签证书 → .ovpn  │
                └───────────────┬─────────────────────────┘
                                │ 写 CCD / 调 easyrsa / 读 status.log
                                ▼
┌──────────┐        ┌────────────────────────────────────┐
│ 客户端    │ OpenVPN│         VPS（干净新机）             │
│ .ovpn    │◄──────►│  openvpn@wm :1194                  │
│ macOS    │  UDP   │  ├─ ccd/<user>   ← profile 决定分流 │
│ Windows  │        │  ├─ dnsmasq      ← 国内外域名分流   │
│ Linux    │        │  ├─ stubby(DoT)  ← 防污染核心       │
│ iKuai    │        │  └─ iptables: NAT + IPv6 DROP       │
└────┬─────┘        │                  + 封明文53出站      │
     │              └────────────────────────────────────┘
     ▼
 客户端侧断线策略（由 .ovpn 头的 FAILMODE 决定）
   ① close-all      → pf/netsh 全阻断
   ② close-foreign  → pf/netsh 放行 CN 表，阻断其余
   ③ open           → 无防火墙，fail-watch 守护回落本地
```

> 🔗 **游戏加速器（封海外媒体 / 白名单出海 / 扫码收款 / 自研 Windows 客户端）在独立项目 `openvpn-game`，与本项目零共享。**

---

## 2. Profile 引擎（主线核心设计）

**关键洞察**：三种方案的**服务端差异极小**。真正的差异只在两个维度：

| Profile | 服务端 CCD 内容 | 客户端 kill-switch |
|---|---|---|
| `trade-global` | **空**（不 push CN 路由）→ 全局 | `fail-close-all` |
| `trade-strict` | push 1300 条 CN 大网段（≈98.7%）+ 私有段 | `fail-close-foreign` |
| `game-open` | push 1300 条 CN 大网段（≈98.7%）+ 私有段 | **无**（fail-open） |

> 全量 CN 数据文件仍保留 4147 条；OpenVPN Connect 官方客户端有推送字节
> 上限（3.7.1=256KB / 3.8.2=768KB），全量精确推送无法装载，因此默认按
> `CN_ROUTE_LIMIT=1300` 取最大网段。详见 `docs/openvpn-connect-push-limit.md`。

所以**不要为每个 profile 复制一套服务端**。设计成：

```
profiles/
├── trade-global/
│   ├── profile.conf          # 声明式: SPLIT=none  FAILMODE=close-all
│   └── ccd.tpl               # 空模板
├── trade-strict/
│   ├── profile.conf          # SPLIT=cn-bypass  FAILMODE=close-foreign
│   └── ccd.tpl               # 引用 cn-ipv4.txt
└── game-open/
    ├── profile.conf          # SPLIT=cn-bypass  FAILMODE=open
    └── ccd.tpl               # 同 trade-strict
```

`gen-ccd.sh <user> <profile>` 读 `profile.conf` → 渲染 CCD。
`gen-client.sh <user> <profile>` → 生成 .ovpn，**并在 .ovpn 注释头写入 `# PROFILE=xxx` 和 `# FAILMODE=xxx`**，客户端安装器读这个决定装不装 kill-switch。

> 一个服务端实例同时服务 3 种 profile，靠 CCD 区分。**不需要 3 个端口 / 3 个实例。**

---

## 3. DNS 加固架构（防污染，跨所有 profile）

这是用户最在意的点（"chatgpt 封号"）。三层防御：

### 第 1 层：客户端不许用本地 DNS
```
# .ovpn 里
dhcp-option DNS 10.8.0.1          # 只用 VPN 内网 DNS
block-outside-dns                  # Windows 专用，强制
pull-filter ignore "dhcp-option DNS"  # 忽略服务端可能推的其他 DNS
```
- macOS：客户端 up 脚本 `networksetup -setdnsservers` 指到 10.8.0.1，down 时还原
- Linux：`systemd-resolved` 或 `resolvconf` 独占
- Windows：`block-outside-dns`（必须，OpenVPN 原生支持）

### 第 2 层：服务端 dnsmasq 分流
```
国内域名 (11 万条 china-list) → 223.5.5.5 / 119.29.29.29  (UDP 直连, 国内不污染)
其他所有域名               → 127.0.0.1#5353 (本机 DoT 转发器)
```

### 第 3 层：DoT/DoH 上游 + 出站封锁（关键加固）
```
dnsmasq → stubby / unbound (DoT) → 1.1.1.1:853 / 8.8.8.8:853 / 9.9.9.9:853
                                    ↑ TLS 加密，无法被中间人污染

iptables OUTPUT:
  -p udp --dport 53 ! -d 223.5.5.5,119.29.29.29 -j DROP   # 禁止明文 DNS 出境
  -p tcp --dport 853 -j ACCEPT                             # 只放 DoT
```
> 这样即使服务端所在机房 DNS 被劫持，也污染不到，因为**明文 53 出口被物理封死**。

### 额外：ECS 与 CDN 就近
- 国内域名走国内 DNS → CDN 返回国内节点 → 直连快
- 国外域名走 DoT → 返回海外节点 → 走 VPN 出口，源 IP 是 VPS，CDN 分配合理节点

---

## 4. Kill-switch 详细设计

### 4.1 `fail-close-all`（外贸A）

macOS pf anchor：
```
# 默认全阻
block drop out all
# 放行：本机回环 / VPN 服务器本身 / VPN 隧道
pass out on lo0 all
pass out proto udp to <VPN_SERVER_IP> port 1194
pass out on utun# all
# 放行局域网基础（否则连不上路由器）
pass out proto udp to 255.255.255.255 port 67   # DHCP
pass out to <LAN_GW>
```

Windows（自研客户端用 WFP；通用客户端用 netsh）：
```
netsh advfirewall set allprofiles firewallpolicy blockoutbound,allowinbound
netsh advfirewall firewall add rule name="VPN-tun" dir=out action=allow interfacetype=any remoteip=any program="openvpn.exe"
netsh advfirewall firewall add rule name="VPN-server" dir=out action=allow protocol=UDP remoteip=<VPN_IP> remoteport=1194
```

### 4.2 `fail-close-foreign`（外贸B）— 半 kill-switch

**逻辑**：默认阻断出站，白名单放行「国内 + VPN 隧道 + 局域网」。

macOS pf：
```
table <cn4> persist file "/etc/openvpn-split/cn-ipv4.txt"   # 4147 条
table <priv> persist { 10/8, 172.16/12, 192.168/16, 100.64/10, 169.254/16 }

block drop out all
pass out on lo0 all
pass out on utun# all                        # 隧道通就走隧道
pass out proto udp to <VPN_SERVER_IP> port 1194
pass out to <cn4>                            # 国内 IP 段永远放行 ← 核心
pass out to <priv>
```

**效果**：
- 隧道活着：国外走 utun，国内走 cn4 直连 → 正常分流
- 隧道死了：utun 消失 → 国外流量**无路可走且被 pf block** → 阻断 ✅
- 隧道死了：国内流量仍匹配 `<cn4>` → 正常访问 ✅

> 这就是用户要的「vpn 不通了不要走本地，但业务不能全瘫」。

### 4.3 `fail-open`（游戏A/B）
不装任何 pf/防火墙规则。客户端 `fail-watch` 守护：
```
每 5s 检测:  ping VPN 网关 (10.8.0.1)  或  检查 utun 存在
连续 3 次失败 → 恢复原默认路由 + 恢复原 DNS + 记日志 + 托盘提示
VPN 恢复 → 重新拉起 openvpn
```

### 4.4 逃生门（强制要求）
每个装了 kill-switch 的客户端必须附带：
```
unlock-network.sh   /  unlock-network.bat     # 一键 pf flush / netsh reset
```
并在托盘菜单放「紧急解除网络限制」按钮。

---

## 5. Web 管理端架构

```
web-panel/
├── backend/                  FastAPI
│   ├── main.py
│   ├── models.py             User / Profile / Node / Order / AuditLog
│   ├── auth.py               管理员登录 + TOTP 2FA
│   ├── routers/
│   │   ├── users.py          开户 / 列表 / 吊销 / 续期
│   │   ├── nodes.py          节点管理
│   │   ├── stats.py          在线状态 / 流量
│   │   └── audit.py
│   └── services/
│       ├── easyrsa.py        签发/吊销证书 (subprocess)
│       ├── ccd.py            渲染 CCD 文件
│       ├── ovpn.py           拼装 .ovpn
│       └── status_parser.py  解析 openvpn-status.log
├── frontend/                 Vue3 + Element Plus
└── db/                       SQLite (第一期) → Postgres (多节点后)
```

**关键设计**：
- 面板与 openvpn **同机部署**（第一期），直接读写 `/etc/openvpn/ccd/` 和跑 `easyrsa`
- 多节点阶段：面板独立机，通过 **SSH + 幂等脚本** 或 **轻量 agent** 下发
- 所有变更写 `audit_log` 表
- `.ovpn` **不落盘**，请求时实时生成 + 一次性下载令牌（防泄漏）

### 数据模型草案
```
users(id, username, profile, node_id, status, expire_at, quota_bytes, used_bytes, created_at)
nodes(id, name, region, public_ip, ssh_port, openvpn_port, status)
sessions(id, user_id, connected_at, disconnected_at, real_ip, rx, tx)
audit_log(id, admin, action, target, detail, ts)
```

---

## 6. 目录结构

见 `README.md` 的「目录结构」章节。

---

## 7. 与 openvpn-game 的隔离边界

| 项 | 说明 |
|---|---|
| 代码 | 零共享。不 import / 不 source 对方任何文件 |
| 服务器 | 各自独立 VPS |
| PKI | 各自独立 CA |
| 数据库 | 各自独立 |
| Web 面板 | 各自独立（本项目面板**不含支付功能**） |
| 唯一"共享" | 公开数据（国内 IP 段 / 域名列表）——**各存一份副本**，不做软链 |

> 理由：`openvpn-game` 涉及资金（扫码收款），一旦被入侵/串号损失不可逆，必须物理与逻辑双隔离。
