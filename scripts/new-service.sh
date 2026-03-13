#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Uso:
  ./scripts/new-service.sh <service-name> [opcoes]

Opcoes:
  --port <numero>                Porta HTTP do servico (default: 8080)
  --module-prefix <path>         Prefixo do modulo Go (default: github.com/example/project/src/services)
  --image-repo-prefix <repo>     Prefixo do repositorio de imagem (default: ghcr.io/example)
  --gitops-env <env>             Overlay padrao ArgoCD (default: dev)
  --namespace <namespace>        Namespace Kubernetes alvo (default: inferido do api-gateway)
  --argocd-namespace <namespace> Namespace do ArgoCD (default: inferido de argocd-applications.yaml)

Exemplo:
  ./scripts/new-service.sh billing --port 8091 \
    --module-prefix github.com/acme/platform/src/services \
    --image-repo-prefix ghcr.io/acme/platform
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

SERVICE_NAME="$1"
shift

PORT="8080"
MODULE_PREFIX="github.com/example/project/src/services"
IMAGE_REPO_PREFIX="ghcr.io/example"
GITOPS_ENV="${GITOPS_ENV:-dev}"
NAMESPACE=""
ARGOCD_NAMESPACE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      PORT="$2"
      shift 2
      ;;
    --module-prefix)
      MODULE_PREFIX="$2"
      shift 2
      ;;
    --image-repo-prefix)
      IMAGE_REPO_PREFIX="$2"
      shift 2
      ;;
    --gitops-env)
      GITOPS_ENV="$2"
      shift 2
      ;;
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --argocd-namespace)
      ARGOCD_NAMESPACE="$2"
      shift 2
      ;;
    *)
      echo "Opcao invalida: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ ! "${SERVICE_NAME}" =~ ^[a-z][a-z0-9-]+$ ]]; then
  echo "service-name invalido. Use apenas minusculas, numeros e hifen."
  exit 1
fi

if [[ ! "${PORT}" =~ ^[0-9]+$ ]]; then
  echo "porta invalida: ${PORT}"
  exit 1
fi

if [[ ! "${GITOPS_ENV}" =~ ^(dev|hml|prd)$ ]]; then
  echo "gitops-env invalido: ${GITOPS_ENV} (use dev|hml|prd)"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_DIR="${ROOT_DIR}/src/services/${SERVICE_NAME}"
APP_DIR="${ROOT_DIR}/infra/k8s/gitops/apps/${SERVICE_NAME}"
ARGO_FILE="${ROOT_DIR}/infra/k8s/manifests/argocd-applications.yaml"

if [[ -d "${SERVICE_DIR}" || -d "${APP_DIR}" ]]; then
  echo "Servico ja existe: ${SERVICE_NAME}"
  exit 1
fi

if [[ -z "${NAMESPACE}" ]]; then
  NAMESPACE="$(awk '/^namespace:/ {print $2; exit}' "${ROOT_DIR}/infra/k8s/gitops/apps/api-gateway/base/kustomization.yaml" 2>/dev/null || true)"
fi
if [[ -z "${ARGOCD_NAMESPACE}" ]]; then
  ARGOCD_NAMESPACE="$(awk '/^  namespace:/ {print $2; exit}' "${ARGO_FILE}" 2>/dev/null || true)"
fi

if [[ -z "${NAMESPACE}" || "${NAMESPACE}" == *"__"* ]]; then
  echo "Namespace nao resolvido. Execute primeiro ./scripts/init-template.sh no novo repositorio."
  exit 1
fi
if [[ -z "${ARGOCD_NAMESPACE}" || "${ARGOCD_NAMESPACE}" == *"__"* ]]; then
  echo "Namespace do ArgoCD nao resolvido. Execute primeiro ./scripts/init-template.sh no novo repositorio."
  exit 1
fi

IMAGE_REPO="${IMAGE_REPO_PREFIX}/${SERVICE_NAME}"
MODULE_PATH="${MODULE_PREFIX}/${SERVICE_NAME}"

mkdir -p "${SERVICE_DIR}/cmd/server"
mkdir -p "${APP_DIR}/base" "${APP_DIR}/overlays/dev" "${APP_DIR}/overlays/hml" "${APP_DIR}/overlays/prd"

cat > "${SERVICE_DIR}/go.mod" <<EOF
module ${MODULE_PATH}

go 1.24.5
EOF

cat > "${SERVICE_DIR}/cmd/server/main.go" <<EOF
package main

import (
  "encoding/json"
  "log"
  "net/http"
)

func main() {
  mux := http.NewServeMux()
  mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    _ = json.NewEncoder(w).Encode(map[string]string{"status": "ok", "service": "${SERVICE_NAME}"})
  })
  mux.HandleFunc("/readyz", func(w http.ResponseWriter, _ *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    _ = json.NewEncoder(w).Encode(map[string]string{"status": "ready", "service": "${SERVICE_NAME}"})
  })

  log.Printf("${SERVICE_NAME} listening on :${PORT}")
  if err := http.ListenAndServe(":${PORT}", mux); err != nil {
    log.Fatalf("server failed: %v", err)
  }
}
EOF

cat > "${SERVICE_DIR}/Dockerfile" <<EOF
FROM golang:1.24.5 AS builder
WORKDIR /app
COPY . .
RUN go mod download && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /bin/${SERVICE_NAME} ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /bin/${SERVICE_NAME} /${SERVICE_NAME}
EXPOSE ${PORT}
ENTRYPOINT ["/${SERVICE_NAME}"]
EOF

cat > "${SERVICE_DIR}/Makefile" <<'EOF'
APP_NAME := service

.PHONY: run build test tidy

run:
	go run ./cmd/server

build:
	go build -o bin/$(APP_NAME) ./cmd/server

test:
	go test ./...

tidy:
	go mod tidy
EOF

sed -i.bak "s/APP_NAME := service/APP_NAME := ${SERVICE_NAME}/g" "${SERVICE_DIR}/Makefile"
rm -f "${SERVICE_DIR}/Makefile.bak"

cat > "${SERVICE_DIR}/README.md" <<EOF
# ${SERVICE_NAME}

Servico base gerado automaticamente pelo template.

## Executar local
\`\`\`bash
cd src/services/${SERVICE_NAME}
make run
\`\`\`

## Build e testes
\`\`\`bash
cd src/services/${SERVICE_NAME}
make test
make build
\`\`\`
EOF

cat > "${APP_DIR}/base/deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${SERVICE_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${SERVICE_NAME}
spec:
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: ${SERVICE_NAME}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ${SERVICE_NAME}
    spec:
      serviceAccountName: __PROJECT_SLUG__-workload
      automountServiceAccountToken: false
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: ${SERVICE_NAME}
          image: ${IMAGE_REPO}:latest
          imagePullPolicy: Always
          ports:
            - name: http
              containerPort: ${PORT}
          readinessProbe:
            httpGet:
              path: /readyz
              port: http
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /healthz
              port: http
            initialDelaySeconds: 15
            periodSeconds: 20
          securityContext:
            runAsNonRoot: true
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
EOF

cat > "${APP_DIR}/base/service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${SERVICE_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${SERVICE_NAME}
spec:
  selector:
    app.kubernetes.io/name: ${SERVICE_NAME}
  ports:
    - name: http
      port: 80
      targetPort: ${PORT}
  type: ClusterIP
EOF

cat > "${APP_DIR}/base/pdb.yaml" <<EOF
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: ${SERVICE_NAME}
  namespace: ${NAMESPACE}
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: ${SERVICE_NAME}
EOF

cat > "${APP_DIR}/base/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${NAMESPACE}
resources:
  - deployment.yaml
  - service.yaml
  - pdb.yaml
images:
  - name: ${IMAGE_REPO}
    newTag: latest
EOF

for env in dev hml prd; do
  replicas="1"
  sampler="1.0"
  if [[ "${env}" == "hml" ]]; then
    replicas="2"
    sampler="0.4"
  fi
  if [[ "${env}" == "prd" ]]; then
    replicas="3"
    sampler="0.2"
  fi

  cat > "${APP_DIR}/overlays/${env}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
patches:
  - path: patch-deployment.yaml
EOF

  cat > "${APP_DIR}/overlays/${env}/patch-deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${SERVICE_NAME}
  namespace: ${NAMESPACE}
spec:
  replicas: ${replicas}
  template:
    spec:
      containers:
        - name: ${SERVICE_NAME}
          env:
            - name: OTEL_ENVIRONMENT
              value: ${env}
            - name: OTEL_TRACES_SAMPLER_RATIO
              value: "${sampler}"
EOF
done

if ! grep -q "name: __PROJECT_SLUG__-${SERVICE_NAME}" "${ARGO_FILE}" && ! grep -q "name: ${SERVICE_NAME}" "${ARGO_FILE}"; then
  cat >> "${ARGO_FILE}" <<EOF
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: __PROJECT_SLUG__-${SERVICE_NAME}
  namespace: ${ARGOCD_NAMESPACE}
spec:
  project: default
  source:
    repoURL: __GIT_REPO_URL__
    targetRevision: __GIT_DEFAULT_BRANCH__
    path: infra/k8s/gitops/apps/${SERVICE_NAME}/overlays/${GITOPS_ENV}
  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
fi

echo "Servico criado: ${SERVICE_NAME}"
echo "Diretorio: ${SERVICE_DIR}"
echo "GitOps: ${APP_DIR}"
echo "Proximos passos:"
echo "  1) cd ${SERVICE_DIR} && make tidy && make test"
echo "  2) Ajustar imagem em ${APP_DIR}/base/kustomization.yaml"
echo "  3) Commitar e validar sync ArgoCD para overlay ${GITOPS_ENV}"
