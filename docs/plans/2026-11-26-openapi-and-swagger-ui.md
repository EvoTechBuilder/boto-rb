# Plugin `:openapi` e gem `boto-rb-swaggerui` (propostas 0012 e 0013)

Status: **concluído**

## Objetivo

- Servir o documento OpenAPI em qualquer ambiente com `app.use :openapi`.
- Servir o Swagger UI com `app.use :swagger_ui`, numa gem nova,
  `boto-rb-swaggerui`, com os arquivos da UI embutidos.

## Fora de escopo

- Redoc ou outras UIs.
- O plugin `:secure_headers`. A página já nasce sem script inline, para não
  depender dele.
- Repassar o bearer token pela UI.
- Ler a versão do documento da gemspec do projeto: o default fica `"0.0.0"`.

## Task 1: plugin `:openapi` (core)

- **Objetivo:** `Boto::Plugins::Openapi`, como descrito na proposta 0012.
- **Arquivos:**
  - `gems/boto-rb/lib/boto/plugins/openapi.rb` (novo):
    - `scope :global`;
    - opções `path:` (`"/openapi.json"`), `version:` (`"0.0.0"`) e
      `auth:` (`true`), validadas no `configure`;
    - `#path` e `#auth?` públicos;
    - `attach(app)`:
      - guarda o `:auth` declarado no projeto quando `auth: true`;
      - falha se um endpoint tem `route == ["GET", path]`;
    - `start` gera o JSON uma vez com `Boto::OpenAPI.generate`;
    - `call` responde a `GET`/`HEAD` no `path`, passando pelo
      `auth.call(env, responder)` quando houver `:auth`;
  - `gems/boto-rb/lib/boto/plugin.rb`: `ORDER` passa a ser
    `health hosts cors secure_headers sessions csrf openapi swagger_ui auth rate_limit`;
  - `gems/boto-rb/lib/boto/http/app.rb`: a rota de development não é montada
    quando o projeto usa `:openapi`;
  - `gems/boto-rb/test/boto/plugins/openapi_test.rb` (novo) e testes do App.
- **Testes:** a seção "Testes planejados" da 0012. Os casos de auth usam um
  plugin `:auth` falso, definido no teste, porque o core não depende da
  `boto-rb-security`.
- **Dependências:** nenhuma.
- **Comando:** `cd gems/boto-rb && bundle exec rake test`.

## Task 2: plugins de outras gems pelo nome

- **Objetivo:**
  - `app.use :swagger_ui` encontra o plugin sem `require` manual;
  - depois da `boto-rb-security`, o lookup tenta `require "boto/<nome>"`.
- **Arquivos:**
  - `gems/boto-rb/lib/boto/configuration.rb`:
    - o `lookup` tenta, em ordem, o plugin já carregado, a `boto/security` e
      `boto/<nome>`;
    - um `LoadError` de outro arquivo continua subindo;
    - a mensagem de plugin desconhecido passa a ser
      `unknown plugin :<nome> (add the gem that provides it to the Gemfile, e.g. "boto-rb-security")`;
  - `gems/boto-rb/test/boto/configuration_test.rb`.
- **Testes:**
  - um plugin num arquivo `boto/<nome>.rb` de um diretório temporário no
    `$LOAD_PATH` é achado;
  - um nome inexistente dá a mensagem nova;
  - um `LoadError` vindo de dentro do arquivo do plugin não é engolido.
- **Dependências:** nenhuma. Roda em paralelo com as Tasks 1 e 3.
- **Comando:** `cd gems/boto-rb && bundle exec rake test`.

## Task 3: gem `boto-rb-swaggerui`, arquivos e página

- **Objetivo:** criar o esqueleto da gem, os arquivos do Swagger UI e as
  classes puras `Assets` e `Page`.
- **Arquivos:**
  - `gems/boto-rb-swaggerui/`:
    - `boto-rb-swaggerui.gemspec`: depende de `boto-rb` na mesma versão, e o
      `spec.files` inclui `vendor/**/*`;
    - `LICENSE` e `Rakefile`, no molde da `boto-rb-redis`;
  - `lib/boto/swagger_ui.rb`: Zeitwerk `for_gem_extension(Boto)`;
  - `lib/boto/swagger_ui/version.rb`: `VERSION = "0.10.0"`;
  - `lib/boto/swagger_ui/assets.rb`:
    - lê `vendor/swagger-ui/` uma vez;
    - devolve `[content-type, body]` congelados por nome, numa lista fixa;
  - `lib/boto/swagger_ui/page.rb`:
    - monta o HTML com título e URL do documento escapados;
    - monta o `initializer.js`;
    - nenhum `<script>` inline;
  - `vendor/swagger-ui/`:
    - `swagger-ui.css`, `swagger-ui-bundle.js` e `LICENSE`;
    - `VERSION` com `5.36.0`;
  - `lib/tasks/vendor.rake` ou o próprio `Rakefile`: `vendor:update[VERSION]`
    baixa o tarball do registro do npm, confere o `integrity` (sha512) e
    extrai os três arquivos;
  - `test/`: testes de `Assets` e `Page`.
- **Download:** esta task baixa o `swagger-ui-dist` 5.36.0 (cerca de 1,5 MB)
  de `registry.npmjs.org`, pelo próprio `rake vendor:update`.
- **Dependências:** nenhuma. Roda em paralelo com as Tasks 1 e 2.
- **Comando:** `cd gems/boto-rb-swaggerui && bundle exec rake test`. O
  `Gemfile` da raiz ganha a gemspec nesta task.

## Task 4: plugin `:swagger_ui`

- **Objetivo:** `Boto::Plugins::SwaggerUi`, como descrito na proposta 0013.
- **Arquivos:**
  - `gems/boto-rb-swaggerui/lib/boto/plugins/swagger_ui.rb`:
    - `scope :global`;
    - opção `path:` (`"/docs"`);
    - `attach(app)`:
      - acha o `:openapi`;
      - falha sem ele;
      - falha se ele está protegido por um `:auth` que não é `:basic`;
      - falha numa colisão com um endpoint;
    - `call`:
      - serve a página e os assets em `<path>/assets/<versão>/<arquivo>`;
      - fora da lista de arquivos, responde 404;
      - quando o documento é protegido, usa o mesmo `:auth`;
  - `gems/boto-rb-swaggerui/test/boto/plugins/swagger_ui_test.rb`.
- **Testes:** a seção "Testes planejados" da 0013. O caso de `:basic` usa o
  `:auth` real da `boto-rb-security`, como dependência de desenvolvimento.
- **Dependências:** Tasks 1, 2 e 3.
- **Comando:** `cd gems/boto-rb-swaggerui && bundle exec rake test`.

## Fechamento (eu)

- `Rakefile` da raiz: `GEM_DIRS` ganha `gems/boto-rb-swaggerui`.
- `.github/workflows/ci.yml`:
  - `boto-rb-swaggerui` entra no build e no push da publicação, depois do
    `boto-rb-security`;
  - os testes já rodam pelo `rake test` da raiz.
- CHANGELOG (Added), CLAUDE.md (repositório e lista de plugins) e as propostas
  marcadas como implementadas.
- As quatro suítes, mais a nova, com e sem YJIT.
- A skill `benchmark`, porque o `ORDER` mudou e um plugin global novo entra
  no caminho, mesmo que só quando estiver ligado.
- Teste de ponta a ponta: `boto run` com `:openapi` e `:swagger_ui`,
  conferindo o `/docs` e o `/openapi.json` com `curl`.

## Ação sua antes do release

No rubygems.org, cadastrar um **pending trusted publisher** para
`boto-rb-swaggerui`: repositório `EvoTechBuilder/boto-rb`, workflow
`ci.yml` e environment `rubygems`. Sem isso, o push da gem nova falha na
primeira tag.
