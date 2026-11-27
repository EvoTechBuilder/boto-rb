# Gem `boto-rb-gateway` (proposta 0023)

Status: **em andamento**

## Objetivo

- No dev, a solution responde numa porta só: o gateway monta os apps das
  `refs` no mesmo processo, um prefixo por serviço.
- O painel `/_boto` mostra serviços, rotas, health e links.

## Fora de escopo

- Gateway em produção (proxy reverso): o plugin recusa o boot em
  `production`.
- `X-Forwarded-Prefix`, agregação de health e qualquer JavaScript no painel.

## Task 1: `mounts_refs` e `App#services` (core)

- **Arquivos:**
  - `gems/boto-rb/lib/boto/template.rb`: opção `mounts_refs` (padrão
    `false`) no `Data` e na DSL;
  - `gems/boto-rb/lib/boto/http/app.rb`: keyword `services: {}` no
    construtor e `#services` (Hash congelado);
  - `gems/boto-rb/lib/boto/solution/boot.rb`:
    - `#app(name)` de um projeto com `mounts_refs` monta antes os apps das
      refs (`services`) e passa ao `App`;
    - um app já montado no mesmo `Boot` é reaproveitado (cache por nome);
    - ref que não é HTTP: `Boto::App::BootError`
      `gateway borda: ref "dominio" is not an HTTP project`;
  - testes em `gems/boto-rb/test/` (template, app, boot).
- **Dependências:** nenhuma.
- **Comando:** `cd gems/boto-rb && bundle exec rake test`.

## Task 1b: origem das variáveis e `App#env` (core)

- **Arquivos:**
  - `gems/boto-rb/lib/boto/env.rb` e `gems/boto-rb/lib/boto/env/files.rb`:
    - `Env#source(key)`: o arquivo de onde a variável veio, relativo à raiz
      da solution (`.env.local`, `apps/catalogo/.env.development`), ou
      `"process"` quando o processo a define;
    - `Env#file_keys`: só as variáveis definidas em arquivos `.env*`;
    - `Env#fetch`, `#[]`, `#key?` e `#to_h` não mudam;
  - `gems/boto-rb/lib/boto/solution/boot.rb`: passa as origens ao montar o
    `Env` e entrega `env:` ao `App`;
  - `gems/boto-rb/lib/boto/http/app.rb`: keywords `env:` e `port:`, mais
    `#env` e `#port`; o `Boot` aceita `ports:` (nome -> porta), entrega a
    de cada app e grava `PORT` no `Env` do projeto (camada no topo, origem
    `boto run` quando a porta foi escolhida, senão o arquivo);
  - testes.
- **Dependências:** Task 1, porque as duas mexem no `boot.rb` e no `app.rb`.
- **Comando:** `cd gems/boto-rb && bundle exec rake test`.

## Task 2: OpenAPI com `servers` pelo `SCRIPT_NAME` (core)

- **Arquivos:**
  - `gems/boto-rb/lib/boto/http/app.rb`: o `/openapi.json` de development;
  - `gems/boto-rb/lib/boto/plugins/openapi.rb`: o plugin `:openapi`;
  - os dois: com `SCRIPT_NAME` vazio, o documento de hoje; com prefixo, o
    mesmo documento mais `servers: [{ url: SCRIPT_NAME }]`, gerado uma vez
    por prefixo e guardado num Hash;
  - testes.
- **Dependências:** Task 1b, porque mexem no `app.rb`.
- **Comando:** `cd gems/boto-rb && bundle exec rake test`.

## Task 3: Swagger UI com o `SCRIPT_NAME`

- **Arquivos:**
  - `gems/boto-rb-swaggerui/lib/boto/plugins/swagger_ui.rb` e
    `lib/boto/swagger_ui/page.rb`:
    - os links dos assets e do documento levam o `SCRIPT_NAME`;
    - a tabela de respostas é montada uma vez por prefixo e guardada;
  - testes.
- **Dependências:** nenhuma. Roda em paralelo com a Task 1.
- **Comando:** `cd gems/boto-rb-swaggerui && bundle exec rake test`.

## Task 4: gem `boto-rb-gateway`, plugin e template

- **Arquivos:**
  - eu gero o esqueleto com
    `boto plugin new boto-rb-gateway --plugin gateway --template gateway --http`
    em `gems/`, e o Gemfile aponta para o `boto-rb` local;
  - `lib/boto/plugins/gateway.rb`:
    - escopo global; opções `prefixes:` e `panel:`;
    - `attach(app)` lê `app.services` e monta o `Rack::URLMap`;
    - `call` repassa ao serviço quando o prefixo casa, senão ao próprio
      gateway;
    - em `production`, `ArgumentError` com a mensagem da proposta;
  - `lib/boto/gateway/mounts.rb`: prefixos (padrão `/<projeto>`) e a
    validação (começa com `/`, não é `/`, sem repetição, fora de `/_boto`);
  - `lib/boto/templates/gateway/template.rb`: `mounts_refs true`, e os
    `files/` com `app.use :health` e `app.use :gateway`;
  - testes.
- **Dependências:** Task 1.
- **Comando:** `cd gems/boto-rb-gateway && bundle exec rake test`.

## Task 5: painel `/_boto`

- **Arquivos:**
  - `lib/boto/gateway/service_info.rb`: `Data` com nome, template, prefixo,
    rotas, health e links;
  - `lib/boto/gateway/panel.rb`:
    - `/_boto` em HTML com escape, sem script inline, seguindo o design
      aprovado em `docs/design/gateway-panel.dc.html`:
      - topo escuro com o rubi, "Boto / gateway <nome>", selo do ambiente,
        host e link para o `services.json`;
      - resumo: serviços, prontos, fora do ar e total de rotas;
      - um cartão por serviço: nome, template, prefixo, health (ícone e
        texto: Ready, Not ready com o motivo, No health check), links do
        OpenAPI e do Swagger, e a tabela de rotas (método colorido por
        verbo, caminho com o prefixo em cinza, classe do endpoint);
      - bloco "Solution environment" (variáveis cuja origem é um arquivo da
        raiz) e, em cada cartão, um `<details>` "Environment" com as do
        projeto (`App#env`): nome, valor e origem;
      - no cabeçalho do cartão, o link `localhost:<App#port>` com
        "fixed PORT" ou "random port";
      - só `Env#file_keys`; nomes com `PASSWORD`, `SECRET`, `TOKEN`, `KEY`,
        `DSN` ou `CREDENTIAL` têm o valor trocado por `••••••••`, e URLs com
        senha mascaram só a senha (no HTML e no JSON);
      - rodapé com a versão da gem;
      - os estilos inline do design viram classes no `panel.css`;
    - `/_boto/services.json` e `/_boto/panel.css`;
    - o health é chamado no mesmo processo (`/health/ready`) quando o serviço
      usa `:health`;
  - `lib/boto/gateway/assets/panel.css`;
  - o plugin liga o painel por `panel:` (padrão: só em development);
  - testes.
- **Dependências:** Tasks 1b e 4.
- **Comando:** `cd gems/boto-rb-gateway && bundle exec rake test`.

## Task 6: `boto run` com gateway

- **Arquivos:**
  - `gems/boto-rb-cli/lib/boto/cli/commands/run.rb`:
    - as refs de um projeto `mounts_refs` não ganham porta sequencial;
    - `PORT` dos `.env` do próprio projeto (`Env#source` sob a pasta do
      projeto): `N` fixa; `0` porta livre (TCPServer na porta 0); sem
      `PORT`, porta livre se o projeto é ref de um gateway, senão a
      sequencial de hoje, que pula as fixas; `PORT` inválida e repetida são
      erro;
    - as portas resolvidas vão para o `Boot` (`ports:`), que entrega
      `App#port` a cada app;
    - o anúncio com o gateway, os prefixos e o painel;
  - testes, incluindo o reload (o `Reloader` já monta por porta com
    `boot.app`).
- **Dependências:** Tasks 1 e 1b (precisa do `Env#source`). Roda em paralelo com a Task 4.
- **Comando:** `cd gems/boto-rb-cli && bundle exec rake test`.

## Fechamento (eu)

- CI: a gem nova nas listas de teste e publicação do `ci.yml`, e o lockfile
  com as plataformas `ruby` e `x86_64-linux`.
- CHANGELOG, README (seção do gateway) e CLAUDE.md.
- Suítes com e sem YJIT; benchmark por causa do `App`.
- De ponta a ponta: solution com dois webapis e um gateway, `boto run`,
  `curl` nos prefixos, no `/_boto` e no Swagger de um serviço.
- Antes do release: o pending trusted publisher da `boto-rb-gateway`.
