<template>
  <div>
    <el-card shadow="never">
      <div class="toolbar">
        <span class="hint">节点规范域名：例如 vpn.example.com、vpn2.example.com，也可使用自有域名</span>
        <el-button type="success" @click="openAdd">新增节点</el-button>
      </div>
      <el-table :data="rows" stripe style="margin-top: 12px">
        <el-table-column prop="name" label="名称" />
        <el-table-column prop="region" label="地区" />
        <el-table-column prop="public_domain" label="规范域名" />
        <el-table-column prop="public_ip" label="IP" />
        <el-table-column prop="ssh_port" label="SSH端口" width="90" />
        <el-table-column prop="openvpn_port" label="VPN端口" width="90" />
        <el-table-column label="状态" width="90">
          <template #default="{ row }">
            <el-tag :type="row.status === 'active' ? 'success' : 'warning'">{{ statusName(row.status) }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="160">
          <template #default="{ row }">
            <el-button link type="danger" @click="remove(row)">删除</el-button>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <el-dialog v-model="addVisible" title="新增节点" width="460px">
      <el-form :model="form" label-width="110px">
        <el-form-item label="名称"><el-input v-model="form.name" /></el-form-item>
        <el-form-item label="地区"><el-input v-model="form.region" /></el-form-item>
        <el-form-item label="规范域名"><el-input v-model="form.public_domain" placeholder="vpn2.your-domain.com" /></el-form-item>
        <el-form-item label="公网 IP"><el-input v-model="form.public_ip" /></el-form-item>
        <el-form-item label="SSH 端口"><el-input-number v-model="form.ssh_port" :min="1" :max="65535" /></el-form-item>
        <el-form-item label="VPN 端口"><el-input-number v-model="form.openvpn_port" :min="1" :max="65535" /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="addVisible = false">取消</el-button>
        <el-button type="primary" @click="add">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { onMounted, reactive, ref } from "vue";
import { ElMessage, ElMessageBox } from "element-plus";
import http from "../api/http";

const rows = ref([]);
const addVisible = ref(false);
const form = reactive({
  name: "",
  region: "中国",
  public_domain: "",
  public_ip: "",
  ssh_port: 12346,
  openvpn_port: 1194,
  status: "active"
});

function statusName(s) {
  return { active: "可用", maintenance: "维护", offline: "离线" }[s] || s;
}

async function load() {
  const { data } = await http.get("/nodes");
  rows.value = data;
}

function openAdd() {
  Object.assign(form, { name: "", public_domain: "", public_ip: "", ssh_port: 12346, openvpn_port: 1194 });
  addVisible.value = true;
}

async function add() {
  await http.post("/nodes", { ...form });
  ElMessage.success("节点已新增");
  addVisible.value = false;
  load();
}

async function remove(row) {
  await ElMessageBox.confirm(`确认删除节点 ${row.name}？`, "提示", { type: "warning" });
  await http.delete(`/nodes/${row.id}`);
  ElMessage.success("已删除");
  load();
}

onMounted(() => load());
</script>

<style scoped>
.toolbar {
  display: flex;
  justify-content: space-between;
}
.hint {
  color: #909399;
}
</style>
