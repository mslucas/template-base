# Release Notes - template-v1.1

Data: 2026-03-11  
Tag Git: `template-v1.1`

## Novidades da v1.1
- GitOps com overlays por ambiente (`dev/hml/prd`) para o `api-gateway`.
- Pack de observabilidade SLO:
  - `ServiceMonitor` para scraping;
  - `PrometheusRule` com alertas de disponibilidade, latencia e error budget;
  - dashboard Grafana `API Gateway SLO`.
- Correlacao de observabilidade ponta a ponta:
  - `trace_id` e `span_id` nos logs HTTP do gateway;
  - endpoint `/metrics` para Prometheus;
  - export OTLP do collector para backend real configuravel (`OTEL_BACKEND_OTLP_ENDPOINT`).
- Baseline de seguranca Kubernetes:
  - `NetworkPolicy` (`default deny` + excecoes);
  - `PodDisruptionBudget`;
  - `securityContext` restritivo;
  - RBAC minimo para workloads.
- Gerador de novos microservicos:
  - `scripts/new-service.sh` gera scaffold Go + GitOps base/overlays.
- Identidade visual SSO:
  - Keycloak com tema customizado Material aplicado nas telas de login/account para alinhamento com WebApp/Admin.

## Compatibilidade
- Mantem todos os componentes do `template-v1`.
- Recomendado para novos projetos iniciar diretamente em `template-v1.1`.
