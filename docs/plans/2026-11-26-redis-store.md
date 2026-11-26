# Plano — Store Redis do rate limit (gem `boto-redis`)

Status: **concluído** (2026-11-26). O cenário db_auth_redis do benchmark entrou depois, a pedido.
Proposta: `docs/proposals/0005-redis-store.md`

## Objetivo

Criar a gem `boto-redis` com a `Boto::Redis::RateLimitStore`: contagem
atômica por script Lua, timeout curto, `on_error: :allow | :deny` e URL que
nunca aparece em log. A store tem a mesma interface da `MemoryStore`.

## Fora de escopo

- A store de sessões e o cache.
- Janela deslizante.
- Cluster ou sentinel do Redis (um `client:` próprio cobre esses casos).

## Redis para os testes

A máquina não tem Redis instalado, mas tem Docker. Os testes com Redis real
precisam de um servidor. As opções são:

- **Container** `docker run -d --rm -p 6379:6379 redis:7` (minha
  recomendação): baixa a imagem oficial, de cerca de 40 MB.
- `brew install redis`.

Sem Redis, os testes que dependem dele são pulados com aviso, e só o CI os
executa.

## Contratos

```ruby
Boto::Redis::RateLimitStore.new(url: nil, client: nil, prefix: "boto:rate_limit", timeout: 0.1,
                                on_error: :allow, logger: $stderr, clock: -> { Process.clock_gettime(Process::CLOCK_REALTIME) })
#increment(key, period) -> [count, reset_in]     # mesma interface da MemoryStore
```

- **Relógio**: a janela usa o relógio de parede (REALTIME), não o monotônico.
  Instâncias diferentes precisam concordar na janela, e o monotônico de cada
  processo começa num ponto diferente.
- **`on_error: :deny`**: lança `Boto::Error::ServiceUnavailable` (503). Esse
  erro entra no core, em `http/error.rb`, e o plugin devolve a resposta dele.
  Para isso, o `:rate_limit` passa a converter um `Boto::Error` lançado pela
  store em resposta.

## Tasks

R0 e R1 rodam em paralelo, cada uma num subagente `task-runner` (Haiku). A R2
depende das duas.

- **R0 — Scaffold da gem `boto-redis`**:
  - gemspec que depende de `boto-security` (`=` à mesma versão) e de
    `redis-client`;
  - `lib/boto/redis.rb` com `for_gem_extension(Boto)` e
    `Boto::Redis::VERSION`;
  - `test_helper` com um helper `redis_url_or_skip`, que pula o teste com
    aviso quando não há Redis;
  - `Gemfile` e `Rakefile` da raiz.
- **R1 — Core e plugin**:
  - `Boto::Error::ServiceUnavailable` (503) em
    `gems/boto/lib/boto/http/error.rb`, com teste;
  - o `:rate_limit` (`gems/boto-security/.../rate_limit.rb`) converte um
    `Boto::Error` lançado por `store.increment` em resposta, com teste usando
    uma store fake.
- **R2 — `RateLimitStore`** (depende de R0 e R1):
  - `lib/boto/redis/rate_limit_store.rb` e `rate_limit_store/script.rb`;
  - testes com Redis real (contagem, janela, expiração, duas stores somando e
    `NOSCRIPT` caindo para `EVAL`);
  - testes com um cliente fake (`:allow` loga uma vez por janela, `:deny`
    gera 503, URL com senha não vaza, validação de opções);
  - integração com o plugin `:rate_limit` real.
- **R3 — CI e benchmark** (eu faço, depois da R2):
  - service container `redis:7` no job de testes, com `REDIS_URL`;
  - cenário `db_auth_redis` no benchmark, só quando houver Redis.

## Fechar (eu faço)

1. Rodo as suítes com e sem YJIT.
2. Faço o fluxo de ponta a ponta: `boto run` com dois processos apontando
   para o mesmo Redis, provando que o limite é somado entre eles.
3. Subo a versão para `0.5.0` nas quatro gems, atualizo o CHANGELOG e faço o
   push.
