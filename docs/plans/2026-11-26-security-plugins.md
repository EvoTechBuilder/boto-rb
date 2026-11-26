# Plano — Plugins de segurança

Status: **concluído** (2026-11-26)
Proposta: `docs/proposals/0004-security-plugins.md`

## Objetivo

Implementar `Boto.configure` e os plugins `:hosts`, `:cors`, `:auth` (com as
estratégias basic, bearer, api_key, jwt e signature) e `:rate_limit`, além de
`skip`, `authenticate` e `principal` no endpoint. Também entram os
`securitySchemes` no OpenAPI e o template `webapi` com os plugins padrão.

Os plugins ficam na gem nova `gems/boto-security`. O core recebe só a base
(`Boto.configure`, `Plugin`, `Stack`, `Configuration` e os erros), a DSL do
endpoint, a integração no App e no Boot, e o OpenAPI.

## Fora de escopo

- `:secure_headers`, `:sessions` e `:csrf`.
- A store Redis do `:rate_limit`.
- O `boto credentials`.

## Contratos entre tasks

Eles são fixados aqui para que as tasks paralelas não dependam umas das outras.

### Base (P1)

```ruby
class Boto::Plugin
  ORDER = %i[hosts cors secure_headers sessions csrf auth rate_limit].freeze
  SCOPES = %i[global endpoint].freeze

  def self.scope(value = nil)      # macro na subclasse (scope :endpoint) e leitor; padrão :endpoint
  def self.plugin_name             # :rate_limit para Boto::Plugins::RateLimit (snake_case do último segmento)
  def self.order_index             # posição em ORDER; plugins de terceiros vão para o fim, na ordem de declaração

  def initialize(env_name:, **options)  # valida e lê segredos (chama as lambdas) no boot; ArgumentError se inválido
  def call(env, app)                    # faz o trabalho e chama app.call(env) para seguir, ou devolve a resposta
end

Boto::Plugin::Stack.build(plugins, inner) # => callable(env); plugins já ordenados; o primeiro é o mais externo

class Boto::Configuration
  def initialize(env_name:)
  def use(plugin, **options)  # Symbol -> Boto::Plugins.const_get(camelize) com nome /\A[a-z][a-z0-9_]*\z/; ou Class < Boto::Plugin
                              # constante inexistente -> ArgumentError 'unknown plugin :x (add gem "boto-security" to the Gemfile)'
                              # duplicado -> ArgumentError; instancia com env_name:
  def plugins                 # Array congelado, ordenado por order_index
  def global_plugins / endpoint_plugins
  def plugin(name)            # instância ou nil
  def self.load(path, env_name:)  # avalia o arquivo capturando o Boto.configure; sem arquivo -> configuração vazia
end

Boto.configure { |app| ... }  # definido em lib/boto.rb; delega para Boto::Configuration; fora de um load -> Boto::Configuration::OutsideBootError
```

Novos erros em `http/error.rb`:

- `Unauthorized` (401): recebe `challenge` e manda o header
  `www-authenticate`.
- `Forbidden` (403).
- `TooManyRequests` (429): recebe `retry_after` (segundos) e manda o header
  `retry-after`.

### Estratégias de auth (P5 e P6)

```ruby
class Boto::Plugins::Auth::<Strategy>
  def initialize(**options)   # valida e lê segredos; ArgumentError se inválido
  def authenticate(env)       # => Hash de principal (congelado) ou nil
  def challenge               # => valor do WWW-Authenticate (ex. 'Bearer realm="api"')
  def security_scheme         # => Hash do OpenAPI (ex. { "type" => "http", "scheme" => "bearer" })
end
```

As estratégias e o `Auth` ficam na `boto-security`.

- `Boto::Plugins::Auth.new(env_name:, strategy:, **opts)` resolve
  `Auth::<Strategy>` pelo nome.
- Quando autentica, grava `env["boto.principal"]`. Quando não autentica,
  lança `Unauthorized.new(challenge)`.
- Expõe `strategy` (o objeto da estratégia).

### Endpoint (P7)

- `skip(*names)`: os nomes são Symbols, e o leitor é `skipped_plugins`, um
  Array congelado.
- `authenticate(strategy, **options)`: o leitor `authentication` devolve
  `[strategy, options]` ou nil.
- `principal`, na instância: devolve `env["boto.principal"]`.

### App (P8)

- `Boto::App.new(namespace:, plugins: [], env_name:, error_output:)`:
  - os plugins globais formam uma `Stack` em volta do dispatch;
  - cada rota ganha a pilha de endpoint dela no boot, já sem os `skip`. Se o
    endpoint tem `authenticate`, uma instância própria de `Auth` substitui a
    do projeto.
  - `skip` de um plugin que não está configurado gera `BootError`;
  - os path params vão para `env["boto.path_params"]`.
- `app.auth_for(endpoint)`: devolve a instância de `Auth` que vale para o
  endpoint, ou nil. É o que o OpenAPI usa.
- `Boot#app(name, **opts)`: carrega `config/app.rb` do projeto com
  `Configuration.load`, se existir, e passa `plugins:`.

## Tasks

Cada task roda num subagente `task-runner` (Haiku) e vira um commit. Os
grupos marcados com ∥ rodam em paralelo, com um subagente por task.

### Onda 1 ∥

**P0 — Scaffold da gem `boto-security`**

- **Arquivos novos:** `gems/boto-security/boto-security.gemspec` (depende de
  `boto` `= VERSION` e de `jwt ~> 3.0`, ou da maior versão disponível),
  `Rakefile`, `lib/boto/security.rb` (`Zeitwerk::Loader.for_gem_extension(Boto)`),
  `lib/boto/security/version.rb` (`Boto::Security::VERSION`, igual à do core),
  `test/test_helper.rb` e um teste de versão.
- **Na raiz:** `gemspec path: "gems/boto-security"` no `Gemfile` e a gem em
  `GEM_DIRS` no `Rakefile`.
- **Verificação:** `bundle install` e `rake test` na raiz.

**P1 — Base no core**

- **Arquivos:** `lib/boto.rb` (`Boto.configure`), `lib/boto/plugin.rb`,
  `lib/boto/plugin/stack.rb`, `lib/boto/configuration.rb`,
  `lib/boto/http/error.rb` e os testes.
- **Pasta de plugins:** o core não cria `lib/boto/plugins/`. Os testes usam
  plugins de mentira definidos no próprio teste.

### Onda 2 ∥ (depende de P0 e P1)

Os plugins são criados em `gems/boto-security/lib/boto/plugins/`, e os testes
em `gems/boto-security/test/boto/plugins/`.

- **P2 — `:hosts`** (`plugins/hosts.rb`):
  - `scope :global`;
  - `allow:` aceita nomes exatos e sufixos com `.`;
  - em development, `localhost`, `127.0.0.1` e `[::1]` são liberados;
  - em production sem `allow`, gera `ArgumentError`;
  - um host bloqueado recebe 403.
- **P3 — `:cors`** (`plugins/cors.rb`):
  - `scope :global`;
  - preflight `OPTIONS` com `Access-Control-Request-Method` devolve 204 com
    os headers;
  - uma origem não permitida passa sem headers CORS;
  - `"*"` com `credentials: true` gera `ArgumentError`;
  - os métodos padrão são `GET HEAD POST PUT PATCH DELETE QUERY`.
- **P4 — `:rate_limit`** (`plugins/rate_limit.rb` e
  `plugins/rate_limit/memory_store.rb`):
  - `scope :endpoint`;
  - janela fixa, com relógio injetável (`clock:`);
  - Mutex na store;
  - `key:` é uma lambda, e `trusted_proxies:` libera o `X-Forwarded-For`;
  - headers `RateLimit-*` e 429 com `retry-after`.
- **P5 — `:auth` com `basic`, `bearer` e `api_key`**
  (`plugins/auth.rb` e `plugins/auth/{basic,bearer,api_key}.rb`):
  - comparação constante sobre digests SHA-256 com
    `Rack::Utils.secure_compare`.
- **P6 — `jwt` e `signature`** (`plugins/auth/{jwt,signature}.rb`):
  - a `jwt` é dependência da `boto-security`, então o `require "jwt"` fica no
    próprio arquivo;
  - na `signature`, o corpo bruto é lido e o `rack.input` recebe `rewind`.
- **P7 — Endpoint (core)**: `skip`, `authenticate` e `principal` em
  `gems/boto/lib/boto/endpoint/endpoint.rb`.

### Onda 3

**P8 — App e Boot** (`http/app.rb`, `solution/boot.rb` e
`solution/project_loader.rb`, se necessário; depende de P1 a P7)

- Monta as pilhas e valida os `skip`.
- Expõe `auth_for`.
- O Boot carrega o `config/app.rb`.
- **Onde ficam os testes:** o core não depende da `boto-security`. Os testes
  do core usam plugins de mentira, e os de integração com os plugins reais
  ficam em `gems/boto-security/test/integration/`.
- **Testes de integração:**
  - um preflight sem token passa;
  - um 404 recebe os headers CORS;
  - um `skip` vale só para aquele endpoint;
  - um `authenticate` sobrepõe a estratégia do projeto;
  - o `principal` chega ao endpoint;
  - endpoints sem plugins mantêm as alocações de hoje (teste de alocação).

### Onda 4 ∥

- **P9 — OpenAPI**:
  - `components.securitySchemes` e `security` global quando há auth;
  - `security: []` nos endpoints com `skip :auth`;
  - o snapshot sem auth não muda.
- **P10 — Template webapi**:
  - `templates/solution/Gemfile.erb` ganha `gem "boto-security"`;
  - `templates/webapi/config/app.rb.erb` com `:cors`, `:auth` (bearer) e
    `:rate_limit`;
  - o `health` ganha `skip :auth, :rate_limit`;
  - testes do `add` e um teste de ponta a ponta com `boto test`.
- **P11 — Benchmark**: cenário `db_auth`, só para o Boto, com bearer e
  rate_limit, e testes. O `benchmarks/Gemfile` ganha a `boto-security` (path
  a partir de `BOTO_ROOT`).

### Onda 5 (eu faço)

1. Atualizo a ordem dos plugins no CLAUDE.md.
2. Rodo as suítes e o `allocations.rb`.
3. Faço o fluxo de ponta a ponta com `boto run`:
   - `curl` sem token dá 401 e com token dá 200;
   - o `/health` responde sem token;
   - um preflight CORS funciona.
4. Subo a versão para `0.4.0` nas três gems e atualizo o CHANGELOG.
5. Faço os commits e o push.
