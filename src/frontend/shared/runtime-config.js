const DEFAULT_API_BASE_URL = "https://__HOST_API__";
const DEFAULT_KEYCLOAK_BASE_URL = "https://__HOST_SSO__";
const DEFAULT_KEYCLOAK_REALM = "__KEYCLOAK_REALM__";

function readGlobal(name) {
  if (typeof window === "undefined") {
    return "";
  }
  const value = window[name];
  return typeof value === "string" ? value.trim() : "";
}

export function resolveApiBaseUrl() {
  const explicit = readGlobal("TEMPLATE_API_BASE_URL");
  if (explicit) {
    return explicit.replace(/\/$/, "");
  }
  return DEFAULT_API_BASE_URL;
}

export function resolveWebSocketUrl() {
  const explicit = readGlobal("TEMPLATE_WS_URL");
  if (explicit) {
    return explicit;
  }
  const parsed = new URL(resolveApiBaseUrl());
  parsed.protocol = parsed.protocol === "https:" ? "wss:" : "ws:";
  parsed.pathname = "/ws";
  parsed.search = "";
  return parsed.toString();
}

export function resolveKeycloakBaseUrl() {
  return readGlobal("TEMPLATE_KEYCLOAK_BASE_URL") || DEFAULT_KEYCLOAK_BASE_URL;
}

export function resolveKeycloakRealm() {
  return readGlobal("TEMPLATE_KEYCLOAK_REALM") || DEFAULT_KEYCLOAK_REALM;
}

export function resolveClientId(appKind) {
  if (appKind === "admin") {
    return readGlobal("TEMPLATE_ADMIN_CLIENT_ID") || "__ADMIN_CLIENT_ID__";
  }
  return readGlobal("TEMPLATE_WEBAPP_CLIENT_ID") || "__WEBAPP_CLIENT_ID__";
}

