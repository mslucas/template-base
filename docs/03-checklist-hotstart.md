# Checklist de Hot Start

## Preparacao
1. Copiar `template/` para o novo repositorio.
2. Preencher `.env.template` a partir de `template.env.example`.
3. Definir `GITOPS_ENV` (`dev`, `hml` ou `prd`) para o primeiro deploy.
4. Executar `./scripts/check-prereqs.sh`.
5. Executar `./scripts/init-template.sh .env.template`.

## Cluster
1. Validar contexto do `kubectl`.
2. Exportar variaveis de bootstrap (`LETSENCRYPT_EMAIL`, `ARGOCD_REPO_TOKEN`, `GHCR_PULL_TOKEN`).
3. Executar `./infra/k8s/scripts/bootstrap.sh`.
4. Confirmar pods base em `Running`.
5. Confirmar `otel-collector` ativo no namespace do projeto.
6. Confirmar `NetworkPolicy` aplicada no namespace do projeto.

## Publicacao
1. Confirmar hosts `app/admin/api/sso` com TLS valido.
2. Confirmar `api` respondendo `/api/v1/platform/meta`.
3. Confirmar login OIDC no `webapp/admin`.
4. Confirmar telas de login/account do Keycloak renderizando tema Material customizado.
5. Gerar trafego no `api-gateway` e validar spans no log do `otel-collector`.
6. Confirmar `api` expondo `/metrics` com sucesso.

## GitOps
1. Confirmar `argocd Application` sincronizada.
2. Confirmar pipeline CI/CD atualiza `base/kustomization.yaml` com nova tag.
3. Confirmar overlay ativo (`overlays/dev|hml|prd`) corresponde ao ambiente alvo.

## Monitoramento
1. Confirmar `ServiceMonitor` criado (quando CRD estiver instalada).
2. Confirmar `PrometheusRule` criado (quando CRD estiver instalada).
3. Confirmar dashboard `API Gateway SLO` importada no Grafana via ConfigMap.
