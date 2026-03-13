# Frontend Skeleton

Estrutura base:
- `webapp/`: aplicacao de usuario final.
- `admin/`: backoffice operacional.
- `design-system/`: tokens e componentes compartilhados.
- `shared/`: runtime config, client HTTP/WS e auth OIDC.

Todos os arquivos sao runtime ESM para evitar dependencia obrigatoria de Node no bootstrap inicial.

Entrypoints:
- `webapp/main.js`: valida SSO + API meta + websocket + endpoint protegido.
- `admin/main.js`: valida os mesmos contratos em contexto administrativo.
