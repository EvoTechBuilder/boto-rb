# `title:`/`description:` no `:openapi` e topbar do Boto no Swagger UI (proposta 0015)

Status: **concluído**

## Objetivo

- O `:openapi` passa a aceitar `title:` e `description:`.
- A página do `:swagger_ui` passa a ter a topbar do Swagger UI, com um rubi
  próprio e o nome **Boto** no lugar da marca do Swagger.

## Fora de escopo

- Opção `--title` no `boto openapi` (CLI).
- Opções de marca no `:swagger_ui`.
- Logo oficial do Ruby.

## Task 1: `title:` e `description:` no core

- **Arquivos:**
  - `gems/boto-rb/lib/boto/openapi.rb`: `generate(app, title:, version:, description: nil)`,
    com `info.description` só quando o `description` é passado;
  - `gems/boto-rb/lib/boto/plugins/openapi.rb`:
    - opções `title:` (default `nil`, que vira `app.title` no `attach` ou no
      `start`) e `description:` (default `nil`);
    - validação no boot: `title` como String não vazia, `description` como
      String;
    - `#title` público, com o título efetivo depois do `attach`;
  - testes em `gems/boto-rb/test/boto/openapi_test.rb` e
    `gems/boto-rb/test/boto/plugins/openapi_test.rb`.
- **Testes:** os da seção "Testes planejados" da 0015 para o `:openapi` e o
  `generate`.
- **Dependências:** nenhuma. Roda em paralelo com a Task 2.
- **Comando:** `cd gems/boto-rb && bundle exec rake test`.

## Task 2: topbar e marca no `boto-rb-swaggerui`

- **Arquivos:**
  - `lib/tasks/vendor.rake`:
    - `FILES` ganha `swagger-ui-standalone-preset.js`;
    - roda de novo o `rake "vendor:update[5.36.0]"`, baixando do npm e
      conferindo o sha512;
  - `assets/ruby.svg`: o rubi do brief;
  - `assets/boto.css`: esconde o SVG do Swagger na topbar e mostra o rubi e
    "Boto";
  - `lib/boto/swagger_ui/assets.rb`:
    - lê os arquivos de `vendor/` (css, bundle, preset) e de `assets/`
      (`boto.css` com `text/css`, `ruby.svg` com `image/svg+xml`);
    - mantém a lista fixa;
  - `lib/boto/swagger_ui/page.rb`:
    - o HTML carrega o preset, o `swagger-ui.css` e depois o `boto.css`;
    - o `initializer.js` usa `presets: [SwaggerUIBundle.presets.apis, SwaggerUIStandalonePreset]`
      e `layout: "StandaloneLayout"`;
  - `gemspec`: `spec.files` inclui `assets/**/*`;
  - testes de `Assets` e `Page`.
- **Testes:**
  - os arquivos novos são carregados, com o content-type certo;
  - a página referencia o preset e o `boto.css`, sem script inline;
  - o initializer usa o `StandaloneLayout`;
  - o `gem build` inclui `assets/`.
- **Dependências:** nenhuma. Roda em paralelo com a Task 1.
- **Comando:** `cd gems/boto-rb-swaggerui && bundle exec rake test`.

## Fechamento (eu)

- `lib/boto/plugins/swagger_ui.rb`:
  - o `<title>` da página passa a vir de `openapi.title`;
  - a tabela ganha `boto.css`, `ruby.svg` e o preset;
  - testes do plugin.
- CHANGELOG, README (`title:` e `description:` na tabela de plugins), a
  proposta e o plano.
- Suítes com e sem YJIT.
- Conferir a topbar no navegador do app, com `boto run`, e tirar um print.
