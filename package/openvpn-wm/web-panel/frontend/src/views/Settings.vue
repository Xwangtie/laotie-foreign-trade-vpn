<template>
  <div>
    <el-card shadow="never">
      <template #header>VPN 局域网互访</template>
      <el-form label-width="220px" style="max-width: 860px">
        <el-form-item label="全部互访（总开关）">
          <div class="line">
            <el-switch v-model="lanEnabled" :loading="saving" @change="toggleLan" />
            <span class="hint">
              开启后所有 VPN 客户互相都能访问；关闭后仅“分组互访 1/2”内成员可互访
            </span>
          </div>
        </el-form-item>
        <el-alert
          v-if="lanEnabled"
          type="warning"
          :closable="false"
          show-icon
          title="当前为全部互访模式，分组隔离暂不生效"
          description="若想按分组隔离，请先关闭上面的总开关，再保存下方分组。"
          style="margin: 4px 0 8px"
        />
        <p class="tip">切换总开关会重启 OpenVPN，当前在线客户会短暂断开。</p>
      </el-form>
    </el-card>

    <el-card shadow="never" style="margin-top: 16px">
      <template #header>
        <div class="card-head">
          分组互访（家庭组/办公室组）
          <el-button
            type="primary"
            size="small"
            :loading="savingGroups"
            @click="saveGroups"
          >
            保存分组
          </el-button>
        </div>
      </template>
      <el-alert
        type="info"
        :closable="false"
        show-icon
        style="margin-bottom: 14px"
        title="同组客户可互相访问，两组互相隔离，未加入任何分组的客户不能访问其它 VPN 客户"
        description="加入分组的客户会自动获得固定隧道地址（10.8.0.201-250），重连后生效；互访时使用对方在线状态中显示的隧道 IP。"
      />
      <div v-for="g in GROUPS" :key="g.id" class="group-block">
        <div class="group-title">{{ g.name }}</div>
        <el-select
          v-model="groupMembers[g.id]"
          multiple
          filterable
          collapse-tags
          collapse-tags-tooltip
          clearable
          placeholder="选择加入本组的客户账号"
          style="width: 100%"
        >
          <el-option
            v-for="user in userOptions"
            :key="user.username"
            :label="userLabel(user)"
            :value="user.username"
            :disabled="inOtherGroup(user.username, g.id)"
          />
        </el-select>
        <div v-if="memberSummary(g.id)" class="member-list">
          {{ memberSummary(g.id) }}
        </div>
        <div v-else class="member-empty">尚未选择客户</div>
      </div>
    </el-card>
  </div>
</template>

<script setup>
import { onMounted, reactive, ref } from "vue";
import { ElMessage, ElMessageBox } from "element-plus";
import http from "../api/http";

const GROUPS = [
  { id: "group1", name: "分组互访1" },
  { id: "group2", name: "分组互访2" }
];
const STATUS_TEXT = {
  active: "有效",
  expired: "已到期",
  suspended: "已暂停"
};

const lanEnabled = ref(false);
const saving = ref(false);
const savingGroups = ref(false);
const userOptions = ref([]);
const groupMembers = reactive({ group1: [], group2: [] });

function userLabel(user) {
  const name = user.customer_name || STATUS_TEXT[user.status] || user.status;
  return `${user.username}（${name}）`;
}

function findUser(username) {
  return userOptions.value.find((u) => u.username === username);
}

function inOtherGroup(username, gid) {
  const other = gid === "group1" ? "group2" : "group1";
  return groupMembers[other].includes(username);
}

function memberSummary(gid) {
  return groupMembers[gid]
    .map((username) => {
      const user = findUser(username);
      return user && user.vpn_ip ? `${username} → ${user.vpn_ip}` : username;
    })
    .join("、");
}

async function load() {
  const { data } = await http.get("/settings/vpn-groups");
  lanEnabled.value = data.global_enabled;
  userOptions.value = data.users;
  data.groups.forEach((g) => {
    groupMembers[g.id] = g.members;
  });
}

async function toggleLan(value) {
  if (value) {
    try {
      await ElMessageBox.confirm(
        "开启后所有 VPN 客户之间都能互访，并会重启 OpenVPN（在线连接短暂断开）。确认开启？",
        "全部互访",
        { type: "warning" }
      );
    } catch {
      lanEnabled.value = false;
      return;
    }
  } else {
    try {
      await ElMessageBox.confirm(
        "关闭后仅两个分组内成员可互访，其它 VPN 客户不能互访；会重启 OpenVPN（在线连接短暂断开）。确认关闭？",
        "关闭全部互访",
        { type: "warning" }
      );
    } catch {
      lanEnabled.value = true;
      return;
    }
  }
  saving.value = true;
  try {
    const { data } = await http.put("/settings/vpn-lan", { enabled: value });
    lanEnabled.value = data.enabled;
    ElMessage.success(data.message || "已保存");
    await load();
  } catch {
    lanEnabled.value = !value;
  } finally {
    saving.value = false;
  }
}

async function saveGroups() {
  savingGroups.value = true;
  try {
    const { data } = await http.put("/settings/vpn-groups", {
      group1: groupMembers.group1,
      group2: groupMembers.group2
    });
    ElMessage.success(data.message || "分组已保存");
    await load();
  } finally {
    savingGroups.value = false;
  }
}

onMounted(load);
</script>

<style scoped>
.line {
  display: flex;
  align-items: center;
  gap: 10px;
}
.hint {
  color: #909399;
  font-size: 13px;
}
.tip {
  color: #e6a23c;
  margin: 0;
}
.card-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding-right: 4px;
}
.group-block {
  border: 1px solid #ebeef5;
  border-radius: 8px;
  padding: 14px 16px;
  margin-bottom: 14px;
}
.group-title {
  font-weight: 600;
  margin-bottom: 10px;
}
.member-list {
  margin-top: 8px;
  color: #606266;
  font-size: 13px;
  line-height: 1.7;
}
.member-empty {
  margin-top: 8px;
  color: #c0c4cc;
  font-size: 13px;
}
</style>
