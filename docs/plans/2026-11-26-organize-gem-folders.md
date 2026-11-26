# Plano — Organizar pastas das gems por área

Status: **concluído** (2026-11-26)

## Objetivo

Agrupar os arquivos de `gems/boto/lib/boto/` e de `gems/boto-cli/lib/boto/cli/`
por área, sem mudar nenhuma constante. As pastas de área usam o `collapse` do
Zeitwerk: agrupam no disco e não criam namespace. Os testes seguem a mesma
estrutura de pastas.

## Fora de escopo

- Mudar nomes de classes, módulos ou a API pública.
- Mudar comportamento.
- Mexer em `templates/`, `test/fixtures/`, `benchmarks/` e `docs/`.

## Estrutura final

```
gems/boto/lib/boto.rb                 # + collapse de http/, endpoint/ e solution/
gems/boto/lib/boto/
  version.rb
  http/        app.rb, router.rb, request_body.rb, problem.rb, error.rb
  endpoint/    endpoint.rb, params.rb, boolean.rb
  solution/    botofile.rb, solution.rb, project.rb, project_loader.rb, boot.rb
  schema.rb, schema/compiler.rb                 (sem mudança)
  types.rb, types/*.rb                          (sem mudança)
  openapi.rb, openapi/operation.rb, openapi/schema_catalog.rb

gems/boto/test/boto/
  version_test.rb, schema_test.rb, types_test.rb, openapi_test.rb
  http/, endpoint/, solution/   (os *_test.rb correspondentes)

gems/boto-cli/lib/boto/cli.rb         # + collapse de support/
gems/boto-cli/lib/boto/cli/
  runner.rb, command.rb, error.rb, version.rb
  commands/    (sem mudança)
  support/     affected_projects.rb, botofile_editor.rb, generator.rb, server.rb

gems/boto-cli/test/boto/cli/
  runner_test.rb, exe_test.rb, version_test.rb, server_integration_test.rb
  commands/    (sem mudança)
  support/     affected_projects_test.rb, botofile_editor_test.rb, generator_test.rb
```

## Tasks

R1, R2 e R3 não têm arquivos em comum e rodam em paralelo, cada uma num
subagente `task-runner` (Haiku). Todos os movimentos usam `git mv`, para
preservar o histórico.

### R1 — Gem boto: http/, endpoint/ e solution/

- **Mover:**
  - os 15 arquivos de lib para as três pastas de área;
  - os testes correspondentes para `test/boto/<área>/`.
- **`lib/boto.rb`:** `loader.collapse` das três pastas, antes do
  `loader.setup`.
- **Verificar:**
  - `Zeitwerk::Loader.eager_load_all`;
  - todas as constantes mantêm o mesmo nome;
  - `bundle exec rake test`, com e sem YJIT.
- **Atenção a `__dir__` e caminhos relativos:** os testes que leem fixtures
  usam `File.expand_path("../fixtures/...", __dir__)` e precisam de um
  `../` a mais depois de mudarem de pasta.

### R2 — Gem boto-cli: support/

- **Mover:**
  - os 4 arquivos de suporte para `lib/boto/cli/support/`;
  - os testes deles para `test/boto/cli/support/`.
- **`lib/boto/cli.rb`:** `loader.collapse` de `support/`.
- **`Generator::TEMPLATES_ROOT`:** o caminho relativo a `__dir__` ganha
  um `../` a mais.
- **Verificar:** `eager_load_all` e `bundle exec rake test` com e sem
  YJIT, incluindo o teste de integração do `boto run`.

### R3 — Dividir openapi.rb

- **Novos arquivos:** `SchemaCatalog` vai para
  `lib/boto/openapi/schema_catalog.rb` (`Boto::OpenAPI::SchemaCatalog`) e
  `Operation` para `lib/boto/openapi/operation.rb` (`Boto::OpenAPI::Operation`).
- **Escopo:** só move código. O comportamento e o snapshot
  `test/fixtures/openapi/shop.json` ficam iguais.
- **Verificar:** `test/boto/openapi_test.rb` com e sem YJIT.

### R4 — Fechar (eu faço)

1. Rodo as suítes das duas gems e do benchmark, com e sem YJIT.
2. Faço o fluxo de ponta a ponta do CLI: `new`, `add`, `ref`, `test`,
   `openapi`, e `run` com curl.
3. Confiro que `git log --follow` acompanha os arquivos movidos.
4. Faço um commit por task (`refactor(boto): ...`, `refactor(cli): ...`).
   Não vai no CHANGELOG, porque nada muda para quem usa.
