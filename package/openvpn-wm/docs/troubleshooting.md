# 故障排查

## 表

| 症状 | 原因 | 解决 |
|---|---|---|
| 国内网站打不开 | 路由表没生效 | 跑 `split-status.sh` 看 |
| 国外网站打不开 | VPN 没连上 | 看 `openvpn.log` |
| DNS 解析慢 | smartdns 没起来 | `pgrep smartdns` |
| DNS 仍然被污染 | 系统 DNS 没改 | `scutil --dns` |
| IPv6 仍能通（方案 A）| pf 锚点没挂上 | `pfctl -s anchor` |
| 国外速度慢 | 服务端远 | 换近的 VPS |
| OpenVPN 一直重连 | 服务端挂了 | `systemctl status openvpn@server` |

## 详细排查

### 1. 国内网站打不开

```bash
# 看路由表
netstat -nr | head -20
# 应看到 100+ 条国内路由指向 LOCAL_GW (e.g. 192.168.1.1)

# 看具体一个国内 IP
route get 114.114.114.114
# 应通过 en0 (本地)

# 测试直连
curl -4 --interface en0 https://baidu.com
```

### 2. 国外网站打不开

```bash
# 看 openvpn 进程
ps aux | grep openvpn

# 看日志
tail -50 /var/log/openvpn-status.log   # openvpn 状态
tail -50 /var/log/openvpn-split/openvpn.log

# 测 VPN 出口
curl -4 https://api.ipify.org
# 应 = 美国 IP (YOUR_OLD_SERVER_IP 附近)

# 看默认路由
route get 8.8.8.8
# 应通过 utun0
```

### 3. DNS 仍然被污染

```bash
# 1. smartdns 在吗？
pgrep smartdns
# 2. 监听 53 端口？
sudo lsof -i :53
# 3. 系统 DNS 改了？
scutil --dns | grep nameserver
# 4. 手动测
dig @127.0.0.1 chatgpt.com
# 应 = Cloudflare 真实 IP (104.18.x.x)
```

### 4. VPN 断了没自动恢复

```bash
# 1. fail-watch 在跑？
cat /var/run/openvpn-split/fail-watch.pid
kill -0 $(cat /var/run/openvpn-split/fail-watch.pid)  # 应返回 0
# 2. 手动跑 debug
sudo VPN_GATEWAY=<vpn_ip> ~/.openvpn-split/shared/common/fail-watch.sh foreground
```

### 5. macOS pf 报错

```bash
# 看 pf 状态
sudo pfctl -s info
sudo pfctl -s rules | head -30

# 重置 pf（慎用，会清掉所有规则）
sudo pfctl -F all
sudo pfctl -f /etc/pf.conf

# 重新挂锚点
sudo ~/.openvpn-split/macos/pf/enable-anchor.sh
```

### 6. OpenVPN 连不上

```bash
# 详细日志
sudo openvpn --config /etc/openvpn/client.conf --verb 5

# 常见错误:
# - "TLS Error" → 服务端证书/CA 不对
# - "Connection refused" → 服务端没开端口
# - "Auth failed" → 客户端证书密码错
# - "Permission denied" → 权限不够
```

### 7. 性能问题

```bash
# 看 tun 设备的丢包/错误
netstat -I utun0

# 看 openvpn 状态
cat /var/log/openvpn-split/openvpn-status.log

# 切换到更近的 VPS
# 或启用压缩: compress lz4-v2
```

## 收集信息

发 issue 时附上：

```bash
# 1. 系统信息
sw_vers
which openvpn && openvpn --version

# 2. split 状态
sudo ~/.openvpn-split/macos/bin/split-status.sh

# 3. 路由表
netstat -nr > /tmp/routes.txt
route get 8.8.8.8 >> /tmp/routes.txt
route get 114.114.114.114 >> /tmp/routes.txt

# 4. 进程
ps aux | grep -E "openvpn|smartdns" > /tmp/ps.txt

# 5. 日志
tail -100 /var/log/openvpn-split/openvpn.log > /tmp/openvpn.txt
tail -100 ~/.openvpn-split/logs/smartdns.log > /tmp/smartdns.txt

# 6. DNS
scutil --dns > /tmp/dns.txt
```
