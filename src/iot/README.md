# IoT Integration Skeleton

Este diretorio guarda contratos tecnicos para devices IoT no template base.

## Objetivo
- Padronizar topicos MQTT e envelopes de payload.
- Garantir compatibilidade entre firmware, backend e analytics.
- Facilitar onboarding de novos microservicos de dominio IoT.

## Estrutura
- `contracts/telemetry-envelope.example.json`: exemplo de telemetria uplink.
- `contracts/command-envelope.example.json`: exemplo de comando downlink.
- `contracts/ack-envelope.example.json`: exemplo de ack/nack de comando.

## Convencoes
- Sempre enviar `device_id`, `tenant`, `firmware_version`, `ts_utc`, `correlation_id`.
- Timestamps sempre em UTC (`RFC3339`).
- Evitar payloads sem versao de schema.

## Topicos de referencia
- `iot/{tenant}/{device_id}/telemetry/v1`
- `iot/{tenant}/{device_id}/cmd/reboot`
- `iot/{tenant}/{device_id}/ack/reboot`
