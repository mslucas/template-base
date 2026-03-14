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

echo "[1/19] Namespaces"
kubectl apply -f "${ROOT_DIR}/infra/k8s/manifests/namespaces.yaml"

echo "[2/19] Secrets"
"${ROOT_DIR}/infra/k8s/scripts/create-secrets.sh"

echo "[3/19] ServiceAccount padrao"
kubectl apply -f "${ROOT_DIR}/infra/k8s/manifests/workload-serviceaccount.yaml"

echo "[4/19] Repos Helm"
"${HELM_BIN}" repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null
"${HELM_BIN}" repo add jetstack https://charts.jetstack.io >/dev/null
"${HELM_BIN}" repo add emqx https://repos.emqx.io/charts >/dev/null
"${HELM_BIN}" repo add kong https://charts.konghq.com >/dev/null
"${HELM_BIN}" repo add bitnami https://charts.bitnami.com/bitnami >/dev/null
"${HELM_BIN}" repo add argo https://argoproj.github.io/argo-helm >/dev/null
"${HELM_BIN}" repo update >/dev/null

echo "[5/19] NGINX Ingress"
"${HELM_BIN}" upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --values "${ROOT_DIR}/infra/k8s/values/ingress-nginx.yaml" \
  --wait --timeout 15m

echo "[6/19] cert-manager"
"${HELM_BIN}" upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --values "${ROOT_DIR}/infra/k8s/values/cert-manager.yaml" \
  --wait --timeout 15m

echo "[7/19] ClusterIssuer"
sed "s|\${LETSENCRYPT_EMAIL}|${LETSENCRYPT_EMAIL}|g" \
  "${ROOT_DIR}/infra/k8s/manifests/cluster-issuer-letsencrypt-prod.yaml.tpl" | kubectl apply -f -

echo "[8/19] EMQX Operator"
"${HELM_BIN}" upgrade --install emqx-operator emqx/emqx-operator \
  --namespace emqx-operator-system \
  --create-namespace \
  --wait --timeout 15m
kubectl -n emqx-operator-system rollout status deployment/emqx-operator-controller-manager --timeout=10m || \
  kubectl -n emqx-operator-system wait --for=condition=Ready pod -l control-plane=controller-manager --timeout=10m

echo "[9/19] ArgoCD"
"${HELM_BIN}" upgrade --install argocd argo/argo-cd \
  --namespace __ARGOCD_NAMESPACE__ \
  --values "${ROOT_DIR}/infra/k8s/values/argocd.yaml" \
  --wait --timeout 15m

echo "[10/19] PostgreSQL/Redis/RabbitMQ"
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

echo "[11/19] OpenTelemetry Collector"
kubectl apply -f "${ROOT_DIR}/infra/k8s/manifests/opentelemetry-collector.yaml"
kubectl -n __K8S_NAMESPACE__ rollout status deployment/otel-collector --timeout=10m

echo "[12/19] Keycloak"
kubectl apply -f "${ROOT_DIR}/infra/k8s/manifests/keycloak.yaml"
kubectl -n __K8S_NAMESPACE__ rollout status deployment/keycloak --timeout=15m
"${ROOT_DIR}/infra/k8s/scripts/bootstrap-keycloak-realm.sh" || true

echo "[13/19] LiteLLM AI Gateway"
kubectl apply -f "${ROOT_DIR}/infra/k8s/manifests/litellm.yaml"
kubectl -n __K8S_NAMESPACE__ rollout status deployment/litellm --timeout=10m

echo "[14/19] EMQX MQTT Broker"
kubectl apply -f "${ROOT_DIR}/infra/k8s/manifests/emqx.yaml"
kubectl -n __K8S_NAMESPACE__ wait --for=jsonpath='{.spec.clusterIP}' service/emqx-dashboard --timeout=10m
kubectl -n __K8S_NAMESPACE__ wait --for=jsonpath='{.spec.clusterIP}' service/emqx-listeners --timeout=10m

echo "[15/19] Kong"
"${HELM_BIN}" upgrade --install kong kong/kong \
  --namespace kong \
  --values "${ROOT_DIR}/infra/k8s/values/kong.yaml" \
  --wait --timeout 15m
kubectl apply -f "${ROOT_DIR}/infra/k8s/manifests/kong-ingresses.yaml"

echo "[16/19] Web entrypoints"
"${ROOT_DIR}/infra/k8s/scripts/render-web-entrypoints.sh"
kubectl apply -f "${ROOT_DIR}/infra/k8s/manifests/web-entrypoints.yaml"

echo "[17/19] ArgoCD applications"
"${ROOT_DIR}/infra/k8s/scripts/configure-argocd-repo.sh"
kubectl apply -f "${ROOT_DIR}/infra/k8s/manifests/argocd-applications.yaml"

echo "[18/19] Monitoring pack (Prometheus/Grafana)"
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

echo "[19/19] Security baseline (NetworkPolicy)"
kubectl apply -f "${ROOT_DIR}/infra/k8s/manifests/security-networkpolicies.yaml"

echo "Bootstrap finalizado."
