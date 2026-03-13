import { resolveClientId, resolveKeycloakBaseUrl, resolveKeycloakRealm } from "./runtime-config.js";

const WELL_KNOWN_CACHE = new Map();
const STORAGE_PREFIX = "template.auth";

function sessionStorageKey(clientId) {
  return `${STORAGE_PREFIX}.session.${clientId}`;
}

function txStorageKey(clientId) {
  return `${STORAGE_PREFIX}.tx.${clientId}`;
}

function nowEpochSeconds() {
  return Math.floor(Date.now() / 1000);
}

function base64UrlEncode(byteArray) {
  const binary = String.fromCharCode(...byteArray);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function base64UrlDecodeToString(input) {
  const normalized = input.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  return atob(padded);
}

function randomString(byteSize = 32) {
  const bytes = new Uint8Array(byteSize);
  window.crypto.getRandomValues(bytes);
  return base64UrlEncode(bytes);
}

async function sha256Base64Url(value) {
  const encoder = new TextEncoder();
  const buffer = encoder.encode(value);
  const digest = await window.crypto.subtle.digest("SHA-256", buffer);
  return base64UrlEncode(new Uint8Array(digest));
}

async function fetchWellKnown() {
  const baseUrl = resolveKeycloakBaseUrl();
  const realm = resolveKeycloakRealm();
  const cacheKey = `${baseUrl}|${realm}`;

  if (WELL_KNOWN_CACHE.has(cacheKey)) {
    return WELL_KNOWN_CACHE.get(cacheKey);
  }

  const response = await fetch(`${baseUrl}/realms/${realm}/.well-known/openid-configuration`, {
    method: "GET",
    headers: {
      Accept: "application/json",
    },
  });

  if (!response.ok) {
    throw new Error(`oidc discovery failed (${response.status})`);
  }

  const payload = await response.json();
  WELL_KNOWN_CACHE.set(cacheKey, payload);
  return payload;
}

export function decodeJwtPayload(token) {
  if (!token || typeof token !== "string") {
    return null;
  }
  const pieces = token.split(".");
  if (pieces.length < 2) {
    return null;
  }

  try {
    const payload = base64UrlDecodeToString(pieces[1]);
    return JSON.parse(payload);
  } catch {
    return null;
  }
}

export function getActiveSession({ appKind }) {
  const clientId = resolveClientId(appKind);
  const raw = window.sessionStorage.getItem(sessionStorageKey(clientId));
  if (!raw) {
    return null;
  }

  try {
    const parsed = JSON.parse(raw);
    if (!parsed || !parsed.access_token || !parsed.expires_at) {
      return null;
    }

    if (parsed.expires_at <= nowEpochSeconds() + 15) {
      window.sessionStorage.removeItem(sessionStorageKey(clientId));
      return null;
    }

    return parsed;
  } catch {
    window.sessionStorage.removeItem(sessionStorageKey(clientId));
    return null;
  }
}

export function getAuthenticatedUser({ appKind }) {
  const session = getActiveSession({ appKind });
  if (!session) {
    return null;
  }

  const claims = decodeJwtPayload(session.id_token) || decodeJwtPayload(session.access_token) || {};
  const realmRoles = claims?.realm_access?.roles || [];

  return {
    username: claims.preferred_username || claims.email || "usuario",
    name: claims.name || claims.given_name || "",
    email: claims.email || "",
    roles: Array.isArray(realmRoles) ? realmRoles : [],
    accessToken: session.access_token,
    expiresAt: session.expires_at,
  };
}

export async function startLoginFlow({ appKind }) {
  const clientId = resolveClientId(appKind);
  const redirectUri = `${window.location.origin}${window.location.pathname}`;

  const verifier = randomString(64);
  const challenge = await sha256Base64Url(verifier);
  const state = randomString(24);
  const nonce = randomString(24);

  window.sessionStorage.setItem(
    txStorageKey(clientId),
    JSON.stringify({
      verifier,
      state,
      nonce,
      redirectUri,
      appKind,
      created_at: nowEpochSeconds(),
    }),
  );

  const discovery = await fetchWellKnown();
  const url = new URL(discovery.authorization_endpoint);
  url.searchParams.set("client_id", clientId);
  url.searchParams.set("redirect_uri", redirectUri);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("scope", "openid profile email");
  url.searchParams.set("state", state);
  url.searchParams.set("nonce", nonce);
  url.searchParams.set("code_challenge", challenge);
  url.searchParams.set("code_challenge_method", "S256");

  window.location.assign(url.toString());
}

export async function handleLoginCallback({ appKind }) {
  const clientId = resolveClientId(appKind);
  const current = new URL(window.location.href);
  const code = current.searchParams.get("code");
  const state = current.searchParams.get("state");
  const error = current.searchParams.get("error");

  if (error) {
    throw new Error(`oidc callback error: ${error}`);
  }

  if (!code || !state) {
    return false;
  }

  const txRaw = window.sessionStorage.getItem(txStorageKey(clientId));
  if (!txRaw) {
    throw new Error("oidc transaction not found");
  }

  let tx;
  try {
    tx = JSON.parse(txRaw);
  } catch {
    throw new Error("oidc transaction invalid");
  }

  if (!tx || tx.state !== state || !tx.verifier || !tx.redirectUri) {
    throw new Error("oidc state mismatch");
  }

  const discovery = await fetchWellKnown();
  const tokenResponse = await fetch(discovery.token_endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json",
    },
    body: new URLSearchParams({
      grant_type: "authorization_code",
      client_id: clientId,
      code,
      redirect_uri: tx.redirectUri,
      code_verifier: tx.verifier,
    }).toString(),
  });

  if (!tokenResponse.ok) {
    const body = await tokenResponse.text();
    throw new Error(`token exchange failed (${tokenResponse.status}): ${body}`);
  }

  const tokenPayload = await tokenResponse.json();
  const expiresIn = Number(tokenPayload.expires_in || 0);

  const session = {
    access_token: tokenPayload.access_token,
    id_token: tokenPayload.id_token,
    refresh_token: tokenPayload.refresh_token,
    token_type: tokenPayload.token_type,
    scope: tokenPayload.scope,
    issued_at: nowEpochSeconds(),
    expires_at: nowEpochSeconds() + Math.max(expiresIn, 60),
  };

  window.sessionStorage.setItem(sessionStorageKey(clientId), JSON.stringify(session));
  window.sessionStorage.removeItem(txStorageKey(clientId));

  window.history.replaceState({}, document.title, tx.redirectUri);
  return true;
}

export async function logoutFromKeycloak({ appKind }) {
  const clientId = resolveClientId(appKind);
  const session = getActiveSession({ appKind });
  const redirectUri = `${window.location.origin}${window.location.pathname}`;

  window.sessionStorage.removeItem(sessionStorageKey(clientId));
  window.sessionStorage.removeItem(txStorageKey(clientId));

  if (!session?.id_token) {
    window.location.assign(redirectUri);
    return;
  }

  try {
    const discovery = await fetchWellKnown();
    const endpoint = discovery.end_session_endpoint;
    if (!endpoint) {
      window.location.assign(redirectUri);
      return;
    }

    const logoutUrl = new URL(endpoint);
    logoutUrl.searchParams.set("id_token_hint", session.id_token);
    logoutUrl.searchParams.set("post_logout_redirect_uri", redirectUri);
    logoutUrl.searchParams.set("client_id", clientId);
    window.location.assign(logoutUrl.toString());
  } catch {
    window.location.assign(redirectUri);
  }
}
