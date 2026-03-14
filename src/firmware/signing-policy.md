# Politica de Assinatura de Firmware

## Objetivo
Garantir autenticidade e integridade de firmware antes da instalacao no device.

## Regras
- Chaves de assinatura devem ficar em HSM/KMS.
- Assinatura deve ser aplicada no artefato final de release.
- Device deve validar assinatura antes de gravar firmware.
- Device deve validar checksum SHA-256 antes e depois do download.
- Chave comprometida implica revogacao imediata e rotacao.

## Fluxo recomendado
1. Build reproduzivel do firmware.
2. Geracao de hash SHA-256.
3. Assinatura do hash com chave de release.
4. Publicacao do artefato + manifesto.
5. Verificacao em staging antes de liberar em producao.
