<template>
  <div>
    <el-row :gutter="16">
      <el-col :span="6" v-for="card in cards" :key="card.label">
        <el-card shadow="hover">
          <div class="stat-label">{{ card.label }}</div>
          <div class="stat-value">{{ card.value }}</div>
        </el-card>
      </el-col>
    </el-row>
    <el-row :gutter="16" style="margin-top: 16px">
      <el-col :span="12">
        <el-card shadow="hover">
          <template #header>账号类型分布</template>
          <div ref="pieRef" class="chart" />
        </el-card>
      </el-col>
      <el-col :span="12">
        <el-card shadow="hover">
          <template #header>最近在线</template>
          <el-table :data="online" size="small" max-height="300">
            <el-table-column prop="username" label="用户名" />
            <el-table-column prop="profile" label="类型" />
            <el-table-column prop="real_ip" label="来源 IP" />
            <el-table-column label="连接时间">
              <template #default="{ row }">{{ fmtTime(row.connected_at) }}</template>
            </el-table-column>
          </el-table>
        </el-card>
      </el-col>
    </el-row>
  </div>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from "vue";
import * as echarts from "echarts";
import http from "../api/http";

const stats = ref({});
const online = ref([]);
const pieRef = ref(null);
let chart = null;

const cards = computed(() => [
  { label: "在线连接", value: stats.value.online ?? "-" },
  { label: "有效客户", value: stats.value.active_users ?? "-" },
  { label: "今日流量", value: formatBytes((stats.value.today_rx || 0) + (stats.value.today_tx || 0)) },
  { label: "本月新增", value: stats.value.new_users_this_month ?? "-" }
]);

function formatBytes(n) {
  if (!n) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  let i = 0;
  while (n >= 1024 && i < units.length - 1) {
    n /= 1024;
    i++;
  }
  return `${n.toFixed(1)} ${units[i]}`;
}

function fmtTime(t) {
  return t ? new Date(t).toLocaleString("zh-CN") : "-";
}

function renderPie() {
  if (!pieRef.value) return;
  chart = chart || echarts.init(pieRef.value);
  const dist = stats.value.profile_distribution || {};
  const names = {
    "trade-global": "① 全局",
    "trade-strict": "② 分流+严格",
    "game-open": "③ 分流+回落"
  };
  chart.setOption({
    tooltip: { trigger: "item" },
    series: [
      {
        type: "pie",
        radius: ["35%", "65%"],
        data: Object.entries(dist).map(([k, v]) => ({
          name: names[k] || k,
          value: v
        }))
      }
    ]
  });
}

async function load() {
  const [s, o] = await Promise.all([http.get("/dashboard"), http.get("/online")]);
  stats.value = s.data;
  online.value = o.data;
  renderPie();
}

onMounted(() => {
  load();
  window.addEventListener("resize", resize);
});

function resize() {
  chart?.resize();
}

onBeforeUnmount(() => {
  window.removeEventListener("resize", resize);
  chart?.dispose();
});
</script>

<style scoped>
.stat-label {
  color: #909399;
  font-size: 13px;
}
.stat-value {
  font-size: 26px;
  font-weight: 600;
  margin-top: 6px;
}
.chart {
  height: 320px;
}
</style>
