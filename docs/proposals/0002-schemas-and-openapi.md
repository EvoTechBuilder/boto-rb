# 0002 — Schemas e OpenAPI (Fase 1, parte 1)

Status: **aprovada**

## Problema

Hoje o endpoint devolve qualquer Hash, e o App serializa tudo com
`JSON.generate`. Isso traz três problemas:

- nada impede de vazar um campo como `password_hash`;
- não há como validar um corpo JSON estruturado (objetos aninhados, listas);
- não existe documentação da API.

O CLAUDE.md pede "schemas declarados uma vez: validam entrada, serializam
saída, geram OpenAPI". O cliente TypeScript do template `spa` (Fase 3)
depende desse OpenAPI.

## API pública

### Schema

```ruby
# services/orders/schemas/address_schema.rb
class Orders::AddressSchema < Boto::Schema
  field :street, String, max: 200
  field :zip, String, pattern: /\A\d{5}-?\d{3}\z/
end

# services/orders/schemas/user_schema.rb
class Orders::UserSchema < Boto::Schema
  field :id, Integer
  field :name, String, min: 1, max: 100
  field :email, String, required: false
  field :role, String, enum: %w[admin member]
  field :tags, [String], max: 10
  field :address, Orders::AddressSchema, required: false
  field :created_at, Time
end
```

- **Tipos**:
  - `String`, `Integer`, `Float` e `Boto::Boolean`, como hoje;
  - novos: `Date` (ISO 8601 `YYYY-MM-DD`) e `Time` (ISO 8601 com fuso);
  - listas, com `[Tipo]`;
  - outros schemas, para aninhar.
- **Restrições**:
  - `min` e `max`: valor para números, tamanho para String e listas;
  - `enum`;
  - `pattern`: só String, com regex ancorada.
- **Obrigatoriedade**: `required: false` aceita o campo ausente ou `null`,
  que vira `nil`.
- **Params usam os mesmos tipos e restrições**:
  `param :page, Integer, min: 1, default: 1` e `param :ids, [Integer]` (de
  `?ids=1&ids=2`).

### Endpoint

```ruby
class Orders::Users::Create < Boto::Endpoint
  post "/users"
  status 201
  summary "Create a user"
  body Orders::UserInputSchema
  returns Orders::UserSchema
  errors 409

  def call(body:)
    user = Users.create(name: body.name, email: body.email)
    user                      # modelo, Hash ou qualquer objeto com os métodos dos campos
  end
end

class Orders::Users::Index < Boto::Endpoint
  get "/users"
  param :page, Integer, min: 1, default: 1
  returns [Orders::UserSchema]

  def call(page:) = Users.page(page)
end
```

- **`body Schema`**: o corpo JSON inteiro é validado pelo schema e chega
  como `body:`.
  - O `body:` é uma instância congelada do schema, com leitores
    (`body.name`) e `#to_h`.
  - Campos não declarados são descartados.
  - Com `body`, os params vêm só do path e da query.
  - Um param chamado `body` gera erro no boot.
- **`returns Schema`** ou **`returns [Schema]`**: a saída passa pelo schema.
  - Só os campos declarados saem.
  - O objeto pode ser um Hash (chave símbolo ou string) ou responder aos
    nomes dos campos.
  - `Date` e `Time` saem em ISO 8601.
  - Um campo obrigatório que fique `nil` na saída gera 500, com log. É um
    bug do servidor, não do cliente.
- **Sem `returns`**: o comportamento continua o de hoje (`JSON.generate` do
  valor).
- **`summary`** e **`errors`** (status extras) só alimentam o OpenAPI.

### Erros de validação

O formato continua o mesmo 422, com o caminho completo do campo:

```json
{ "type": "about:blank", "title": "Unprocessable Content", "status": 422,
  "errors": [
    { "param": "address.zip", "message": "must match the pattern" },
    { "param": "tags[2]", "message": "must be a String" }
  ] }
```

As mensagens nunca repetem o valor recebido.

### OpenAPI

```ruby
Boto::OpenAPI.generate(app, title: "orders", version: "1.0.0") # => Hash (OpenAPI 3.1)
```

```
boto openapi orders                    # imprime o JSON
boto openapi orders -o openapi.json    # grava em arquivo
```

- **O que entra no documento**:
  - `paths`: rota, params de path e query (com tipo e restrições),
    `requestBody` vindo do `body`, a resposta com o `status` e o schema do
    `returns`, e `summary`;
  - `components.schemas`, um por classe de schema, com o nome da classe sem
    o namespace do projeto;
  - o schema `Problem` (RFC 9457), usado em 422 (quando há params ou body),
    em 404 (quando há path params) e nos status declarados em `errors`.
- **Rota `GET /openapi.json`**: o App serve o documento só quando
  `env_name == "development"`.

### Templates

- **`webapi`**:
  - ganha `schemas/`;
  - o `health` passa a usar `returns Api::HealthSchema`;
  - entra um exemplo de teste de schema.
- **`library`**: ganha `schemas/`.

## Estrutura

```
gems/boto/
  lib/boto/types.rb            # compila (tipo, restrições) em coercer + JSON Schema; compartilhado
  lib/boto/schema.rb           # DSL field, .coerce(input) -> instância, .serialize(obj), .json_schema
  lib/boto/schema/compiler.rb  # gera no boot o código de coerce/serialize de cada schema
  lib/boto/openapi.rb          # Boto::OpenAPI.generate(app, title:, version:)
  lib/boto/endpoint.rb         # + body, returns, summary, errors
  lib/boto/params.rb           # passa a usar Boto::Types
  lib/boto/app.rb              # body via schema, saída via returns, /openapi.json em dev
  lib/boto/project_loader.rb   # CODE_DIRS ganha schemas
gems/boto-cli/
  lib/boto/cli/commands/openapi.rb
  templates/webapi/, templates/library/   # schemas/ + exemplos
```

O App ganha um leitor `title` (o nome do namespace) para o OpenAPI.

## Fase do roadmap

Fase 1, parte 1. Os plugins (`:auth`, `:cors`, `:rate_limit` e `:hosts`)
ficam para a proposta 0003.

## Performance

- **No boot**:
  - cada schema é compilado uma vez. O coerce e o serialize viram métodos
    gerados com `class_eval` a partir dos campos, um acesso direto por
    campo e sem reflexão por request;
  - os tipos e as restrições viram lambdas congeladas, como já acontece em
    `Params`;
  - o documento OpenAPI é gerado uma vez e cacheado em JSON.
- **Por request**:
  - entrada: um parse de JSON, já feito hoje, mais uma instância do schema;
  - saída: um Hash por objeto serializado, no lugar do objeto do usuário.
- **Medição**: os testes de alocação travam o serialize em 1 Hash por
  objeto e o coerce em 1 instância (mais 1 objeto por schema aninhado). O
  cenário `db` do benchmark ganha uma variante `db_schema`, só para o Boto,
  para medir o custo do `returns`. O Roda e o Sinatra não têm equivalente
  direto.

## Segurança

- **Saída**: o `returns` é uma allowlist, e só os campos declarados saem.
  Isso evita vazar dados de modelos.
- **Entrada**:
  - campos não declarados são descartados;
  - tipos e restrições são validados antes de chegar ao `call`;
  - o limite de 1 MB e o de aninhamento do `JSON.parse` (100) continuam
    valendo.
- **Regex**: uma `pattern` sem âncoras `\A`/`\z` gera erro no boot. Não há
  avaliação de regex do cliente.
- **Mensagens de erro**: nunca ecoam o valor recebido, para evitar
  reflexão de conteúdo.
- **OpenAPI**: em produção, a rota não existe. Quem quiser publicar usa o
  `boto openapi` no build.

## Compatibilidade

- Tudo é aditivo: endpoints sem `body` e sem `returns` funcionam como hoje.
- A versão sobe para minor, `0.2.0`.
- O CHANGELOG ganha, em `Added`: schemas, `body`, `returns`, `summary`,
  `errors`, os tipos `Date`, `Time` e listas, as restrições, o OpenAPI e o
  `boto openapi`.

## Testes planejados

- **Types**:
  - coerção válida e inválida de cada tipo;
  - cada restrição;
  - JSON Schema gerado para cada caso.
- **Schema**:
  - coerce com aninhamento e listas;
  - caminhos de erro (`address.zip`, `tags[2]`) agregados;
  - campos extras descartados;
  - `required: false` com ausente e com `null`;
  - instância congelada e `to_h`;
  - serialize de Hash (chave símbolo ou string) e de objeto;
  - campo obrigatório `nil` na saída gera erro;
  - `pattern` sem âncora gera erro no boot.
- **Endpoint e App**:
  - `body` chega como instância;
  - 422 com caminho;
  - `returns` filtra os campos (teste de vazamento com `password_hash`);
  - `returns [Schema]`;
  - param chamado `body` gera erro no boot;
  - sem `returns`, o comportamento é o de antes.
- **OpenAPI**:
  - o documento do projeto fixture é validado contra a estrutura do 3.1
    (chaves obrigatórias, `$ref` resolvíveis);
  - teste de snapshot do JSON;
  - `/openapi.json` existe em development e dá 404 em production.
- **CLI**:
  - `boto openapi` imprime e grava;
  - projeto inexistente gera erro;
  - os templates geram `schemas/`, e o teste gerado passa (fluxo de ponta
    a ponta).
- **Alocação**: limites para o coerce e o serialize.

## Fora de escopo

- Herança e composição de schemas (`oneOf`, `allOf`).
- Campos calculados.
- Versionamento de API.
- Validação de corpo que não seja JSON (form, multipart).
- Exemplos no OpenAPI.

## Alternativas descartadas

- **dry-schema / dry-validation**: dependência pesada e mais alocações por
  request. O núcleo do Boto precisa ser mínimo.
- **Arquivos JSON Schema escritos à mão**: duplicam a declaração e perdem a
  DSL Ruby.
- **`body` com os campos espalhados como params**: fica ambíguo com os
  params de query e não suporta aninhamento.
- **Serializar por reflexão (`public_send` por campo e por request)**: viola
  a rule de performance. O código gerado no boot é mais rápido.
- **Servir `/openapi.json` sempre**: expõe a superfície da API em produção
  por padrão.
- **`body` como Hash simples**: perde os leitores e a imutabilidade.
