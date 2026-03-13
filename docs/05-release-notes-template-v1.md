# Release Notes - template-v1

Data: 2026-03-10  
Tag Git: `template-v1`

## Escopo fechado
- Arquitetura tecnica neutra de negocio.
- Infra base Kubernetes (Microk8s) com bootstrap automatizado.
- Stack padrao: NGINX Ingress, cert-manager, Kong, ArgoCD, PostgreSQL, Redis, RabbitMQ, Keycloak e OpenTelemetry Collector.
- GitOps com base unica e overlays por ambiente (`dev/hml/prd`) via Kustomize.
- Frontend base `webapp/admin` em runtime ESM.
- Backend base `api-gateway` em Go com:
  - `/healthz`
  - `/readyz`
  - `/api/v1/platform/meta`
  - `/swagger/openapi.yaml`
  - `/metrics`
  - `/ws`
  - `/api/v1/template/secure` (JWT/JWKS + RBAC)
- Camada de observabilidade:
  - instrumentacao OpenTelemetry no `api-gateway` (middleware HTTP);
  - logs HTTP com correlacao por `trace_id` e `span_id`;
  - exportacao OTLP para `otel-collector` interno;
  - collector preparado para receber OTLP gRPC (`4317`) e OTLP HTTP (`4318`) e encaminhar para backend OTLP (ex.: Tempo).
- Pack de monitoramento:
  - `ServiceMonitor` para scraping do `api-gateway`;
  - `PrometheusRule` com alertas SLO (availability/latency/error budget);
  - dashboard Grafana (`API Gateway SLO`) via ConfigMap.
- Baseline de seguranca Kubernetes:
  - `securityContext` restritivo;
  - `PodDisruptionBudget`;
  - `NetworkPolicy` com default deny + excecoes;
  - RBAC minimo para workload.
- Gerador de novos microservicos (`scripts/new-service.sh`) com scaffold Go + GitOps.
- Pipeline CI/CD GitOps para imagem do `api-gateway`.

## Artefatos principais
- `template/template.env.example`
- `template/scripts/*`
- `template/infra/k8s/**`
- `template/src/frontend/**`
- `template/src/services/api-gateway/**`
- `template/docs/04-guia-rapido-template-v1.md`

## Validacao da release
- `go test ./...` em `template/src/services/api-gateway` (ok)
- `bash -n` nos scripts do template (ok)
- `init-template.sh` testado em copia temporaria (ok)
- placeholders resolvidos sem sobras no smoke test (ok)

## Observacao
- Nesta baseline, a release operacional foi consolidada por tag Git (`template-v1`) e por estas release notes versionadas no repositorio.
