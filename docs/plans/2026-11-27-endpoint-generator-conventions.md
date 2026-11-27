# Convenções no `boto generate endpoint` (proposta 0024)

Status: **em andamento**

## Objetivo

`boto g endpoint catalogo products/update` gera o endpoint certo sem verbo,
rota, tipo do `:id` nem schemas explícitos, e a ajuda mostra exemplos.

## Fora de escopo

- `boto g resource` (CRUD completo), que terá proposta própria.
- Gerar schemas que não existem.

## Task 1: `EndpointConvention` (puro)

- **Arquivos:**
  - `gems/boto-rb-cli/lib/boto/cli/support/endpoint_convention.rb`:
    - `EndpointConvention.for(name)` devolve `nil` para ação desconhecida, ou
      um `Data` com `verb`, `path`, `returns` (`"product"`, `"[product]"` ou
      nil) e `body` (`"product_input"`, `"product_filter"` ou nil);
    - a ação é a última parte do nome, e as anteriores formam a rota;
    - `singular(word)`: `ies` -> `y`, `s` final sai (exceto `ss`), senão a
      palavra fica igual;
    - `KNOWN_ACTIONS` para a mensagem de erro e a ajuda;
  - `gems/boto-rb-cli/test/boto/cli/support/endpoint_convention_test.rb`.
- **Testes:** as seis ações, `admin/products/show`, ação desconhecida (nil),
  singular de `products`, `categories`, `pedidos`, `address`, `status`.
- **Dependências:** nenhuma.
- **Comando:** `cd gems/boto-rb-cli && bundle exec rake test`.

## Task 2: o gerador usa a convenção

- **Arquivos:**
  - `support/blueprint_builder.rb`:
    - se o primeiro argumento depois do nome é um verbo conhecido, a forma
      explícita de hoje; senão, todos os argumentos são `param:type` e verbo
      e rota vêm da convenção (ação desconhecida: erro com as ações
      conhecidas e um exemplo explícito);
    - schemas deduzidos só entram quando existem (`@folder.schema?`); os
      ausentes viram avisos; `--body`/`--returns` explícitos vencem e
      `--no-body`/`--no-returns` desligam;
  - `support/endpoint_blueprint.rb`: tipo padrão do param de caminho é
    `integer` para `id` e `*_id`, `string` para os outros;
  - `commands/generate.rb`: as opções `--no-body` e `--no-returns`; a linha
    de resumo (`endpoint PATCH /products/:id  body: product_input  returns:
    product`) e os avisos; o uso e a ajuda com a tabela das ações e
    exemplos;
  - testes em `test/boto/cli/commands/generate_test.rb` (e dos suportes
    tocados).
- **Testes:** cada ação gera o arquivo esperado; schemas presentes e
  ausentes; opções explícitas e `--no-*`; forma explícita igual a hoje;
  `:id` vira `Integer` e `id:uuid` vence; ação desconhecida sem verbo é
  erro; resumo e ajuda.
- **Dependências:** Task 1.
- **Comando:** `cd gems/boto-rb-cli && bundle exec rake test`.

## Fechamento (eu)

- CHANGELOG, README (Gerando código) e CLAUDE.md.
- Suítes com e sem YJIT.
- De ponta a ponta numa solution: as seis ações com e sem schemas.
