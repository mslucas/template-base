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

mkdir -p "${SERVICE_DIR}/cmd/server" "${SERVICE_DIR}/internal/eda"
mkdir -p "${APP_DIR}/base" "${APP_DIR}/overlays/dev" "${APP_DIR}/overlays/hml" "${APP_DIR}/overlays/prd"

cat > "${SERVICE_DIR}/go.mod" <<EOF
module ${MODULE_PATH}

go 1.24.5
EOF

cat > "${SERVICE_DIR}/internal/eda/contracts.go" <<EOF
package eda

import (
  "context"
  "encoding/json"
  "time"
)

type Event struct {
  Type       string          \`json:"type"\`
  RoutingKey string          \`json:"routing_key"\`
  Payload    json.RawMessage \`json:"payload"\`
  Timestamp  time.Time       \`json:"timestamp"\`
}

type Handler func(context.Context, Event) error

type Producer interface {
  Publish(context.Context, Event) error
}

type Consumer interface {
  Start(context.Context, Handler) error
}
EOF

cat > "${SERVICE_DIR}/internal/eda/noop.go" <<EOF
package eda

import "context"

type NoopProducer struct{}

func NewNoopProducer() *NoopProducer {
  return &NoopProducer{}
}

func (*NoopProducer) Publish(context.Context, Event) error {
  return nil
}

type NoopConsumer struct{}

func NewNoopConsumer() *NoopConsumer {
  return &NoopConsumer{}
}

func (*NoopConsumer) Start(ctx context.Context, _ Handler) error {
  <-ctx.Done()
  return nil
}
EOF

cat > "${SERVICE_DIR}/cmd/server/main.go" <<EOF
package main

import (
  "context"
  "bytes"
  "encoding/json"
  "errors"
  "fmt"
  "io"
  "log"
  "net/http"
  "os"
  "os/signal"
  "strings"
  "syscall"
  "time"

  "${MODULE_PATH}/internal/eda"
)

type publishRequest struct {
  EventType  string          \`json:"event_type"\`
  RoutingKey string          \`json:"routing_key,omitempty"\`
  Payload    json.RawMessage \`json:"payload"\`
}

func main() {
  logger := log.New(os.Stdout, "", log.LstdFlags|log.LUTC)
  producer := eda.NewNoopProducer()
  consumer := eda.NewNoopConsumer()

  lifecycleCtx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
  defer stop()

  go func() {
    _ = consumer.Start(lifecycleCtx, func(_ context.Context, event eda.Event) error {
      logger.Printf("eda_event_consumed type=%s routing_key=%s", event.Type, event.RoutingKey)
      return nil
    })
  }()

  mux := http.NewServeMux()
  mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    _ = json.NewEncoder(w).Encode(map[string]string{"status": "ok", "service": "${SERVICE_NAME}"})
  })
  mux.HandleFunc("/readyz", func(w http.ResponseWriter, _ *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    _ = json.NewEncoder(w).Encode(map[string]string{"status": "ready", "service": "${SERVICE_NAME}"})
  })

  mux.HandleFunc("/api/v1/events/publish", func(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
      http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
      return
    }

    body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 1<<20))
    if err != nil {
      http.Error(w, "invalid request body", http.StatusBadRequest)
      return
    }

    var req publishRequest
    if err := json.Unmarshal(body, &req); err != nil {
      http.Error(w, "invalid request body", http.StatusBadRequest)
      return
    }
    if strings.TrimSpace(req.EventType) == "" {
      http.Error(w, "event_type is required", http.StatusBadRequest)
      return
    }
    if len(bytes.TrimSpace(req.Payload)) == 0 {
      req.Payload = json.RawMessage(\`{}\`)
    }

    routingKey := strings.TrimSpace(req.RoutingKey)
    if routingKey == "" {
      routingKey = fmt.Sprintf("platform.${SERVICE_NAME}.%s", normalizeRoutingToken(req.EventType))
    }

    err = producer.Publish(r.Context(), eda.Event{
      Type:       strings.TrimSpace(req.EventType),
      RoutingKey: routingKey,
      Payload:    req.Payload,
      Timestamp:  time.Now().UTC(),
    })
    if err != nil {
      http.Error(w, "failed to publish event", http.StatusBadGateway)
      return
    }

    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(http.StatusAccepted)
    _ = json.NewEncoder(w).Encode(map[string]string{
      "status": "accepted",
      "routing_key": routingKey,
    })
  })

  server := &http.Server{
    Addr:              ":${PORT}",
    Handler:           mux,
    ReadHeaderTimeout: 10 * time.Second,
  }

  go func() {
    <-lifecycleCtx.Done()
    shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()
    _ = server.Shutdown(shutdownCtx)
  }()

  logger.Printf("${SERVICE_NAME} listening on :${PORT}")
  if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
    logger.Fatalf("server failed: %v", err)
  }
}

func normalizeRoutingToken(value string) string {
  token := strings.ToLower(strings.TrimSpace(value))
  token = strings.ReplaceAll(token, " ", ".")
  token = strings.ReplaceAll(token, "/", ".")
  token = strings.ReplaceAll(token, ":", ".")
  token = strings.ReplaceAll(token, "-", ".")
  token = strings.Trim(token, ".")
  if token == "" {
    return "event"
  }
  return token
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

Servico base gerado automaticamente pelo template, com camada EDA pronta para producer/consumer.

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

## Endpoints tecnicos
- \`GET /healthz\`
- \`GET /readyz\`
- \`POST /api/v1/events/publish\`
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
          env:
            - name: EDA_ENABLED
              value: "true"
            - name: EDA_EXCHANGE
              value: __PROJECT_SLUG__.events
            - name: EDA_ROUTING_KEY_BASE
              value: platform.${SERVICE_NAME}
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
