# Boto

Framework Ruby open source (licença MIT) para APIs e microservices, criado pela
Evo Tech Builder. O nome vem do boto, o golfinho da Amazônia.

## Proposta de valor

Organizar projetos Ruby como as *solutions* do .NET: uma solution reúne vários
projetos (frontends, APIs, workers, bibliotecas compartilhadas) com referências
explícitas entre eles. O Ruby não tem nada nativo equivalente; esse é o
diferencial do Boto. Performance alta é um requisito, mas não é o único
argumento.

**Regra:** `boto new` sempre cria uma solution. Não existe projeto avulso.

## Conceitos centrais

- **Botofile**: DSL Ruby na raiz da solution, equivalente ao `.sln`. Cada
  projeto declara o template de origem e suas referências.
  ```ruby
  solution "loja"

  project "dominio",      template: :library
  project "pedidos",      template: :microservice, refs: %w[dominio]
  project "notificacoes", template: :worker,       refs: %w[dominio]
  project "painel",       template: :spa,          refs: %w[pedidos]
  ```
- **Cada projeto Ruby é uma gem.** Referências viram dependências gerenciadas
  pelo Boto; ninguém edita Gemfile na mão.
- **Isolamento**: um projeto só enxerga o código dos projetos que referencia
  (carregamento isolado por projeto via Zeitwerk). Acesso sem referência é erro.
- **Modo dev**: a solution inteira roda num único processo (monólito modular).
  **Produção**: cada serviço roda separado, sem mudar código.
- **Build**: cada serviço gera uma imagem Docker só com seu código e as libs que
  referencia. Grafo de dependências permite build/teste/deploy incrementais.
- **Testes dentro de cada projeto** (convenção Ruby), não em projetos de teste
  separados. `boto test` roda todos.

## Templates

Equivalentes aos `dotnet new <template>`:

- **web**: páginas renderizadas no servidor, estilo Rails/Hotwire. Views em ERB
  ou Phlex, Turbo e Stimulus configurados, assets via importmap (sem Node).
- **spa**: frontend React ou Vue com Vite (`--framework react|vue`). `boto run`
  sobe Vite + APIs com proxy (sem CORS no dev). Em produção, gera estáticos
  servidos pelo Boto ou por CDN. Quando referencia uma API, o Boto gera um
  **cliente TypeScript tipado a partir do OpenAPI** dessa API: mudança de
  contrato quebra o build do frontend.
- **webapi**: API REST com rotas, schemas, OpenAPI gerado e erros JSON.
- **microservice**: webapi pronto para produção distribuída: OpenTelemetry,
  health checks, graceful shutdown, config via env, Dockerfile e manifesto
  para o PaaS da Evo.
- **worker**: consumidor de filas sem HTTP (só health check), com retry e
  dead letter.
- **library**: código compartilhado entre projetos.

Templates são **distribuídos como gems**. Os oficiais vêm embutidos; terceiros
podem publicar os seus (`boto templates install boto-template-graphql`), como
no `dotnet new install`.

## CLI (papel do `dotnet`)

- `boto new <solution> [-t <template>]` (sem template: solution vazia)
- `boto add <template> <nome> [--framework react|vue]`
- `boto ref <projeto> <referencia>`
- `boto generate <schema|model|endpoint|operation> <projeto> <nome> [campos]`
  (atalho `boto g`): gera o arquivo e o teste; `--skip-tests`, `--force`, e
  `generators tests: false` no Botofile (por projeto: `generators: { tests: }`)
- `boto graph`
- `boto run [projeto]` (sem argumento, sobe a solution inteira)
- `boto test [--all | --affected]`
- `boto openapi <projeto> [-o arquivo]`
- `boto check [projeto]` (isolamento: só usa projetos referenciados)
- `boto templates list | install <gem>`

## Estrutura de pastas

### Solution (gerada pelo `boto new`)
```
loja/
├── Botofile
├── Botofile.lock        # grafo resolvido + versões
├── .ruby-version
├── config/credentials/  # credentials compartilhadas
├── apps/                # projetos webapi, microservice, web e spa
├── libs/                # projetos library
└── workers/             # projetos worker
```

As pastas `apps/`, `libs/` e `workers/` não vêm vazias no `boto new`: cada uma
nasce no primeiro `boto add` de um projeto daquele tipo. Não existe
`services/`; um projeto HTTP ainda em `services/` é recusado com o `git mv`
que o move para `apps/`.

### Projeto (template microservice)
```
apps/pedidos/
├── pedidos.gemspec      # gerenciado pelo Boto
├── config/
│   ├── app.rb           # plugins
│   ├── settings.rb      # config tipada via env
│   └── credentials.yml.enc
├── endpoints/           # um endpoint por classe
├── schemas/             # contratos de entrada/saída
├── operations/          # regras de negócio (casos de uso)
├── models/              # persistência
├── test/                # espelha as pastas acima
└── Dockerfile
```

### Variações por template
- **webapi**: igual ao microservice, sem Dockerfile/manifesto de deploy.
- **worker**: `jobs/` no lugar de `endpoints/`.
- **library**: só `schemas/`, `operations/` e `models/`.
- **web**: `endpoints/` + `views/`, `components/` (Phlex) e `assets/`
  (controllers Stimulus e CSS).
- **spa**: estrutura padrão do Vite; `src/api/` contém o cliente TypeScript
  gerado (nunca editado à mão).

### Regra de namespace
Todo projeto tem **namespace próprio derivado do nome** (`pedidos` ->
`Pedidos::`). O Zeitwerk carrega cada projeto sob seu namespace. Isso evita
colisões quando a solution roda num único processo (modo dev) e reforça o
isolamento: um projeto só enxerga o namespace dos projetos que referencia
(`pedidos` usa `Dominio::` porque referencia `dominio`).

### Repositório do próprio Boto
```
boto/
├── gems/
│   ├── boto-rb/          # core (o nome `boto` já existe no RubyGems)
│   ├── boto-rb-cli/      # inclui templates/ oficiais
│   ├── boto-rb-security/ # plugins de segurança (hosts, cors, auth, rate_limit...)
│   ├── boto-rb-redis/    # store Redis do rate_limit
│   ├── boto-rb-swaggerui/ # plugin :swagger_ui (Swagger UI embutido)
│   └── boto-rb-telemetry/
├── benchmarks/
├── examples/            # solutions completas de exemplo
└── docs/
```

## Core do framework

- **HTTP: Rack 3 é o contrato.** O Boto fala apenas Rack; o servidor é uma
  peça trocável via adaptador `Boto::Server`.
- **Servidor padrão: Falcon** (async/fibers). Puma como alternativa pelo
  adaptador.
- **Não construir servidor HTTP próprio** por enquanto. Só reavaliar se
  benchmarks mostrarem o Falcon como gargalo medido.
- Roteador radix compilado no boot, mínimo de alocação por request.
- Schemas declarados uma vez: validam entrada, serializam saída, geram OpenAPI.
- **Um endpoint por classe** (estilo FastEndpoints), herdando de
  `Boto::Endpoint`. Cada classe declara rota, params tipados e schema de
  retorno; a lógica fica em `call`, com os params injetados como keyword args.
  ```ruby
  # apps/pedidos/endpoints/users/show.rb
  class Pedidos::Users::Show < Boto::Endpoint
    get "/users/:id"
    param :id, Integer
    returns UserSchema

    def call(id:)
      Users.find(id) or not_found
    end
  end
  ```
- **Verbos**: `get`, `post`, `put`, `patch`, `delete` e `query`. O `query`
  corresponde ao método HTTP QUERY, que é seguro e idempotente como o GET,
  mas leva a consulta no corpo, com `body Schema`. Ele serve para buscas que
  não cabem na query string. `HEAD` continua respondendo a partir do `get`.
  ```ruby
  class Pedidos::Users::Search < Boto::Endpoint
    query "/users/search"
    body UserFilterSchema
    returns [UserSchema]

    def call(body:) = Users.search(body)
  end
  ```
- **Descoberta automática**: tudo em `endpoints/` é carregado via Zeitwerk e as
  rotas são registradas sozinhas, sem arquivo de rotas central. A pasta espelha
  o namespace, sempre sob o namespace do projeto
  (`apps/pedidos/endpoints/users/show.rb` -> `Pedidos::Users::Show`).
- **Plugins no nível do projeto** (como o `builder.Services` do .NET), nunca
  dentro dos endpoints. Núcleo mínimo; telemetria, auth, CORS etc. são plugins.
  ```ruby
  # apps/pedidos/config/app.rb
  Boto.configure do |app|
    app.use :telemetry
    app.use :auth, strategy: :jwt
    app.use :cors, origins: %w[https://painel.loja.com]
  end
  ```
- Um endpoint pode abrir mão de um plugin do projeto quando necessário
  (ex.: `skip :auth` em health check ou login).
- Endpoints são testados chamando `call` direto, sem subir servidor.
- **OpenAPI em produção**: sem plugin, `/openapi.json` só existe em
  development. `app.use :openapi` (core) serve o documento em qualquer
  ambiente (`path:`, `version:`, `auth:`), protegido pelo `:auth` do projeto
  por padrão. `app.use :swagger_ui` (gem `boto-rb-swaggerui`) serve a UI em
  `/docs`, com os arquivos embutidos na gem, sem CDN.

## Segurança

Cada proteção é um **plugin ligado no projeto** (`config/app.rb`); endpoints
só declaram exceções (`skip`) ou exigências específicas (`authenticate`).

- **Padrões por template:**
  - `web` (cookies/formulários): `:sessions`, `:csrf`, `:secure_headers`,
    `:hosts` ligados por padrão.
  - `webapi`/`microservice` (stateless com token): `:auth`, `:cors`,
    `:rate_limit`. Sem CSRF (o ataque depende de cookies enviados
    automaticamente; APIs com bearer token não usam isso).
- **Equivalentes ao Rails:**
  - `protect_from_forgery` -> `:csrf`: token por sessão, mascarado por página,
    validado em todo método que altera estado, mais checagem do header
    `Origin`. Integrado ao Turbo no template web.
  - `http_basic_authenticate_with` -> `:auth, strategy: :basic`;
    `authenticate_with_http_token` -> `strategy: :bearer`. Também `:jwt`,
    `:api_key` e `:signature` (webhooks).
  - Strong parameters -> já resolvido: só passam params declarados no
    endpoint, com tipo.
  - Cookies assinados e criptografados: AES-256-GCM via OpenSSL, chave nas
    credentials.
  - Credentials criptografadas: `boto credentials edit`, por projeto ou
    compartilhadas na solution.
  - Headers de segurança (CSP, HSTS, X-Frame-Options) -> `:secure_headers`.
  - Host authorization (DNS rebinding) -> `:hosts`.
  - `rate_limit` -> `:rate_limit` (memória ou Redis).
  - `filter_parameters` -> telemetria mascara senhas e tokens nos logs por
    padrão.
  - `force_ssl` -> respeita `X-Forwarded-Proto` (TLS termina no ingress).
- **Exemplo:**
  ```ruby
  # apps/admin/config/app.rb
  Boto.configure do |app|
    app.use :sessions, store: :cookie
    app.use :csrf
    app.use :secure_headers
    app.use :auth, strategy: :basic,
            credentials: -> { Boto.credentials.admin }
  end

  # apps/admin/endpoints/webhooks/pagamento.rb
  class Admin::Webhooks::Pagamento < Boto::Endpoint
    post "/webhooks/pagamento"
    skip :csrf, :auth
    authenticate :signature, header: "X-Signature"

    def call(payload:)
      # ...
    end
  end
  ```
- **Implementação:** cada plugin é um middleware Rack inserido numa ordem fixa:
  hosts -> cors -> secure_headers -> sessions -> csrf -> auth -> rate_limit.
  - **Plugins globais** (hosts, cors e os de sessão/CSRF) rodam antes do
    roteamento, então também valem para 404, 405 e preflight.
  - **Plugins de endpoint** (auth, rate_limit) rodam depois do roteamento e
    podem ser pulados com `skip`.
  - **CORS antes do auth:** o preflight não leva credenciais, então o `cors`
    precisa vir antes do `auth`.
  - **Onde ficam:** o core guarda só a base (`Boto::Plugin`,
    `Boto.configure`). Os plugins de segurança vivem na gem `boto-rb-security`.
- **Nunca escrever primitivas de criptografia próprias:** usar OpenSSL,
  `Rack::Utils.secure_compare` e, onde fizer sentido, reaproveitar código
  auditado como o `rack-protection`.

## Roadmap

- **Fase 0 (atual)**: monorepo com as gems `boto-rb` (core) e `boto-rb-cli`; parser
  do Botofile com validação de refs e detecção de ciclos; `boto new` criando
  solution; comandos básicos do CLI; `Boto::Endpoint` com roteador, params
  tipados, descoberta automática de endpoints e erros JSON; testes; benchmark contra Roda e Sinatra (hello world e
  cenário com banco).
- **Fase 1**: schemas, geração de OpenAPI, tratamento de erros; templates
  `webapi` e `library`; plugins `:auth`, `:cors`, `:rate_limit` e `:hosts`.
- **Fase 2**: async por padrão, OpenTelemetry, health checks, graceful
  shutdown; templates `microservice` e `worker`; sistema de templates como gems.
- **Fase 3**: template `spa` (primeiro, pois reaproveita o OpenAPI) com geração
  do cliente TypeScript; depois template `web` (Hotwire),
  com os plugins `:sessions` e `:csrf`.
- **Fase 4**: site de docs, exemplos e beta num serviço real da Evo antes do
  lançamento público.

## Versões do Ruby

- **Mínimo: Ruby 3.4.** No gemspec: `spec.required_ruby_version = ">= 3.4"`.
- **Desenvolvimento:** `.ruby-version` do repositório em `4.0`.
- **Política:** o Boto suporta as versões do Ruby mantidas pelo core team
  (manutenção normal ou de segurança). Quando uma versão chega ao fim de vida,
  o suporte a ela é removido na próxima versão minor do Boto, com aviso no
  CHANGELOG.
- Recursos que podem ser usados livremente por causa do mínimo 3.4: fiber
  scheduler (base do async), YJIT, Prism.

## Convenções

- Testes com Minitest. Matriz da CI: Ruby 3.4, 4.0 e `ruby-head` (este último
  não bloqueante), cada uma com YJIT ligado e desligado.
- Benchmark no CI falha em caso de regressão de performance.
- Versionamento semântico e CHANGELOG desde o início.
- Antes de implementar algo grande, propor estrutura e API pública para revisão.

## Como o Claude trabalha neste projeto

- **Sempre responder em português**, incluindo planos, resumos, perguntas e
  relatórios de subagentes.
- **Nomes de pastas e arquivos sempre em inglês**, assim como classes,
  métodos e variáveis (o Zeitwerk liga o nome do arquivo ao da constante).
- **Commits sempre em Conventional Commits**, pela skill `commit`.
- **Toda feature passa pela skill `implement-feature`**: primeiro o plano, que
  é dividido em tasks, e cada task roda num subagente `task-runner` com o
  modelo Haiku.
- **Código limpo e sempre testável** (veja `.claude/rules/clean-code.md`).