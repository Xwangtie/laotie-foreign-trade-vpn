# OpenVPN Connect 路由推送上限与精简直连表（2026-09-04 实测定稿）

## 现象

macOS OpenVPN Connect（3.7.1 / 3.8.2 均实测）在 `game-open` / `trade-strict`
推送全量 4156 条 CN 路由时无法正常建立分流连接：

```text
Client exception in transport_recv: ERR_INVALID_CONFIG:
  option_error: server-pushed options data too large
Client terminated, restarting in 2000 ms...
```

## 为什么全量 4156 条放不下

OpenVPN3 客户端不是按“条数”而是按“字节预算”计费：

- 每条推送选项计 64 字节；
- 每个 CSV 字段再计 16 字节；
- 每个空格参数再计 16 字节；
- 实际文本字节全部计入。

因此每条 `route <ip> <mask> net_gateway` 大约占 190+ 字节。精确核算：

| 路由形式 | 4156/4147 条全量推送量 | 结论 |
|---|---|---|
| `route IP 掩码 net_gateway`（旧格式） | 约 802 KB | 超过新版 768 KB，也超过旧版 256 KB |
| `route IP/前缀 net_gateway`（CIDR） | 约 666 KB | 新版上限内，但 **OpenVPN Connect 不解析 CIDR，会静默丢弃整条路由**，等于没有分流 |

OpenVPN Connect 3.8.2（内置核心 3.11.3）经反汇编确认上限已提升到
`786432`（768 KB），但只够约 3900 条“IP+掩码”路由，仍小于全量 4156。

旧版 3.7.1（内置核心 3.11.1）上限仍是 `262144`（256 KB），只够约
1300–1350 条。

## 当前默认方案：大网段优先的精简直连表

不再追求全量精确推送，改为 **大网段优先、数量封顶**：

- 国内 IPv4 数据仍保留全量 4147 条原始文件；
- CCD 生成时按网段大小倒序取前 `CN_ROUTE_LIMIT`（默认 **1300**）条；
- 国内 1300 条覆盖约 **98.7%** 的国内 IPv4 地址空间；
- 额外追加 9 条私有网段（LAN 访问）；
- 输出仍为 OpenVPN Connect 支持的 `route <ip> <mask> net_gateway` 格式。

实测推送量约 **243 KB**，旧版（256 KB）和新版（768 KB）客户端都能稳定接收。

## macOS 3.8.2 真机验收结果（2026-09-04）

- `splittest1`（game-open）连接成功并自动重连稳定；
- 客户端日志显示 1309 条直连路由写入系统路由表（网关 192.168.8.254 / en6）；
- 国内大网段：`223.5.5.5`、`180.101.50.242` 及按国内 DNS 解析的
  `110.242.70.57`（百度）、`119.167.175.60`（淘宝）走本地网关，HTTP 200；
- 国外出口：`api.ipify.org` 返回 VPN 服务器 `YOUR_SERVER_IP`；
- 已覆盖的小网段（如 `1.1.8.0/24`）因精简会走 VPN——这是“不要那么精确”
  的已知取舍，未覆盖地址仅占国内空间约 1.3%。

## 配置说明

`profiles/trade-strict/profile.conf`、`profiles/game-open/profile.conf`：

```bash
CN_ROUTE_LIMIT=1300
```

`server/scripts/gen-ccd.sh` 负责排序、截断与 CIDR→点分掩码输出。
如需在能承载更多路由的客户端上恢复更全量，可临时提高
`CN_ROUTE_LIMIT`（新版 Connect 上限约 3900）。

## 兼容性提示

- OpenVPN Connect 不支持 `route x.x.x.x/n` CIDR 推送：不报错，但会静默忽略，
  导致误以为已分流实际全流量走 VPN；
- 不要把 CIDR 简写推广到 Connect 客户端；
- 标准 OpenVPN 2.4+ / Tunnelblick / iKuai 可承载全量精确路由，
  如有需要可单独走全量列表；
- 客户端版本建议引导客户使用 3.8.2+（安全更新 + 768 KB 上限）。
