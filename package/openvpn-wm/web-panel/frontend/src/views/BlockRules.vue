<template>
  <el-card shadow="never">
    <el-tabs v-model="tab">
      <el-tab-pane label="全局封锁" name="global">
        <div class="row">
          <el-input v-model="globalDomain" placeholder="域名，例如 example.com（封该域名及其所有子域名）" style="width: 360px" @keyup.enter="addGlobal" />
          <el-button type="primary" @click="addGlobal">添加全局封锁</el-button>
        </div>
        <el-table :data="globalRules" stripe style="margin-top: 10px">
          <el-table-column prop="domain" label="域名" />
          <el-table-column prop="remark" label="备注" />
          <el-table-column label="添加时间" width="170">
            <template #default="{ row }">{{ fmt(row.created_at) }}</template>
          </el-table-column>
          <el-table-column label="操作" width="100">
            <template #default="{ row }">
              <el-button link type="danger" @click="removeGlobal(row)">解除</el-button>
            </template>
          </el-table-column>
        </el-table>
      </el-tab-pane>

      <el-tab-pane label="按客户封锁" name="user">
        <div class="row">
          <el-select v-model="selectedUser" filterable placeholder="选择客户账号" style="width: 260px">
            <el-option v-for="u in users" :key="u.id" :label="`${u.username}（${u.customer_name || '-'}）`" :value="u.id" />
          </el-select>
          <el-input v-model="userDomain" placeholder="域名" style="width: 260px" @keyup.enter="addUser" />
          <el-button type="primary" @click="addUser">添加该客户封锁</el-button>
        </div>
        <p v-if="selectedUserLabel" class="hint">当前客户：{{ selectedUserLabel }}</p>
        <el-table :data="userRules" stripe style="margin-top: 10px">
          <el-table-column prop="domain" label="域名" />
          <el-table-column prop="remark" label="备注" />
          <el-table-column label="操作" width="100">
            <template #default="{ row }">
              <el-button link type="danger" @click="removeUser(row)">解除</el-button>
            </template>
          </el-table-column>
        </el-table>
      </el-tab-pane>
    </el-tabs>
  </el-card>
</template>

<script setup>
import { computed, onMounted, ref, watch } from "vue";
import dayjs from "dayjs";
import { ElMessage } from "element-plus";
import http from "../api/http";

const tab = ref("global");
const globalRules = ref([]);
const globalDomain = ref("");
const users = ref([]);
const selectedUser = ref(null);
const userDomain = ref("");
const userRules = ref([]);
const selectedUserLabel = computed(() => {
  const u = users.value.find((x) => x.id === selectedUser.value);
  return u ? `${u.username}（${u.customer_name || "-"}）` : "";
});

function fmt(t) {
  return t ? dayjs(t).format("YYYY-MM-DD HH:mm") : "-";
}

async function loadGlobal() {
  const { data } = await http.get("/blocked-domains/global");
  globalRules.value = data;
}

async function addGlobal() {
  const domain = globalDomain.value.trim();
  if (!domain) return;
  await http.post("/blocked-domains/global", { domain });
  ElMessage.success("已添加全局封锁");
  globalDomain.value = "";
  loadGlobal();
}

async function removeGlobal(row) {
  await http.delete("/blocked-domains/global", { params: { domain: row.domain } });
  ElMessage.success("已解除");
  loadGlobal();
}

async function loadUsers() {
  const { data } = await http.get("/users", { params: { page: 1, page_size: 200 } });
  users.value = data.items;
}

async function loadUserRules() {
  if (!selectedUser.value) {
    userRules.value = [];
    return;
  }
  const { data } = await http.get(`/users/${selectedUser.value}/blocked-domains`);
  userRules.value = data;
}

async function addUser() {
  if (!selectedUser.value || !userDomain.value.trim()) return;
  await http.post(`/users/${selectedUser.value}/blocked-domains`, { domain: userDomain.value.trim() });
  ElMessage.success("已添加该客户封锁");
  userDomain.value = "";
  loadUserRules();
}

async function removeUser(row) {
  await http.delete(`/users/${selectedUser.value}/blocked-domains`, {
    params: { domain: row.domain }
  });
  ElMessage.success("已解除");
  loadUserRules();
}

watch(selectedUser, () => loadUserRules());
onMounted(async () => {
  loadGlobal();
  loadUsers();
});
</script>

<style scoped>
.row {
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
}
.hint {
  color: #909399;
  margin: 8px 0;
}
</style>
