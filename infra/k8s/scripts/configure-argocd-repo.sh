#!/usr/bin/env bash
set -euo pipefail

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-__ARGOCD_NAMESPACE__}"
ARGOCD_REPO_URL="${ARGOCD_REPO_URL:-__GIT_REPO_URL__}"
ARGOCD_REPO_SECRET_NAME="${ARGOCD_REPO_SECRET_NAME:-argocd-repo-__PROJECT_SLUG__}"
ARGOCD_REPO_USERNAME="${ARGOCD_REPO_USERNAME:-x-access-token}"
ARGOCD_REPO_TOKEN="${ARGOCD_REPO_TOKEN:-}"

if [[ -z "${ARGOCD_REPO_TOKEN}" ]]; then
  echo "WARNING: ARGOCD_REPO_TOKEN nao informado; sync pode falhar em repositorio privado."
  exit 0
fi

kubectl -n "${ARGOCD_NAMESPACE}" create secret generic "${ARGOCD_REPO_SECRET_NAME}" \
  --from-literal=type=git \
  --from-literal=url="${ARGOCD_REPO_URL}" \
  --from-literal=username="${ARGOCD_REPO_USERNAME}" \
  --from-literal=password="${ARGOCD_REPO_TOKEN}" \
  --dry-run=client -o yaml | \
  kubectl label --local -f - argocd.argoproj.io/secret-type=repository --overwrite -o yaml | \
  kubectl apply -f -

echo "Secret de repositorio ArgoCD aplicado: ${ARGOCD_NAMESPACE}/${ARGOCD_REPO_SECRET_NAME}"

