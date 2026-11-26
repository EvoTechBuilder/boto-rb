# Health checks e graceful shutdown (proposta 0010)

Status: **concluído**

## Objetivo

Plugin `:health` no core, com `/health/live` e `/health/ready`, checagens do
projeto e dos plugins, e graceful shutdown no `boto run`.

## Fora de escopo

- Template `microservice` e Dockerfile, que são o próximo passo.
- Telemetria das checagens.

## Task H1: `:health` e drenagem no core (boto-rb)

- **Arquivos:**
  - `gems/boto-rb/lib/boto/plugin.rb`: `health_checks` (`{}`) e `drain` (não
    faz nada); `:health` no início do `ORDER`;
  - `gems/boto-rb/lib/boto/plugins/health.rb` (novo):
    - `Boto::Plugins::Health`, global, com `checks:` e `timeout:` validados
      no boot;
    - responde `/health/live` e `/health/ready` e repassa o resto sem
      alocar;
    - no `start`, junta as checagens dos outros plugins da app;
    - `drain` liga o 503 do ready;
    - as checagens rodam em paralelo, com timeout, e os erros vão para o log
      sem aparecer na resposta;
  - `gems/boto-rb/lib/boto/http/app.rb`: `drain!` chama `drain` em todos os
    plugins do lifecycle e é idempotente. O `:health` precisa enxergar os
    plugins da app para juntar as checagens; a task decide o caminho mais
    simples, por exemplo a app entregando a lista no `start`.
  - Testes em `gems/boto-rb/test/boto/plugins/health_test.rb` e
    `gems/boto-rb/test/boto/http/`.
- **Testes:** os da proposta para o `:health` e o `drain!`. O
  `/health/*` não aparece no OpenAPI.
- **Dependências:** nenhuma.

## Task H2: checagem da store Redis (boto-rb-security e boto-rb-redis)

- **Arquivos:**
  - `gems/boto-rb-redis/lib/boto/redis/rate_limit_store.rb`: `healthy?` faz um
    `PING` com o timeout da store e devolve `true` ou `false`, sem lançar;
  - `gems/boto-rb-security/lib/boto/plugins/rate_limit.rb`: `health_checks`
    devolve `{ rate_limit_store: -> { store.healthy? } }` quando a store
    responde a `healthy?`, e `{}` quando não responde;
  - os testes.
- **Testes:**
  - `healthy?` com Redis real dá `true`, e com client fake que falha dá
    `false`;
  - `health_checks` com e sem `healthy?`.
- **Dependências:** nenhuma. Roda em paralelo com a H1.

## Task H3: graceful shutdown no `boto run` (boto-rb-cli)

- **Arquivos:**
  - `gems/boto-rb-cli/lib/boto/cli/support/server.rb`:
    - endpoints já ligados (`bound`);
    - um middleware que conta os requests em andamento;
    - `drain(delay:, timeout:)` chama `drain!` nas apps, espera o `delay`,
      fecha os listeners (tratando o `IOError` do accept), espera os
      requests em andamento até o `timeout` e para o servidor;
  - `gems/boto-rb-cli/lib/boto/cli/commands/run.rb`:
    - `OPTIONS` `--shutdown-timeout N` (padrão 25) e `--drain-delay N`
      (padrão 0);
    - `SIGTERM` e `SIGINT` disparam a drenagem, e um segundo sinal encerra
      com 1;
    - no fim, o `boot.shutdown` que já existe;
  - os testes do `run` e do server.
- **Testes:**
  - a drenagem espera um request lento e só depois chama o `stop` dos
    plugins;
  - estourando o timeout, encerra mesmo assim;
  - um segundo sinal encerra na hora;
  - a ajuda do `run` mostra as opções novas.
- **Dependências:** H1 (`App#drain!`).

## Task H4: template `webapi` com `:health`

- **Arquivos:**
  - em `gems/boto-rb-cli/templates/webapi/`:
    - remover `endpoints/health.rb.erb` e `schemas/health_schema.rb.erb` e
      os testes deles;
    - colocar `app.use :health` no `config/app.rb.erb`, como primeira linha;
  - os testes do gerador e do `add`;
  - o teste de integração do `run`, que passa a chamar `/health/live`.
- **Testes:**
  - um projeto gerado responde 200 em `/health/live` e em `/health/ready`;
  - o `boto test` do projeto gerado passa;
  - o OpenAPI do projeto gerado não tem `/health`.
- **Dependências:** H1 e H3, porque mexe nos testes do `run`.

## Execução

H1 e H2 rodam em paralelo, e depois H3 e H4 em sequência, com um commit por
task. A H1 coloca um plugin no caminho quente, então meço alocações e req/s
do cenário `hello` com e sem `:health` (skill `benchmark`). No fechamento:

- corrijo o plural "1 projects tested" do `boto test`;
- rodo as quatro suítes com e sem YJIT;
- atualizo o CHANGELOG;
- marco a 0010 como implementada.

## Resultado

- H1: `0854459`. H2: `73a5ab0`. H3: `fd51630`. H4: `8970647`.
- O `:health` não acrescenta alocação por request. Numa rota comum, chamando a
  app direto, custou de 5% a 7% de chamadas por segundo.
- Teste manual do `boto run`, inclusive via `bundle exec`:
  - o TERM drena e sai com 0;
  - o segundo sinal sai com 1;
  - o timeout corta o request lento.
