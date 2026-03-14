# IoT Devices e Firmware Customizado

## Objetivo
Definir baseline tecnica para integracao com devices IoT e evolucao de firmware customizado, mantendo padrao de microservicos por dominio, seguranca e observabilidade.

## Dominios sugeridos
- `device-registry`: cadastro tecnico de device, modelo, lote e ciclo de vida.
- `device-identity`: provisionamento de identidade, certificados e revogacao.
- `telemetry-ingestion`: ingestao MQTT, validacao de schema e roteamento para EDA.
- `device-shadow`: estado desejado/atual do device.
- `command-dispatcher`: envio de comandos para topic downlink e correlacao de ack.
- `firmware-catalog`: metadados de versoes, checksum, assinatura e compatibilidade.
- `firmware-ota-orchestrator`: regras de rollout por lote, tenant e percentual.
- `firmware-ota-worker`: execucao de campanha OTA e politica de retry/rollback.

## Topicos MQTT de referencia
- Telemetria uplink: `iot/{tenant}/{device_id}/telemetry/{schema_version}`
- Estado/report: `iot/{tenant}/{device_id}/state/{schema_version}`
- Evento sistema: `iot/{tenant}/{device_id}/event/{event_type}`
- Comando downlink: `iot/{tenant}/{device_id}/cmd/{command_name}`
- Ack de comando: `iot/{tenant}/{device_id}/ack/{command_name}`
- Progresso OTA: `iot/{tenant}/{device_id}/ota/progress`

## Requisitos tecnicos obrigatorios
- Toda mensagem MQTT de device deve conter `device_id`, `tenant`, `firmware_version`, `ts_utc` e `correlation_id`.
- Telemetria recebida deve ser republicada em eventos de dominio (EDA) para desacoplamento de consumidores.
- Comando para device deve ser idempotente e possuir timeout de confirmacao (ack/nack).
- Provisionamento de device deve usar credencial por device (certificado ou segredo unico), sem credencial compartilhada por lote.
- Firmware deve ser versionado semanticamente e distribuido com checksum SHA-256.
- Firmware deve ser assinado (assinatura offline) e validado antes de apply no device.
- OTA deve suportar rollout progressivo (canary por percentual) e rollback automatizado.

## Seguranca e compliance
- TLS obrigatorio no plano de controle e no acesso externo ao dashboard MQTT.
- Permissoes por tenant/device para publish/subscribe em topicos.
- Lista de revogacao para credenciais comprometidas.
- Auditoria de acoes de OTA (quem aprovou, quando, para quais lotes/devices).

## Observabilidade minima
- Metricas de conexao: devices conectados, desconexoes, reconnect.
- Metricas de telemetria: throughput por tenant/modelo e taxa de erro de parse/schema.
- Metricas de comando: latencia de ack, taxa de timeout e taxa de falha.
- Metricas de OTA: sucesso, falha, rollback e distribuicao por versao.
- Correlacao de trace entre ingestao MQTT, processamento de dominio e persistencia.

## Estrutura base no template
- `src/iot/`: contratos e convencoes de payload/topic para integracao.
- `src/firmware/`: manifestos de release, politica de assinatura e fluxo OTA.

## Evolucao recomendada
1. Criar microservicos de dominio IoT com `./scripts/new-service.sh`.
2. Implementar validacao de schema dos payloads em `telemetry-ingestion`.
3. Implementar orquestracao OTA com rollout progressivo e rollback.
4. Integrar CI de firmware com assinatura e publicacao de manifesto.
