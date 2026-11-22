<template>
  <el-card shadow="never">
    <el-table :data="rows" v-loading="loading" stripe>
      <el-table-column prop="id" label="ID" width="70" />
      <el-table-column prop="admin_username" label="操作人" width="110">
        <template #default="{ row }">{{ row.admin_username || "系统" }}</template>
      </el-table-column>
      <el-table-column prop="action" label="动作" width="170" />
      <el-table-column prop="target_type" label="对象" width="90" />
      <el-table-column prop="target_id" label="对象ID" width="90" />
      <el-table-column prop="ip" label="IP" width="130" />
      <el-table-column label="详情" min-width="260" show-overflow-tooltip>
        <template #default="{ row }">
          <code class="detail">{{ row.detail_json }}</code>
        </template>
      </el-table-column>
      <el-table-column label="时间" width="160">
        <template #default="{ row }">{{ fmt(row.created_at) }}</template>
      </el-table-column>
    </el-table>
    <el-pagination
      style="margin-top: 12px"
      layout="total, prev, pager, next"
      :total="total"
      :page-size="20"
      @current-change="load"
    />
  </el-card>
</template>

<script setup>
import { onMounted, ref } from "vue";
import dayjs from "dayjs";
import http from "../api/http";

const rows = ref([]);
const total = ref(0);
const loading = ref(false);

function fmt(t) {
  return t ? dayjs(t).format("YYYY-MM-DD HH:mm:ss") : "-";
}

async function load(page = 1) {
  loading.value = true;
  try {
    const { data } = await http.get("/audit", { params: { page, page_size: 50 } });
    rows.value = data.items;
    total.value = data.total;
  } finally {
    loading.value = false;
  }
}

onMounted(() => load());
</script>

<style scoped>
.detail {
  font-size: 12px;
  color: #606266;
}
</style>
