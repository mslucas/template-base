#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-__K8S_NAMESPACE__}"
GHCR_PULL_SECRET_NAME="${GHCR_PULL_SECRET_NAME:-ghcr-pull-secret}"
GHCR_PULL_USERNAME="${GHCR_PULL_USERNAME:-__PROJECT_SLUG__-ci}"
GHCR_PULL_EMAIL="${GHCR_PULL_EMAIL:-ci@__PROJECT_SLUG__.local}"
GHCR_PULL_TOKEN="${GHCR_PULL_TOKEN:-}"

resolve_value() {
  local explicit_value="$1"
  local fallback_value="$2"
  if [[ -n "${explicit_value}" ]]; then
    echo "${explicit_value}"
    return
  fi
  echo "${fallback_value}"
}

postgres_admin_password="$(resolve_value "${POSTGRES_ADMIN_PASSWORD:-}" "$(openssl rand -base64 32)")"
postgres_user_password="$(resolve_value "${POSTGRES_USER_PASSWORD:-}" "$(openssl rand -base64 32)")"
redis_password="$(resolve_value "${REDIS_PASSWORD:-}" "$(openssl rand -base64 32)")"
rabbitmq_password="$(resolve_value "${RABBITMQ_PASSWORD:-}" "$(openssl rand -base64 32)")"
rabbitmq_erlang_cookie="$(resolve_value "${RABBITMQ_ERLANG_COOKIE:-}" "$(openssl rand -base64 24 | tr -d '=+/')")"
keycloak_admin_password="$(resolve_value "${KEYCLOAK_ADMIN_PASSWORD:-}" "$(openssl rand -base64 32)")"
litellm_master_key="$(resolve_value "${LITELLM_MASTER_KEY:-}" "sk-$(openssl rand -hex 24)")"
litellm_salt_key="$(resolve_value "${LITELLM_SALT_KEY:-}" "$(openssl rand -hex 32)")"
openai_api_key="$(resolve_value "${OPENAI_API_KEY:-}" "sk-placeholder-change-me")"

kubectl -n "${NAMESPACE}" create secret generic postgresql-auth \
  --from-literal=postgres-password="${postgres_admin_password}" \
  --from-literal=password="${postgres_user_password}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" create secret generic redis-auth \
  --from-literal=redis-password="${redis_password}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" create secret generic rabbitmq-auth \
  --from-literal=rabbitmq-password="${rabbitmq_password}" \
  --from-literal=rabbitmq-erlang-cookie="${rabbitmq_erlang_cookie}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" create secret generic keycloak-admin-secret \
  --from-literal=admin-password="${keycloak_admin_password}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" create secret generic litellm-auth \
  --from-literal=LITELLM_MASTER_KEY="${litellm_master_key}" \
  --from-literal=LITELLM_SALT_KEY="${litellm_salt_key}" \
  --from-literal=OPENAI_API_KEY="${openai_api_key}" \
  --dry-run=client -o yaml | kubectl apply -f -

if [[ -n "${GHCR_PULL_TOKEN}" ]]; then
  kubectl -n "${NAMESPACE}" create secret docker-registry "${GHCR_PULL_SECRET_NAME}" \
    --docker-server=ghcr.io \
    --docker-username="${GHCR_PULL_USERNAME}" \
    --docker-password="${GHCR_PULL_TOKEN}" \
    --docker-email="${GHCR_PULL_EMAIL}" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

echo "Secrets aplicados em ${NAMESPACE}."
