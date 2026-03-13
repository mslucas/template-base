#!/usr/bin/env bash
set -euo pipefail

KEYCLOAK_BASE_URL="${KEYCLOAK_BASE_URL:-https://__HOST_SSO__}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-__KEYCLOAK_REALM__}"
KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-__K8S_NAMESPACE__}"
KEYCLOAK_ADMIN_USERNAME="${KEYCLOAK_ADMIN_USERNAME:-__KEYCLOAK_ADMIN_USERNAME__}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-}"
WEBAPP_CLIENT_ID="${WEBAPP_CLIENT_ID:-__WEBAPP_CLIENT_ID__}"
ADMIN_CLIENT_ID="${ADMIN_CLIENT_ID:-__ADMIN_CLIENT_ID__}"
KEYCLOAK_THEME="${KEYCLOAK_THEME:-__PROJECT_SLUG__-material}"

if [[ -z "${KEYCLOAK_ADMIN_PASSWORD}" ]]; then
  KEYCLOAK_ADMIN_PASSWORD="$(kubectl -n "${KEYCLOAK_NAMESPACE}" get secret keycloak-admin-secret -o jsonpath='{.data.admin-password}' | base64 -d)"
fi

ACCESS_TOKEN="$(curl -sS -X POST "${KEYCLOAK_BASE_URL}/realms/master/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "grant_type=password" \
  --data-urlencode "client_id=admin-cli" \
  --data-urlencode "username=${KEYCLOAK_ADMIN_USERNAME}" \
  --data-urlencode "password=${KEYCLOAK_ADMIN_PASSWORD}" \
  | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')"

if [[ -z "${ACCESS_TOKEN}" ]]; then
  echo "Falha ao obter token admin do Keycloak."
  exit 1
fi

kc_get_code() {
  local path="$1"
  curl -sS -o /tmp/kc-body.json -w '%{http_code}' \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "${KEYCLOAK_BASE_URL}${path}"
}

kc_post() {
  local path="$1"
  local payload="$2"
  curl -sS -o /tmp/kc-body.json -w '%{http_code}' \
    -X POST \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H 'Content-Type: application/json' \
    "${KEYCLOAK_BASE_URL}${path}" \
    -d "${payload}"
}

kc_put() {
  local path="$1"
  local payload="$2"
  curl -sS -o /tmp/kc-body.json -w '%{http_code}' \
    -X PUT \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H 'Content-Type: application/json' \
    "${KEYCLOAK_BASE_URL}${path}" \
    -d "${payload}"
}

find_client_uuid() {
  local client_id="$1"
  local response
  response="$(curl -sS \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/clients?clientId=${client_id}")"
  printf '%s' "${response}" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -n1
}

ensure_realm() {
  local payload
  payload="$(cat <<JSON
{
  "realm": "${KEYCLOAK_REALM}",
  "enabled": true,
  "registrationAllowed": false,
  "loginWithEmailAllowed": true,
  "bruteForceProtected": true,
  "loginTheme": "${KEYCLOAK_THEME}",
  "accountTheme": "${KEYCLOAK_THEME}"
}
JSON
)"

  local code
  code="$(kc_get_code "/admin/realms/${KEYCLOAK_REALM}")"
  if [[ "${code}" != "200" && "${code}" != "404" ]]; then
    echo "Falha ao consultar realm (${code}): $(cat /tmp/kc-body.json)" >&2
    exit 1
  fi

  if [[ "${code}" == "404" ]]; then
    code="$(kc_post "/admin/realms" "${payload}")"
    if [[ "${code}" != "201" ]]; then
      echo "Falha ao criar realm (${code}): $(cat /tmp/kc-body.json)" >&2
      exit 1
    fi
  fi

  code="$(kc_put "/admin/realms/${KEYCLOAK_REALM}" "${payload}")"
  if [[ "${code}" != "204" ]]; then
    echo "Falha ao atualizar configuracoes do realm (${code}): $(cat /tmp/kc-body.json)" >&2
    exit 1
  fi
}

ensure_realm_role() {
  local role_name="$1"
  local code
  code="$(kc_get_code "/admin/realms/${KEYCLOAK_REALM}/roles/${role_name}")"
  if [[ "${code}" == "200" ]]; then
    return
  fi

  local payload
  payload="$(cat <<JSON
{
  "name": "${role_name}",
  "description": "${role_name} role"
}
JSON
)"

  code="$(kc_post "/admin/realms/${KEYCLOAK_REALM}/roles" "${payload}")"
  if [[ "${code}" != "201" ]]; then
    echo "Falha ao criar role ${role_name} (${code}): $(cat /tmp/kc-body.json)" >&2
    exit 1
  fi
}

ensure_client() {
  local client_id="$1"

  local payload
  payload="$(cat <<JSON
{
  "clientId": "${client_id}",
  "enabled": true,
  "protocol": "openid-connect",
  "publicClient": true,
  "standardFlowEnabled": true,
  "directAccessGrantsEnabled": false,
  "serviceAccountsEnabled": false,
  "frontchannelLogout": true,
  "fullScopeAllowed": true,
  "redirectUris": [
    "https://__HOST_APP__/*",
    "https://__HOST_ADMIN__/*",
    "http://localhost:4173/*",
    "http://127.0.0.1:4173/*"
  ],
  "webOrigins": [
    "https://__HOST_APP__",
    "https://__HOST_ADMIN__",
    "http://localhost:4173",
    "http://127.0.0.1:4173"
  ],
  "attributes": {
    "pkce.code.challenge.method": "S256"
  }
}
JSON
)"

  local existing_uuid
  existing_uuid="$(find_client_uuid "${client_id}")"

  local code
  if [[ -z "${existing_uuid}" ]]; then
    code="$(kc_post "/admin/realms/${KEYCLOAK_REALM}/clients" "${payload}")"
    if [[ "${code}" != "201" ]]; then
      echo "Falha ao criar client ${client_id} (${code}): $(cat /tmp/kc-body.json)" >&2
      exit 1
    fi
    return
  fi

  code="$(kc_put "/admin/realms/${KEYCLOAK_REALM}/clients/${existing_uuid}" "${payload}")"
  if [[ "${code}" != "204" ]]; then
    echo "Falha ao atualizar client ${client_id} (${code}): $(cat /tmp/kc-body.json)" >&2
    exit 1
  fi
}

ensure_realm

ensure_realm_role "contractor_user"
ensure_realm_role "provider_user"
ensure_realm_role "platform_admin"
ensure_realm_role "platform_support"

ensure_client "${WEBAPP_CLIENT_ID}"
ensure_client "${ADMIN_CLIENT_ID}"

echo "Bootstrap Keycloak concluido para realm ${KEYCLOAK_REALM} (theme=${KEYCLOAK_THEME})."
