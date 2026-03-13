# API Gateway (Template)

Servico base em Go para iniciar novos projetos, com foco em arquitetura tecnica:
- health/readiness (`/healthz`, `/readyz`)
- metadata de plataforma (`/api/v1/platform/meta`)
- contrato OpenAPI (`/swagger/openapi.yaml`)
- endpoint de metricas (`/metrics`)
- websocket de validacao (`/ws`)
- endpoint protegido por JWT + RBAC (`/api/v1/template/secure`)
- tracing distribuido com OpenTelemetry (OTLP)
- logs estruturados com `trace_id` e `span_id` para correlacao

## Executar local
```bash
cd src/services/api-gateway
make tidy
make run
```

## Build e testes
```bash
cd src/services/api-gateway
make test
make build
```

## Variaveis principais
- `PORT` (default: `8080`)
- `SERVICE_NAME` (default: `api-gateway`)
- `SERVICE_VERSION` (default: `0.1.0`)
- `DEFAULT_TIMEZONE` (default: `__DEFAULT_TIMEZONE__`)
- `AUTH_ENABLED` (default: `true`)
- `AUTH_KEYCLOAK_ISSUER` (default: `https://__HOST_SSO__/realms/__KEYCLOAK_REALM__`)
- `AUTH_KEYCLOAK_JWKS_URL` (default: `https://__HOST_SSO__/realms/__KEYCLOAK_REALM__/protocol/openid-connect/certs`)
- `AUTH_ALLOWED_AUDIENCES` (default: `__WEBAPP_CLIENT_ID__,__ADMIN_CLIENT_ID__`)
- `AUTH_TEMPLATE_READ_ROLES` (default: `platform_admin,platform_support`)
- `CORS_ALLOWED_ORIGINS` (default: `https://__HOST_APP__,https://__HOST_ADMIN__,http://localhost:4173,http://127.0.0.1:4173`)
- `OTEL_ENABLED` (default: `true`)
- `OTEL_EXPORTER_OTLP_ENDPOINT` (default: `otel-collector.__K8S_NAMESPACE__.svc.cluster.local:4317`)
- `OTEL_EXPORTER_OTLP_INSECURE` (default: `true`)
- `OTEL_TRACES_SAMPLER_RATIO` (default: `1.0`)
- `OTEL_ENVIRONMENT` (default: `platform`)
