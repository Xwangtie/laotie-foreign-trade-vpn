# OpenVPN 钩子机制

## 什么是钩子

OpenVPN 在不同阶段会调用外部脚本，让你插入自己的逻辑。

## 主要钩子

| 钩子 | 触发时机 | 用途 |
|---|---|---|
| `route-up` | 隧道建立 + 路由生效后 | **我们的核心钩子** |
| `route-pre-down` | 路由删除前 | 清理路由前的最后机会 |
| `route-down` | 路由删除后 / VPN 断开 | **我们的核心钩子** |
| `up` | TUN/TAP 设备就绪（但路由未生效）| 一般用不到 |
| `down` | TUN/TAP 设备 down 后 | 一般用不到 |
| `client-connect` | 客户端连接时（服务端）| 服务端推送 |
| `client-disconnect` | 客户端断开时（服务端）| 服务端清理 |
| `learn-address` | 客户端地址学习（服务端）| 服务端 |

## 钩子被调用的环境变量

OpenVPN 会注入一堆环境变量给钩子：

| 变量 | 含义 | 示例 |
|---|---|---|
| `dev` | TUN 设备名 | `utun0` |
| `ifconfig_local` | 本地 VPN IP | `10.9.0.2` |
| `ifconfig_remote` | 远端 VPN IP | `10.9.0.1` |
| `ifconfig_ipv6_local` | 本地 VPN IPv6 | `2001:db8:9::2` |
| `ifconfig_ipv6_remote` | 远端 VPN IPv6 | `2001:db8:9::1` |
| `route_vpn_gateway` | VPN 网关（route-up 特有）| `10.9.0.1` |
| `route_ipv6_gateway_1` | VPN IPv6 网关 | `2001:db8:9::1` |
| `trusted_ip` | 真实远端 IP | `YOUR_OLD_SERVER_IP` |
| `trusted_port` | 真实远端端口 | `1195` |
| `proto` | 协议 | `udp` |
| `script_type` | 脚本类型 | `route-up` |
| `tap` | 是否 tap 设备 | `0` |

## 关键配置

要让钩子工作，.ovpn 必须有：

```ini
script-security 2          # 允许外部脚本执行
route-up    "/path/to/up.sh"
route-down  "/path/to/down.sh"
```

`script-security 2` 是必须的，否则 OpenVPN 默认拒绝执行脚本（安全考虑）。

## 我们的实现

`split-up.sh` 流程（route-up 触发）：

```
1. 读取环境变量 (dev, route_vpn_gateway, ifconfig_local, ...)
2. 检测本机默认网关 (net_gateway)
3. 写状态文件
4. 把 VPN 网关设为默认路由
5. 灌入"国内+私有"路由表（指回原网关）
6. 加载 pf 锚点（block IPv6 / 路由 IPv6）
7. 启动 smartdns + 改系统 DNS
8. 启动 fail-watch 守护
```

`split-down.sh` 流程（route-down 触发）：

```
1. 停止 fail-watch 守护
2. 卸载 pf 锚点
3. 删除"国内+私有"路由表
4. 还原默认路由到本地网关
5. 还原系统 DNS
6. 停止 smartdns
7. 清理状态文件
```

## 调试技巧

```bash
# 1. 前台跑 openvpn，看 hook 输出
sudo openvpn --config /etc/openvpn/client.conf --verb 5

# 2. 手动跑钩子测试
sudo VPN_GATEWAY=10.9.0.1 ~/.openvpn-split/macos/bin/split-up.sh

# 3. 看 split 日志
tail -f /var/run/openvpn-split/split.log

# 4. 加 DEBUG
DEBUG=1 sudo openvpn --config /etc/openvpn/client.conf
```

## 常见问题

### Q: 钩子没执行？

1. `script-security 2` 有没有？
2. 路径用绝对路径？OpenVPN 不解析相对路径
3. 脚本有 `+x` 权限？
4. 用户名 / sudo 权限对吗？

### Q: 钩子报 "Permission denied"？

OpenVPN 默认以 root 跑，钩子应该能跑。
但如果用 `user nobody` 降权（服务端），钩子可能跑不了。
解决：把钩子放到 nobody 可读的地方。

### Q: 钩子跑了一半就退出？

加 `set -x` 看哪里出错：
```bash
#!/bin/bash
set -x  # 打印每条命令
...
```

### Q: 怎么避免钩子和 openvpn 自身抢路由？

关键：`route-noexec` —— 让 openvpn 不要自己加路由，由钩子完全接管。

```ini
route-noexec    # 关键
route-up    "/path/to/up.sh"
route-down  "/path/to/down.sh"
```
