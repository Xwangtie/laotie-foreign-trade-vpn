import { createRouter, createWebHistory } from "vue-router";

import Login from "../views/Login.vue";
import TOTPSetup from "../views/TOTPSetup.vue";
import Layout from "../views/Layout.vue";
import Dashboard from "../views/Dashboard.vue";
import Users from "../views/Users.vue";
import Admins from "../views/Admins.vue";
import Nodes from "../views/Nodes.vue";
import Audit from "../views/Audit.vue";
import Mail from "../views/Mail.vue";
import PortMappings from "../views/PortMappings.vue";
import Maintenance from "../views/Maintenance.vue";
import BlockRules from "../views/BlockRules.vue";
import VpnLogs from "../views/VpnLogs.vue";
import SettingsView from "../views/Settings.vue";
import { clearSession, getRole, homeFor, homePath, setRole } from "../api/session";

const SUPER_ONLY = ["superadmin"];

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: "/login", component: Login },
    { path: "/totp-setup", component: TOTPSetup },
    {
      path: "/",
      component: Layout,
      redirect: () => homePath(),
      children: [
        { path: "dashboard", component: Dashboard, meta: { title: "总览", roles: SUPER_ONLY } },
        { path: "users", component: Users, meta: { title: "客户账号" } },
        { path: "admins", component: Admins, meta: { title: "管理员", roles: SUPER_ONLY } },
        { path: "nodes", component: Nodes, meta: { title: "服务器节点", roles: SUPER_ONLY } },
        { path: "audit", component: Audit, meta: { title: "审计日志", roles: SUPER_ONLY } },
        { path: "port-mappings", component: PortMappings, meta: { title: "端口映射", roles: SUPER_ONLY } },
        { path: "maintenance", component: Maintenance, meta: { title: "服务维护", roles: SUPER_ONLY } },
        { path: "mail", component: Mail, meta: { title: "邮件设置", roles: SUPER_ONLY } },
        { path: "block-rules", component: BlockRules, meta: { title: "访问控制", roles: SUPER_ONLY } },
        { path: "vpn-logs", component: VpnLogs, meta: { title: "连接日志", roles: SUPER_ONLY } },
        { path: "settings", component: SettingsView, meta: { title: "VLAN设置", roles: SUPER_ONLY } }
      ]
    }
  ]
});

async function fetchRole() {
  const token = localStorage.getItem("access_token");
  if (!token) return null;
  const res = await fetch("/api/auth/me", {
    headers: { Authorization: `Bearer ${token}` }
  });
  if (!res.ok) return null;
  const data = await res.json();
  if (data.role) setRole(data.role);
  return data.role || null;
}

router.beforeEach(async (to) => {
  const token = localStorage.getItem("access_token");
  const publicPaths = ["/login", "/totp-setup"];
  if (!token) {
    return publicPaths.includes(to.path) ? true : "/login";
  }

  let role = getRole();
  if (!role) {
    try {
      role = await fetchRole();
    } catch {
      role = null;
    }
    if (!role) {
      clearSession();
      return "/login";
    }
  }

  if (publicPaths.includes(to.path)) return homeFor(role);
  const allowed = to.meta?.roles;
  if (allowed && !allowed.includes(role)) return homeFor(role);
  if (to.path === "/") return homeFor(role);
  return true;
});

export default router;
