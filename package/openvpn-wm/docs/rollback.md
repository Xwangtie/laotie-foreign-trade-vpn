# 服务器与客户端运维回滚手册

> 适用时间：2026-09-04（分流路由精简、OpenVPN Connect 3.8.2、面板管理员校验）
> 原则：任何改动先留备份；回滚只做“恢复上一个可用状态”，不做数据删除。

## 1. 涉及位置速查

| 对象 | 路径 |
|---|---|
| OpenVPN 路由生成脚本 | `/etc/openvpn/scripts/gen-ccd.sh` |
| 方案配置 | `/etc/openvpn/profiles/{trade-global,trade-strict,game-open}/profile.conf` |
| 客户端 CCD | `/etc/openvpn/ccd/<username>` |
| 国内 IP 数据 | `/etc/openvpn/data/cn-ipv4.txt`（保持全量 4147 条，不删） |
| 面板前端 | `/opt/openvpn-wm/web-panel/frontend/`（源码 `src/`、产物 `dist/`） |
| 面板数据库 | `/var/lib/openvpn-wm/panel.db` |
| OpenVPN 状态日志 | `/var/log/openvpn/status.log` |
| macOS 客户端 | `/Applications/OpenVPN Connect/`（当前 3.8.2 build 6009） |

## 2. 2026-09-04 变更清单

### 2.1 分流路由精简（服务器，已生效）

- `gen-ccd.sh` 改为“按网段大小取前 `CN_ROUTE_LIMIT` 条 + 私有段”，默认 1300；
- 输出保持 OpenVPN Connect 可用的 `route IP 掩码 net_gateway`；
- 配置文件保留全量 CN 数据，只影响“推送给客户端的精简直连表”。
- 仓库提交：`26302dc`

回滚到“全量精确推送”：

```bash
# 服务器上恢复旧脚本（全量格式）
cd /root/openvpn-wm-deploy 2>/dev/null || cd /opt/openvpn-wm
# 若仓库保留旧版，可先拉回 26302dc 之前的 gen-ccd.sh
cp /root/splittest1-ccd-decimal.bak /etc/openvpn/ccd/splittest1
# 重新生成其它用户则使用旧版脚本重跑：
/etc/openvpn/scripts/gen-ccd.sh <username> <profile>
```

备份：
- `/root/wangtie-ccd.backup`（旧全量 4156 条 CCD）
- `/root/splittest1-ccd-decimal.bak`（旧全量 decimal CCD）

### 2.2 macOS OpenVPN Connect 升级（本机，已生效）

- 旧 3.7.1 (5558) 已卸载，官方 3.8.2 (6009) 已安装；
- 若需退回旧版：从 OpenVPN 官网 release notes（2025-04-25）重新下载
  `openvpn-connect-3.7.1.5558_signed.dmg` 安装即可；
- 旧版配置数据已随卸载清除，重装后重新导入 `.ovpn`。

### 2.3 面板管理员创建校验（本地已提交，服务器待部署）

- 前端新增用户名/密码校验提示，错误明细可读；
- 仓库提交：`de6dc43`
- 服务器部署前必须先备份当前 dist：

```bash
mkdir -p /root/openvpn-wm-backups/20260904
tar -C /opt/openvpn-wm/web-panel/frontend \
  -czf /root/openvpn-wm-backups/20260904/frontend-dist-before-adminfix.tar.gz dist
```

部署：

```bash
tar -C /opt/openvpn-wm/web-panel/frontend/dist -xzf /tmp/openvpn-wm-frontend-dist.tar.gz
tar -C /opt/openvpn-wm/web-panel/frontend/src  -xzf /tmp/openvpn-wm-frontend-src.tar.gz
chown -R openvpnwm:openvpnwm /opt/openvpn-wm/web-panel/frontend
```

回滚前端：

```bash
rm -rf /opt/openvpn-wm/web-panel/frontend/dist
tar -C /opt/openvpn-wm/web-panel/frontend \
  -xzf /root/openvpn-wm-backups/20260904/frontend-dist-before-adminfix.tar.gz
chown -R openvpnwm:openvpnwm /opt/openvpn-wm/web-panel/frontend
```

### 2.4 面板状态日志权限（待部署）

修复：

```bash
chgrp openvpnwm /var/log/openvpn/status.log
chmod 640 /var/log/openvpn/status.log
```

回滚：

```bash
chgrp root /var/log/openvpn/status.log
chmod 600 /var/log/openvpn/status.log
```

### 2.5 端口映射功能（新增，代码已就绪，待部署）

- 数据库新表 `port_mappings`（Alembic revision `b91f7c2a2f10`）；
- 新增 `server/scripts/portmap.sh` 与 sudoers 白名单；
- 前端新增左侧导航“端口映射”页；
- 端口映射与客户到期状态**不联动**，只由管理员手动删除。

回滚：

```bash
# 删除数据库表（会同时失去映射记录）
cd /opt/openvpn-wm/web-panel/backend
.venv/bin/python -m alembic downgrade a44803841a39
# 移除 sudoers 白名单行：
sed -i '/portmap.sh/d' /etc/sudoers.d/openvpnwm-panel
# 恢复前端 dist：使用 §2.3 备份包
```

> 回滚前若有已生效映射，先用 `portmap.sh list` 记录规则，
> 再执行 `iptables -t nat -F OVPN-WM-DNAT`、`iptables -F OVPN-WM-PORTFWD`
> 清理并 `iptables-save > /etc/iptables/rules.v4`。

## 3. 数据库与 PKI 备份（重要）

每次重大变更前建议：

```bash
B=/root/openvpn-wm-backups/$(date +%Y%m%d)
mkdir -p "$B"
sqlite3 /var/lib/openvpn-wm/panel.db ".backup '$B/panel.db'"
tar -C /etc/openvpn/easy-rsa -czf "$B/pki.tar.gz" pki
tar -C /etc/openvpn -czf "$B/openvpn-etc.tar.gz" \
  --exclude=easy-rsa/pki/private --exclude=easy-rsa/pki/issued . 2>/dev/null || true
```

> PKI 一旦丢失必须重签所有客户端，务必保留 `pki/private`。

## 4. 快速回滚决策表

| 现象 | 回滚动作 |
|---|---|
| 客户端仍提示 “server-pushed options data too large” | 确认 CCD 条数 ≤1300；把 `CN_ROUTE_LIMIT` 调小后重跑 `gen-ccd.sh` |
| 国内网站全走 VPN（直连失效） | 确认客户端是 3.8.2；确认 CCD 不是 CIDR 简写（Connect 会静默丢弃 CIDR）；重跑 decimal 版 `gen-ccd.sh` |
| 面板无法创建管理员 | 用 3-32 位英文用户名 + ≥10 位密码；或回滚前端 dist |
| 面板在线状态一直失败 | 执行 §2.4 权限修复 |
| 想完全恢复 2026-09-04 之前 | 按 §2.1~2.4 逐一还原，再恢复 §3 数据库/PKI 备份 |
