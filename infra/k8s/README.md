# Bootstrap Kubernetes (Template)

Stack base instalada pelo bootstrap:
- NGINX Ingress Controller
- cert-manager + ClusterIssuer Let's Encrypt
- ArgoCD
- PostgreSQL
- Redis
- RabbitMQ
- OpenTelemetry Collector
- Keycloak
- Kong
- Monitoring pack (ServiceMonitor + PrometheusRule + dashboard Grafana)
- Security baseline (NetworkPolicy + RBAC minimo)
- Entry points WebApp/Admin

## Estrutura
- `values/`: valores Helm.
- `manifests/`: manifests complementares.
- `gitops/`: workloads gerenciados por ArgoCD (base + overlays `dev/hml/prd`).
- `scripts/`: automacao de bootstrap e suporte operacional.

## Execucao
```bash
LETSENCRYPT_EMAIL="__LETSENCRYPT_EMAIL__" \
ARGOCD_REPO_TOKEN="<token_git>" \
GHCR_PULL_TOKEN="<token_ghcr>" \
ENABLE_MONITORING_PACK="true" \
./infra/k8s/scripts/bootstrap.sh
```
