# Alinhamento Arquitetural do Template

Use este arquivo para validar os detalhes antes de iniciar o novo projeto.

## 1) Infra e entrega
- [ ] Manter Kubernetes on-prem (Microk8s) como padrao.
- [ ] Manter ArgoCD como mecanismo oficial de deploy GitOps.
- [ ] Manter GHCR como registry principal.
- [ ] Manter NGINX + Kong no edge de publicacao.
- [ ] Manter overlays Kustomize para `dev/hml/prd`.

## 2) Dados e integracao
- [ ] Manter PostgreSQL compartilhado com database-per-service.
- [ ] Manter Redis para cache de leitura repetida.
- [ ] Manter RabbitMQ para toda escrita assíncrona de negocio.
- [ ] Manter padrao producer-consumer no backend.

## 3) Identidade e seguranca
- [ ] Manter Keycloak como SSO central.
- [ ] Manter JWT validado por JWKS no backend.
- [ ] Manter RBAC por role e por acao.
- [ ] Manter cert-manager + Let's Encrypt.

## 4) Frontend e backend base
- [ ] Manter dois frontends base (webapp/admin).
- [ ] Manter design system compartilhado.
- [ ] Manter Material Design 3 como referencia visual oficial (`https://m3.material.io`).
- [ ] Mapear identidade de marca sobre color roles/tokens Material 3, sem quebrar usabilidade base.
- [ ] Manter tema customizado Material no Keycloak (login/account) para consistencia visual com webapp/admin.
- [ ] Manter API gateway Go como primeiro servico tecnico.
- [ ] Manter endpoints tecnicos padrao (health/ready/meta/openapi/ws).
- [ ] Manter instrumentacao OpenTelemetry no backend.
- [ ] Manter script `new-service.sh` para onboarding tecnico de microservicos.

## 5) Observabilidade
- [ ] Manter `otel-collector` no namespace da plataforma.
- [ ] Manter ingestao OTLP gRPC (`4317`) e OTLP HTTP (`4318`).
- [ ] Manter estrategia de amostragem de traces (ratio configuravel por env).
- [ ] Confirmar backend de destino dos traces (ex.: Tempo/Jaeger/Datadog).
- [ ] Manter endpoint `/metrics` e scraping Prometheus (`ServiceMonitor`).
- [ ] Manter alertas SLO (`PrometheusRule`) e dashboard Grafana.

## 6) Seguranca Kubernetes
- [ ] Manter `securityContext` restritivo nos workloads.
- [ ] Manter `PodDisruptionBudget` para workloads criticos.
- [ ] Manter `NetworkPolicy` com `default deny` + excecoes.
- [ ] Manter RBAC minimo por service account.

## 7) Parametrizacao
- [ ] Confirmar padrao de nomes e domínios do novo projeto.
- [ ] Confirmar timezone default.
- [ ] Confirmar naming do realm/clientes OIDC.

## Observacoes
Registre aqui quaisquer ajustes necessarios para derivar variacao do template.
