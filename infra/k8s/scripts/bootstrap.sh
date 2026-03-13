#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HELM_BIN="${HELM_BIN:-helm}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-__LETSENCRYPT_EMAIL__}"
DB_BOOTSTRAP_TIMEOUT="${DB_BOOTSTRAP_TIMEOUT:-120s}"
ENABLE_MONITORING_PACK="${ENABLE_MONITORING_PACK:-true}"

if ! command -v "${HELM_BIN}" >/dev/null 2>&1; then
  fallback_helm="${ROOT_DIR}/.tools/helm"
  if [[ -x "${fallback_helm}" ]]; then
    HELM_BIN="${fallback_helm}"
  else
    echo "Helm nao encontrado (${HELM_BIN}) e fallback ${fallback_helm} indisponivel."
    exit 1
  fi
fi

echo "[1/16] Namespaces"
kubectl apply -f "${ROOT_DIR}/infra/k8s/manifests/namespaces.yaml"

echo "[2/16] Secrets"
"${ROOT_DIR}/infra/k8s/scripts/create-secrets.sh"

echo "[3/16] ServiceAccount padrao"
kubectl apply -f "${ROOT_DIR}/infra/k8s/manifests/workload-serviceaccount.yaml"

echo "[4/16] Repos Helm"
"${HELM_BIN}" repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null
"${HELM_BIN}" repo add jetstack https://charts.jetstack.io >/dev/null
"${HELM_BIN}" repo add kong https://charts.konghq.com >/dev/null
"${HELM_BIN}" repo add bitnami https://charts.bitnami.com/bitnami >/dev/null
"${HELM_BIN}" repo add argo https://argoproj.github.io/argo-helm >/dev/null
"${HELM_BIN}" repo update >/dev/null

echo "[5/16] NGINX Ingress"
"${HELM_BIN}" upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --values "${ROOT_DIR}/infra/k8s/values/ingress-nginx.yaml" \
  --wait --timeout 15m

echo "[6/16] cert-manager"
"${HELM_BIN}" upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --values "${ROOT_DIR}/infra/k8s/values/cert-manager.yaml" \
  --wait --timeout 15m

echo "[7/16] ClusterIssuer"
sed "s|\${LETSENCRYPT_EMAIL}|${LETSENCRYPT_EMAIL}|g" \
  "${ROOT_DIR}/infra/k8s/manifests/cluster-issuer-letsencrypt-prod.yaml.tpl" | kubectl apply -f -

echo "[8/16] ArgoCD"
"${HELM_BIN}" upgrade --install argocd argo/argo-cd \
  --namespace __ARGOCD_NAMESPACE__ \
  --values "${ROOT_DIR}/infra/k8s/values/argocd.yaml" \
  --wait --timeout 15m

echo "[9/16] PostgreSQL/Redis/RabbitMQ"
"${HELM_BIN}" upgrade --install postgresql-shared bitnami/postgresql \
  --namespace __K8S_NAMESPACE__ \
  --values "${ROOT_DIR}/infra/k8s/values/postgresql.yaml" \
  --wait --timeout 15m

kubectl apply -f "${ROOT_DIR}/infra/k8s/manifests/postgresql-databases-configmap.yaml"
kubectl -n __K8S_NAMESPACE__ delete job postgresql-databases-bootstrap --ignore-not-found
kubectl apply -f "${ROOT_DIR}/infra/k8s/manifests/postgresql-databases-job.yaml"
kubectl -n __K8S_NAMESPACE__ wait --for=condition=complete job/postgresql-databases-bootstrap --timeout="${DB_BOOTSTRAP_TIMEOUT}" || true

"${HELM_BIN}" upgrade --install redis bitnami/redis \
  --namespace __K8S_NAMESPACE__ \
  --values "${ROOT_DIR}/infra/k8s/values/redis.yaml" \
  --wait --timeout 15m

"${HELM_BIN}" upgrade --install rabbitmq bitnami/rabbitmq \
  --namespace __K8S_NAMESPACE__ \
  --values "${ROOT_DIR}/infra/k8s/values/rabbitmq.yaml" \
  --wait --timeout 15m

echo "[10/16] OpenTelemetry Collector"
kubectl apply -f "${ROOT_DIR}/infra/k8s/manifests/opentelemetry-collector.yaml"
kubectl -n __K8S_NAMESPACE__ rollout status deployment/otel-collector --timeout=10m

echo "[11/16] Keycloak"
kubectl apply -f "${ROOT_DIR}/infra/k8s/manifests/keycloak.yaml"
kubectl -n __K8S_NAMESPACE__ rollout status deployment/keycloak --timeout=15m
"${ROOT_DIR}/infra/k8s/scripts/bootstrap-keycloak-realm.sh" || true

echo "[12/16] Kong"
"${HELM_BIN}" upgrade --install kong kong/kong \
  --namespace kong \
  --values "${ROOT_DIR}/infra/k8s/values/kong.yaml" \
  --wait --timeout 15m
kubectl apply -f "${ROOT_DIR}/infra/k8s/manifests/kong-ingresses.yaml"

echo "[13/16] Web entrypoints"
"${ROOT_DIR}/infra/k8s/scripts/render-web-entrypoints.sh"
kubectl apply -f "${ROOT_DIR}/infra/k8s/manifests/web-entrypoints.yaml"

echo "[14/16] ArgoCD applications"
"${ROOT_DIR}/infra/k8s/scripts/configure-argocd-repo.sh"
kubectl apply -f "${ROOT_DIR}/infra/k8s/manifests/argocd-applications.yaml"

echo "[15/16] Monitoring pack (Prometheus/Grafana)"
if [[ "${ENABLE_MONITORING_PACK}" == "true" ]]; then
  kubectl apply -f "${ROOT_DIR}/infra/k8s/manifests/monitoring-grafana-dashboard-api-gateway.yaml"

  if kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
    kubectl apply -f "${ROOT_DIR}/infra/k8s/manifests/monitoring-servicemonitor-api-gateway.yaml"
  else
    echo "WARNING: CRD ServiceMonitor nao encontrada; pulando manifest de scraping."
  fi

  if kubectl get crd prometheusrules.monitoring.coreos.com >/dev/null 2>&1; then
    kubectl apply -f "${ROOT_DIR}/infra/k8s/manifests/monitoring-prometheus-rules-api-gateway.yaml"
  else
    echo "WARNING: CRD PrometheusRule nao encontrada; pulando manifest de alertas."
  fi
else
  echo "Monitoring pack desabilitado (ENABLE_MONITORING_PACK=${ENABLE_MONITORING_PACK})."
fi

echo "[16/16] Security baseline (NetworkPolicy)"
kubectl apply -f "${ROOT_DIR}/infra/k8s/manifests/security-networkpolicies.yaml"

echo "Bootstrap finalizado."
