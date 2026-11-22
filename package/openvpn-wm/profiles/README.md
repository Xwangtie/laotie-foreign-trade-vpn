# Profile 定义（S1 服务端 与 S2 客户端 的共享契约）

本项目三种方案：

| 目录 | 方案 | SPLIT | FAILMODE |
|---|---|---|---|
| `trade-global/` | ① 全局代理 | `none` | `close-all` |
| `trade-strict/` | ② 分流 + 断网不走本地 | `cn-bypass` | `close-foreign` |
| `game-open/` | ③ 分流 + 断网走本地 | `cn-bypass` | `open` |

> ② 与 ③ 的服务端配置**完全相同**，差异只在客户端装不装 kill-switch。


每个 profile 一个目录，含 `profile.conf`（声明式，被 shell `source`）。

## 字段规范

| 字段 | 取值 | 谁用 | 说明 |
|---|---|---|---|
| `PROFILE_ID` | 字符串 | 双方 | 唯一标识，等于目录名 |
| `PROFILE_NAME` | 中文名 | 面板 | 展示用 |
| `SPLIT` | `none` \| `cn-bypass` | S1 | `none`=全局；`cn-bypass`=国内走本地 |
| `FAILMODE` | `close-all` \| `close-foreign` \| `open` | S2 | 断线策略，决定客户端装哪套 kill-switch |
| `IPV6` | `block` | 双方 | 目前全部 block |
| `DNS_MODE` | `vpn-only` \| `local` | S1 | `vpn-only`=CCD 推送 VPN DNS（推荐：服务端 dnsmasq 做国内域名 ECS 分流 + 国外 DoH）；`local`=不推送 DNS，客户端保持本地 DNS（备用） |
| `LAN_ACCESS` | `0` \| `1` | S1 | 是否放行客户端本地局域网 |
| `EGRESS_ACL` | `all` | S1 | 出海策略。本项目固定 `all`（不做白名单出海） |

## 契约规则（重要）

1. `gen-client.sh` 生成的 `.ovpn` **必须**在文件头写入：
   ```
   # PROFILE=<PROFILE_ID>
   # FAILMODE=<FAILMODE>
   # SPLIT=<SPLIT>
   # SERVER=<公网IP>
   # PORT=<端口>
   ```
2. 客户端安装器 `install-client.sh` **必须** grep 这些注释来决定行为。
   → 这样 S1 和 S2 可以完全并行开发，只要遵守这 5 行注释。
3. 新增 profile = 新建一个目录，**不改任何代码**。

---

## 与 openvpn-game 的区别

`openvpn-game` 项目有自己的策略配置（`server/acl/policy.conf`），含 `EGRESS_ACL=game-whitelist`（仅游戏白名单出海）。

**不要**把它加到本项目，也不要让本项目代码依赖它。两个项目零共享。
