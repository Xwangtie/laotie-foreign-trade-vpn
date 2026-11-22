# smartdns.conf - 国内/国外 DNS 分流（防污染）
#
# 安装: brew install smartdns   或  https://github.com/pymumu/smartdns/releases
# 运行: smartdns -c smartdns.conf -p
# 验证: dig @127.0.0.1 -p 53 baidu.com     (应返回国内 IP)
#        dig @127.0.0.1 -p 53 google.com    (应返回国外 IP)
#        dig @127.0.0.1 -p 53 chatgpt.com   (应返回 Cloudflare/海外 IP)
#
# ⚠️  本文件是模板，部署时把 {{CN_LIST_FILE}} 替换成实际路径，
#     或者用 smartdns 的 conf-file 指令 include 域名列表。

# ===== 基础 =====
bind 127.0.0.1:53
bind :53@lo0
cache-size 4096
cache-persist yes
cache-file /var/run/openvpn-split/smartdns-cache
prefetch-domain yes
prefetch-time 300
serve-expired yes
serve-expired-prefetch-time 1800
log-level info
log-file /var/log/openvpn-split/smartdns.log
log-size 128K
log-num 2

# ===== 国内 DNS 上游（无污染，UDP 协议走国内）=====
# 阿里 DNS
server 223.5.5.5
server 119.29.29.29
# 腾讯 DNS
server 119.29.29.29
# 114 DNS
server 114.114.114.114
# 备用（运营商 DNS，从 system 自动获取也可）
# server 202.96.209.5

# ===== 国外 DNS 上游（走 DoH，防污染 + 防泄漏）=====
# Cloudflare DoH
server-https https://1.1.1.1/dns-query
# Google DoH
server-https https://8.8.8.8/dns-query
# Quad9 DoH
server-https https://9.9.9.9/dns-query

# ===== 国内域名分流 =====
# 把 felixonmars/dnsmasq-china-list 的域名列表转换成 smartdns 格式
# 转换命令: awk '{print "nameserver /$1/ 223.5.5.5"}' accelerated-domains.china.conf > cn-names.txt
# 然后下面 include
# conf-file {{CN_LIST_FILE}}

# 也可直接 inline（运行时由 install 脚本处理）
# 格式: nameserver /domain/ upstream
# 例如: nameserver /baidu.com/ 223.5.5.5

# ===== 测速与选择 =====
# 启用响应测速，smartdns 会选择最快的 IP
response-mode fastest-address
# 测速模式：ping（仅 TCP ping）
ping-timeout 1500
# 强制走 TCP（DNS-over-TCP 模式，可选）
# force-https

# ===== 安全 =====
# 阻止 AAAA 强制走 IPv4 优先（IPv6 分流模式下才需要）
# force-AAAA-SOA 500,500,500,500
# 允许 IPv6
force-AAAA-SOA 0,0,0,0

# ===== 转发所有剩余查询到 DoH（兜底）=====
# 上游 DoH 失败时再降级到 UDP
fallback-server https://1.1.1.1/dns-query
