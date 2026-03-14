# Arquitetura Base (Neutra de Negocio)

## Objetivo
Definir baseline tecnica para iniciar projetos novos com padrao escalavel, observavel e com seguranca por padrao.

## Stack padrao
- Plataforma: Kubernetes on-prem (Microk8s).
- Ingress primario: NGINX Ingress Controller.
- API Gateway: Kong.
- Certificados TLS: cert-manager + Let's Encrypt.
- SSO/IAM: Keycloak (OIDC).
- Banco relacional: PostgreSQL compartilhado, modelo database-per-service.
- Cache: Redis.
- Mensageria: RabbitMQ.
- Broker MQTT: EMQX (gerenciado por EMQX Operator).
- AI Gateway: LiteLLM (open source).
- Observabilidade: OpenTelemetry SDK no backend + OpenTelemetry Collector (OTLP).
- Deploy GitOps: ArgoCD.
- Gestao de ambientes: overlays `dev/hml/prd` com Kustomize.
- CI/CD: GitHub Actions com publicacao de imagem no GHCR e update GitOps.

## Frontend padrao
- WebApp e Admin em React runtime ESM.
- Design system compartilhado (`tokens.css` + `components.js`).
- Direcao visual oficial: Material Design 3 (`https://m3.material.io`).
- Componentes visuais devem seguir padroes Material 3 (color roles, type scale, shape/elevation, state layer, motion).
- Telas do Keycloak SSO (login/account) devem usar tema customizado Material para manter consistencia de UI/UX com WebApp/Admin.
- Cliente compartilhado para runtime config, plataforma HTTP/WS e auth OIDC.

## Backend padrao
- API Gateway em Go.
- Camada EDA obrigatoria com contratos de producer/consumer por dominio.
- Endpoints tecnicos padrao:
  - `/healthz`
  - `/readyz`
  - `/api/v1/platform/meta`
  - `/swagger/openapi.yaml`
  - `/metrics`
  - `/ws`
- Middleware CORS.
- Middleware JWT + RBAC por role (Keycloak JWKS).
- Instrumentacao HTTP com OpenTelemetry.

## Principios tecnicos obrigatorios
- Arquitetura de aplicacao: 100% baseada em microservicos por dominio.
- Escritas de negocio (`INSERT`/`UPDATE`): assíncronas via RabbitMQ (producer-consumer).
- Leituras de alta repeticao: cache-first em Redis.
- Persistencia de timestamps: UTC.
- Exibicao de datas: timezone configuravel por usuario/tenant.
- Segredos: Kubernetes Secrets (com rotacao operacional definida).
- Traces distribuidos: exportacao OTLP para `otel-collector` no namespace da plataforma.
- Seguranca Kubernetes baseline:
  - `securityContext` restritivo em workloads;
  - `PodDisruptionBudget` para alta disponibilidade minima;
  - `NetworkPolicy` com `default deny` + excecoes explicitas;
  - RBAC minimo por service account.

## Dominios publicos de referencia
- `__HOST_APP__`
- `__HOST_ADMIN__`
- `__HOST_API__`
- `__HOST_WEBHOOK__`
- `__HOST_MQTT__`
- `__HOST_AI__`
- `__HOST_SSO__`
- `__HOST_MQ__`
- `__HOST_KONG_ADMIN__`
- `__HOST_KONG_MANAGER__`
- `__HOST_ARGOCD__`
