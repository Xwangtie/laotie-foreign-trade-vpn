# OpenVPN Web 管理端同类项目调研（2026-09-03）

> 目的：为 S3（Web 管理端）找功能与架构参考。以下项目仅作**设计参考**；
> 本项目技术栈已拍板为 FastAPI + SQLAlchemy + Vue3 + Element Plus，**不直接改栈或整仓照抄**。
> 若将来要复制任何代码，必须先核对对应仓库 LICENSE。

## 0. 已下载到本地的参考代码（不入 git，仅本地研究）

| 目录 | 项目 | 许可 | 关键参考文件 |
|---|---|---|---|
| `reference/OpenVPN-Admin` | [arvage/OpenVPN-Admin](https://github.com/arvage/OpenVPN-Admin) | **AGPL-3.0**（只可看思路，不搬代码） | `sql/schema-*.sql`（用户/日志表）、README 安全清单 |
| `reference/openvpn-mng` | [tldr-it-stepankutaj/openvpn-mng](https://github.com/tldr-it-stepankutaj/openvpn-mng) | Apache-2.0 | `internal/models/{user,role,audit}.go`、`internal/handlers/vpn_auth_handler.go`（连接时校验有效期） |
| `reference/openvpn-webui` | [taoshanghu/openvpn-webui](https://github.com/taoshanghu/openvpn-webui) | Apache-2.0 | `openvpn/api.py` / `views.py`（连接鉴权、强制下线、流量入库） |
| `reference/ovpn-admin` | [palark/ovpn-admin](https://github.com/palark/ovpn-admin) | Apache-2.0 | `certificates.go`、`kubernetes.go`（EasyRSA 调用/CRL/CCD）、master/slave 同步参数 |

> ⚠️ 除 `reference/OpenVPN-Admin`（AGPL）外，其余三个为 Apache-2.0，可参考实现，
> 若直接复用其代码需保留原 LICENSE 与版权声明并在本仓库标注来源。

## 1. 候选项目对比

| 项目 | 技术栈 | 与我们的相似度 | 值得借鉴 | 不适合照抄的原因 |
|---|---|---|---|---|
| [arvage/OpenVPN-Admin](https://github.com/arvage/OpenVPN-Admin) | PHP + MySQL/MariaDB + Apache + Bootstrap | 🔥 功能最接近 | 用户「开始/到期日期」、启停、过期行高亮；EasyRSA 发证/吊销/下载 `.ovpn`/邮件发送；SMTP 配置与测试邮件；到期前 7 天提醒；super-admin / read-only 两级管理员；10 秒刷新的在线 Dashboard；连接历史汇总 | PHP 栈与我们的 FastAPI+Vue 不一致；未提 2FA、多节点 |
| [tldr-it-stepankutaj/openvpn-mng](https://github.com/tldr-it-stepankutaj/openvpn-mng)（Apache-2.0） | Go + Gin + GORM + Bootstrap | 🔥 现代、安全设计好 | RBAC（USER/MANAGER/ADMIN 三级）；`valid_from/valid_to` 有效期；审计含登录/登出；JWT token 失效（登出黑名单）；登录限流 + 账号锁定；`.ovpn` 模板在线编辑/预览/下载；会话/流量/审计 REST API；Swagger | Go 栈与我们的不一致；无 2FA、无到期邮件提醒 |
| [eylandoo/OVPN Manager](https://github.com/eylandoo/openvpn_webpanel_manager) | Flask + SQLAlchemy + Tailwind | 🔥 多节点 + 子管理员概念最全 | 子管理员（reseller）+ 开户配额；用户流量限额/并发数/到期日；实时启停；用户订阅页（二维码/下载链接）；多节点集中管理；后台任务、备份恢复、节点健康状态 | 仓库含付费授权（试用/购买），**仅看流程，不借代码**；多协议超出我们范围 |
| [taoshanghu/openvpn-webui](https://github.com/taoshanghu/openvpn-webui)（中文） | Django + nginx | ✅ 中文、轻量 | 创建/删除/禁用/强制下线用户；在线用户上下行流量；按日期查上线/下线日志 | Django 栈与我们的不一致；功能集偏简单；README 明确不建议公网开放 |
| [palark/ovpn-admin](https://github.com/palark/ovpn-admin) | Go + Vue.js | ✅ 和我们前/后端形态相似 | 用户/证书/吊销/恢复/轮换；CCD 与静态 IP；master/slave 双机证书与 CCD 同步；OpenVPN management 在线状态；Prometheus 指标（证书到期/在线数） | 作者声明**非安全加固产品**、面向内网；EasyRSA/OpenVPN 版本较老；无到期自动化、无管理后台 |

## 2. 对本项目最有用的结论

### 2.1 用户模型
参考 `arvage` + `openvpn-mng`，客户账号应同时具备：

- 状态机：`active / suspended / expired / revoked`
- 有效期字段：`valid_from`、`expire_at`（到期任务按 `expire_at` 扫）
- 启停是轻操作，吊销是重操作（写 CRL）
- 用户列表对**已过期行做视觉区分**，避免漏看

### 2.2 管理员与安全（对应我们已定的「管理员管理 P0」）
- 两级角色不够用就三级：`superadmin` / `admin` / 只读（`arvage` 有 read-only，`openvpn-mng` 有 MANAGER）
- 管理员列表记录：最近登录时间、登录 IP、创建人
- 登录失败限流 + 账号锁定 + **锁定/解锁也写审计**（`openvpn-mng`）
- 登出或停用后 JWT 立即失效（token 黑名单）
- 2FA 重置后强制重新绑定（本项目额外要求，参考项目里少见，属加分项）

### 2.3 证书与 .ovpn
- 发证/吊销都走后端调 EasyRSA，且用**白名单 sudoers**（如只允许 web 用户执行 `easyrsa` 与 `openvpn` 相关命令），不要给任意 root shell（`arvage`）
- `.ovpn` 模板可在线编辑并留版本历史（`arvage` / `openvpn-mng`）
- 下载 `.ovpn` 用一次性短令牌（本项目要求，不落盘）
- 可选「直接发到客户邮箱」——对应我们的到期提醒之外，可做成「开户即发 .ovpn」的可选按钮

### 2.4 在线与强制下线
- 解析 `status.log` 每 5–10 秒刷新（我们已定 5 秒）
- **强制下线 = OpenVPN management 接口**（`ovpn-admin` 使用 mgmt；`openvpn-webui` 有强制下线）
- 到期自动停用时同一个 mechanism 踢在线会话（我们已定）

### 2.5 多节点/多服务器
- `ovpn-admin` 的 master/slave 证书同步、`eylandoo` 的中央面板管理多节点，都是概念参考
- 我们采用「中央面板 + 每节点规范域名 `vpn{n}.example.com` + 面板跨机执行幂等脚本」，一期只接本机节点
- 每个客户账号记 `node_id`，`.ovpn` 按所选节点的 `public_domain` 生成

### 2.6 审计范围（建议补充）
`openvpn-mng` 把登录/登出也纳入审计。本项目现有 `audit_log` 只写业务操作，**建议补充**：

- 登录成功/失败/锁定（含 IP、时间、管理员）
- 停用/恢复/重置 2FA/改密/删管理员等管理员管理动作
- `.ovpn` 下载（谁下载了谁，虽然配置不落盘）

### 2.7 「到期禁止再连」的实现路线（已据此定案）
纯证书本身不表达"到期/续费"状态；CRL 吊销后也不方便"续费即恢复"。
同类项目有两种做法：

1. `openvpn-mng` / `openvpn-webui`：客户端额外送账号密码，OpenVPN 每次连接调认证 API/数据库。
2. 纯证书 + `client-connect` 钩子：脚本按证书 CN（=用户名）查账号状态，
   **返回非零即拒绝该次连接**（OpenVPN 文档与社区实测均确认）。在线连接另用
   management 接口 `kill <username>` 断开。

本项目采用 **方案 2（纯证书 + client-connect 状态校验）**：
客户端体验最简（.ovpn 不用输密码），且到期/停用/恢复都只改 DB，无需重发证书。

## 3. 建议执行方式

1. 继续使用本项目已拍板技术栈（FastAPI + Vue3），不复刻 PHP/Django/Go 代码；
2. 按「功能与交互」借鉴：开户/到期/启停/吊销/下载/续期/邮件/管理员/节点；
3. 把 §2.6 的审计补充和「.ovpn 模板版本历史」加入 S3 需求（如认可）；
4. 若之后发现某个交互细节要抄源码，先查 LICENSE 再决定是否允许及如何标注。

## 4. 结论一句话

**主参考 `arvage/OpenVPN-Admin` 的业务流程 + `openvpn-mng` 的角色/审计/安全设计 + `eylandoo` 的多节点/子管理员概念**；代码用自己的 FastAPI + Vue3 实现，到期拦截走「纯证书 + client-connect 状态校验」。
