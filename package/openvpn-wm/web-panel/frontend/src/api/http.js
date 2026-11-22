import axios from "axios";
import { ElMessage } from "element-plus";
import router from "../router";
import { clearSession } from "./session";

const http = axios.create({
  baseURL: "/api",
  timeout: 30000
});

http.interceptors.request.use((config) => {
  const token = localStorage.getItem("access_token");
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

http.interceptors.response.use(
  (response) => response,
  (error) => {
    const status = error.response?.status;
    const detail = error.response?.data?.detail;
    if (status === 401) {
      clearSession();
      router.push("/login");
    } else if (status === 403) {
      const text = typeof detail === "string" ? detail : "";
      if (text.includes("停用") || text.includes("TOTP")) {
        clearSession();
        router.push("/login");
      }
    }
    let msg = error.message || "请求失败";
    if (typeof detail === "string") {
      msg = detail;
    } else if (Array.isArray(detail)) {
      // FastAPI 422 校验错误：detail = [{loc, msg, ...}]
      const parts = detail.map((e) => {
        const field = e.loc && e.loc.length > 1 ? e.loc[e.loc.length - 1] : "";
        const text = e.msg || "";
        return field ? `${field}: ${text}` : text;
      });
      if (parts.length) msg = parts.join("；");
    }
    ElMessage.error(msg);
    return Promise.reject(error);
  }
);

export default http;
