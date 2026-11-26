# Lifecycle de plugins (proposta 0007)

Status: **concluído**

## Objetivo

Plugins ganham `start` e `stop`. A app inicia os plugins no boot e os para no
shutdown, em ordem inversa, com tratamento de falhas e de forma idempotente.
O `:rate_limit` passa a fechar a store, e a store Redis fecha o pool.

## Fora de escopo

- Health checks e graceful shutdown do Falcon (Fase 2).
- Lifecycle para os loaders do Zeitwerk, que o `Boot#shutdown` já cobre.

## Task L1: `start`/`stop` no Plugin e no App (boto-rb)

- **Arquivos:**
  - `gems/boto-rb/lib/boto/plugin.rb`: `start` e `stop` públicos, que não fazem
    nada.
  - `gems/boto-rb/lib/boto/http/app.rb`:
    - `App#start` inicia, na ordem de `ORDER`, todos os plugins da app: os
      globais, os de endpoint e as instâncias de `:auth` criadas por
      `authenticate` nos endpoints, sem repetir a mesma instância;
    - se um `start` falha, para os que já iniciaram em ordem inversa e lança
      `BootError` com o nome do plugin e a causa;
    - `App#stop` para os plugins iniciados em ordem inversa. Uma falha num
      `stop` é registrada no `error_output` e não interrompe os outros;
    - os dois são idempotentes.
  - Testes em `gems/boto-rb/test/boto/http/app_lifecycle_test.rb` (novo).
- **Testes:**
  - `start` em ordem;
  - `stop` em ordem inversa;
  - `start` e `stop` chamados duas vezes rodam uma vez só;
  - falha no terceiro `start`: os dois primeiros param e sai um `BootError`
    com o plugin na mensagem;
  - falha num `stop`: os outros param e o erro vai para o `error_output`;
  - um plugin de `authenticate` no endpoint também inicia e para;
  - um plugin sem `start`/`stop` próprios funciona.
- **Dependências:** nenhuma.

## Task L2: `close` na store Redis e `stop` no `:rate_limit`

- **Arquivos:**
  - `gems/boto-rb-redis/lib/boto/redis/rate_limit_store.rb`: `close` encerra o
    pool que a store criou a partir de `url:`. Um `client:` injetado pertence a
    quem o passou e não é fechado. O método é idempotente.
  - `gems/boto-rb-security/lib/boto/plugins/rate_limit.rb`: `stop` chama
    `@store.close` quando a store responde a `close`.
  - Testes espelhados nas duas gems.
- **Testes:**
  - o `stop` do rate_limit fecha uma store com `close` e ignora uma sem
    `close`, como a `MemoryStore`;
  - o `close` da store com `url:` fecha o pool, e um segundo `close` não
    falha. O teste usa Redis real e é pulado sem Redis, como os testes de
    integração que já existem;
  - o `close` com `client:` injetado não fecha o client.
- **Dependências:** nenhuma. O método `stop` funciona mesmo antes da L1, e roda
  em paralelo com ela.

## Task L3: Boot inicia e para as apps (boto-rb e boto-rb-cli)

- **Arquivos:**
  - `gems/boto-rb/lib/boto/solution/boot.rb`:
    - `app` chama `start` antes de devolver a app e guarda as apps criadas;
    - `shutdown` para as apps em ordem inversa e depois descarrega os loaders;
    - `shutdown` é idempotente.
  - `gems/boto-rb/test/boto/solution/boot_test.rb`.
  - `gems/boto-rb-cli/test/boto/cli/commands/run_test.rb`: confirma que o
    `boto run` para as apps ao sair. O comando já chama `boot.shutdown` no
    `ensure`, então não deve precisar de mudança.
- **Testes:**
  - `app` devolve a app iniciada;
  - `shutdown` chama `stop` das apps antes de descarregar os loaders;
  - `shutdown` duas vezes não falha;
  - no `boto run`, um plugin de teste registra `stop` ao sair.
- **Dependências:** L1.

## Execução

L1 e L2 rodam em paralelo, e a L3 roda depois da L1. Cada task tem seu commit.
No fechamento:

- rodo as quatro suítes com e sem YJIT;
- atualizo o CHANGELOG (`Added`: `Plugin#start`/`#stop`, `App#start`/`#stop` e
  `RateLimitStore#close`; `Changed`: `Boot#app` inicia a app e
  `Boot#shutdown` para as apps);
- marco a proposta 0007 como implementada.

O caminho por request não muda, então não precisa de benchmark.

Comando: `cd gems/<gem> && bundle exec rake test`, com e sem
`RUBY_YJIT_ENABLE=1`. A L2 precisa do Redis (`boto-redis-dev`, porta 6379).

## Resultado

- L1: `5248356`. L2: `1184470`. L3: commit seguinte a `5248356` (Boot).
- Depois do `close`, o `redis-client` reabre o pool no próximo uso; o `stop` precisa ser a última chamada, o que o `Boot#shutdown` garante.
