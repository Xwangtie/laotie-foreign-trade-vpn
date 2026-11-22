<template>
  <div>
    <el-card shadow="never">
      <div class="toolbar">
        <el-input v-model="q" placeholder="搜索管理员" clearable style="width: 220px" @keyup.enter="load(1)" />
        <el-button type="primary" @click="load(1)">查询</el-button>
        <el-button type="success" @click="createVisible = true">新增管理员</el-button>
      </div>
      <el-table :data="rows" stripe style="margin-top: 12px">
        <el-table-column prop="id" label="ID" width="60" />
        <el-table-column prop="username" label="用户名" />
        <el-table-column label="角色" width="110">
          <template #default="{ row }">
            <el-tag :type="row.role === 'superadmin' ? 'danger' : 'info'">{{ row.role === "superadmin" ? "超级管理员" : "管理员" }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column label="状态" width="90">
          <template #default="{ row }">
            <el-tag :type="row.is_active ? 'success' : 'info'">{{ row.is_active ? "启用" : "停用" }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column label="TOTP" width="100">
          <template #default="{ row }">
            <el-tag :type="row.totp_confirmed ? 'success' : 'warning'" size="small">
              {{ row.totp_confirmed ? "已绑定" : "未绑定" }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="last_login_ip" label="最近登录 IP" width="140" />
        <el-table-column label="最近登录" width="160">
          <template #default="{ row }">{{ fmt(row.last_login_at) }}</template>
        </el-table-column>
        <el-table-column label="操作" width="330" fixed="right">
          <template #default="{ row }">
            <el-button link type="primary" @click="toggle(row)">{{ row.is_active ? "停用" : "启用" }}</el-button>
            <el-button link type="warning" @click="resetTotp(row)">重置TOTP</el-button>
            <el-button link type="warning" @click="resetPassword(row)">重置密码</el-button>
            <el-button link type="danger" @click="remove(row)">删除</el-button>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <el-dialog v-model="createVisible" title="新增管理员" width="460px">
      <el-form ref="adminFormRef" :model="form" :rules="rules" label-width="100px">
        <el-form-item label="用户名" prop="username">
          <el-input v-model="form.username" placeholder="3-32位：英文/数字/_/-，不能中文" />
        </el-form-item>
        <el-form-item label="初始密码" prop="password">
          <el-input v-model="form.password" type="password" show-password placeholder="至少 6 位" />
        </el-form-item>
        <el-form-item label="角色">
          <el-radio-group v-model="form.role">
            <el-radio label="admin">管理员（仅客户账号）</el-radio>
            <el-radio label="superadmin">超级管理员（全部权限）</el-radio>
          </el-radio-group>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="createVisible = false">取消</el-button>
        <el-button type="primary" @click="create">创建</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { onMounted, reactive, ref } from "vue";
import { ElMessage, ElMessageBox } from "element-plus";
import { useRouter } from "vue-router";
import dayjs from "dayjs";
import http from "../api/http";
import { clearSession } from "../api/session";

const router = useRouter();

const rows = ref([]);
const total = ref(0);
const q = ref("");
const createVisible = ref(false);
const form = reactive({ username: "", password: "", role: "admin" });
const adminFormRef = ref();
const rules = {
  username: [
    { required: true, message: "请输入用户名", trigger: "blur" },
    { pattern: /^[A-Za-z0-9_-]{3,32}$/, message: "仅允许 3-32 位英文/数字/下划线/短横线", trigger: "blur" }
  ],
  password: [
    { required: true, message: "请输入初始密码", trigger: "blur" },
    { min: 6, max: 128, message: "密码长度需 6-128 位", trigger: "blur" }
  ]
};

function fmt(t) {
  return t ? dayjs(t).format("YYYY-MM-DD HH:mm") : "-";
}

async function load(page = 1) {
  const { data } = await http.get("/admins", { params: { page, page_size: 20, q: q.value } });
  rows.value = data.items;
  total.value = data.total;
}

async function create() {
  try {
    await adminFormRef.value.validate();
  } catch {
    return;
  }
  try {
    await http.post("/admins", { ...form });
    ElMessage.success("创建成功");
    createVisible.value = false;
    load();
  } catch (e) {
    // 后端校验失败时已在拦截器统一提示，这里避免重复弹窗
    if (!e.response?.data?.detail) {
      ElMessage.error("创建失败，请检查用户名是否重复或字段格式");
    }
  }
}

async function toggle(row) {
  await http.patch(`/admins/${row.id}`, { is_active: !row.is_active });
  ElMessage.success("已更新");
  load();
}

async function resetTotp(row) {
  await ElMessageBox.confirm(`重置 ${row.username} 的 TOTP？该管理员需重新登录并绑定。`, "提示", { type: "warning" });
  await http.post(`/admins/${row.id}/reset-totp`);
  ElMessage.success("已重置");
}

async function resetPassword(row) {
  const me = (await http.get("/auth/me")).data;
  const { value } = await ElMessageBox.prompt(
    `为管理员 ${row.username} 设置新密码（6-128 位）`,
    "重置密码",
    {
      inputPlaceholder: "输入新密码",
      inputPattern: /^[\s\S]{6,128}$/,
      inputErrorMessage: "密码长度需 6-128 位",
      confirmButtonText: "保存"
    }
  );
  const { data } = await http.post(`/admins/${row.id}/reset-password`, {
    new_password: value
  });
  ElMessage.success(data.message || "密码已重置");
  if (me.id === row.id) {
    clearSession();
    router.push("/login");
    return;
  }
  load();
}

async function remove(row) {
  await ElMessageBox.confirm(`确认删除管理员 ${row.username}？`, "危险操作", { type: "error" });
  await http.delete(`/admins/${row.id}`);
  ElMessage.success("已删除");
  load();
}

onMounted(() => load());
</script>

<style scoped>
.toolbar {
  display: flex;
  gap: 10px;
}
</style>
