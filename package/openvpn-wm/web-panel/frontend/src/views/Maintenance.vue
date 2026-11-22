<template>
  <div>
    <el-card shadow="never">
      <template #header>
        <span>服务维护（日志清理）</span>
      </template>
      <el-alert
        title="日志只保留 30 天：服务器已配置每日自动执行；也可随时手动执行。"
        type="info"
        :closable="false"
        show-icon
        style="margin-bottom: 18px"
      />
      <el-space direction="vertical" alignment="start" :size="16">
        <div>
          <el-button type="danger" :loading="busy" @click="cleanAll">一键清理全部日志</el-button>
          <div class="desc">立即清空 OpenVPN / Nginx 当前日志及已轮转的旧日志，保留日志文件本身。</div>
        </div>
        <div>
          <el-button type="warning" :loading="busy" @click="retain30">清理 30 天前日志</el-button>
          <div class="desc">删除超过 30 天的轮转日志，并整理系统日志到 30 天内。</div>
        </div>
      </el-space>
    </el-card>
  </div>
</template>

<script setup>
import { ref } from "vue";
import { ElMessage, ElMessageBox } from "element-plus";
import http from "../api/http";

const busy = ref(false);

async function run(path, title) {
  await ElMessageBox.confirm(`确认执行“${title}”？`, "服务维护", {
    type: "warning"
  });
  busy.value = true;
  try {
    const { data } = await http.post(path);
    ElMessage.success(data.message || "执行完成");
  } finally {
    busy.value = false;
  }
}

async function cleanAll() {
  await run("/maintenance/logs/clean", "一键清理全部日志");
}

async function retain30() {
  await run("/maintenance/logs/retain30", "清理 30 天前日志");
}
</script>

<style scoped>
.desc {
  color: #909399;
  font-size: 12px;
  margin-top: 4px;
}
</style>
