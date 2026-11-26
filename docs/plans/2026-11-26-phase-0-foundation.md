# Plano — Fase 0 (fundação)

Status: **concluído** (2026-11-26)
Proposta: `docs/proposals/0001-phase-0-foundation.md`

## Objetivo

Entregar as gems `boto` (core) e `boto-cli` com os seguintes itens, tudo com
testes:

- Botofile validado;
- roteador radix;
- params tipados;
- `Boto::Endpoint` com descoberta automática;
- erros problem+json;
- CLI `new`, `add`, `ref`, `graph`, `test` e `run`;
- benchmark contra Roda e Sinatra.

## Fora de escopo

Fica fora tudo o que a seção "Fora de escopo" da proposta 0001 lista.

## Convenções para todas as tasks

- Ruby 4.0.10 local, com mínimo de 3.4 no gemspec.
- `# frozen_string_literal: true` em todo `.rb`.
- Zeitwerk: a gem `boto` usa `Zeitwerk::Loader.for_gem`, e a `boto-cli` usa
  `Zeitwerk::Loader.for_gem_extension(Boto)` com a inflexão
  `"cli" => "CLI"`. Um arquivo define uma constante. Constantes aninhadas no
  mesmo arquivo da constante-mãe são permitidas.
- Minitest. `test/` espelha `lib/`, e cada gem tem um `test/test_helper.rb`.
- **Testes por gem**:
  - todos: `cd gems/<gem> && bundle exec rake test`;
  - arquivo único: `bundle exec ruby -Ilib -Itest <arquivo>`.
  
  Tudo precisa passar também com `RUBY_YJIT_ENABLE=1`.
- Sem dependências além das listadas na task.

## Tasks

Os grupos marcados com ∥ rodam em paralelo. Cada task é executada por um
subagente `task-runner` (Haiku), e cada uma ganha um commit.

### Onda 0

**T1 — Scaffold do monorepo**

- Arquivos na raiz: `Gemfile` (com `gemspec path:` das duas gems, mais rake e
  minitest), `Rakefile` (roda `rake test` em cada gem), `.ruby-version`
  (`4.0.10`), `.gitignore`, `LICENSE` (MIT, Evo Tech Builder) e `CHANGELOG.md`
  (com a seção `Unreleased`).
- `gems/boto/`:
  - `boto.gemspec`, que depende de `rack ~> 3.1` e `zeitwerk ~> 2.7`;
  - `Rakefile`;
  - `lib/boto.rb` e `lib/boto/version.rb` (`0.1.0`);
  - `test/test_helper.rb` e `test/boto/version_test.rb`.
- `gems/boto-cli/`:
  - `boto-cli.gemspec`, que depende de `boto` e `falcon ~> 0.47`;
  - `Rakefile` e `exe/boto` (stub);
  - `lib/boto/cli.rb` (`Boto::CLI` vazio, com o loader de extensão);
  - `lib/boto/cli/version.rb`;
  - `test/test_helper.rb` e `test/boto/cli/version_test.rb`.
- **Pronto quando**: `bundle install` e o `rake test` da raiz passam.

### Onda 1 ∥ (depende de T1)

**T2 — Botofile, Solution e Project** (`gems/boto`)

- **`lib/boto/project.rb`**: `Boto::Project = Data.define(:name, :template, :refs, :line)`.
  - `#path` é derivado do template (library -> `libs/`, webapi e
    microservice -> `services/`, worker -> `workers/`, web e spa -> `apps/`).
  - `#namespace_name` vem em CamelCase.
- **`lib/boto/solution.rb`**:
  - `#name`, `#projects` e `#project(name)`, que lança erro se o projeto não
    existir;
  - `#topological_order`: as dependências vêm antes;
  - `#dependencies_of(name)` e `#dependents_of(name)`, ambos transitivos.
- **`lib/boto/botofile.rb`**:
  - `Boto::Botofile.parse(source, path:)` e `.load(path)` retornam uma
    `Solution`;
  - a DSL tem `solution` e `project`;
  - os erros de validação usam `Boto::Botofile::InvalidError`, com a linha e
    o caminho do ciclo.
- **Testes**: um por regra da proposta.

**T3 — Router radix** (`gems/boto`)

- `lib/boto/router.rb` tem a API `#add(verb, pattern, target)`, `#compile`
  (congela tudo), `#match(verb, path)` e `#allowed_verbs(path)`.
  - `match` retorna um `Match(target, params)` ou `nil`.
  - `HEAD` cai no `GET`.
- O segmento estático tem prioridade sobre o `:param`.
- Uma rota duplicada lança `Boto::Router::DuplicateRouteError` no `add`.
- Não usa regex no caminho estático.

**T4 — Erros, Problem e Boolean** (`gems/boto`)

- **`lib/boto/error.rb`**: `Boto::Error`, com `#status`. Tem as subclasses
  aninhadas `BadRequest` (400), `NotFound` (404), `MethodNotAllowed` (405,
  com `allowed`), `PayloadTooLarge` (413) e `Unprocessable` (422, com
  `errors`).
- **`lib/boto/problem.rb`**:
  - `Boto::Problem.response(status, detail: nil, errors: nil, headers: {})`
    devolve a tripla Rack com `content-type: application/problem+json`;
  - o `title` vem de `Rack::Utils::HTTP_STATUS_CODES`.
- **`lib/boto/boolean.rb`**: `Boto::Boolean.coerce(value)` aceita
  `true`/`false` e `"true"`/`"false"`/`"1"`/`"0"`, e lança `ArgumentError`
  no resto.

### Onda 2 ∥

**T5 — Params e RequestBody** (`gems/boto`, depende de T4)

- **`lib/boto/params.rb`**:
  - `Boto::Params.new` com `#declare(name, type, default:, required:)` e
    `#freeze`;
  - `#call(path:, query:, body:)` devolve um Hash com chaves símbolo. A
    precedência é path > query > body.
  - Erros agregados lançam `Boto::Error::Unprocessable` com
    `[{param:, message:}]`.
  - `#needs_query?` e `#needs_body?` são verdadeiros quando existe param fora
    do path (o App usa isso para evitar parse).
- **`lib/boto/request_body.rb`**: `Boto::RequestBody.parse(env, limit: 1_048_576)`.
  - Devolve `{}` se o content-type não for JSON.
  - Lança `PayloadTooLarge` se o corpo passar do limite e `BadRequest` se o
    JSON for inválido.

**T6 — Base do CLI e `boto new`** (`gems/boto-cli`, depende de T2)

- **`lib/boto/cli.rb`**: `Boto::CLI.new(out:, err:, cwd:).run(argv)` devolve
  o exit code.
  - O comando é resolvido como `Boto::CLI::Commands.const_get(camelize(name))`,
    só se o nome bater com `/\A[a-z]+\z/`.
  - `boto` sem argumento ou `boto help` lista os comandos com o `SUMMARY` de
    cada um.
- **`lib/boto/cli/command.rb`**: classe base com
  `initialize(argv, out:, err:, cwd:)` e `#call`. O helper `solution` carrega
  `cwd/Botofile`.
- **`lib/boto/cli/commands/new.rb`** usa os templates ERB de
  `templates/solution/`: `Botofile`, `Gemfile`, `.ruby-version`, `.gitignore`
  e as pastas `libs/`, `services/`, `workers/` e `apps/` com `.keep`. Se o
  diretório já existir, lança erro.
- `exe/boto` passa a chamar o CLI.

### Onda 3 ∥

**T7 — Endpoint** (`gems/boto`, depende de T5)

- `lib/boto/endpoint.rb` define a DSL de classe:
  - `get`, `post`, `put`, `patch` e `delete` (só uma rota por classe; uma
    segunda lança erro);
  - `param`, que delega para `Boto::Params`;
  - `status`;
  - os leitores `route` e `default_status`.
- `initialize(env = {})` e um `request` preguiçoso (`Rack::Request`).
- Os helpers `not_found`, `bad_request` e `unprocessable` lançam os erros de
  T4.

**T8 — `boto add`** (`gems/boto-cli`, depende de T6)

- **`lib/boto/cli/commands/add.rb`**:
  - recebe `boto add <webapi|library> <name>`;
  - cria a pasta a partir de `templates/<template>/` (ERB, com o namespace
    vindo do nome);
  - acrescenta `project "<name>", template: :<t>` ao final do Botofile;
  - lança erro se o nome já existir.
- **Templates**:
  - `webapi`: `config/app.rb`, `endpoints/health.rb` (`GET /health` -> `{status: "ok"}`), `operations/.keep`, `models/.keep`, `test/test_helper.rb` e `test/endpoints/health_test.rb`;
  - `library`: o mesmo, sem `endpoints/` e `config/`.

**T9 — `boto ref`** (`gems/boto-cli`, depende de T6)

- **`lib/boto/cli/botofile_editor.rb`**: `Boto::CLI::BotofileEditor.add_ref(source, project:, ref:)`.
  - Recebe e devolve o source do Botofile.
  - Usa `Prism.parse` para achar o `CallNode` `project` cujo primeiro
    argumento é `project`.
  - Se já houver um keyword `refs:` com `%w[]` ou `[...]`, insere o nome nele;
    se não houver, acrescenta `, refs: %w[ref]` antes do fim da chamada.
  - Edita por offsets de byte e preserva o resto do texto.
- **`lib/boto/cli/commands/ref.rb`**: valida a solution depois de editar (para
  não deixar ciclo nem ref inexistente) e só então grava.

**T10 — `boto graph`** (`gems/boto-cli`, depende de T6)

- **`lib/boto/cli/commands/graph.rb`**: imprime a árvore em texto, na ordem
  topológica, com cada projeto e as refs indentadas.

**T11 — `boto test`** (`gems/boto-cli`, depende de T6)

- **`lib/boto/cli/commands/test.rb`**: recebe
  `boto test [project] [--affected [--base REF]]`.
  - Roda cada projeto em subprocesso (`ruby -Itest -e 'Dir["test/**/*_test.rb"].each { require File.expand_path(_1) }'`), com o cwd na pasta do projeto.
  - Um projeto sem `test/` é pulado.
  - A seleção do `--affected` fica em
    `lib/boto/cli/affected_projects.rb`, como função pura: recebe a lista de
    arquivos alterados e a solution e devolve os nomes dos projetos.
  - Os arquivos alterados vêm de `git diff --name-only <base>` mais
    `git ls-files --others --exclude-standard`.
  - O executor de subprocessos é injetado, para os testes não rodarem Ruby
    de verdade.

### Onda 4

**T12 — App** (`gems/boto`, depende de T3 e T7)

- **`lib/boto/app.rb`**: `Boto::App.new(namespace:, env_name: ENV.fetch("BOTO_ENV", "production"), error_output: $stderr)`.
- **No boot**:
  - percorre as constantes do módulo `namespace` (recursivamente) e coleta as
    subclasses de `Boto::Endpoint` que têm `route`;
  - lança erro se algum `:param` do path não estiver declarado;
  - monta o router e o compila.
- **`#call(env)`**:
  1. faz o match; sem rota, responde 404, ou 405 com `Allow`;
  2. faz o parse da query e do body só quando necessário;
  3. aplica os params;
  4. executa `endpoint.new(env).call(**params)`.
- **Resposta**:
  - `Hash` ou `Array` vira JSON com `default_status`, e `nil` vira 204;
  - `HEAD` sai sem corpo;
  - `Boto::Error` vira problem;
  - qualquer outra exceção vira 500. Em production a resposta não traz
    detalhes; em development, traz a mensagem e o backtrace. Em ambos os
    casos o erro é logado no `error_output`.

### Onda 5

**T13 — ProjectLoader e Boot** (`gems/boto`, depende de T2 e T12)

- **`lib/boto/project_loader.rb`**: um `Zeitwerk::Loader` por projeto.
  - Cria o módulo do namespace se ele não existir.
  - Faz `push_dir` de `endpoints/`, `operations/` e `models/` (os que
    existirem) com `namespace:`, depois `setup`.
- **`lib/boto/boot.rb`**: `Boto::Boot.new(solution, root:)`.
  - `#app(name)` prepara os loaders das refs transitivas e do próprio
    projeto (um loader por projeto, cacheado), faz `eager_load` e devolve um
    `Boto::App`.
- **Teste**: uma solution fixture em `test/fixtures/shop/` (com `domain` e
  `orders`) e um request via `Rack::MockRequest`.

### Onda 6 ∥

**T14 — Server e `boto run`** (`gems/boto-cli`, depende de T13)

- **`lib/boto/cli/server.rb`**: `Boto::CLI::Server.new(apps_by_port, host:)`
  com `#run`. Sobe um servidor Falcon por porta dentro de um único reactor
  `Async`.
- **`lib/boto/cli/commands/run.rb`**: recebe `boto run [project] [--port 3000]`.
  - Serve os projetos com template `webapi` ou `microservice`, em ordem
    topológica e com portas incrementais.
  - Imprime a tabela de projeto e URL.
- **Teste de integração**: sobe num thread com a porta 0 ou uma livre, faz um
  GET `/health` via `Net::HTTP` e encerra.

**T15 — Benchmarks** (`benchmarks/`, depende de T13)

- **`benchmarks/Gemfile`**: boto (path), roda, sinatra, sequel, sqlite3 e
  falcon.
- **`benchmarks/apps/<framework>/{hello,db}.ru`**:
  - `hello`: `GET /` responde `{"hello":"world"}`;
  - `db`: `GET /users/:id` lê do SQLite via Sequel, com 1000 linhas
    semeadas.
- **`benchmarks/run.rb`**:
  - sobe cada `.ru` no Falcon;
  - mede com `wrk` se estiver instalado, e senão com `ab -k`;
  - grava `benchmarks/results/latest.json`;
  - compara com `benchmarks/results/baseline.json`;
  - termina com exit 1 se piorar mais de 5% em req/s ou p99.
- **Alocação**: `benchmarks/allocations.rb` mede os objetos por request via
  `GC.stat` com `Rack::MockRequest`.

**T16 — CI** (depende de T1)

- `.github/workflows/ci.yml` roda a matriz Ruby `3.4`, `4.0` e `head`
  (`head` com `continue-on-error`) × YJIT on/off, executando o `rake test` da
  raiz.
- Um job de benchmark roda depois, com `benchmarks/run.rb`.

## Revisão e commits

Depois de cada task:

1. eu leio o diff;
2. rodo os testes com e sem YJIT;
3. confiro as rules;
4. faço o commit (`feat(boto): ...`, `feat(cli): ...`, `ci: ...`,
   `chore: ...`).

Ao final, rodo a suíte completa e o benchmark, atualizo o CHANGELOG e marco
este plano como concluído.
