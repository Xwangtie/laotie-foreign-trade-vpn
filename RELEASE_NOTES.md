# 老铁外贸网络管理系统 v1.0

首个 GitHub 公共下载版本，包含：

- OpenVPN 三方案服务端
- DNS 防污染配置
- 防火墙与断线策略
- Web 管理面板
- Ubuntu 22.04 / 24.04 一键安装脚本
- macOS、Windows、Linux 客户端辅助脚本

## 公开版安全调整

- 安装时必须显式提供自己的 `DOMAIN`
- 不再默认使用生产域名 `vpn.xeonas.cn`
- 不再默认使用 `admin/admin`
- 未提供 `PANEL_ADMIN_PASSWORD` 时自动生成随机管理员密码

## 已知限制

- 需要用户自备 Ubuntu 服务器和域名
- 不包含任何生产证书、私钥、客户配置或数据库
- 安装前应阅读包内 `deploy/README-package.md`

请使用 Release 中的 `SHA256SUMS.txt` 校验下载文件。
