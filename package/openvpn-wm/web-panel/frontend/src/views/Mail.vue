<template>
  <el-card shadow="never" style="max-width: 640px">
    <template #header>邮件设置（到期提醒）</template>
    <el-descriptions :column="1" border>
      <el-descriptions-item label="SMTP 状态">
        <el-tag :type="status.configured ? 'success' : 'warning'">{{ status.configured ? "已配置" : "未配置" }}</el-tag>
      </el-descriptions-item>
      <el-descriptions-item label="安全报告">{{ status.report || "-" }}</el-descriptions-item>
      <el-descriptions-item label="发件显示">老铁外贸网络管理系统 &lt;ymwww@qq.com&gt;</el-descriptions-item>
    </el-descriptions>
    <el-divider />
    <el-form inline>
      <el-form-item label="测试收件邮箱">
        <el-input v-model="testEmail" placeholder="输入测试收件邮箱" />
      </el-form-item>
      <el-button type="primary" @click="sendTest">发送测试邮件</el-button>
    </el-form>
    <p class="note">SMTP 配置写在 /opt/openvpn-wm/web-panel/.env（生产）或 web-panel/.env（开发），配置后重启面板。密码不会出现在审计日志中。</p>
  </el-card>
</template>

<script setup>
import { onMounted, ref } from "vue";
import { ElMessage } from "element-plus";
import http from "../api/http";

const status = ref({ configured: false, report: "" });
const testEmail = ref("");

async function load() {
  const { data } = await http.get("/mail/status");
  status.value = data;
}

async function sendTest() {
  await http.post("/mail/test", { email: testEmail.value });
  ElMessage.success("测试邮件已发送，请查收");
}

onMounted(() => load());
</script>

<style scoped>
.note {
  color: #909399;
  font-size: 12px;
  margin-top: 8px;
}
</style>
