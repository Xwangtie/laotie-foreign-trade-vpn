#!/usr/bin/env bash
# install-new-server.sh - 老铁外贸网络管理系统 · 全新 Ubuntu 服务器一键安装
# 同时安装：OpenVPN(三方案) + DNS防污染(dnsmasq ECS + stubby DoT) + 防火墙 + Web面板 + Nginx
#
# 用法（在服务器上 root 执行）：
#   cd /root/openvpn-wm-package
#   DOMAIN=vpn2.example.com PUBLIC_IP=1.2.3.4 SSH_PORT=22 \
#     bash install-new-server.sh
#
# 可选环境变量：
#   DOMAIN       面板/节点域名（默认 vpn.example.com，必须已 A 记录指向本机）
#   PUBLIC_IP    服务器公网 IPv4（默认自动探测）
#   SSH_PORT     本机 SSH 端口（默认自动探测，防火墙只放行该端口）
#   VPN_PORT     OpenVPN UDP 端口（默认 1194）
#   ADMIN_USER   首个超级管理员用户名（默认 admin）
#   PANEL_ADMIN_PASSWORD  首个超级管理员密码（默认 admin）
#   AUTO_HTTPS   1=自动签发 Let's Encrypt（默认，失败自动回退自签）；0=直接自签
#   REPLACE_OLD_OPENVPN 1=先停用/清除本机旧 OpenVPN(1199/server目录)再安装本系统
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "请以 root 运行: sudo bash $0" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "$SCRIPT_DIR/web-panel" && -d "$SCRIPT_DIR/server" && -d "$SCRIPT_DIR/profiles" ]]; then
  PAYLOAD="$SCRIPT_DIR"
else
  PAYLOAD="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
[[ -d "$PAYLOAD/web-panel" && -d "$PAYLOAD/server" && -d "$PAYLOAD/profiles" ]] || {
  echo "找不到安装包目录（需要包含 web-panel/server/profiles/shared）" >&2
  exit 1
}

export DEBIAN_FRONTEND=noninteractive
export EASYRSA_CA_EXPIRE=36500 EASYRSA_CERT_EXPIRE=36500 EASYRSA_CRL_DAYS=36500

DOMAIN="${DOMAIN:-vpn.example.com}"
PUBLIC_IP="${PUBLIC_IP:-$(curl -4 -sS -m 10 https://api.ip.sb/ip 2>/dev/null || true)}"
PUBLIC_IP="${PUBLIC_IP:-127.0.0.1}"
VPN_PORT="${VPN_PORT:-1194}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${PANEL_ADMIN_PASSWORD:-admin}"
AUTO_HTTPS="${AUTO_HTTPS:-1}"
if command -v ss >/dev/null 2>&1; then
  SSH_PORT="${SSH_PORT:-$(ss -tlnp 2>/dev/null | grep sshd | grep -oE ':[0-9]+' | head -1 | tr -d ':')}"
fi
SSH_PORT="${SSH_PORT:-22}"

WEB=/opt/openvpn-wm/web-panel
DB=/var/lib/openvpn-wm/panel.db

hdr() { echo; echo "======== $* ========"; }

hdr "0. 参数确认"
echo "安装包:   $PAYLOAD"
echo "域名:     $DOMAIN"
echo "公网IP:   $PUBLIC_IP"
echo "SSH端口:  $SSH_PORT"
echo "VPN端口:  $VPN_PORT"
echo "超管账号: $ADMIN_USER / $ADMIN_PASS"

hdr "1. 系统依赖与基础目录"
if [[ "${REPLACE_OLD_OPENVPN:-0}" == "1" ]]; then
  echo "[replace] 停止并清除旧 OpenVPN（备份已由调用方负责）"
  systemctl stop openvpn-server@server.service 2>/dev/null || true
  systemctl disable openvpn-server@server.service 2>/dev/null || true
  systemctl stop openvpn-iptables.service 2>/dev/null || true
  systemctl disable openvpn-iptables.service 2>/dev/null || true
  rm -rf /etc/openvpn/server /etc/openvpn/client
  rm -f /etc/systemd/system/openvpn-iptables.service
  iptables -F FORWARD 2>/dev/null || true
  iptables -t nat -F POSTROUTING 2>/dev/null || true
  ufw --force disable 2>/dev/null || true
  systemctl daemon-reload
fi
apt-get update -qq
apt-get install -y -qq \
  openvpn easy-rsa dnsmasq stubby iptables-persistent \
  nginx python3 python3-venv python3-pip certbot python3-certbot-nginx \
  curl openssl netcat-openbsd rsync jq >/dev/null

mkdir -p /etc/openvpn /etc/openvpn/ccd /etc/openvpn/data /etc/openvpn/profiles \
         /etc/openvpn/scripts /etc/openvpn/easy-rsa \
         /etc/dnsmasq.d /etc/stubby /var/lib/openvpn-wm /var/log/openvpn \
         /var/www/letsencrypt /etc/nginx/ssl
id openvpnwm >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin openvpnwm
install -d -o openvpnwm -g openvpnwm /opt/openvpn-wm /var/lib/openvpn-wm

hdr "2. EasyRSA PKI（证书默认不过期）"
EASYRSA=/etc/openvpn/easy-rsa
if [[ ! -f "$EASYRSA/pki/ca.crt" ]]; then
  rm -rf "$EASYRSA"
  if command -v make-cadir >/dev/null 2>&1; then
    make-cadir "$EASYRSA"
  else
    mkdir -p "$EASYRSA"
    cp -a /usr/share/easy-rsa/. "$EASYRSA/"
  fi
  cat > "$EASYRSA/vars" <<'EOF'
set_var EASYRSA_CA_EXPIRE 36500
set_var EASYRSA_CERT_EXPIRE 36500
set_var EASYRSA_REQ_CN "openvpn-wm-ca"
set_var EASYRSA_CRL_DAYS 3650
EOF
  (cd "$EASYRSA" && ./easyrsa init-pki \
    && mv "$EASYRSA/vars" "$EASYRSA/pki/vars" \
    && ./easyrsa --batch build-ca nopass \
    && sed -i '/EASYRSA_REQ_CN/d' "$EASYRSA/pki/vars" \
    && ./easyrsa --batch build-server-full server nopass \
    && ./easyrsa gen-dh \
    && ./easyrsa gen-crl)
fi
cp -f "$EASYRSA/pki/ca.crt"      /etc/openvpn/ca.crt
cp -f "$EASYRSA/pki/dh.pem"      /etc/openvpn/dh.pem
cp -f "$EASYRSA/pki/private/server.key" /etc/openvpn/server.key
cp -f "$EASYRSA/pki/issued/server.crt"  /etc/openvpn/server.crt
cp -f "$EASYRSA/pki/crl.pem"     /etc/openvpn/crl.pem
chmod 600 /etc/openvpn/server.key
[[ -f /etc/openvpn/tc.key ]] || openvpn --genkey secret /etc/openvpn/tc.key

hdr "3. 部署 OpenVPN 配置 / 脚本 / profile / 数据"
cp -f "$PAYLOAD/server/openvpn/server.conf" /etc/openvpn/server.conf
cp -f "$PAYLOAD/server/dnsmasq/dnsmasq-wm.conf" /etc/dnsmasq.d/openvpn-wm.conf
cp -f "$PAYLOAD/server/dnsmasq/dnsmasq-wm-cn-ecs.conf" /etc/dnsmasq-wm-cn-ecs.conf
cp -f "$PAYLOAD/server/systemd/dnsmasq-wm-cn.service" /etc/systemd/system/dnsmasq-wm-cn.service
cp -f "$PAYLOAD/server/systemd/openvpn-wm-dns.service" /etc/systemd/system/openvpn-wm-dns.service
sed 's#/114\.114\.114\.114#/127.0.0.1#5354#g' \
  "$PAYLOAD/shared/data/accelerated-domains.china.conf" > /etc/dnsmasq.d/china-domains.conf
cp -f "$PAYLOAD/server/stubby/stubby.yml" /etc/stubby/stubby.yml
cp -f "$PAYLOAD/shared/data/cn-ipv4.txt" "$PAYLOAD/shared/data/private-ranges.txt" \
      "$PAYLOAD/shared/data/private-ranges6.txt" /etc/openvpn/data/ 2>/dev/null || true
rm -rf /etc/openvpn/profiles/* && cp -a "$PAYLOAD/profiles/." /etc/openvpn/profiles/
rm -rf /etc/openvpn/scripts/* && cp -a "$PAYLOAD/server/scripts/." /etc/openvpn/scripts/
chmod +x /etc/openvpn/scripts/*.sh /etc/openvpn/scripts/vpn-auth.py 2>/dev/null || true
if [[ ! -s /var/lib/openvpn-wm/mgmt.pass ]]; then
  openssl rand -hex 24 > /var/lib/openvpn-wm/mgmt.pass
  chmod 600 /var/lib/openvpn-wm/mgmt.pass
fi

hdr "4. DNS 防污染（stubby DoT + dnsmasq 国内ECS）"
systemctl enable stubby >/dev/null 2>&1 || true
systemctl restart stubby
sleep 2
systemctl disable --now systemd-resolved >/dev/null 2>&1 || true
chattr -i /etc/resolv.conf 2>/dev/null || true
rm -f /etc/resolv.conf
printf 'nameserver 127.0.0.1\n' > /etc/resolv.conf
chattr +i /etc/resolv.conf 2>/dev/null || true
systemctl daemon-reload
systemctl enable dnsmasq-wm-cn.service >/dev/null 2>&1 || true
systemctl enable openvpn-wm-dns.service >/dev/null 2>&1 || true

hdr "5. 防火墙 + 转发"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
printf 'net.ipv4.ip_forward=1\n' > /etc/sysctl.d/99-openvpn-wm.conf
SSH_PORT="$SSH_PORT" VPN_PORT="$VPN_PORT" bash "$PAYLOAD/server/firewall/firewall.sh" apply
SSH_PORT="$SSH_PORT" VPN_PORT="$VPN_PORT" bash "$PAYLOAD/server/firewall/firewall.sh" persist

hdr "6. 启动 OpenVPN / dnsmasq"
systemctl daemon-reload
systemctl enable openvpn@server >/dev/null 2>&1 || true
systemctl restart openvpn@server
sleep 3
systemctl enable dnsmasq >/dev/null 2>&1 || true
systemctl restart dnsmasq
systemctl restart dnsmasq-wm-cn.service
sleep 1
systemctl restart openvpn-wm-dns.service
sleep 1
# 面板运行用户可读 OpenVPN 状态日志（流量统计）
chgrp openvpnwm /var/log/openvpn/status.log 2>/dev/null || true
chmod 640 /var/log/openvpn/status.log 2>/dev/null || true
echo "OpenVPN:  $(systemctl is-active openvpn@server)"
echo "dnsmasq:  $(systemctl is-active dnsmasq)"
echo "ECS-DNS:  $(systemctl is-active dnsmasq-wm-cn.service)"
echo "PolicyDNS: $(systemctl is-active openvpn-wm-dns.service)"
echo "stubby:   $(systemctl is-active stubby)"

hdr "7. Web 面板代码与依赖"
cp -a "$PAYLOAD/web-panel/." "$WEB/"
chown -R openvpnwm:openvpnwm "$WEB" /var/lib/openvpn-wm
cd "$WEB/backend"
if [[ ! -x .venv/bin/python ]]; then
  python3 -m venv .venv
fi
.venv/bin/pip install --quiet --upgrade pip
.venv/bin/pip install --quiet -r requirements.txt

hdr "8. 生成 .env（超管 admin/admin）"
JWT_SECRET_VALUE="$(openssl rand -hex 32)"
cat > "$WEB/.env" <<EOF
APP_NAME=老铁外贸网络管理系统
SUPPORT_PHONE=13905394878
SUPPORT_EMAIL=ymwww@qq.com
OPENVPN_WM_DB_PATH=$DB
MOCK_EASY_RSA=false
OPENVPN_WM_PROFILES_DIR=/etc/openvpn/profiles
OPENVPN_WM_CCD_DIR=/etc/openvpn/ccd
S1_USE_SUDO=true
GEN_CCD_SCRIPT=/etc/openvpn/scripts/gen-ccd.sh
GEN_CLIENT_SCRIPT=/etc/openvpn/scripts/gen-client.sh
REVOKE_CLIENT_SCRIPT=/etc/openvpn/scripts/revoke-client.sh
LIST_CLIENTS_SCRIPT=/etc/openvpn/scripts/list-clients.sh
SUSPEND_CCD_SCRIPT=/etc/openvpn/scripts/suspend-client.sh
VPN_KILL_SCRIPT=/etc/openvpn/scripts/vpn-kill.sh
OPENVPN_STATUS_LOG=/var/log/openvpn/status.log
PORTMAP_SCRIPT=/etc/openvpn/scripts/portmap.sh
LOG_CLEAN_SCRIPT=/etc/openvpn/scripts/log-clean.sh
LAN_MODE_SCRIPT=/etc/openvpn/scripts/set-lan-mode.sh
LAN_STATE_FILE=/var/lib/openvpn-wm/lan-groups.json
JWT_SECRET=$JWT_SECRET_VALUE
ACCESS_TOKEN_MINUTES=15
REFRESH_TOKEN_DAYS=7
TOTP_ISSUER=老铁外贸网络管理系统
REQUIRE_TOTP=false
BOOTSTRAP_ADMIN_PASSWORD=$ADMIN_PASS
SMTP_HOST=
SMTP_PORT=465
SMTP_USER=
SMTP_PASSWORD=
SMTP_FROM=ymwww@qq.com
SMTP_FROM_NAME=老铁外贸网络管理系统
SMTP_USE_SSL=true
DEFAULT_NODE_NAME=节点1
DEFAULT_NODE_REGION=中国
DEFAULT_NODE_DOMAIN=$DOMAIN
DEFAULT_NODE_IP=$PUBLIC_IP
DEFAULT_NODE_SSH_PORT=$SSH_PORT
DEFAULT_NODE_OPENVPN_PORT=$VPN_PORT
ENABLE_SCHEDULER=true
ENABLE_EMAIL_REMINDERS=false
EOF
chmod 600 "$WEB/.env"

hdr "9. 面板 sudoers 白名单 + 数据库 + systemd"
cat > /etc/sudoers.d/openvpnwm-panel <<'EOF'
openvpnwm ALL=(root) NOPASSWD: /etc/openvpn/scripts/gen-ccd.sh, /etc/openvpn/scripts/gen-client.sh, /etc/openvpn/scripts/revoke-client.sh, /etc/openvpn/scripts/list-clients.sh, /etc/openvpn/scripts/suspend-client.sh, /etc/openvpn/scripts/vpn-kill.sh
openvpnwm ALL=(root) NOPASSWD: /etc/openvpn/scripts/portmap.sh
openvpnwm ALL=(root) NOPASSWD: /etc/openvpn/scripts/log-clean.sh
openvpnwm ALL=(root) NOPASSWD: /etc/openvpn/scripts/set-lan-mode.sh
EOF
chmod 440 /etc/sudoers.d/openvpnwm-panel
chown -R openvpnwm:openvpnwm "$WEB" /var/lib/openvpn-wm
cd "$WEB/backend"
.venv/bin/python -m alembic upgrade head
chown openvpnwm:openvpnwm "$DB"
cp -f "$WEB/deploy/panel.service" /etc/systemd/system/openvpnwm-panel.service
systemctl daemon-reload
systemctl enable --now openvpnwm-panel >/dev/null 2>&1 || true
sleep 4
systemctl is-active openvpnwm-panel
# 首次启动已用 admin/admin 创建超管，随即清除引导密码
sed -i "s#^BOOTSTRAP_ADMIN_PASSWORD=.*#BOOTSTRAP_ADMIN_PASSWORD=#" "$WEB/.env"
systemctl restart openvpnwm-panel
sleep 2
cat > /root/openvpn-wm-admin.txt <<EOF
老铁外贸网络管理系统 - 初始超级管理员
username: $ADMIN_USER
password: $ADMIN_PASS
面板地址: https://$DOMAIN
请首次登录后立即修改密码。
EOF
chmod 600 /root/openvpn-wm-admin.txt

hdr "10. 定时维护（日志30天 / 每月DNS数据）"
cat > /etc/cron.d/openvpn-wm-logclean <<'EOF'
10 4 * * * root /etc/openvpn/scripts/log-clean.sh retain30 >/dev/null 2>&1
EOF
cat > /etc/cron.d/openvpn-wm-dnsupdate <<'EOF'
20 4 1 * * root /etc/openvpn/scripts/update-data.sh >/dev/null 2>&1
EOF
chmod 644 /etc/cron.d/openvpn-wm-logclean /etc/cron.d/openvpn-wm-dnsupdate
chmod +x /etc/openvpn/scripts/portmap.sh /etc/openvpn/scripts/log-clean.sh

hdr "11. Nginx + HTTPS"
bootstrap_http() {
  cat > /etc/nginx/sites-available/panel-bootstrap.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/letsencrypt; }
    location / { return 200 'install-pending'; }
}
EOF
  rm -f /etc/nginx/sites-enabled/default
  ln -sf /etc/nginx/sites-available/panel-bootstrap.conf /etc/nginx/sites-enabled/panel-bootstrap.conf
  nginx -t
  systemctl restart nginx
}
rm -f /etc/nginx/sites-enabled/panel-bootstrap.conf
bootstrap_http
CERT_OK=1
if [[ "$AUTO_HTTPS" == "1" ]]; then
  certbot certonly --webroot -w /var/www/letsencrypt -d "$DOMAIN" \
    --non-interactive --agree-tos --register-unsafely-without-email || CERT_OK=0
fi
rm -f /etc/nginx/sites-available/panel-bootstrap.conf /etc/nginx/sites-enabled/panel-bootstrap.conf
sed "s/vpn\.xeonas\.cn/$DOMAIN/g" "$PAYLOAD/web-panel/deploy/nginx-vpn.example.com.conf" \
  > "/etc/nginx/sites-available/$DOMAIN"
if [[ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
  echo "[nginx] 证书未签发，生成自签证书作为 HTTPS 兜底"
  mkdir -p "/etc/nginx/ssl/$DOMAIN"
  openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
    -keyout "/etc/nginx/ssl/$DOMAIN/privkey.pem" \
    -out "/etc/nginx/ssl/$DOMAIN/fullchain.pem" \
    -subj "/CN=$DOMAIN" >/dev/null 2>&1
  sed -i \
    -e "s#ssl_certificate .*#ssl_certificate /etc/nginx/ssl/$DOMAIN/fullchain.pem;#" \
    -e "s#ssl_certificate_key .*#ssl_certificate_key /etc/nginx/ssl/$DOMAIN/privkey.pem;#" \
    "/etc/nginx/sites-available/$DOMAIN"
fi
ln -sf "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN"
nginx -t
systemctl reload nginx

hdr "12. 完成摘要"
systemctl is-active openvpn@server dnsmasq dnsmasq-wm-cn openvpn-wm-dns stubby openvpnwm-panel nginx
curl -fsS http://127.0.0.1:8000/api/health || true
echo
echo "======================================================"
echo " 安装完成"
echo " 管理面板:  https://$DOMAIN"
echo " 初始账号:  $(cat /root/openvpn-wm-admin.txt | grep username)"
echo "            $(cat /root/openvpn-wm-admin.txt | grep password)"
echo " 证书状态:  $([ -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem ] && echo Lets-Encrypt-已签发 || echo 自签证书-建议尽快签发)"
echo "======================================================"
