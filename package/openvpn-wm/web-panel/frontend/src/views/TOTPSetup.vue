<template>
  <div class="page">
    <el-card class="box">
      <h2>绑定两步验证（TOTP）</h2>
      <p>请用 Google Authenticator / 1Password 等扫描二维码，并输入 6 位动态码完成绑定。</p>
      <template v-if="setup">
        <img v-if="qr" :src="qr" alt="TOTP 二维码" class="qr" />
        <p>手动密钥：<code>{{ setup.manual_key }}</code></p>
        <el-input v-model="code" maxlength="6" placeholder="6 位动态验证码" class="code-input" />
        <el-button type="primary" :loading="loading" @click="confirm">完成绑定并进入后台</el-button>
      </template>
      <el-button v-else @click="$router.push('/login')">返回登录</el-button>
    </el-card>
  </div>
</template>

<script setup>
import { onMounted, ref } from "vue";
import { useRouter } from "vue-router";
import QRCode from "qrcode";
import http from "../api/http";
import { homePath, saveLogin } from "../api/session";

const router = useRouter();
const setup = ref(JSON.parse(sessionStorage.getItem("totp_setup") || "null"));
const qr = ref("");
const code = ref("");
const loading = ref(false);

onMounted(async () => {
  if (!setup.value) return;
  qr.value = await QRCode.toDataURL(setup.value.otpauth_uri, { width: 220, margin: 1 });
});

async function confirm() {
  if (!code.value) return;
  loading.value = true;
  try {
    const { data } = await http.post("/auth/totp/confirm", {
      setup_token: setup.value.setup_token,
      code: code.value
    });
    saveLogin(data);
    sessionStorage.removeItem("totp_setup");
    router.push(homePath());
  } finally {
    loading.value = false;
  }
}
</script>

<style scoped>
.page {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #f0f2f5;
}
.box {
  width: 460px;
  text-align: center;
}
.qr {
  width: 220px;
  height: 220px;
  margin: 10px auto;
}
.code-input {
  max-width: 260px;
  margin: 8px auto 16px;
}
</style>
