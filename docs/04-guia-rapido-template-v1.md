# Guia Rapido - Template v1 (1 pagina)

Objetivo: iniciar um novo projeto tecnico em minutos usando a base `template-v1`.

## 1) Copiar base para novo repositorio
No repositorio atual:
```bash
cp -R template /caminho/novo-repositorio/
```

No novo repositorio:
```bash
cd /caminho/novo-repositorio/template
cp template.env.example .env.template
```

## 2) Parametrizar
Editar `.env.template` e preencher no minimo:
- `PROJECT_SLUG`
- `K8S_NAMESPACE`
- `HOST_APP`, `HOST_ADMIN`, `HOST_API`, `HOST_AI`, `HOST_MQTT`, `HOST_WEBHOOK`, `HOST_SSO`
- `HOST_MQ`, `HOST_KONG_ADMIN`, `HOST_KONG_MANAGER`, `HOST_ARGOCD`
- `LETSENCRYPT_EMAIL`
- `API_IMAGE_REPO`
- `GIT_REPO_URL`, `GIT_DEFAULT_BRANCH`, `GITOPS_ENV`
- `KEYCLOAK_REALM`, `WEBAPP_CLIENT_ID`, `ADMIN_CLIENT_ID`
- `OTEL_BACKEND_OTLP_ENDPOINT`, `OTEL_BACKEND_OTLP_INSECURE`
- `EDA_EXCHANGE`, `EDA_QUEUE`, `EDA_BINDING_KEY`, `EDA_ROUTING_KEY_BASE`
- `OPENAI_API_KEY` (ou provider key equivalente para o LiteLLM)

## 3) Inicializar placeholders
```bash
./scripts/check-prereqs.sh
./scripts/init-template.sh .env.template
```

## 4) Bootstrap do cluster
```bash
LETSENCRYPT_EMAIL="ops@seudominio.com" \
ARGOCD_REPO_TOKEN="<token_git>" \
GHCR_PULL_TOKEN="<token_ghcr>" \
OPENAI_API_KEY="<token_provider>" \
ENABLE_MONITORING_PACK="true" \
./infra/k8s/scripts/bootstrap.sh
```

## 5) Validacao rapida pos-bootstrap
```bash
kubectl get pods -n __K8S_NAMESPACE__
kubectl get deploy otel-collector -n __K8S_NAMESPACE__
kubectl get emqx -n __K8S_NAMESPACE__
kubectl get svc emqx-listeners emqx-dashboard -n __K8S_NAMESPACE__
kubectl get networkpolicy -n __K8S_NAMESPACE__
curl -fsSL https://__HOST_API__/healthz
curl -fsSL https://__HOST_API__/api/v1/platform/meta
curl -fsSL https://__HOST_API__/metrics
curl -fsSL https://__HOST_AI__/health/liveliness
curl -fsSL https://__HOST_MQTT__/status
curl -fsSL -X POST https://__HOST_API__/api/v1/template/events \
  -H 'Content-Type: application/json' \
  -d '{"event_type":"platform.smoke","payload":{"ok":true}}'
curl -fsSL https://__HOST_SSO__/realms/__KEYCLOAK_REALM__/.well-known/openid-configuration
```

Confirmar artefatos base de IoT/Firmware no repositorio:
```bash
ls src/iot/contracts
ls src/firmware/manifests
```

Validar visualmente se login/account do Keycloak carregam o tema Material customizado.

Gerar ao menos uma chamada no gateway e validar traces chegando no collector:
```bash
curl -fsSL https://__HOST_API__/api/v1/platform/meta
kubectl logs deploy/otel-collector -n __K8S_NAMESPACE__ --tail=100
```

## 6) Primeira esteira CI/CD
- Commit inicial do novo repositorio.
- Push no branch definido em `GIT_DEFAULT_BRANCH`.
- Validar workflow `api-gateway-cicd-argocd`.
- Confirmar sincronizacao da `Application` no ArgoCD.

## 7) Pronto para evolucao de negocio
- Arquitetura base ativa.
- SSO e gateway operacionais.
- Frontend tecnico e backend tecnico publicados.
- Projeto apto para receber regras de dominio do novo produto.
