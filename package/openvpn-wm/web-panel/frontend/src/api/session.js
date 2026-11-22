const ACCESS_KEY = "access_token";
const REFRESH_KEY = "refresh_token";
const ROLE_KEY = "role";

export function getRole() {
  return localStorage.getItem(ROLE_KEY);
}

export function setRole(role) {
  localStorage.setItem(ROLE_KEY, role);
}

export function saveLogin(data) {
  localStorage.setItem(ACCESS_KEY, data.access_token);
  localStorage.setItem(REFRESH_KEY, data.refresh_token);
  if (data.role) setRole(data.role);
}

export function clearSession() {
  localStorage.removeItem(ACCESS_KEY);
  localStorage.removeItem(REFRESH_KEY);
  localStorage.removeItem(ROLE_KEY);
}

export function homeFor(role) {
  return role === "superadmin" ? "/dashboard" : "/users";
}

export function homePath() {
  return homeFor(getRole() || "admin");
}
