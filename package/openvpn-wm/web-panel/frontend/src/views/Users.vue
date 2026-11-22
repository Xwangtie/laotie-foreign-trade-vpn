<template>
  <div>
    <el-card shadow="never">
      <div class="toolbar">
        <el-input v-model="query.q" placeholder="用户名/姓名/电话/公司/邮箱" clearable style="width: 260px" @keyup.enter="load(1)" />
        <el-select v-model="query.profile" placeholder="全部类型" clearable style="width: 150px">
          <el-option label="① 全局代理" value="trade-global" />
          <el-option label="② 分流+断网保护" value="trade-strict" />
          <el-option label="③ 分流+回落本地" value="game-open" />
        </el-select>
        <el-select v-model="query.status" placeholder="全部状态" clearable style="width: 140px">
          <el-option label="有效" value="active" />
          <el-option label="已到期" value="expired" />
          <el-option label="已暂停" value="suspended" />
          <el-option label="已吊销" value="revoked" />
        </el-select>
        <el-button type="primary" @click="load(1)">查询</el-button>
        <el-button type="success" @click="openCreate">+ 开户</el-button>
      </div>

      <el-table :data="rows" v-loading="loading" stripe style="margin-top: 12px">
        <el-table-column prop="username" label="用户名" width="130" />
        <el-table-column label="类型" width="150">
          <template #default="{ row }">{{ profileName(row.profile) }}</template>
        </el-table-column>
        <el-table-column prop="customer_name" label="姓名" width="110" />
        <el-table-column prop="phone" label="电话" width="130" />
        <el-table-column prop="company" label="公司" min-width="150" show-overflow-tooltip />
        <el-table-column label="状态" width="90">
          <template #default="{ row }">
            <el-tag :type="statusType(row.status)">{{ statusName(row.status) }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column label="到期时间" width="160">
          <template #default="{ row }">{{ fmt(row.expire_at) }}</template>
        </el-table-column>
        <el-table-column label="已用流量" width="120" sortable :sort-by="(a,b)=>a.used_bytes-b.used_bytes">
          <template #default="{ row }">
            <el-tag v-if="row.quota_bytes && row.used_bytes >= row.quota_bytes" type="danger" size="small">已超限</el-tag>
            <span v-else>{{ fmtBytes(row.used_bytes) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="流量上限" width="100">
          <template #default="{ row }">
            <span>{{ row.quota_bytes ? fmtBytes(row.quota_bytes) : "不限" }}</span>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="430" fixed="right">
          <template #default="{ row }">
            <el-button link type="primary" @click="download(row)">下载配置</el-button>
            <el-button link type="primary" @click="openEdit(row)">修改</el-button>
            <el-button link type="warning" @click="openRenew(row)">续期</el-button>
            <el-button v-if="row.status !== 'suspended'" link type="warning" @click="suspend(row)">暂停</el-button>
            <el-button v-else link type="success" @click="resume(row)">恢复</el-button>
            <el-button v-if="row.status !== 'revoked'" link type="danger" @click="revoke(row)">吊销</el-button>
            <el-button v-if="row.status === 'revoked'" link type="danger" @click="remove(row)">删除</el-button>
          </template>
        </el-table-column>
      </el-table>

      <el-pagination
        style="margin-top: 12px"
        layout="total, prev, pager, next"
        :total="total"
        :page-size="query.page_size"
        :current-page="query.page"
        @current-change="load"
      />
    </el-card>

    <!-- 开户 -->
    <el-dialog v-model="createVisible" title="新增 VPN 客户" width="560px" destroy-on-close>
      <el-form :model="form" label-width="110px" ref="createRef" :rules="createRules">
        <el-form-item label="客户用户名" prop="username">
          <el-input v-model="form.username" placeholder="1-32 位字母/数字/_/-" />
        </el-form-item>
        <el-form-item label="账号类型" prop="profile">
          <el-select v-model="form.profile" style="width: 100%">
            <el-option
              v-for="p in profiles"
              :key="p.profile_id"
              :label="`${p.name}（${p.desc}）`"
              :value="p.profile_id"
            />
          </el-select>
        </el-form-item>
        <el-form-item label="客户姓名" prop="customer_name"><el-input v-model="form.customer_name" /></el-form-item>
        <el-form-item label="联系电话" prop="phone"><el-input v-model="form.phone" /></el-form-item>
        <el-form-item label="公司名称" prop="company"><el-input v-model="form.company" /></el-form-item>
        <el-form-item label="联系邮箱" prop="email"><el-input v-model="form.email" placeholder="用于到期提醒" /></el-form-item>
        <el-form-item label="到期时间" prop="expire_at">
          <el-date-picker v-model="form.expire_at" type="datetime" value-format="YYYY-MM-DDTHH:mm:ss" style="width: 100%" />
        </el-form-item>
        <el-form-item label="流量上限"><el-input v-model="form.quota_gb" placeholder="GB，留空不限" /></el-form-item>
        <el-form-item label="备注"><el-input v-model="form.remark" type="textarea" /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="createVisible = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="create">开户</el-button>
      </template>
    </el-dialog>

    <!-- 开户成功 -->
    <el-dialog v-model="resultVisible" title="开户成功" width="480px">
      <p>客户账号 {{ result?.username }} 已创建。</p>
      <p>请将下方下载链接发给客户，导入后即可直接连接。</p>
      <el-alert :title="`客服电话：13905394878　客服邮箱：ymwww@qq.com`" type="info" :closable="false" style="margin: 10px 0" />
      <el-button type="primary" tag="a" :href="result?.download_url" target="_blank">下载 .ovpn 配置文件</el-button>
    </el-dialog>

    <!-- 续期 -->
    <el-dialog v-model="renewVisible" title="续期" width="380px">
      <p>客户：{{ renewTarget?.username }}</p>
      <el-input-number v-model="renewMonths" :min="1" :max="12" /> 个月
      <template #footer>
        <el-button @click="renewVisible = false">取消</el-button>
        <el-button type="primary" @click="renew">确认续期</el-button>
      </template>
    </el-dialog>

    <!-- 修改客户资料 -->
    <el-dialog v-model="editVisible" title="修改客户资料" width="560px" destroy-on-close>
      <el-form :model="editForm" label-width="110px">
        <el-form-item label="客户用户名"><el-input :model-value="editForm.username" disabled /></el-form-item>
        <el-form-item label="客户姓名"><el-input v-model="editForm.customer_name" /></el-form-item>
        <el-form-item label="联系电话"><el-input v-model="editForm.phone" /></el-form-item>
        <el-form-item label="公司名称"><el-input v-model="editForm.company" /></el-form-item>
        <el-form-item label="联系邮箱"><el-input v-model="editForm.email" /></el-form-item>
        <el-form-item label="到期时间">
          <el-date-picker v-model="editForm.expire_at" type="datetime" value-format="YYYY-MM-DDTHH:mm:ss" style="width: 100%" />
        </el-form-item>
        <el-form-item label="流量上限"><el-input v-model="editForm.quota_gb" placeholder="GB，留空不限" /></el-form-item>
        <el-form-item label="备注"><el-input v-model="editForm.remark" type="textarea" /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="editVisible = false">取消</el-button>
        <el-button type="primary" @click="saveEdit">保存修改</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { onMounted, reactive, ref } from "vue";
import dayjs from "dayjs";
import { ElMessage, ElMessageBox } from "element-plus";
import http from "../api/http";

const rows = ref([]);
const total = ref(0);
const loading = ref(false);
const query = reactive({ page: 1, page_size: 20, q: "", profile: "", status: "" });
const profiles = ref([]);

const createVisible = ref(false);
const resultVisible = ref(false);
const result = ref(null);
const renewVisible = ref(false);
const renewTarget = ref(null);
const renewMonths = ref(1);
const saving = ref(false);
const editVisible = ref(false);
const editForm = reactive({});

const form = reactive({
  username: "",
  profile: "",
  customer_name: "",
  phone: "",
  company: "",
  email: "",
  expire_at: dayjs().add(1, "month").format("YYYY-MM-DDTHH:mm:ss"),
  quota_gb: "",
  remark: ""
});

const createRules = {
  username: [{ required: true, message: "请输入用户名" }],
  profile: [{ required: true, message: "请选择类型" }],
  customer_name: [],
  phone: [],
  company: [],
  email: [{ required: false, type: "email", message: "邮箱格式不正确" }]
};

function profileName(id) {
  return { "trade-global": "① 全局代理", "trade-strict": "② 分流+断网保护", "game-open": "③ 分流+回落本地" }[id] || id;
}
function statusName(s) {
  return { active: "有效", expired: "已到期", suspended: "已暂停", revoked: "已吊销" }[s] || s;
}
function statusType(s) {
  return { active: "success", expired: "info", suspended: "warning", revoked: "danger" }[s] || "info";
}
function fmt(t) {
  return t ? dayjs(t).format("YYYY-MM-DD HH:mm") : "-";
}

function fmtBytes(n) {
  if (n == null) return "-";
  const units = ["B", "KB", "MB", "GB", "TB"];
  let v = Number(n);
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i += 1;
  }
  return `${v >= 10 || i === 0 ? v.toFixed(0) : v.toFixed(1)} ${units[i]}`;
}

async function load(page) {
  loading.value = true;
  try {
    const { data } = await http.get("/users", {
      params: { ...query, page, page_size: query.page_size }
    });
    query.page = page;
    rows.value = data.items;
    total.value = data.total;
  } finally {
    loading.value = false;
  }
}

function openCreate() {
  Object.assign(form, {
    username: "",
    profile: profiles.value[0]?.profile_id || "trade-global",
    customer_name: "",
    phone: "",
    company: "",
    email: "",
    expire_at: dayjs().add(1, "month").format("YYYY-MM-DDTHH:mm:ss"),
    quota_gb: "",
    remark: ""
  });
  createVisible.value = true;
}

async function create() {
  saving.value = true;
  try {
    const { data } = await http.post("/users", {
      username: form.username,
      profile: form.profile,
      customer_name: form.customer_name,
      phone: form.phone,
      company: form.company,
      email: form.email,
      expire_at: form.expire_at,
      quota_bytes: form.quota_gb ? Number(form.quota_gb) * 1024 ** 3 : null,
      remark: form.remark || null
    });
    result.value = {
      username: data.username,
      download_url: `/api/users/${data.id}/ovpn?token=${data.download_token}`
    };
    createVisible.value = false;
    resultVisible.value = true;
    load(1);
  } finally {
    saving.value = false;
  }
}

async function download(row) {
  const { data } = await http.post(`/users/${row.id}/download-token`);
  window.open(data.download_url, "_blank");
}

function openEdit(row) {
  Object.assign(editForm, {
    id: row.id,
    username: row.username,
    customer_name: row.customer_name || "",
    phone: row.phone || "",
    company: row.company || "",
    email: row.email || "",
    expire_at: row.expire_at ? dayjs(row.expire_at).format("YYYY-MM-DDTHH:mm:ss") : "",
    quota_gb: row.quota_bytes ? String(Math.round(row.quota_bytes / 1024 ** 3)) : "",
    remark: row.remark || ""
  });
  editVisible.value = true;
}

async function saveEdit() {
  const payload = {
    customer_name: editForm.customer_name,
    phone: editForm.phone,
    company: editForm.company,
    email: editForm.email || undefined,
    expire_at: editForm.expire_at || undefined,
    quota_bytes: editForm.quota_gb ? Number(editForm.quota_gb) * 1024 ** 3 : undefined,
    remark: editForm.remark || undefined
  };
  await http.patch(`/users/${editForm.id}`, payload);
  ElMessage.success("已保存");
  editVisible.value = false;
  load(query.page);
}

function openRenew(row) {
  renewTarget.value = row;
  renewMonths.value = 1;
  renewVisible.value = true;
}

async function renew() {
  await http.post(`/users/${renewTarget.value.id}/renew`, { months: renewMonths.value });
  ElMessage.success("续期成功");
  renewVisible.value = false;
  load(query.page);
}

async function suspend(row) {
  await ElMessageBox.confirm(`确定暂停账号 ${row.username}？在线连接会被立即断开。`, "提示", { type: "warning" });
  await http.post(`/users/${row.id}/suspend`);
  ElMessage.success("已暂停");
  load(query.page);
}

async function resume(row) {
  await http.post(`/users/${row.id}/resume`);
  ElMessage.success("已恢复");
  load(query.page);
}

async function revoke(row) {
  await ElMessageBox.confirm(`吊销后证书将进入 CRL，无法恢复，只能重新开户。确认吊销 ${row.username}？`, "危险操作", { type: "error" });
  await http.post(`/users/${row.id}/revoke`);
  ElMessage.success("已吊销");
  load(query.page);
}

async function remove(row) {
  await ElMessageBox.confirm(
    `客户 ${row.username} 已吊销，删除后将永久清除该客户记录与流量/会话历史，不可恢复；其名下的端口映射也会一并清理。确认删除？`,
    "删除客户",
    { type: "error", confirmButtonText: "确认删除" }
  );
  const { data } = await http.delete(`/users/${row.id}`);
  ElMessage.success(data.message || "客户已删除");
  load(query.page);
}

onMounted(async () => {
  const { data } = await http.get("/profiles");
  profiles.value = data;
  load(1);
});
</script>

<style scoped>
.toolbar {
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
}
.hint {
  color: #909399;
  font-size: 12px;
  margin-left: 8px;
}
</style>
