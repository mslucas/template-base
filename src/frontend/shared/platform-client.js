import { resolveApiBaseUrl, resolveWebSocketUrl } from "./runtime-config.js";

export async function fetchPlatformMeta({ signal } = {}) {
  const baseUrl = resolveApiBaseUrl();
  const response = await fetch(`${baseUrl}/api/v1/platform/meta`, {
    signal,
    headers: { Accept: "application/json" },
  });
  if (!response.ok) {
    throw new Error(`platform meta request failed (${response.status})`);
  }
  const payload = await response.json();
  return { baseUrl, payload };
}

export async function fetchSecureTemplateData({ accessToken, signal } = {}) {
  const baseUrl = resolveApiBaseUrl();
  const response = await fetch(`${baseUrl}/api/v1/template/secure`, {
    signal,
    headers: {
      Accept: "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
  });
  if (!response.ok) {
    throw new Error(`secure endpoint request failed (${response.status})`);
  }
  return response.json();
}

export function probeWebSocket({ timeoutMs = 4000 } = {}) {
  const wsUrl = resolveWebSocketUrl();
  return new Promise((resolve, reject) => {
    const startedAt = Date.now();
    const socket = new WebSocket(wsUrl);
    const timeout = window.setTimeout(() => {
      socket.close();
      reject(new Error("websocket timeout"));
    }, timeoutMs);

    socket.onopen = () => socket.send("tpl:ping");
    socket.onmessage = () => {
      window.clearTimeout(timeout);
      socket.close();
      resolve({ latencyMs: Date.now() - startedAt, wsUrl });
    };
    socket.onerror = () => {
      window.clearTimeout(timeout);
      reject(new Error("websocket probe failed"));
    };
  });
}
