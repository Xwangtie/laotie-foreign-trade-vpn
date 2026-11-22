<template>
  <div class="login-bg">
    <el-card class="login-card">
      <h1 class="title">老铁外贸网络管理系统</h1>
      <p class="subtitle">VPN 客户开户 / 续期 / 管理后台</p>
      <el-form label-position="top" @keyup.enter="submit">
        <el-form-item label="管理员账号">
          <el-input v-model="form.username" placeholder="请输入管理员账号" />
        </el-form-item>
        <el-form-item label="密码">
          <el-input v-model="form.password" type="password" show-password placeholder="请输入密码" />
        </el-form-item>
        <el-form-item v-if="needCode" label="TOTP 动态验证码">
          <el-input v-model="form.code" maxlength="6" placeholder="6 位动态码" />
        </el-form-item>
        <el-button type="primary" class="w-full" :loading="loading" @click="submit">
          {{ needCode ? "验证并登录" : "登 录" }}
        </el-button>
      </el-form>
      <p class="footer">客服电话：13905394878　客服邮箱：ymwww@qq.com</p>
    </el-card>
  </div>
</template>

<script setup>
import { reactive, ref } from "vue";
import { useRouter } from "vue-router";
import http from "../api/http";
import { homePath, saveLogin } from "../api/session";

const router = useRouter();
const form = reactive({ username: "", password: "", code: "" });
const needCode = ref(false);
const loading = ref(false);

async function submit() {
  if (!form.username || !form.password) return;
  loading.value = true;
  try {
    const { data } = await http.post("/auth/login", {
      username: form.username,
      password: form.password,
      code: form.code || undefined
    });
    if (data.setup_token) {
      sessionStorage.setItem("totp_setup", JSON.stringify(data));
      router.push("/totp-setup");
      return;
    }
    saveLogin(data);
    router.push(homePath());
  } catch (e) {
    if (e.response?.status === 428) needCode.value = true;
  } finally {
    loading.value = false;
  }
}
</script>

<style scoped>
.login-bg {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #1f2d3d 0%, #35495e 100%);
}
.login-card {
  width: 420px;
  padding: 16px 8px;
}
.title {
  text-align: center;
  margin: 0 0 4px;
  font-size: 24px;
}
.subtitle {
  text-align: center;
  color: #909399;
  margin-bottom: 20px;
}
.w-full {
  width: 100%;
}
.footer {
  margin-top: 18px;
  text-align: center;
  color: #909399;
  font-size: 12px;
}
</style>
