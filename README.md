# 老铁外贸 VPN / 老铁外贸网络管理系统

面向外贸网络场景的 OpenVPN 服务端与 Web 管理面板，支持国内直连、国外流量分流、DNS 防污染、客户端开户与到期管理。

## 功能

- OpenVPN 全局代理、外贸严格分流、游戏可用分流三种模式
- dnsmasq 国内域名分流与 stubby DNS-over-TLS
- IPv4/IPv6 防火墙策略与 VPN 断线处理
- Web 管理面板、账号开户、证书生成、吊销、流量与到期管理
- Ubuntu 22.04 / 24.04 一键部署脚本
- macOS、Windows、Linux 客户端辅助脚本

## 下载与安装

请打开本仓库右侧的 **Releases** 页面，下载：

`laotie-foreign-trade-vpn-server-v1.0.zip`

服务器要求：

- 全新 Ubuntu 22.04 或 24.04
- root 或 sudo 权限
- 一个已解析到服务器公网 IP 的域名
- 开放 SSH、TCP 80、TCP 443 和 OpenVPN UDP 1194；如修改端口，请同步调整云防火墙

上传并解压后，在服务器上运行：

```bash
cd openvpn-wm
DOMAIN=vpn.example.com PUBLIC_IP=你的公网IP SSH_PORT=22 \
  sudo -E bash install-new-server.sh
```

`DOMAIN` 必须替换为你自己的域名。安装完成后，初始管理员密码会随机生成并保存在服务器：

```text
/root/openvpn-wm-admin.txt
```

首次登录后请立即修改管理员密码，并建议启用 TOTP。

## 三种模式

| 模式 | profile | 行为 |
| --- | --- | --- |
| 外贸全局 | `trade-global` | 所有流量走 VPN |
| 外贸严格分流 | `trade-strict` | 国内直连、国外走 VPN，断线阻断国外流量 |
| 游戏分流 | `game-open` | 国内直连、国外走 VPN，断线回落本地网络 |

## 安全说明

- 本仓库和 Release 不包含生产服务器私钥、VPN 客户端证书或数据库。
- 每台新服务器安装时会自行生成 PKI。
- 默认会自动申请 Let's Encrypt 证书；失败时回退到自签证书。
- 请自行确认当地法律、运营商政策、云服务商条款及目标网站服务条款。本软件仅用于合法、授权的网络访问与运维场景。

## 许可与支持

本仓库用于发布软件和安装说明。当前未授予第三方再发布、改名销售或衍生发行许可；如需商业授权或定制部署，请联系：

- 官网：<https://xeonet.cn>
- 电话：13905394878
- 邮箱：<ymwww@qq.com>
