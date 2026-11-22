# S2 客户端断线策略（老铁外贸网络管理系统）

本目录是客户端安装层：读取 S1 生成的 `.ovpn` 文件头，按方案自动安装
对应断线策略、逃生门与看门狗。

| FAILMODE | 方案 | 断线行为 | 客户端动作 |
|---|---|---|---|
| `close-all` | ① 全局 | VPN 断 → 全部断网 | 防火墙默认 block out，只放隧道/VPN服务器/局域网 |
| `close-foreign` | ② 分流严格 | VPN 断 → 国内通、国外断 | 防火墙默认 block out，白名单放行国内 IP |
| `open` | ③ 分流宽松 | VPN 断 → 全部回落本地 | 不装防火墙，装 fail-watch 守护 + 通知 |

> 逃生门是 P0：任何模式下 `unlock-network` 必须能在断网时一键恢复，
> 且脚本不依赖网络、不依赖额外下载。

## 快速开始（macOS / Linux）

```bash
sudo ./install-client.sh /path/to/xxx.ovpn
```

连接 / 断开 / 紧急解除：

```bash
sudo openvpnwm-connect       # 前台连接（Ctrl-C 断开）
sudo openvpnwm-disconnect    # 断开
openvpnwm-unlock             # 紧急解除防火墙/恢复 DNS
```

## Windows

```powershell
# PowerShell（管理员）
.\install-client.ps1 -OvpnPath C:\path\to\xxx.ovpn
```

连接使用 OpenVPN GUI/官方客户端（配置文件已放入其 config 目录并带
`block-outside-dns`），紧急解除双击 `unlock-network.bat`。

## 数据文件

- 国内 IPv4 段：`/etc/openvpn-wm/cn-ipv4.txt`（来自 `shared/data/cn-ipv4.txt`）
- 安装元数据：`/etc/openvpn-wm/profile.env`
- OpenVPN 配置：`/etc/openvpn-wm/client.ovpn`

安装器要求 `.ovpn` 文件头包含 S1 契约的 5 行注释，缺失时拒绝安装。

## 未实机验证清单

- Windows 全部（无 Windows 测试机）
- Linux nft/ipset 实机规则验证
- macOS 真实 VPN 断线、pf 规则验证

上述项在真机验收通过前不得向最终客户发放 ① ② 配置。
