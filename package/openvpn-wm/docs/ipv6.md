# IPv6 策略：方案 A vs 方案 B

## 背景

你之前用 `block-ipv6` 是因为：VPN 全局模式下，IPv6 流量走本地 ISP 出口，被污染。
即使开了全局 VPN，IPv6 也是绕过的（因为服务端没分配 IPv6）。

## 方案 A：block-ipv6（适合现状）

**前提**：你的 OpenVPN 服务端没配 `tun-ipv6`，所以 IPv6 流量本来就走本地 ISP。
**结论**：必须 block，否则国内 IPv6 网站会被污染 + 暴露真实 IP。

**实现**：
1. OpenVPN 客户端配置 `block-ipv6`
2. pf 锚点 `block drop quick inet6 all`（双重保险）
3. smartdns 强制 IPv4 优先

**代价**：
- 不能用 IPv6 网站（baidu.com 的 IPv6、IPv6 NAS 访问等）
- 一些应用优先解析 AAAA，记录被丢，会回退 A
- chatgpt 等仍正常（用 IPv4）

## 方案 B：IPv6 完整分流（推荐升级）

**前提**：VPN 服务端开 `tun-ipv6` + `push "route-ipv6 2000::/3"`。
**结论**：国内 IPv6 走本地，国外 IPv6 走 VPN，DNS 全 DoH 防污染。

**实现**：
1. OpenVPN 服务端配 IPv6（`方案B_服务端独立实例/server/server.conf`）
2. 客户端去掉 `block-ipv6`
3. pf 锚点路由 IPv6（不 block）
4. 客户端加载 cn6 表（国内 IPv6 段）
5. smartdns 启用 IPv6

**优势**：
- 国内 IPv6 网站照常访问（baidu IPv6 / 京东 IPv6 等）
- 国外 IPv6 服务可访问（Cloudflare / Google IPv6）
- 国内外 IPv6 都不受污染

**代价**：
- 服务端要改（要 `tun-ipv6` + IPv6 子网）
- 客户端配置稍复杂
- 部分系统不支持 IPv6 隧道

## 怎么升级

1. **服务端**：
   ```bash
   # 在 VPS 上
   bash 方案B_服务端独立实例/server/scripts/install-server.sh
   # 它会建独立 PKI + tun-ipv6 + push route-ipv6
   ```

2. **生成新客户端**：
   ```bash
   bash 方案B_服务端独立实例/server/scripts/gen-client.sh apei06-split
   ```

3. **本机切换**：
   ```bash
   sudo openvpn --config /etc/openvpn/client.conf   # 用新的 .ovpn
   ```

4. **验证**：
   ```bash
   ping6 2400:3200::1      # baidu IPv6, 应通
   ping6 2606:4700:4700::1111  # Cloudflare, 应通
   curl -6 https://ip.sb    # 应 = VPN 出口
   ```

## 关键技术点

### OpenVPN 服务端 IPv6
```ini
# server.conf
tun-ipv6
server-ipv6 2001:db8:9::/64
push "route-ipv6 2000::/3"
push "redirect-gateway ipv6"
```

### 客户端 IPv6 路由
```bash
# 国内 IPv6 走本地
route add -inet6 2001:da8::/32 <local_gw>
# 国外 IPv6 默认走 VPN
# (openvpn push 的 redirect-gateway ipv6 会自动设)
```

### pf IPv6 路由（方案 B）
```
# 不 block IPv6
# 但 block IPv4-mapped IPv6 (::ffff:0.0.0.0/96)
block drop quick inet6 to ::ffff:0.0.0.0/96
pass out all keep state
```

## 常见问题

### Q: 我服务端不让我加 tun-ipv6 怎么办？

**A**: 继续用方案 A。`block-ipv6` 是当前最稳的方案。

### Q: 方案 B 装上后，国内 IPv6 网站还是被污染？

**A**: 检查：
1. `route get -inet6 2400:3200::1` 应通过 en0（本地）
2. 没走 en0 的话：cn6 表没加载、或者 split-up 没跑
3. 跑 `split-status.sh` 看

### Q: 能同时跑方案 A 和方案 B 吗？

**A**: 可以！两个用不同端口、不同 tun 设备，互不影响。
但需要不同 openvpn 实例。
