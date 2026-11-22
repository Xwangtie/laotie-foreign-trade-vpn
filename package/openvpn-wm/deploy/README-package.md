# 老铁外贸网络管理系统 · 服务器一键交付包

> 版本：2026-09-04（v1.0）｜适用：全新 Ubuntu 22.04 / 24.04 服务器
> 交付内容：OpenVPN 服务端（三方案）+ DNS 防污染 + 防火墙 + Web 管理面板 + Nginx

## 一、包内结构

```
openvpn-wm/
├── README.md                    # 本说明
├── install-new-server.sh        # ★ 一键安装脚本（在服务器 root 下运行）
├── profiles/                    # 三方案 profile 定义
├── server/                      # OpenVPN/dnsmasq/stubby/防火墙/服务端脚本
├── shared/data/                 # 国内 IP 段、私有网段、国内域名表
└── web-panel/                   # Web 面板（后端源码 + 已构建前端）
```

## 二、新服务器安装前准备

1. 全新 **Ubuntu 22.04 / 24.04** 服务器（有 root 或 sudo）。
2. 准备一个域名并做好 **A 记录指向新服务器公网 IP**（例如 `vpn2.example.com`）。
   `DOMAIN` 为必填项，公开版不会默认使用作者服务器域名。
3. 开放端口：SSH（自定）、UDP 1194、TCP 80、TCP 443。安装脚本会自动写防火墙，
   请勿在云控制台额外关闭 1194。

## 三、把包传到服务器

在 Mac / 本地电脑执行（把 `VPS_IP` 换成新服务器地址）：

```bash
rsync -avz --delete -e "ssh -p SSH_PORT" \
  ~/Desktop/openvpn-wm/ root@VPS_IP:/root/openvpn-wm-package/
```

## 四、一键安装

SSH 登录新服务器后：

```bash
cd /root/openvpn-wm-package
DOMAIN=vpn2.example.com PUBLIC_IP=1.2.3.4 SSH_PORT=22 \
  sudo -E bash install-new-server.sh
```

可选变量：

| 变量 | 默认 | 说明 |
|---|---|---|
| `DOMAIN` | **必填** | 面板与 `.ovpn` 使用的域名，必须替换成你自己的域名 |
| `PUBLIC_IP` | 自动探测 | 服务器公网 IP |
| `SSH_PORT` | 自动探测 | SSH 端口，防火墙只放行该端口 |
| `VPN_PORT` | `1194` | OpenVPN UDP 端口 |
| `ADMIN_USER` | `admin` | 首个超级管理员用户名 |
| `PANEL_ADMIN_PASSWORD` | 自动生成随机值 | 首个超级管理员密码；如不设置会自动生成 |
| `AUTO_HTTPS` | `1` | 自动签发 Let's Encrypt；失败自动回退自签 |

## 五、安装完成后

- 管理面板：`https://<DOMAIN>`
- 初始超级管理员用户名默认为 `admin`，密码会在安装时随机生成并保存于服务器 `/root/openvpn-wm-admin.txt`
- **首次登录后请立即在“管理员”页修改密码**。
- 当前阶段设置：TOTP 扫码不强制（可用后再开）、邮件提醒关闭、客户资料允许不全。
- 面板里“开户”生成的下载链接就是客户端 `.ovpn`，发给客户导入 OpenVPN Connect 即可。

## 六、三种方案说明

| 方案 | profile | 行为 |
|---|---|---|
| ① 外贸全局 | `trade-global` | 所有流量走 VPN，DNS 走服务端 DoT，安全优先 |
| ② 外贸分流 | `trade-strict` | 国内走本地、国外走 VPN；断线后国外须阻断（依赖 kill-switch） |
| ③ 游戏分流 | `game-open` | 国内走本地、国外走 VPN；断线全部回落本地 |

开户时在面板选择对应类型即可；服务器端已内置国内域名 ECS DNS 分流，
保证“百度等国内站返回国内节点、Google/Facebook 返回真实国外节点”。

## 七、运维与回滚

- 备份：安装/更新前自动备份数据库与前端到 `/root/openvpn-wm-backups/`。
- 日志：每日 04:10 自动清理 30 天前日志（`/etc/openvpn/scripts/log-clean.sh`）。
- 数据：每月 1 日自动更新国内 IP/域名表并重建 CCD（`update-data.sh`）。
- 更新：解压新版本后，按相同流程重新执行安装脚本；生产环境应先备份数据库和 PKI。

## 八、安全提醒

- 本包不含任何私钥/证书，每台新服务器安装时会全新生成 PKI。
- 证书有效期默认 100 年，账号有效期由面板数据库控制。
- 面板已按角色隔离：超级管理员全权限；普通管理员只管理客户账号。
- 客户删除必须先“吊销”，删除时自动清理端口映射。
- 生产建议后续开启面板 TOTP，并把 Nginx 配成仅放行管理员出口 IP。
