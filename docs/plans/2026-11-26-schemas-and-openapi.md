# Plano — Schemas e OpenAPI

Status: **concluído** (2026-11-26)
Proposta: `docs/proposals/0002-schemas-and-openapi.md`

## Objetivo

Implementar `Boto::Schema`, os tipos compartilhados, o `body` e o `returns`
no endpoint, o OpenAPI 3.1 (`Boto::OpenAPI`, `/openapi.json` em dev e
`boto openapi`) e os templates com `schemas/`, sem mudar o comportamento de
quem não usa schemas.

## Fora de escopo

Fica fora o que a seção "Fora de escopo" da proposta 0002 lista, e também
os plugins da proposta 0003.

## Contratos entre tasks

São definidos aqui para que as tasks paralelas não dependam umas das outras.

- **`Boto::Types.build(type, min: nil, max: nil, enum: nil, pattern: nil)`**:
  - devolve um objeto congelado com:
    - `#coerce(value)`: devolve o valor convertido, ou lança
      `Boto::Types::Invalid`, cujo `#errors` é `[{ path: String, message: String }]`
      (o `path` é relativo e vazio no próprio campo, como `"[2]"` ou
      `"zip"`);
    - `#dump(value)`: converte para JSON (`Date` e `Time` em ISO 8601,
      listas elemento a elemento, schema via `.serialize`);
    - `#json_schema`: o JSON Schema em Hash.
  - Restrições inválidas lançam `ArgumentError` no build. Entre elas, uma
    `pattern` sem `\A` e `\z`.
  - Um tipo que é schema é reconhecido por duck typing: uma classe que
    responde a `coerce`, `serialize` e `json_schema_ref`.
- **`Boto::Schema`**:
  - `field(name, type, required: true, **restrições)`;
  - `.fields`;
  - `.coerce(input)`: devolve uma instância congelada, ou lança
    `Types::Invalid` com caminhos completos (`"address.zip"`, `"tags[2]"`);
  - `.serialize(object)`: devolve um Hash com chaves símbolo, ou lança
    `Boto::Schema::OutputError` se um campo obrigatório vier nil;
  - `.json_schema`;
  - `.json_schema_ref`: `{ "$ref" => "#/components/schemas/<schema_name>" }`;
  - `.schema_name`: o nome da classe sem o primeiro segmento, com os
    restantes juntos (`Orders::Admin::UserSchema` vira `AdminUserSchema`);
  - `.compile!` (idempotente; compila também os aninhados);
  - instância com leitores, `#to_h` e `==`.
- **`Boto::Endpoint`**:
  - `body(schema)` e `body_schema`;
  - `returns(schema | [schema])`, `return_schema` e `returns_list?`;
  - `summary(text)` e `summary_text`;
  - `errors(*statuses)` e `error_statuses`;
  - `compile!` também compila os schemas e lança `ArgumentError` se houver
    um param `:body` junto com `body`.

## Tasks

Cada task roda num subagente `task-runner` (Haiku) e vira um commit. Os
grupos marcados com ∥ rodam em paralelo.

**Testes:**
- por gem: `cd gems/<gem> && bundle exec rake test`;
- por arquivo: `bundle exec ruby -w -Ilib -Itest <arquivo>`.

Sempre com e sem `RUBY_YJIT_ENABLE=1`.

### Onda 1

**S1 — Types** (`gems/boto/lib/boto/types.rb` e `test/boto/types_test.rb`)

- **Tipos simples**: `String`, `Integer`, `Float`, `Boto::Boolean`, `Date`
  (ISO `YYYY-MM-DD`) e `Time` (ISO 8601 com fuso; sem fuso é erro).
- **Composição**: listas `[Tipo]` e schema (duck typing).
- **Restrições**:
  - `min` e `max` valem para números (valor), String (tamanho) e lista
    (tamanho);
  - `enum` vale para qualquer tipo simples;
  - `pattern` só para String, ancorada.
- **JSON Schema**:
  - `\A` e `\z` viram `^` e `$`;
  - `Date` sai como `format: date` e `Time` como `format: date-time`.
- **Mensagens**: nunca repetem o valor recebido.
- **Teste de alocação**: `coerce` de um Integer vindo de String aloca 0
  objetos.

### Onda 2 ∥

**S2 — Schema** (`lib/boto/schema.rb`, `lib/boto/schema/compiler.rb` e
`test/boto/schema_test.rb`; depende de S1)

- O nome do campo precisa casar com `/\A[a-z_][a-z0-9_]*\z/`. Isso protege o
  código gerado.
- **`coerce`**: aceita um Hash com chave string ou símbolo; qualquer outra
  coisa dá "must be an object". Agrega os erros, prefixa os caminhos e
  descarta campos extras.
- **`serialize`**: lê de um Hash (chave símbolo ou string) ou de um objeto.
  - Para objetos, o `Compiler` gera no `compile!`, via `class_eval`, um
    método que chama cada leitor diretamente.
  - Sem `compile!`, o `serialize` compila na primeira chamada.
- **Testes**:
  - aninhamento e listas;
  - caminhos de erro;
  - `required: false` com valor ausente e com `null`;
  - campo obrigatório nil gera `OutputError`;
  - vazamento: `password_hash` não sai;
  - nome de campo inválido gera erro;
  - alocação: `serialize` de um objeto com 3 campos simples aloca 1 Hash.

**S3 — Params sobre Types** (`lib/boto/params.rb` e `test/boto/params_test.rb`;
depende de S1)

- `declare(name, type, default:, required:, **restrições)` passa a usar
  `Types.build`.
- **Listas**: um valor único da query vira lista de um elemento, e os erros
  saem como `ids[1]`.
- Expõe `#definitions` (para o OpenAPI) e remove o `COERCERS`, que era
  interno.
- O teste de alocação (máximo de 1 objeto) e todos os testes atuais
  continuam passando.

### Onda 3

**S4 — DSL do Endpoint** (`lib/boto/endpoint.rb` e
`test/boto/endpoint_test.rb`; depende de S2)

Implementa o contrato acima, validando que `body` recebe uma subclasse de
`Boto::Schema` e que `returns` recebe `Schema` ou `[Schema]`.

### Onda 4

**S5 — App com body e returns** (`lib/boto/app.rb` e
`test/boto/app_test.rb`; depende de S3 e S4)

- **Com `body_schema`**:
  - os params vêm só do path e da query;
  - `body:` recebe `schema.coerce(RequestBody.parse(env))`;
  - `Types::Invalid` vira 422, com os `errors` no formato
    `{param: path, message:}`.
- **Com `return_schema`**: serializa o retorno, ou cada item se for lista;
  um `OutputError` vira 500 com log.
- Expõe `#title`, que é o nome do namespace.
- **Testes**: os casos da proposta, e todos os testes atuais continuam
  passando.

### Onda 5

**S6 — OpenAPI** (`lib/boto/openapi.rb` e `test/boto/openapi_test.rb`;
depende de S5)

- `Boto::OpenAPI.generate(app, title:, version:)` devolve um Hash 3.1. Ele
  contém:
  - `paths`, com `/users/:id` convertido para `/users/{id}`;
  - `operationId`, o nome do endpoint sem o namespace;
  - parâmetros de path e query;
  - `requestBody`;
  - respostas com o status padrão, o 422, o 404 e os `errors`;
  - `components.schemas`, com os schemas e os aninhados (coletados
    recursivamente) e o `Problem`.
- **Testes**:
  - todo `$ref` resolve;
  - chaves obrigatórias do 3.1;
  - snapshot com uma fixture.

### Onda 6 ∥

**S7 — `/openapi.json` em dev** (`lib/boto/app.rb` e `test/boto/app_test.rb`;
depende de S6)

- Com `env_name == "development"`, o App responde a `GET /openapi.json` com o
  documento, gerado uma vez e cacheado como string.
- Em production, a rota dá 404.

**S8 — `boto openapi`** (`gems/boto-cli/lib/boto/cli/commands/openapi.rb` e
o teste dele; depende de S6)

- Uso: `boto openapi <project> [-o FILE] [--api-version V]`, com a versão
  padrão `0.1.0`.
- Projeto inexistente ou não servível gera erro.
- Faz `Boot#shutdown` no `ensure`.

**S9 — Templates e loader** (`lib/boto/project_loader.rb` com o teste, e
`gems/boto-cli/templates/{webapi,library}`; depende de S5)

- `CODE_DIRS` passa a incluir `schemas`.
- **Template `webapi`**: ganha `schemas/health_schema.rb.erb` (com o campo
  `status`); o `health` usa `returns`; e entra um teste do schema.
- **Template `library`**: ganha `schemas/.keep`.
- Os testes do `add` são atualizados.

**S10 — Cenário `db_schema`** (`benchmarks/`; depende de S5)

- Cria `apps/boto/db_schema.ru`, igual ao `db` mas com `returns UserSchema`.
- O cenário entra no `run.rb` e no `allocations.rb` só para o Boto, e os
  testes do benchmark são atualizados.

### Onda 7 (eu faço)

1. Rodo a suíte completa com e sem YJIT.
2. Faço o fluxo de ponta a ponta: `new`, `add`, `test`, `run` com
   `curl /openapi.json` e `openapi -o`.
3. Rodo `allocations.rb` e `run.rb --quick --compare` contra o baseline
   atual.
4. Subo a versão para `0.2.0` nas duas gems e atualizo o CHANGELOG.
5. Marco este plano como concluído.

## Revisão e commits

Depois de cada task:

1. eu leio o diff;
2. rodo os testes com e sem YJIT;
3. confiro as rules (`clean-code`, `performance`, `security`, `tests`);
4. faço um commit por task (`feat(boto): ...`, `feat(cli): ...`,
   `feat(templates): ...`, `feat(benchmarks): ...`).
