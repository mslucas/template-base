#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Uso: $0 <arquivo_env>"
  echo "Exemplo: $0 .env.template"
  exit 1
fi

ENV_FILE="$1"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Arquivo nao encontrado: ${ENV_FILE}"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

set -a
source "${ENV_FILE}"
set +a

required_vars=(
  PROJECT_SLUG
  K8S_NAMESPACE
  HOST_APP
  HOST_ADMIN
  HOST_API
  HOST_WEBHOOK
  HOST_SSO
  HOST_MQ
  HOST_KONG_ADMIN
  HOST_KONG_MANAGER
  HOST_ARGOCD
  LETSENCRYPT_EMAIL
  API_IMAGE_REPO
  GIT_REPO_URL
  GIT_DEFAULT_BRANCH
  GITOPS_ENV
  KEYCLOAK_REALM
  WEBAPP_CLIENT_ID
  ADMIN_CLIENT_ID
  DEFAULT_TIMEZONE
  OTEL_BACKEND_OTLP_ENDPOINT
  OTEL_BACKEND_OTLP_INSECURE
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "Variavel obrigatoria ausente: ${var_name}"
    exit 1
  fi
done

replace() {
  local key="$1"
  local value="$2"
  local escaped
  escaped="$(printf '%s' "${value}" | sed 's/[\/&]/\\&/g')"
  printf 's|__%s__|%s|g\n' "${key}" "${escaped}" >> "${sed_script}"
}

sed_script="$(mktemp)"
trap 'rm -f "${sed_script}"' EXIT

replace "PROJECT_SLUG" "${PROJECT_SLUG}"
replace "K8S_NAMESPACE" "${K8S_NAMESPACE}"
replace "ARGOCD_NAMESPACE" "${ARGOCD_NAMESPACE:-argocd}"
replace "HOST_APP" "${HOST_APP}"
replace "HOST_ADMIN" "${HOST_ADMIN}"
replace "HOST_API" "${HOST_API}"
replace "HOST_WEBHOOK" "${HOST_WEBHOOK}"
replace "HOST_SSO" "${HOST_SSO}"
replace "HOST_MQ" "${HOST_MQ}"
replace "HOST_KONG_ADMIN" "${HOST_KONG_ADMIN}"
replace "HOST_KONG_MANAGER" "${HOST_KONG_MANAGER}"
replace "HOST_ARGOCD" "${HOST_ARGOCD}"
replace "LETSENCRYPT_EMAIL" "${LETSENCRYPT_EMAIL}"
replace "API_IMAGE_REPO" "${API_IMAGE_REPO}"
replace "GIT_REPO_URL" "${GIT_REPO_URL}"
replace "GIT_DEFAULT_BRANCH" "${GIT_DEFAULT_BRANCH}"
replace "GITOPS_ENV" "${GITOPS_ENV}"
replace "KEYCLOAK_REALM" "${KEYCLOAK_REALM}"
replace "KEYCLOAK_ADMIN_USERNAME" "${KEYCLOAK_ADMIN_USERNAME:-admin}"
replace "WEBAPP_CLIENT_ID" "${WEBAPP_CLIENT_ID}"
replace "ADMIN_CLIENT_ID" "${ADMIN_CLIENT_ID}"
replace "DEFAULT_TIMEZONE" "${DEFAULT_TIMEZONE}"
replace "OTEL_BACKEND_OTLP_ENDPOINT" "${OTEL_BACKEND_OTLP_ENDPOINT}"
replace "OTEL_BACKEND_OTLP_INSECURE" "${OTEL_BACKEND_OTLP_INSECURE}"

while IFS= read -r file_path; do
  sed -i.bak -f "${sed_script}" "${file_path}"
done < <(
  find "${ROOT_DIR}" -type f \
    ! -path "${ROOT_DIR}/scripts/init-template.sh" \
    ! -path "${ROOT_DIR}/template.env.example"
)

find "${ROOT_DIR}" -type f -name "*.bak" -delete

echo "Template inicializado com sucesso."
echo "Revise os arquivos gerados antes do primeiro commit no novo repositorio."
