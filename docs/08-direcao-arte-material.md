# Direcao de Arte Visual - Material Design 3

## Objetivo
Definir a direcao visual oficial do template para interfaces WebApp/Admin com foco em usabilidade, consistencia e velocidade de implementacao.

## Contexto/Fonte
- Referencia oficial: Material Design 3 (`https://m3.material.io`).
- Esta diretriz vale para qualquer novo projeto iniciado a partir do template.

## Decisoes
1. Material Design 3 e o baseline visual obrigatorio para componentes, layout e interacoes.
2. A marca do novo projeto deve ser aplicada por tokenizacao (cores, tipografia, shape e motion) sobre a estrutura Material 3.
3. Componentes de alto uso (button, text field, card, dialog, snackbar, navigation) devem seguir anatomia e estados do Material 3.
4. Telas de autenticacao e conta do Keycloak SSO devem usar tema customizado Material 3 alinhado ao design system do produto.
5. Excecoes ao Material 3 devem ser raras, documentadas e aprovadas no contexto do novo projeto.

## Impacto tecnico
- O design system compartilhado (`tokens.css` + `components.js`) deve mapear tokens internos para semanticas do Material 3.
- Definicoes de acessibilidade devem seguir contraste, foco visivel, estados de erro/sucesso e navegacao por teclado.
- Handoff de UI deve usar nomenclatura de componentes Material 3 para reduzir ambiguidade entre produto, design e engenharia.

## Proximos passos
1. Evoluir o design system base com catalogo de componentes alinhados ao Material 3.
2. Incluir exemplos de tela de referencia (webapp/admin) seguindo o baseline visual.
3. Revisar a cada release do template se a diretriz Material 3 permanece atualizada e consistente.
