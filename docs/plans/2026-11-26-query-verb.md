# Plano — Verbo HTTP QUERY

Status: **concluído** (2026-11-26)
Proposta: `docs/proposals/0003-query-verb.md`

## Objetivo

Aceitar `query "/caminho"` nos endpoints e documentar esses endpoints no
OpenAPI 3.2.0 só quando eles existirem. Apps sem `query` continuam gerando o
3.1.0 de hoje.

## Fora de escopo

- Plugins (CSRF, CORS), que ficam para a proposta 0004.
- Mudanças no roteador, a não ser que os testes provem que são necessárias.

## Tasks

Q1 e Q2 não têm arquivos em comum e rodam em paralelo, cada uma num
subagente `task-runner` (Haiku).

### Q1 — Endpoint e App

- **Arquivos:** `gems/boto/lib/boto/endpoint/endpoint.rb`,
  `gems/boto/test/boto/endpoint/endpoint_test.rb` e
  `gems/boto/test/boto/http/app_test.rb`.
- **Mudança:** `VERBS` ganha `"QUERY"`, e entra o método de classe
  `query(path)`, escrito explicitamente como os outros.
- **Testes do App:**
  - QUERY com `body` e `returns` devolve 200;
  - corpo inválido devolve 422 com o caminho do campo;
  - HEAD numa rota que só tem QUERY devolve 405 com `Allow: QUERY`;
  - GET e QUERY no mesmo path funcionam como rotas distintas.

### Q2 — OpenAPI 3.2 condicional

- **Arquivos:** `gems/boto/lib/boto/openapi.rb` (e
  `openapi/operation.rb`, se for preciso) e
  `gems/boto/test/boto/openapi_test.rb`.
- **Mudança:**
  - `SPEC_VERSION` vira `SPEC_VERSION_DEFAULT = "3.1.0"` e
    `SPEC_VERSION_WITH_QUERY = "3.2.0"`;
  - o documento usa 3.2.0 se algum endpoint tiver verbo QUERY;
  - a operação vai no campo `query` do Path Item.
- **Testes:**
  - com endpoint `query`: 3.2.0 e campo `query`;
  - sem `query`: o snapshot `shop.json` continua idêntico.

### Q3 — Fechar (eu faço)

1. Rodo as suítes com e sem YJIT.
2. Faço o teste de ponta a ponta: `boto run` e `curl -X QUERY`.
3. Rodo `allocations.rb`, que não deve mudar.
4. Subo a versão para `0.3.0` e atualizo o CHANGELOG.
5. Faço um commit por task e o push.
