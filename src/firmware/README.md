# Firmware Custom Skeleton

Este diretorio centraliza o baseline de firmware customizado para devices IoT.

## Objetivo
- Padronizar release de firmware com metadados e assinatura.
- Organizar rollout OTA com seguranca, rastreabilidade e rollback.

## Estrutura
- `manifests/example-firmware-manifest.json`: manifesto de release OTA.
- `signing-policy.md`: politica de assinatura e verificacao de integridade.

## Regras minimas
- Firmware versionado em SemVer.
- Hash SHA-256 obrigatorio em todo artefato.
- Assinatura obrigatoria para producao.
- Rollout em ondas (canary -> gradual -> total) com criterio de abort.
