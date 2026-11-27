# Boto

Framework Ruby para APIs e microservices, organizado em **solutions**. Open
source (MIT), criado pela [Evo Tech Builder](https://github.com/EvoTechBuilder).
O nome vem do boto, o golfinho da Amazônia.

```bash
gem install boto-rb-cli
boto new loja && cd loja
bundle install
boto add webapi pedidos
boto run
```

## Por que o Boto

Uma *solution* reúne vários projetos (APIs, workers, bibliotecas) com
referências explícitas entre eles. Sem isso, um sistema Ruby costuma virar
um monólito, ou cada serviço vive num repositório com cópias do código
compartilhado. O Boto organiza o sistema assim:

- **Uma solution, vários projetos.** O `Botofile` declara os projetos e quem
  referencia quem.
- **Isolamento de verdade.** Um projeto só enxerga o código dos projetos que
  referencia. Usar outro é erro, apontado pelo `boto check`.
- **Um processo no dev, serviços separados em produção.** O `boto run` sobe a
  solution inteira num processo só, sem mudar o código.
- **Contratos declarados uma vez.** O mesmo schema valida a entrada, serializa
  a saída e gera o OpenAPI.
- **Rápido.** Rack 3, Falcon (async, fibers), roteador radix compilado no boot
  e poucas alocações por request. Um benchmark contra Roda e Sinatra roda no
  CI e falha em caso de regressão (veja [benchmarks/](benchmarks/README.md)).

## Requisitos

- Ruby **3.4** ou mais novo. O Boto suporta as versões mantidas pelo core
  team do Ruby.
- Bundler.

## Primeiros passos

```bash
gem install boto-rb-cli
boto new loja            # cria a solution: Botofile, Gemfile, .ruby-version, .gitignore
cd loja
bundle install

boto add library dominio # libs/dominio
boto add webapi pedidos  # apps/pedidos
boto ref pedidos dominio # pedidos passa a enxergar Dominio::

boto run                 # sobe os serviços HTTP em http://127.0.0.1:3000, 3001...
boto test                # roda os testes de todos os projetos
```

As pastas `apps/`, `libs/` e `workers/` nascem no primeiro `boto add` de um
projeto daquele tipo.

## Conceitos

### Botofile

O arquivo na raiz que descreve a solution. Cada projeto declara o template e
as referências:

```ruby
solution "loja"

project "dominio", template: :library
project "pedidos", template: :webapi, refs: %w[dominio]
```

O Boto valida o arquivo: uma referência a um projeto que não existe ou um
ciclo entre projetos é erro. O `boto graph` mostra o grafo.

### Estrutura de pastas

```
loja/
├── Botofile
├── Gemfile
├── apps/        # projetos webapi
│   └── pedidos/
│       ├── config/app.rb   # plugins do projeto
│       ├── endpoints/      # um endpoint por classe
│       ├── schemas/        # contratos de entrada e saída
│       ├── operations/     # regras de negócio (casos de uso)
│       ├── models/         # persistência
│       └── test/           # testes do projeto
└── libs/        # projetos library (schemas/, operations/, models/ e test/)
```

### Namespaces e isolamento

Cada projeto tem um namespace derivado do nome, e o Zeitwerk carrega
`endpoints/`, `schemas/`, `operations/` e `models/` sob ele:

| Arquivo | Constante |
|---|---|
| `apps/pedidos/endpoints/users/show.rb` | `Pedidos::Users::Show` |
| `apps/pedidos/schemas/user_schema.rb` | `Pedidos::UserSchema` |
| `libs/dominio/operations/find_user.rb` | `Dominio::FindUser` |

Isso evita colisões quando a solution roda num processo só e reforça o
isolamento: `pedidos` usa `Dominio::` porque referencia `dominio`. O
`boto check` aponta um projeto que use o namespace de outro sem referência.

## Endpoints

Um endpoint por classe, herdando de `Boto::Endpoint`. A classe declara a rota,
os params tipados e o retorno. A lógica fica em `call`, que recebe os params
como keyword args. Não existe arquivo de rotas: tudo o que está em
`endpoints/` é descoberto no boot.

```ruby
# apps/pedidos/endpoints/users/show.rb
class Pedidos::Users::Show < Boto::Endpoint
  get "/users/:id"
  summary "Mostra um usuário"
  param :id, Integer, min: 1
  returns Pedidos::UserSchema
  errors 404

  USERS = { 1 => { id: 1, name: "Ana" } }.freeze

  def call(id:)
    USERS[id] or not_found("user #{id} not found")
  end
end
```

- **Verbos:** `get`, `post`, `put`, `patch`, `delete` e `query`. `HEAD`
  responde a partir do `get`. O `query` é o método HTTP QUERY: seguro e
  idempotente como o GET, mas com a consulta no corpo, para buscas que não
  cabem na query string.
- **Params:** os do path vêm da rota, e os demais da query string ou do corpo
  JSON. Opções: `required: false`, `default:`, `min:`, `max:`, `enum:` e
  `pattern:`. Listas são declaradas com colchetes (`[Integer]`).
  Só os params declarados chegam ao `call`, já convertidos para o tipo.
- **Corpo com schema:** `body CreateUserSchema` chega ao `call` como `body:`,
  já validado.
- **Retorno:** `returns UserSchema` ou `returns [UserSchema]` serializa a
  saída. Sem `returns`, o retorno vira JSON direto, e `nil` vira `204`.
- **Status:** `status 201` muda o status de sucesso.
- **Erros:** `not_found`, `bad_request` e `unprocessable` respondem com
  `application/problem+json`. Param inválido responde `422`, rota inexistente
  `404`, e verbo não suportado `405` com o header `Allow`. `errors 404, 409`
  documenta outros status no OpenAPI.

```ruby
class Pedidos::Users::Search < Boto::Endpoint
  query "/users/search"
  body Pedidos::UserFilterSchema
  returns [Pedidos::UserSchema]

  def call(body:) = Dominio::SearchUsers.call(body)
end
```

## Schemas

```ruby
# apps/pedidos/schemas/user_schema.rb
class Pedidos::UserSchema < Boto::Schema
  field :id, Integer
  field :name, String, max: 80
  field :email, String, pattern: /\A[^@\s]+@[^@\s]+\z/
  field :role, String, enum: %w[admin customer]
  field :tags, [String], required: false
  field :address, Pedidos::AddressSchema, required: false
end
```

- **Tipos:** `String`, `Integer`, `Float`, `Boto::Boolean`, `Date`, `Time`,
  listas (`[Tipo]`) e outros schemas.
- **Restrições:** `min:` e `max:`, que valem para valores, tamanho de texto ou
  número de itens; `enum:`; `pattern:`, sempre ancorado com `\A` e `\z`; `required: false`.
- **Usos do mesmo schema:** validar a entrada (`body`), serializar a saída
  (`returns`) e gerar os componentes do OpenAPI.

## Plugins

Recursos transversais são plugins ligados no projeto, em `config/app.rb`, e
nunca dentro dos endpoints. O núcleo é mínimo.

```ruby
# apps/pedidos/config/app.rb
Boto.configure do |app|
  app.use :health
  app.use :hosts, allow: %w[api.loja.com]
  app.use :cors, origins: %w[https://painel.loja.com]
  app.use :auth, strategy: :bearer, tokens: -> { ENV.fetch("API_TOKENS").split(",") }
  app.use :rate_limit, limit: 300, period: 60
  app.use :openapi, version: "1.4.0"
end
```

Um endpoint pode abrir mão de um plugin de endpoint (`skip :auth`,
`skip :rate_limit`) ou trocar a autenticação do projeto pela sua
(`authenticate`), como num webhook assinado:

```ruby
class Pedidos::Webhooks::Pagamento < Boto::Endpoint
  post "/webhooks/pagamento"
  authenticate :signature, secret: -> { ENV.fetch("WEBHOOK_SECRET") }, header: "X-Signature"

  def call = nil
end
```

### Plugins disponíveis

| Plugin | Gem | O que faz |
|---|---|---|
| `:health` | `boto-rb` | `GET /health/live` e `GET /health/ready`. O ready roda os `checks:` do projeto e os dos plugins, como o Redis do rate limit, e responde `503` durante o shutdown. Não exige credencial. |
| `:openapi` | `boto-rb` | Serve o documento OpenAPI em qualquer ambiente. Opções: `path:` (`/openapi.json`), `version:` (`"0.0.0"`) e `auth:` (`true`). Por padrão, exige o `:auth` do projeto. |
| `:swagger_ui` | `boto-rb-swaggerui` | Swagger UI em `/docs` (`path:`), com os arquivos embutidos na gem, sem CDN. Precisa do `:openapi`. |
| `:hosts` | `boto-rb-security` | Só aceita os hosts de `allow:`, contra DNS rebinding. |
| `:cors` | `boto-rb-security` | CORS com `origins:`, `methods:`, `headers:`, `expose:`, `credentials:` e `max_age:`. Responde o preflight. |
| `:auth` | `boto-rb-security` | Estratégias `:basic`, `:bearer`, `:api_key`, `:jwt` e `:signature` (webhooks). |
| `:rate_limit` | `boto-rb-security` | Limite por chave (`limit:` e `period:`), em memória. Com o `boto-rb-redis`, a contagem é compartilhada entre processos. |

O `app.use :nome` acha o plugin de qualquer gem do Gemfile, sem `require`
manual.

**A ordem é fixa**, não importa a ordem das linhas no `config/app.rb`:
`health → hosts → cors → secure_headers → sessions → csrf → openapi →
swagger_ui → auth → rate_limit`. Assim, o CORS responde o preflight antes do
`:auth` e os probes de health não exigem credencial.

- **Plugins globais:** rodam antes do roteamento e valem também para `404`,
  `405` e preflight.
- **Plugins de endpoint (`:auth` e `:rate_limit`):** rodam depois do
  roteamento e aceitam `skip`.

**Segredos:** vêm de lambdas (`-> { ENV.fetch(...) }`), lidas uma vez no boot.
Opções inválidas e segredos ausentes fazem o boot falhar com uma mensagem
clara, não o primeiro request.

### OpenAPI e Swagger UI

- **Em development,** o `boto run` serve o documento em `GET /openapi.json`.
- **Em produção, para gerar o arquivo:**
  ```bash
  boto openapi pedidos -o openapi.json --api-version 1.4.0
  ```
- **Em produção, para servir pelo próprio serviço,** com a UI:
  ```ruby
  # Gemfile: gem "boto-rb-swaggerui"
  app.use :openapi, auth: false   # ou proteja com app.use :auth, strategy: :basic
  app.use :swagger_ui             # GET /docs
  ```

O navegador não envia bearer token nem API key sozinho. Por isso o
`:swagger_ui` só aceita um documento público ou protegido por `:basic`. O boot
explica isso se a configuração não servir.

## Rodando

```bash
boto run                     # todos os serviços HTTP, a partir da porta 3000
boto run pedidos --port 4000 # só um projeto
```

- **Ambiente:** o `boto run` sobe com `BOTO_ENV=development`. Fora dele, o
  padrão é `production`.
- **Graceful shutdown:** no `SIGTERM` ou `SIGINT`, o readiness passa a
  responder `503`. Depois de `--drain-delay`, o servidor para de aceitar
  conexões e espera até `--shutdown-timeout` segundos (25 por padrão) pelos
  requests em andamento.

## Testes

Os testes ficam dentro de cada projeto, com Minitest, e o `boto test` roda
todos:

```bash
boto test                    # todos os projetos
boto test pedidos            # um projeto
boto test --affected         # só os projetos afetados desde a main
```

**Endpoint testado chamando `call` direto,** sem servidor:

```ruby
# apps/pedidos/test/endpoints/users/show_test.rb
require "test_helper"

class Pedidos::Users::ShowTest < Minitest::Test
  def test_returns_the_user
    assert_equal "Ana", Pedidos::Users::Show.new.call(id: 1)[:name]
  end
end
```

**Pilha completa (roteamento, params, plugins):** o `test_helper.rb` gerado
expõe o app do projeto como `APP`, para usar com `Rack::MockRequest`:

```ruby
response = Rack::MockRequest.new(APP).get("/users/1", "HTTP_AUTHORIZATION" => "Bearer test-token")
assert_equal 200, response.status
```

## Referência do CLI

| Comando | O que faz |
|---|---|
| `boto new <nome>` | Cria uma solution. Não existe projeto avulso. |
| `boto add <webapi\|library> <nome>` | Adiciona um projeto e registra no Botofile. |
| `boto ref <projeto> <referência>` | Adiciona uma referência; recusa ciclos. |
| `boto graph` | Mostra o grafo de dependências. |
| `boto check [projeto]` | Confere o isolamento entre projetos. |
| `boto run [projeto]` | Sobe os serviços num processo (`--port`, `--host`, `--shutdown-timeout`, `--drain-delay`). |
| `boto test [projeto]` | Roda os testes (`--affected`, `--base REF`). |
| `boto openapi <projeto>` | Imprime ou grava (`-o`) o documento OpenAPI (`--api-version`). |

`boto help <comando>` mostra as opções, e `boto -v` mostra a versão.

## Gems

| Gem | Conteúdo |
|---|---|
| [`boto-rb`](gems/boto-rb) | Core: endpoints, roteador, params, schemas, OpenAPI, Botofile, isolamento, plugins `:health` e `:openapi`. |
| [`boto-rb-cli`](gems/boto-rb-cli) | O comando `boto` e os templates oficiais. |
| [`boto-rb-security`](gems/boto-rb-security) | `:hosts`, `:cors`, `:auth` e `:rate_limit`. |
| [`boto-rb-redis`](gems/boto-rb-redis) | Store Redis do `:rate_limit`. |
| [`boto-rb-swaggerui`](gems/boto-rb-swaggerui) | Plugin `:swagger_ui`. |

O módulo Ruby é sempre `Boto`, e o executável é `boto`. O nome `boto` no
RubyGems já era de outro projeto, por isso as gems se chamam `boto-rb-*`.

## Estado do projeto

O Boto está antes da 1.0: versões minor ainda podem quebrar compatibilidade,
sempre registrada no [CHANGELOG](CHANGELOG.md), com o passo de migração.

**Já existe:**
- solutions, isolamento e grafo;
- templates `webapi` e `library`;
- endpoints, schemas e OpenAPI;
- os plugins da tabela acima;
- health checks e graceful shutdown.

**Próximos passos:**
- template `microservice`, com OpenTelemetry, Dockerfile e deploy;
- template `worker`, para filas, com retry e dead letter;
- templates distribuídos como gems (`boto templates install`);
- template `spa` (React ou Vue com Vite), com cliente TypeScript gerado do
  OpenAPI;
- template `web`, com Hotwire e os plugins `:sessions` e `:csrf`;
- credentials criptografadas;
- imagens Docker por serviço.

## Contribuindo

```bash
git clone https://github.com/EvoTechBuilder/boto-rb.git
cd boto-rb
bundle install
bundle exec rake test        # suítes de todas as gems
```

- **Testes:** Minitest. A CI roda Ruby 3.4, 4.0 e `ruby-head`, cada um com e
  sem YJIT.
- **Redis:** os testes do `boto-rb-redis` usam um Redis real (`REDIS_URL`) e
  são pulados sem ele.
- **Commits:** seguem [Conventional Commits](https://www.conventionalcommits.org/).
- **Mudanças maiores:** começam por uma proposta em
  [docs/proposals/](docs/proposals).

## Licença

[MIT](LICENSE). O Swagger UI embutido no `boto-rb-swaggerui` mantém a licença
Apache-2.0 dele.
