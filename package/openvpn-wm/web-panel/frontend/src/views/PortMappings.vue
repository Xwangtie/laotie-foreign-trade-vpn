<template>
  <div>
    <el-card shadow="never">
      <div class="toolbar">
        <el-input v-model="q" placeholder="搜索目标 IP / 端口" clearable style="width: 240px" @keyup.enter="load" />
        <el-button type="primary" @click="load">查询</el-button>
        <el-button type="success" @click="openCreate">+ 新增端口映射</el-button>
      </div>
      <el-table :data="rows" v-loading="loading" stripe style="margin-top: 12px">
        <el-table-column prop="id" label="ID" width="70" />
        <el-table-column label="绑定账号" width="160">
          <template #default="{ row }">{{ row.username || "手动 IP（不绑定）" }}</template>
        </el-table-column>
        <el-table-column prop="dest_ip" label="目标内网 IP" width="150" />
        <el-table-column label="公网访问地址" min-width="220">
          <template #default="{ row }">{{ publicHost }}:{{ row.ext_port }} → {{ row.dest_ip }}:{{ row.int_port }}</template>
        </el-table-column>
        <el-table-column label="协议" width="100">
          <template #default="{ row }">
            <el-tag size="small">{{ row.protocol.toUpperCase() }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column label="状态" width="90">
          <template #default="{ row }">
            <el-tag :type="row.status === 'active' ? 'success' : 'info'">{{ row.status === "active" ? "生效中" : "停用" }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="remark" label="备注" min-width="140" show-overflow-tooltip />
        <el-table-column label="创建时间" width="160">
          <template #default="{ row }">{{ fmt(row.created_at) }}</template>
        </el-table-column>
        <el-table-column label="操作" width="120" fixed="right">
          <template #default="{ row }">
            <el-button link type="danger" @click="remove(row)">删除</el-button>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <el-dialog v-model="createVisible" title="新增端口映射（后台 NAT 转发）" width="520px" destroy-on-close>
      <el-form ref="formRef" :model="form" :rules="rules" label-width="120px">
        <el-form-item label="绑定账号">
          <el-select v-model="form.user_id" clearable filterable placeholder="可留空，仅手动填 IP" style="width: 100%">
            <el-option v-for="u in users" :key="u.id" :label="`${u.username}（${u.customer_name || u.company || '-'}）`" :value="u.id" />
          </el-select>
        </el-form-item>
        <el-form-item label="目标内网 IP" prop="dest_ip">
          <el-input v-model="form.dest_ip" placeholder="如 10.8.0.2，客户需在线才能访问" />
        </el-form-item>
        <el-form-item label="公网端口" prop="ext_port">
          <el-input-number v-model="form.ext_port" :min="1024" :max="65535" style="width: 100%" />
          <div class="tip">访问方式：{{ publicHost }}:{{ form.ext_port }}（等价 IP:端口）</div>
        </el-form-item>
        <el-form-item label="内网端口" prop="int_port">
          <el-input-number v-model="form.int_port" :min="1" :max="65535" style="width: 100%" />
        </el-form-item>
        <el-form-item label="协议">
          <el-radio-group v-model="form.protocol">
            <el-radio label="tcp">TCP</el-radio>
            <el-radio label="udp">UDP</el-radio>
            <el-radio label="tcpudp">TCP+UDP</el-radio>
          </el-radio-group>
        </el-form-item>
        <el-form-item label="备注">
          <el-input v-model="form.remark" placeholder="如：远程应用/内网服务名" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="createVisible = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="create">保存并生效</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { onMounted, reactive, ref, computed } from "vue";
import { ElMessage, ElMessageBox } from "element-plus";
import dayjs from "dayjs";
import http from "../api/http";

const publicHost = ref("");
const rows = ref([]);
const users = ref([]);
const q = ref("");
const loading = ref(false);
const saving = ref(false);
const createVisible = ref(false);
const formRef = ref();
const form = reactive({
  user_id: null,
  dest_ip: "",
  ext_port: 20000,
  int_port: 80,
  protocol: "tcp",
  remark: ""
});
const rules = {
  dest_ip: [{ required: true, message: "请填客户 VPN 内网 IP", trigger: "blur" }],
  ext_port: [{ required: true, message: "请填公网端口", trigger: "change" }],
  int_port: [{ required: true, message: "请填内网端口", trigger: "change" }]
};

function fmt(t) {
  return t ? dayjs(t).format("YYYY-MM-DD HH:mm") : "-";
}

async function load() {
  loading.value = true;
  try {
    const { data } = await http.get("/port-mappings");
    rows.value = data.filter((r) => {
      if (!q.value) return true;
      const s = `${r.dest_ip} ${r.ext_port} ${r.int_port} ${r.username || ""}`.toLowerCase();
      return s.includes(q.value.toLowerCase());
    });
  } finally {
    loading.value = false;
  }
}

async function loadUsers() {
  const { data } = await http.get("/users", { params: { page: 1, page_size: 200 } });
  users.value = data.items;
}

async function loadNode() {
  const { data } = await http.get("/nodes");
  const active = data.find((n) => n.status === "active");
  publicHost.value = active?.public_domain || "";
}

function openCreate() {
  Object.assign(form, {
    user_id: null,
    dest_ip: "",
    ext_port: 20000,
    int_port: 80,
    protocol: "tcp",
    remark: ""
  });
  createVisible.value = true;
}

async function create() {
  try {
    await formRef.value.validate();
  } catch {
    return;
  }
  saving.value = true;
  try {
    await http.post("/port-mappings", { ...form });
    ElMessage.success("端口映射已生效");
    createVisible.value = false;
    load();
  } finally {
    saving.value = false;
  }
}

async function remove(row) {
  await ElMessageBox.confirm(
    `确认删除 ${publicHost}:${row.ext_port} → ${row.dest_ip}:${row.int_port}？NAT 规则会立即移除。`,
    "删除端口映射",
    { type: "warning" }
  );
  await http.delete(`/port-mappings/${row.id}`);
  ElMessage.success("已删除");
  load();
}

onMounted(() => {
  load();
  loadUsers();
  loadNode();
});
</script>

<style scoped>
.toolbar {
  display: flex;
  gap: 10px;
}
.tip {
  color: #909399;
  font-size: 12px;
  line-height: 20px;
}
</style>
