<template>
  <el-container class="layout">
    <el-aside width="210px">
      <div class="brand">
        <div class="brand-title">老铁外贸网络</div>
        <div class="brand-sub">管理系统</div>
      </div>
      <el-menu router :default-active="$route.path" background-color="#1f2d3d" text-color="#cfd8dc" active-text-color="#409eff">
        <el-menu-item v-if="role === 'superadmin'" index="/dashboard">总览</el-menu-item>
        <el-menu-item index="/users">客户账号</el-menu-item>
        <el-menu-item v-if="role === 'superadmin'" index="/admins">管理员</el-menu-item>
        <el-menu-item v-if="role === 'superadmin'" index="/nodes">服务器节点</el-menu-item>
        <el-menu-item v-if="role === 'superadmin'" index="/audit">审计日志</el-menu-item>
        <el-menu-item v-if="role === 'superadmin'" index="/port-mappings">端口映射</el-menu-item>
        <el-menu-item v-if="role === 'superadmin'" index="/maintenance">服务维护</el-menu-item>
        <el-menu-item v-if="role === 'superadmin'" index="/mail">邮件设置</el-menu-item>
        <el-menu-item v-if="role === 'superadmin'" index="/block-rules">访问控制</el-menu-item>
        <el-menu-item v-if="role === 'superadmin'" index="/vpn-logs">连接日志</el-menu-item>
        <el-menu-item v-if="role === 'superadmin'" index="/settings">VLAN设置</el-menu-item>
      </el-menu>
    </el-aside>
    <el-container>
      <el-header class="header">
        <span>{{ $route.meta.title || "" }}</span>
        <el-dropdown @command="onCommand">
          <span class="user">{{ username }}<el-icon><ArrowDown /></el-icon></span>
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item command="logout">退出登录</el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
      </el-header>
      <el-main>
        <router-view />
      </el-main>
    </el-container>
  </el-container>
</template>

<script setup>
import { onMounted, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { ArrowDown } from "@element-plus/icons-vue";
import http from "../api/http";
import { clearSession, homePath, setRole } from "../api/session";

const router = useRouter();
const route = useRoute();
const username = ref("admin");
const role = ref("admin");

onMounted(async () => {
  try {
    const { data } = await http.get("/auth/me");
    username.value = data.username;
    role.value = data.role;
    setRole(data.role);
    if (!data.role || data.role !== "superadmin") {
      if (route.path !== "/users") router.replace(homePath());
    }
  } catch {
    /* interceptor 会跳登录 */
  }
});

function onCommand(cmd) {
  if (cmd === "logout") {
    clearSession();
    router.push("/login");
  }
}
</script>

<style scoped>
.layout {
  min-height: 100vh;
}
.el-aside {
  background: #1f2d3d;
}
.brand {
  color: #fff;
  padding: 18px 16px;
  text-align: center;
}
.brand-title {
  font-size: 18px;
  font-weight: 600;
}
.brand-sub {
  color: #9fb0bd;
  font-size: 12px;
  letter-spacing: 2px;
}
.el-menu {
  border-right: none;
}
.header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  background: #fff;
  border-bottom: 1px solid #e4e7ed;
}
.user {
  cursor: pointer;
  color: #303133;
  display: inline-flex;
  align-items: center;
  gap: 4px;
}
</style>
