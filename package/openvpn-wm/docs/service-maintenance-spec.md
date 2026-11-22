# 服务维护（日志清理）需求

> 状态：已确认，2026-09-04 开发

## 功能

1. **一键清理全部日志**
   - 清空 OpenVPN（`openvpn.log`、`status.log`、`client-connect.log`、`vpn-auth.log`）
     与 Nginx（`access.log`、`error.log`）；
   - 同时删除已轮转/压缩的旧日志（`.gz` / `.1` / `.old`）；
   - 保留文件本身，服务无需重启。

2. **日志只保留 30 天**
   - 手动：清理超过 30 天的轮转/压缩日志 + 系统日志 `journalctl --vacuum-time=30d`；
   - 自动：服务器每天 04:10 由 cron 执行（`/etc/cron.d/openvpn-wm-logclean`）。

## 入口

左侧导航“服务维护”（超级管理员可见），提供两个按钮：

- 一键清理全部日志；
- 清理 30 天前日志。

## 权限与审计

- 面板进程仅通过 sudoers 白名单调用
  `/etc/openvpn/scripts/log-clean.sh {clean|retain30|stats}`；
- 每次清理写入审计日志（`maintenance.logs.clean` / `maintenance.logs.retain30`）。

## 回滚

- 删除 cron：`rm -f /etc/cron.d/openvpn-wm-logclean`；
- 移除 sudoers 行：`sed -i '/log-clean.sh/d' /etc/sudoers.d/openvpnwm-panel`；
- 日志被清空后不可恢复，需重新产生（运行一段时间后自动累积）。
