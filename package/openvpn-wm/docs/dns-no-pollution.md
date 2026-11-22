# DNS 防污染原理

## 污染是什么

你的 DNS 查询（比如 `chatgpt.com`）被中途劫持，返回假的 IP（比如 Facebook 的 IP）。
原因是：国内 ISP 的 DNS 服务器（114.114.114.114 / 运营商 DNS）会按上级指令返回错误结果。

## 解决方案

### 1. 国内域名 → 国内 DNS（无污染）

对 `baidu.com` / `qq.com` 等国内域名，用 `223.5.5.5` (阿里) / `119.29.29.29` (DNSPod) 解析。
这些 DNS 在国内，返回的是真实 IP（因为他们不针对国内域名做劫持）。

**关键数据源**：[felixonmars/dnsmasq-china-list](https://github.com/felixonmars/dnsmasq-china-list)
- 6000+ 加速域名（被 CDN 加速的国内大站）
- 包括 Apple / Microsoft / Adobe 等在中国有节点的

### 2. 国外域名 → DoH 加密

对 `chatgpt.com` / `github.com` / `google.com` 等国外域名，用 **DNS-over-HTTPS (DoH)** 解析。
- `https://1.1.1.1/dns-query` (Cloudflare)
- `https://8.8.8.8/dns-query` (Google)
- `https://9.9.9.9/dns-query` (Quad9)

DoH 把 DNS 查询包在 HTTPS (443) 里，**中间人看不到你在解析什么**，也无法返回假 IP。

**关键**：DoH 查询**经过 OpenVPN 隧道**走，所以出口 IP 是美国，不在国内被污染。

## smartdns 的工作流

```
客户端查询: chatgpt.com
        │
        ▼
   smartdns (127.0.0.1:53)
        │
        ├── chatgpt.com 在国内域名列表? 否
        │
        ├── 并行查询:
        │   ├─ DoH 1.1.1.1
        │   ├─ DoH 8.8.8.8
        │   └─ DoH 9.9.9.9
        │
        ├── 选最快: 1.1.1.1 返回 104.18.32.47
        │   (测速: 哪个响应快选哪个)
        │
        └── 返回 104.18.32.47 给客户端
                (这个 IP 是 Cloudflare 真实 IP，没被污染)
```

## 为什么 chatgpt 不会封号

1. **DNS 不被污染** → chatgpt.com 解析到 Cloudflare 真实 IP
2. **出口 IP 是美国 VPS** → Cloudflare 看到美国 IP，不是国内 IP
3. **TLS 加密** → 整条连接看不到明文
4. **结果**：Cloudflare 把你当普通美国用户，不会触发风控

## 验证

```bash
# 1. 看系统 DNS
scutil --dns | grep nameserver
# 应 = 127.0.0.1

# 2. 看 smartdns 在跑
pgrep smartdns

# 3. 测解析
dig @127.0.0.1 baidu.com        # 应 = 阿里 IP 段
dig @127.0.0.1 chatgpt.com      # 应 = Cloudflare IP (104.18.x.x)

# 4. 测 DoH
curl https://1.1.1.1/help
# 应显示 "Using DNS over HTTPS (DoH): Yes"

# 5. 测 DNS 泄漏
# 访问 https://www.dnsleaktest.com → Extended Test
# 应只看到 Cloudflare / Google / Quad9
```
