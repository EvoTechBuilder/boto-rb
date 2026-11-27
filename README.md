<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/boto-logo-dark.svg">
  <img src="docs/assets/boto-logo.svg" alt="Boto" height="72">
</picture>

**Framework Ruby para APIs e microservices, organizado em solutions.**

[![Gem](https://img.shields.io/gem/v/boto-rb-cli?label=boto-rb-cli&color=cc342d)](https://rubygems.org/gems/boto-rb-cli)
[![CI](https://github.com/EvoTechBuilder/boto-rb/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/EvoTechBuilder/boto-rb/actions/workflows/ci.yml)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.4-cc342d)](https://www.ruby-lang.org/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

[Primeiros passos](#primeiros-passos) ·
[Endpoints](#endpoints) ·
[Plugins](#plugins) ·
[CLI](#referência-do-cli) ·
[Changelog](CHANGELOG.md)

</div>

---

O Boto organiza um sistema Ruby em **projetos isolados** (APIs, bibliotecas e,
em breve, workers e frontends) dentro de uma mesma **solution**, com
referências explícitas entre eles. No desenvolvimento, tudo roda num processo
só. Em produção, cada serviço roda separado, sem mudar o código.

```bash
gem install boto-rb-cli
boto new loja && cd loja
bundle install
boto add webapi pedidos
boto run
```

Open source, sob a licença [MIT](LICENSE), mantido pela
[Evo Tech Builder](https://github.com/EvoTechBuilder).

## Sumário

- **Visão geral**
  - [Por que o Boto](#por-que-o-boto)
  - [Requisitos](#requisitos)
  - [Primeiros passos](#primeiros-passos)
- **Conceitos**
  - [Botofile](#botofile)
  - [Estrutura de pastas](#estrutura-de-pastas)
  - [Namespaces e isolamento](#namespaces-e-isolamento)
- **Construindo uma API**
  - [Endpoints](#endpoints)
  - [Schemas](#schemas)
  - [Operations](#operations)
  - [Erros](#erros)
- **Plugins**
  - [Configurando plugins](#plugins)
  - [Plugins disponíveis](#plugins-disponíveis)
  - [Ordem de execução](#ordem-de-execução)
  - [Configuração por ambiente](#configuração-por-ambiente)
  - [Variáveis e arquivos `.env`](#variáveis-e-arquivos-env)
  - [OpenAPI e Swagger UI](#openapi-e-swagger-ui)
- **Operação**
  - [Rodando a solution](#rodando-a-solution)
  - [Gerando código](#gerando-código)
  - [Testes](#testes)
- **Referência**
  - [CLI](#referência-do-cli)
  - [Gems](#gems)
- **Projeto**
  - [Contribuindo](#contribuindo)
  - [Licença](#licença)

## Por que o Boto

Uma *solution* reúne vários projetos com referências explícitas entre eles.
Sem isso, um sistema Ruby costuma virar um monólito, ou cada serviço vive num
repositório com cópias do código compartilhado.

| | |
|---|---|
| **Uma solution, vários projetos** | O [`Botofile`](#botofile) declara os projetos e quem referencia quem. |
| **Isolamento de verdade** | Um projeto só enxerga o código dos projetos que referencia. O `boto check` aponta qualquer violação. |
| **Um processo no dev, serviços em produção** | O `boto run` sobe a solution inteira num processo, sem mudar o código. |
| **Contratos declarados uma vez** | O mesmo [schema](#schemas) valida a entrada, serializa a saída e gera o [OpenAPI](https://www.openapis.org/). |
| **Desempenho** | [Rack 3](https://github.com/rack/rack), [Falcon](https://github.com/socketry/falcon) (async, fibers), roteador radix compilado no boot e poucas alocações por request. O CI compara com Roda e Sinatra e falha em caso de regressão ([benchmarks](benchmarks/README.md)). |

<p align="right"><a href="#sumário">↑ voltar ao sumário</a></p>

## Requisitos

- [Ruby](https://www.ruby-lang.org/) **3.4** ou mais novo. O Boto acompanha as
  versões mantidas pelo core team do Ruby.
- [Bundler](https://bundler.io/).

## Primeiros passos

```bash
gem install boto-rb-cli

boto new loja            # cria a solution: Botofile, Gemfile, .ruby-version e .gitignore
cd loja
bundle install

boto add library dominio # cria libs/dominio
boto add webapi pedidos  # cria apps/pedidos
boto ref pedidos dominio # pedidos passa a enxergar Dominio::

boto run                 # sobe os serviços HTTP em http://127.0.0.1:3000, 3001...
boto test                # roda os testes de todos os projetos
```

> [!TIP]
> As pastas `apps/`, `libs/` e `workers/` não vêm vazias no `boto new`: cada
> uma nasce no primeiro `boto add` de um projeto daquele tipo.

<p align="right"><a href="#sumário">↑ voltar ao sumário</a></p>

## Conceitos

### Botofile

O arquivo na raiz que descreve a solution. Cada projeto declara o template e
as referências:

```ruby
solution "loja"

project "dominio", template: :library
project "pedidos", template: :webapi, refs: %w[dominio]
```

O Boto valida o arquivo: uma referência a um projeto que não existe, ou um
ciclo entre projetos, é erro. O `boto graph` mostra o grafo de dependências.

### Estrutura de pastas

```
loja/
├── Botofile
├── Gemfile
├── apps/                     # projetos webapi
│   └── pedidos/
│       ├── config/app.rb     # plugins do projeto
│       ├── endpoints/        # um endpoint por classe
│       ├── schemas/          # contratos de entrada e saída
│       ├── operations/       # regras de negócio (casos de uso)
│       ├── models/           # persistência
│       └── test/             # testes do projeto
└── libs/                     # projetos library: schemas/, operations/, models/ e test/
```

### Namespaces e isolamento

Cada projeto tem um namespace derivado do nome. O
[Zeitwerk](https://github.com/fxn/zeitwerk) carrega `endpoints/`, `schemas/`,
`operations/` e `models/` sob ele:

| Arquivo | Constante |
|---|---|
| `apps/pedidos/endpoints/users/show.rb` | `Pedidos::Users::Show` |
| `apps/pedidos/schemas/user_schema.rb` | `Pedidos::UserSchema` |
| `libs/dominio/operations/search_users.rb` | `Dominio::SearchUsers` |

Isso evita colisões quando a solution roda num processo só e reforça o
isolamento: `pedidos` usa `Dominio::` porque referencia `dominio`. O
`boto check` aponta o uso do namespace de um projeto sem a referência.

<p align="right"><a href="#sumário">↑ voltar ao sumário</a></p>

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

| Declaração | O que faz |
|---|---|
| `get`, `post`, `put`, `patch`, `delete`, `query` | Verbo e rota. O `HEAD` responde a partir do `get`. |
| `param :nome, Tipo, ...` | Param tipado. Os do path vêm da rota; os demais, da query string ou do corpo JSON. Opções: `required: false`, `default:`, `min:`, `max:`, `enum:` e `pattern:`. Listas usam colchetes: `[Integer]`. |
| `body Schema` | Corpo validado pelo schema, entregue ao `call` como `body:`. |
| `returns Schema` / `returns [Schema]` | Serializa a saída. Sem `returns`, o retorno vira JSON direto, e `nil` vira `204`. |
| `status 201` | Status de sucesso. |
| `summary "..."` / `errors 404, 409` | Documentação no OpenAPI. |
| `skip :plugin` / `authenticate :estratégia, ...` | Exceções aos [plugins](#plugins) do projeto. |

Só os params declarados chegam ao `call`, já convertidos para o tipo.

**O verbo `query`** corresponde ao método HTTP
[QUERY](https://datatracker.ietf.org/doc/draft-ietf-httpbis-safe-method-w-body/):
seguro e idempotente como o GET, mas com a consulta no corpo. Serve para
buscas que não cabem na query string.

```ruby
# apps/pedidos/endpoints/users/search.rb
class Pedidos::Users::Search < Boto::Endpoint
  query "/users/search"
  body Pedidos::UserFilterSchema
  returns [Pedidos::UserSchema]

  def call(body:) = Dominio::SearchUsers.call(body)
end
```

<p align="right"><a href="#sumário">↑ voltar ao sumário</a></p>

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

| | |
|---|---|
| **Tipos** | `String`, `Integer`, `Float`, `Boto::Boolean`, `Date`, `Time`, listas (`[Tipo]`) e outros schemas. |
| **Restrições** | `min:` e `max:` (valor, tamanho do texto ou número de itens), `enum:`, `pattern:` (sempre ancorado com `\A` e `\z`) e `required: false`. |
| **Usos** | Validar a entrada (`body`), serializar a saída (`returns`) e gerar os componentes do OpenAPI. |

## Operations

Regras de negócio ficam em `operations/`, como subclasses de
`Boto::Operation`. A operation é chamada com `.call`, que sempre devolve um
`Boto::Operation::Result`:

```ruby
# apps/catalogo/operations/create_product.rb
class Catalogo::CreateProduct < Boto::Operation
  def initialize(input, repository: Catalogo::Products)
    super(input)
    @repository = repository
  end

  def call
    return failure(:conflict, "a product named #{input.name} already exists") if @repository.exists?(input.name)

    @repository.create(input)              # um retorno comum vira success(...)
  end
end
```

```ruby
result = Catalogo::CreateProduct.call(input)
result.success?          # true ou false
result.value             # o valor, no sucesso
result.failure.code      # :conflict, na falha
result.value!            # o valor, ou levanta Boto::Operation::FailedError
```

- **Sucesso implícito, falha explícita:** qualquer retorno vira sucesso, e só
  `failure(:codigo, "mensagem", **details)` é falha. Exceções continuam sendo
  exceções (bug vira `500`).
- **`new` é privado:** a única entrada é o `.call`, com uma instância nova por
  chamada. Dependências entram pelo `initialize`, o que facilita os testes.
- **No endpoint:** devolver o `Result` basta. O sucesso segue o `returns` e o
  `status`, e a falha vira problem+json com o status do código, mais o campo
  `code` na resposta. Os `details` nunca vão para o cliente.

  ```ruby
  def call(body:) = Catalogo::CreateProduct.call(body)
  ```

  | `code` | Status |
  |---|---|
  | `:not_found` | 404 |
  | `:conflict` | 409 |
  | `:unauthorized` | 401 |
  | `:forbidden` | 403 |
  | `:invalid` e qualquer outro | 422 |

## Erros

As respostas de erro seguem o formato *Problem Details*
([RFC 9457](https://www.rfc-editor.org/rfc/rfc9457)), com
`content-type: application/problem+json`:

```json
{ "type": "about:blank", "title": "Unprocessable Content", "status": 422,
  "errors": [{ "param": "id", "message": "must be greater than or equal to 1" }] }
```

| Situação | Status |
|---|---|
| Param ou corpo inválido | `422`, com a lista de `errors` |
| Rota inexistente | `404` |
| Verbo não suportado | `405`, com o header `Allow` |
| `not_found`, `bad_request`, `unprocessable` no endpoint | `404`, `400`, `422` |
| Exceção não tratada | `500`, com detalhes só em development |

<p align="right"><a href="#sumário">↑ voltar ao sumário</a></p>

## Plugins

Recursos transversais são plugins ligados no projeto, em `config/app.rb`, e
nunca dentro dos endpoints. O núcleo é mínimo, e o `app.use :nome` acha o
plugin de qualquer gem do Gemfile, sem `require` manual.

```ruby
# apps/pedidos/config/app.rb
Boto.configure do |app|
  app.use :health
  app.use :hosts, allow: %w[api.loja.com]
  app.use :cors, origins: %w[https://painel.loja.com]
  app.use :auth, strategy: :bearer, tokens: -> { ENV.fetch("API_TOKENS").split(",") }
  app.use :rate_limit, limit: 300, period: 60
  app.use :openapi, title: "Pedidos API", description: "Pedidos e pagamentos da Loja.", version: "1.4.0"
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

> [!NOTE]
> Segredos entram como lambdas (`-> { app.env.fetch(...) }`), lidas uma vez no
> boot. Opções inválidas e segredos ausentes fazem o boot falhar com uma
> mensagem clara, não o primeiro request.

### Configuração por ambiente

O `config/app.rb` vale para todos os ambientes, e o
`config/environments/<BOTO_ENV>.rb` ajusta o que muda. Um `app.use` no arquivo
do ambiente mescla as opções com o geral, e `app.remove` tira um plugin:

```ruby
# config/app.rb
Boto.configure do |app|
  app.use :auth, strategy: :bearer, tokens: -> { app.env.fetch("API_TOKENS").split(",") }
  app.use :rate_limit, limit: 300, period: 60
end

# config/environments/development.rb
Boto.configure do |app|
  app.use :auth, tokens: %w[dev-token]   # só troca os tokens; strategy continua :bearer
  app.use :swagger_ui                    # plugin só do dev
end

# config/environments/test.rb
Boto.configure do |app|
  app.use :auth, tokens: %w[test-token]
  app.remove :rate_limit
end
```

Os plugins são criados no fim, já com as opções finais. Por isso a lambda de
produção do `app.rb` nem roda em development quando o ambiente a substitui.

### Variáveis e arquivos `.env`

O Boto lê os arquivos `.env` sozinho. Vence o primeiro que tiver a chave:

1. as variáveis já exportadas no processo (shell, CI, orquestrador);
2. `.env.<env>.local`;
3. `.env.local` (não é lido no `test`);
4. `.env.<env>`;
5. `.env`.

- **`.env` da solution (raiz):** compartilhados, também vão para o `ENV`, sem
  sobrescrever.
- **`.env` de cada projeto (`apps/<projeto>/`):** ficam só no `app.env`
  daquele projeto. Assim `catalogo` e `pedidos` podem ter cada um o seu
  `DATABASE_URL`, mesmo no mesmo `boto run`.
- **`app.env` em qualquer lugar do projeto:**
  ```ruby
  app.use :cors, origins: app.env.fetch("CORS_ORIGINS", "").split(",")      # config
  def call = { url: app.env.fetch("FRONTEND_URL") }              # endpoint ou operation
  Catalogo.app.env.fetch("FRONTEND_URL")                         # qualquer código do projeto
  ```
- **Formato:** `CHAVE=valor`, `export`, comentários, aspas simples (literal)
  e duplas (`\n`, `\t`). Não há interpolação nem `$(comando)`: ler um `.env`
  nunca executa nada.
- **Git:** o `.gitignore` do `boto new` ignora todos os `.env*`, exceto o
  `.env.example`.

### Plugins disponíveis

| Plugin | Gem | O que faz |
|---|---|---|
| `:health` | [`boto-rb`](gems/boto-rb) | `GET /health/live` e `GET /health/ready`. O ready roda os `checks:` do projeto e os dos plugins (como o Redis do rate limit) e responde `503` durante o shutdown. Não exige credencial. |
| `:openapi` | [`boto-rb`](gems/boto-rb) | Serve o documento OpenAPI em qualquer ambiente: `path:` (`/openapi.json`), `title:` (o namespace do projeto), `description:`, `version:` (`"0.0.0"`) e `auth:` (`true`, protegido pelo `:auth` do projeto). |
| `:swagger_ui` | [`boto-rb-swaggerui`](gems/boto-rb-swaggerui) | [Swagger UI](https://swagger.io/tools/swagger-ui/) em `/docs` (`path:`), com os arquivos embutidos na gem, sem CDN. Precisa do `:openapi`. |
| `:hosts` | [`boto-rb-security`](gems/boto-rb-security) | Só aceita os hosts de `allow:`, contra DNS rebinding. |
| `:cors` | [`boto-rb-security`](gems/boto-rb-security) | [CORS](https://developer.mozilla.org/docs/Web/HTTP/CORS) com `origins:`, `methods:`, `headers:`, `expose:`, `credentials:` e `max_age:`. Responde o preflight. |
| `:auth` | [`boto-rb-security`](gems/boto-rb-security) | Estratégias `:basic`, `:bearer`, `:api_key`, `:jwt` e `:signature` (webhooks). |
| `:rate_limit` | [`boto-rb-security`](gems/boto-rb-security) | Limite por chave (`limit:` e `period:`), em memória. Com o [`boto-rb-redis`](gems/boto-rb-redis), a contagem é compartilhada entre processos. |

### Ordem de execução

A ordem é fixa, não importa a ordem das linhas no `config/app.rb`:

```
health → hosts → cors → secure_headers → sessions → csrf → openapi → swagger_ui → auth → rate_limit
```

- **Plugins globais** rodam antes do roteamento e valem também para `404`,
  `405` e preflight.
- **Plugins de endpoint** (`:auth` e `:rate_limit`) rodam depois do roteamento
  e aceitam `skip`.
- Por isso o CORS responde o preflight antes do `:auth`, e os probes de health
  não exigem credencial.

### OpenAPI e Swagger UI

| Onde | Como |
|---|---|
| **Development** | O `boto run` serve o documento em `GET /openapi.json`, sem configuração. |
| **Arquivo** | `boto openapi pedidos -o openapi.json --api-version 1.4.0` |
| **Produção, pelo serviço** | `app.use :openapi` e, para a UI, `app.use :swagger_ui` |

```ruby
# Gemfile: gem "boto-rb-swaggerui"
app.use :openapi, auth: false   # ou proteja com app.use :auth, strategy: :basic
app.use :swagger_ui             # GET /docs
```

> [!IMPORTANT]
> O navegador não envia bearer token nem API key sozinho. Por isso o
> `:swagger_ui` só aceita um documento público ou protegido por `:basic`, e o
> boot explica isso quando a configuração não serve.

<p align="right"><a href="#sumário">↑ voltar ao sumário</a></p>

## Rodando a solution

```bash
boto run                     # todos os serviços HTTP, a partir da porta 3000
boto run pedidos --port 4000 # só um projeto
```

- **Ambiente:** o `boto run` sobe com `BOTO_ENV=development`. Fora dele, o
  padrão é `production`.
- **Reload automático:** em development, o primeiro request depois de salvar
  um arquivo em `endpoints/`, `schemas/`, `operations/`, `models/` ou
  `config/` já usa o código novo, sem reiniciar o processo. Se o código novo
  não carregar, a resposta é um `500` com o erro, e o servidor segue de pé
  até a correção. `--no-reload` desliga. Mudanças no `Gemfile`, ou no
  `Botofile` que adicionam ou removem projetos, pedem reiniciar.
- **Graceful shutdown:** no `SIGTERM` ou `SIGINT`, o readiness passa a
  responder `503`. Depois de `--drain-delay`, o servidor para de aceitar
  conexões e espera até `--shutdown-timeout` segundos (25 por padrão) pelos
  requests em andamento.

## Gerando código

O `boto generate` (ou `boto g`) cria o arquivo na pasta certa, com o namespace
do projeto, e o teste em `test/`:

```bash
boto g schema catalogo product name:string price:float tags:[string] available_on:date?
boto g endpoint catalogo products/show get /products/:id id:integer --returns product
boto g operation catalogo create_product
boto g model catalogo product id:integer name:string
```

- **Tipos dos campos:** `string`, `integer`, `float`, `boolean`, `date`,
  `time`, listas (`[tipo]`) e outros schemas do projeto pelo nome. Um `?` no
  fim torna o campo opcional.
- **Testes gerados:** falham com `flunk` até serem escritos, para não passar
  verde sem asserção. `--skip-tests` pula o teste num comando, e
  `generators tests: false` no Botofile desliga para a solution, com exceção
  por projeto em `generators: { tests: true }`.
- **Arquivos existentes:** nunca são sobrescritos sem `--force`.
- **Operations:** são verbos sem pasta (`create_product`), porque endpoints e
  operations dividem o namespace do projeto.

## Testes

Os testes ficam dentro de cada projeto, com
[Minitest](https://github.com/minitest/minitest), e o `boto test` roda todos:

```bash
boto test               # todos os projetos
boto test pedidos       # um projeto
boto test --affected    # só os projetos afetados desde a main
```

**Endpoint testado chamando `call` direto**, sem servidor:

```ruby
# apps/pedidos/test/endpoints/users/show_test.rb
require "test_helper"

class Pedidos::Users::ShowTest < Minitest::Test
  def test_returns_the_user
    assert_equal "Ana", Pedidos::Users::Show.new.call(id: 1)[:name]
  end
end
```

**Pilha completa** (roteamento, params e plugins): o `test_helper.rb` gerado
expõe o app do projeto como `APP`, para usar com `Rack::MockRequest`:

```ruby
response = Rack::MockRequest.new(APP).get("/users/1", "HTTP_AUTHORIZATION" => "Bearer test-token")
assert_equal 200, response.status
```

<p align="right"><a href="#sumário">↑ voltar ao sumário</a></p>

## Referência do CLI

| Comando | O que faz |
|---|---|
| `boto new <nome>` | Cria uma solution. Não existe projeto avulso. |
| `boto add <webapi\|library> <nome>` | Adiciona um projeto e o registra no Botofile. |
| `boto ref <projeto> <referência>` | Adiciona uma referência e recusa ciclos. |
| `boto generate <tipo> <projeto> <nome>` | Gera schema, model, endpoint ou operation com o teste (`boto g`, `--skip-tests`, `--force`). |
| `boto graph` | Mostra o grafo de dependências. |
| `boto check [projeto]` | Confere o isolamento entre projetos. |
| `boto run [projeto]` | Sobe os serviços num processo, com reload em development (`--port`, `--host`, `--no-reload`, `--shutdown-timeout`, `--drain-delay`). |
| `boto test [projeto]` | Roda os testes (`--affected`, `--base REF`). |
| `boto openapi <projeto>` | Imprime ou grava (`-o`) o documento OpenAPI (`--api-version`). |

`boto help <comando>` mostra as opções, e `boto -v`, a versão.

## Gems

| Gem | Conteúdo |
|---|---|
| [`boto-rb`](https://rubygems.org/gems/boto-rb) | Core: endpoints, roteador, params, schemas, OpenAPI, Botofile, isolamento e os plugins `:health` e `:openapi`. |
| [`boto-rb-cli`](https://rubygems.org/gems/boto-rb-cli) | O comando `boto` e os templates oficiais. |
| [`boto-rb-security`](https://rubygems.org/gems/boto-rb-security) | `:hosts`, `:cors`, `:auth` e `:rate_limit`. |
| [`boto-rb-redis`](https://rubygems.org/gems/boto-rb-redis) | Store Redis do `:rate_limit`. |
| [`boto-rb-swaggerui`](gems/boto-rb-swaggerui) | Plugin `:swagger_ui`. |

O módulo Ruby é sempre `Boto`, e o executável é `boto`. As gems se chamam
`boto-rb-*` porque o nome `boto` já existia no RubyGems.

<p align="right"><a href="#sumário">↑ voltar ao sumário</a></p>

## Contribuindo

```bash
git clone https://github.com/EvoTechBuilder/boto-rb.git
cd boto-rb
bundle install
bundle exec rake test   # suítes de todas as gems
```

- **CI:** Ruby 3.4, 4.0 e `ruby-head`, cada um com e sem YJIT.
- **Redis:** os testes do `boto-rb-redis` usam um Redis real (`REDIS_URL`) e
  são pulados sem ele.
- **Commits:** seguem [Conventional Commits](https://www.conventionalcommits.org/).
- **Mudanças maiores:** começam por uma proposta em
  [docs/proposals/](docs/proposals).
- **Versões:** [Semantic Versioning](https://semver.org/), com o histórico no
  [CHANGELOG](CHANGELOG.md).

## Licença

Distribuído sob a licença [MIT](LICENSE). O Swagger UI embutido no
`boto-rb-swaggerui` mantém a licença
[Apache-2.0](gems/boto-rb-swaggerui/vendor/swagger-ui/LICENSE) dele.

<p align="right"><a href="#sumário">↑ voltar ao sumário</a></p>
