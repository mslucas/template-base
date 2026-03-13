# Template de Arquitetura Tecnica

Starter kit tecnico para hot start de novos projetos, sem acoplamento de regra de negocio.

## Baseline atual
- Versao oficial: `template-v1.1` (arquivo `VERSION`).
- Diretiva obrigatoria: todo projeto derivado deve ser 100% baseado em microservicos por dominio da aplicacao.
- Stack base:
  - Kubernetes on-prem (Microk8s)
  - NGINX Ingress + Kong
  - cert-manager + Let's Encrypt
  - Keycloak (OIDC + PKCE)
  - PostgreSQL compartilhado (database-per-service)
  - Redis
  - RabbitMQ
  - OpenTelemetry (SDK + Collector OTLP)
  - ArgoCD (GitOps)
  - Frontend WebApp/Admin em React runtime ESM
  - Diretriz visual oficial: Material Design 3

## Estrutura principal
- `docs/`
  - `01-arquitetura-base.md`: baseline tecnica neutra de negocio
  - `02-alinhamento-arquitetural.md`: checklist de validacao antes de iniciar derivacao
  - `03-checklist-hotstart.md`: checklist operacional de bootstrap
  - `04-guia-rapido-template-v1.md`: guia de 1 pagina para copy/paste
  - `06-gerador-servicos.md`: onboarding de microservicos com `new-service.sh`
  - `07-release-notes-template-v1.1.md`: escopo da versao atual
  - `08-direcao-arte-material.md`: diretriz visual Material Design 3
- `scripts/`
  - `check-prereqs.sh`
  - `init-template.sh`
  - `new-service.sh`
- `infra/k8s/`: bootstrap da plataforma, manifests e GitOps
- `.github/workflows/`: CI/CD para build/push e update GitOps
- `src/`: skeleton tecnico inicial (frontend + backend)
- `template.env.example`: variaveis de parametrizacao

## Fluxo recomendado (novo repositorio)
1. Copiar o conteudo de `template/` para a raiz do novo repositorio.
2. Criar `.env.template` a partir de `template.env.example`.
3. Ajustar variaveis obrigatorias (`PROJECT_SLUG`, `K8S_NAMESPACE`, hosts, `API_IMAGE_REPO`, `GITOPS_ENV`, OIDC e OTEL backend).
4. Validar pre-requisitos e resolver placeholders:
```bash
./scripts/check-prereqs.sh
./scripts/init-template.sh .env.template
```
5. Executar bootstrap de cluster:
```bash
LETSENCRYPT_EMAIL="ops@seudominio.com" \
ARGOCD_REPO_TOKEN="<token_git>" \
GHCR_PULL_TOKEN="<token_ghcr>" \
ENABLE_MONITORING_PACK="true" \
./infra/k8s/scripts/bootstrap.sh
```
6. Validar endpoints tecnicos e observabilidade:
```bash
curl -fsSL https://__HOST_API__/healthz
curl -fsSL https://__HOST_API__/api/v1/platform/meta
curl -fsSL https://__HOST_API__/metrics
kubectl get deploy otel-collector -n __K8S_NAMESPACE__
```

## O que sai pronto
- API gateway Go com `/healthz`, `/readyz`, `/api/v1/platform/meta`, `/swagger/openapi.yaml`, `/ws` e `/metrics`.
- Instrumentacao OpenTelemetry no backend com correlacao `trace_id`/`span_id`.
- Overlays GitOps `dev/hml/prd` para o `api-gateway`.
- Pack opcional de monitoramento: `ServiceMonitor`, `PrometheusRule` e dashboard Grafana.
- Baseline de seguranca: `securityContext` restritivo, `PodDisruptionBudget`, `NetworkPolicy` e RBAC minimo.
- Frontends base WebApp/Admin com design system compartilhado.
- Keycloak SSO com tema Material aplicado nas telas de login/account.

## Geracao de novos microservicos
Use o gerador para criar um servico Go com scaffold tecnico + GitOps:
```bash
./scripts/new-service.sh <service-name> --port 8091 --gitops-env dev
```
Detalhes completos em `docs/06-gerador-servicos.md`.

## Direcao visual oficial
Toda evolucao de interface deve usar Material Design 3 como referencia primaria.  
Diretriz completa: `docs/08-direcao-arte-material.md`.
