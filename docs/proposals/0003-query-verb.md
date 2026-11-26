# 0003 — Verbo HTTP QUERY

Status: **aprovada** (OpenAPI 3.2.0 só quando houver endpoint `query`)

## Problema

O CLAUDE.md agora especifica o verbo `query` (método HTTP QUERY), mas o
código só aceita `get`, `post`, `put`, `patch` e `delete`. Uma busca com
filtros complexos hoje precisa de um GET com query string enorme ou de um
POST, que não é seguro nem idempotente.

## API pública

```ruby
class Orders::Users::Search < Boto::Endpoint
  query "/users/search"
  body Orders::UserFilterSchema
  returns [Orders::UserSchema]

  def call(body:) = Users.search(body)
end
```

```
QUERY /users/search HTTP/1.1
Content-Type: application/json

{"name": "ana", "roles": ["admin"]}
```

- **`query(path)`** funciona como os outros verbos: uma rota por classe.
- **Corpo**: lido como em qualquer endpoint. Com `body Schema`, é validado e
  chega como `body:`. Sem `body`, os params podem vir da query string e do
  corpo JSON, como no POST.
- **HEAD**: não responde a partir do QUERY. Só o GET tem esse fallback.
- **Erros**: os 404, 405 (com `Allow` incluindo `QUERY`) e 422 funcionam
  igual aos dos outros verbos.

## Estrutura

- **`gems/boto/lib/boto/endpoint/endpoint.rb`**: `VERBS` ganha `"QUERY"`, e
  entra o método de classe `query(path)`, escrito explicitamente como os
  outros.
- **`gems/boto/lib/boto/http/router.rb` e `app.rb`**: sem mudança esperada,
  porque o roteador já trata o verbo como String. Os testes confirmam.
- **`gems/boto/lib/boto/openapi.rb`**: muda a versão do documento (ver a
  decisão abaixo).

## OpenAPI (decisão)

O OpenAPI 3.1 não tem operação `query` no Path Item. O OpenAPI 3.2 acrescentou
o campo `query`.

- **Recomendação:** gerar `"openapi": "3.2.0"` só quando o app tiver ao
  menos um endpoint `query`, com a operação no campo `query` do Path Item.
  Sem endpoints `query`, o documento continua em `3.1.0`. Assim nada muda
  para quem não usa o verbo, e as ferramentas que ainda não leem 3.2 seguem
  funcionando.
- **Alternativa:** gerar sempre 3.2.0. O documento fica uniforme, mas algumas
  ferramentas e geradores de cliente ainda podem não suportar 3.2.

## Fase do roadmap

Complemento da Fase 1, antes dos plugins. A proposta dos plugins passa a ser
a 0004.

## Performance

Nada muda por request: o verbo é só mais uma chave no Hash de handlers do nó
do roteador.

## Segurança

- **CSRF:** o QUERY é um método seguro, que não altera estado. O plugin
  `:csrf` (proposta 0004) vai tratá-lo como seguro.
- **CORS:** um QUERY cross-origin exige preflight, porque não é um método
  simples. Isso é tratado pelo plugin `:cors`.
- **Corpo:** o limite de 1 MB do corpo JSON vale igual.

## Compatibilidade

É aditivo, e a versão sobe para minor, `0.3.0`. Entra no CHANGELOG, em
`Added`, o verbo `query` e o OpenAPI 3.2 quando há endpoints `query`.

## Testes planejados

- **Endpoint:** `query` define a rota `["QUERY", path]`, e uma segunda rota
  gera erro.
- **App:**
  - QUERY com corpo válido devolve 200 com o `returns`;
  - corpo inválido devolve 422 com o caminho do campo;
  - HEAD numa rota que só tem QUERY devolve 405 com
    `Allow: QUERY`;
  - GET e QUERY no mesmo path funcionam como rotas distintas.
- **OpenAPI:**
  - com endpoint `query`: documento em 3.2.0 e operação no campo `query`;
  - sem endpoint `query`: documento continua em 3.1.0 e o snapshot atual
    não muda.
- **Ponta a ponta:** `boto run` com `curl -X QUERY` responde. Isso confirma
  que o Falcon repassa o método.

## Alternativas descartadas

- **Gerar uma extensão `x-query` no 3.1**: as ferramentas a ignoram, e o 3.2
  já tem o campo oficial.
- **Exigir `body` em todo endpoint `query`**: restringe sem necessidade.
  Uma busca sem corpo continua válida.
