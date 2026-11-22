<template>
  <el-card shadow="never">
    <el-tabs v-model="tab">
      <el-tab-pane label="连接记录" name="sessions">
        <div class="row">
          <el-select v-model="onlineFilter" clearable placeholder="全部" style="width: 120px" @change="loadSessions(1)">
            <el-option label="仅在线" :value="true" />
            <el-option label="已断开" :value="false" />
          </el-select>
          <el-button type="primary" @click="loadSessions(1)">刷新</el-button>
        </div>
        <el-table :data="sessions" stripe style="margin-top: 10px">
          <el-table-column prop="username" label="客户" width="120" />
          <el-table-column prop="real_ip" label="公网 IP" width="150" />
          <el-table-column prop="virtual_ip" label="隧道 IP" width="110" />
          <el-table-column label="上线时间" width="160">
            <template #default="{ row }">{{ row.connected_at ? fmt(row.connected_at) : "-" }}</template>
          </el-table-column>
          <el-table-column label="下线时间" width="160">
            <template #default="{ row }">{{ row.disconnected_at ? fmt(row.disconnected_at) : "-" }}</template>
          </el-table-column>
          <el-table-column label="流量" width="160">
            <template #default="{ row }">{{ fmtBytes(row.rx_bytes + row.tx_bytes) }}</template>
          </el-table-column>
          <el-table-column label="状态" width="90">
            <template #default="{ row }">
              <el-tag :type="row.online ? 'success' : 'info'">{{ row.online ? "在线" : "已断开" }}</el-tag>
            </template>
          </el-table-column>
        </el-table>
      </el-tab-pane>

      <el-tab-pane label="认证日志" name="auth">
        <div class="row">
          <el-input v-model="authUser" placeholder="用户名" clearable style="width: 180px" @keyup.enter="loadAuth(1)" />
          <el-select v-model="authSuccess" clearable placeholder="结果" style="width: 120px" @change="loadAuth(1)">
            <el-option label="成功" :value="true" />
            <el-option label="失败" :value="false" />
          </el-select>
          <el-button type="primary" @click="loadAuth(1)">查询</el-button>
        </div>
        <el-table :data="authLogs" stripe style="margin-top: 10px">
          <el-table-column prop="username" label="用户名" width="120" />
          <el-table-column label="结果" width="90">
            <template #default="{ row }">
              <el-tag :type="row.success ? 'success' : 'danger'">{{ row.success ? "成功" : "失败" }}</el-tag>
            </template>
          </el-table-column>
          <el-table-column prop="reason" label="原因" width="150" />
          <el-table-column prop="real_ip" label="公网 IP" width="150" />
          <el-table-column label="时间" width="170">
            <template #default="{ row }">{{ fmt(row.created_at) }}</template>
          </el-table-column>
        </el-table>
      </el-tab-pane>
    </el-tabs>
  </el-card>
</template>

<script setup>
import { onMounted, ref } from "vue";
import dayjs from "dayjs";
import http from "../api/http";

const tab = ref("sessions");
const sessions = ref([]);
const onlineFilter = ref(null);
const authLogs = ref([]);
const authUser = ref("");
const authSuccess = ref(null);

function fmt(t) {
  return t ? dayjs(t).format("YYYY-MM-DD HH:mm:ss") : "-";
}
function fmtBytes(n) {
  const units = ["B", "KB", "MB", "GB", "TB"];
  let v = Number(n || 0);
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i += 1;
  }
  return `${v >= 10 || i === 0 ? v.toFixed(0) : v.toFixed(1)} ${units[i]}`;
}

async function loadSessions(page = 1) {
  const { data } = await http.get("/vpn-sessions", {
    params: {
      page,
      page_size: 50,
      online: onlineFilter.value === null ? undefined : onlineFilter.value
    }
  });
  sessions.value = data;
}

async function loadAuth(page = 1) {
  const { data } = await http.get("/vpn-auth-logs", {
    params: {
      page,
      page_size: 50,
      username: authUser.value || undefined,
      success: authSuccess.value === null ? undefined : authSuccess.value
    }
  });
  authLogs.value = data.items;
}

onMounted(() => {
  loadSessions();
  loadAuth();
});
</script>

<style scoped>
.row {
  display: flex;
  gap: 10px;
  align-items: center;
}
</style>
