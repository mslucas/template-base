# Gerador de Servicos (new-service.sh)

## Objetivo
Padronizar onboarding de novos microservicos com scaffold tecnico consistente (Go + GitOps + seguranca baseline).

## Comando
```bash
./scripts/new-service.sh <service-name> [opcoes]
```

## Exemplo
```bash
./scripts/new-service.sh billing \
  --port 8091 \
  --module-prefix github.com/acme/plataforma/src/services \
  --image-repo-prefix ghcr.io/acme/plataforma \
  --gitops-env dev
```

## O que o script gera
- `src/services/<service-name>/`:
  - `go.mod`
  - `cmd/server/main.go`
  - `Dockerfile`
  - `Makefile`
  - `README.md`
- `infra/k8s/gitops/apps/<service-name>/`:
  - `base` com `Deployment`, `Service`, `PDB`, `kustomization.yaml`
  - `overlays/dev|hml|prd` com patch de replicas e variaveis OTEL
- Entrada de `Application` no `argocd-applications.yaml` (se ainda nao existir).

## Observacoes
- Execute o `init-template.sh` antes de usar o gerador, para resolver placeholders.
- Revise as variaveis de imagem e modulo Go antes do primeiro commit.
