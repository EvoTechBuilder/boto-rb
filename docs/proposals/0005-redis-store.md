# 0005 — Store Redis para o rate limit (gem `boto-redis`)

Status: **aprovada**

## Problema

A `MemoryStore` do `:rate_limit` conta por processo. Com vários workers do
Falcon ou várias instâncias, cada um conta separado: um `limit: 300` com 4
instâncias deixa passar até 1200 requests por minuto. O plugin já aceita
`store:`, mas não existe uma store compartilhada.

## Por que uma gem nova

A store Redis precisa de um cliente Redis. Colocá-la na `boto-security`
forçaria essa dependência em todo projeto, inclusive os que usam só a store em
memória.

Uma gem `boto-redis` segue o mesmo modelo da `boto-security`. A dependência só
entra em quem precisa, e a gem vira o lugar das outras integrações com Redis
que virão: a store do `:sessions` na Fase 3, e cache depois.

## API pública

```ruby
# Gemfile do projeto
gem "boto-redis"

# services/orders/config/app.rb
Boto.configure do |app|
  app.use :rate_limit, limit: 300, period: 60,
          store: Boto::Redis::RateLimitStore.new(url: -> { ENV.fetch("REDIS_URL") })
end
```

### `Boto::Redis::RateLimitStore`

- **`new(url: nil, client: nil, prefix: "boto:rate_limit", timeout: 0.1, on_error: :allow, logger: $stderr)`**:
  - recebe `url:` (uma String ou uma lambda lida uma vez no boot) **ou**
    `client:`, uma instância já pronta de `RedisClient` ou de um pool. As
    duas opções juntas, ou nenhuma, geram erro;
  - `timeout:` é o limite de conexão, leitura e escrita, em segundos. O
    padrão é curto (100 ms), para o rate limit nunca segurar a request;
  - `on_error:` define o que acontece quando o Redis falha (ver Segurança).
- **Mesma interface da `MemoryStore`**: `increment(key, period) -> [count, reset_in]`.
  O plugin não muda nada.

### Como conta

- **Um script Lua**: é executado com `EVALSHA` e, se o script não estiver no
  Redis, com `EVAL`. Ele faz `INCR` em `"#{prefix}:#{period}:#{janela}:#{key}"`
  e, na primeira contagem da janela, `PEXPIRE` com a duração da janela.
  Depois devolve `[count, pttl]`.
- **Atomicidade**: o script é uma única ida ao Redis e é atômico, então
  instâncias concorrentes nunca contam errado.
- **Mesma janela fixa da `MemoryStore`**: as duas stores se comportam igual.
- **Expiração**: a chave expira sozinha no fim da janela, sem precisar de
  teto de chaves nem de limpeza.

## Estrutura

```
gems/boto-redis/                       # depende de boto-security (= mesma versão) e de redis-client
  boto-redis.gemspec, Rakefile
  lib/boto/redis.rb                    # Zeitwerk.for_gem_extension(Boto); Boto::Redis::VERSION
  lib/boto/redis/rate_limit_store.rb
  lib/boto/redis/rate_limit_store/script.rb   # o Lua e o EVALSHA com fallback para EVAL
  test/...
```

- **Cliente: `redis-client`**, o cliente oficial de baixo nível, o mesmo que
  a gem `redis` 5 usa por baixo. Ele é leve e usa sockets do Ruby, então
  funciona com o fiber scheduler do Falcon: uma espera no Redis não bloqueia
  as outras requests do mesmo processo.
- **A raiz** ganha a gem no `Gemfile` e no `Rakefile`.
- **No CI**, a suíte precisa de um Redis: entra um service container
  `redis:7`. Localmente, os testes que precisam de Redis são pulados com
  aviso quando não há Redis em `REDIS_URL` ou `localhost:6379`.

## Fase do roadmap

Complemento da Fase 1. A versão sobe para `0.5.0`.

## Performance

- **No boot**: a URL é lida, o cliente é criado e o script é carregado com
  `SCRIPT LOAD`.
- **Por request**: uma ida ao Redis, um `EVALSHA`, contra nenhuma na
  `MemoryStore`. Na mesma rede, isso costuma custar menos de 1 ms.
- **Benchmark**: entra um cenário `db_auth_redis` no benchmark, só quando
  houver Redis disponível. No CI, ele usa o mesmo service container.

## Segurança

- **Redis fora do ar** (`on_error:`):
  - **`:allow` (padrão, fail-open)**: a request passa sem contar, e o erro
    vai para o log uma vez por janela, para não inundar o log. A queda do
    Redis não derruba a API.
  - **`:deny` (fail-closed)**: responde 503 problem+json. É para quem prefere
    perder disponibilidade a perder o limite, como em endpoints de login.
- **Segredos**: a URL pode conter senha, então nunca aparece em log nem na
  mensagem de erro. Só o host e a porta são mostrados.
- **Chaves**: o prefixo separa o rate limit de outros dados no mesmo Redis.
  A chave é o IP ou a chave customizada do plugin, sem dado sensível.

## Compatibilidade

Tudo é aditivo: quem não usa a `boto-redis` não muda nada. O CHANGELOG ganha
a gem nova e `Boto::Redis::RateLimitStore`.

## Testes planejados

- **Com Redis real** (pulados localmente sem Redis, obrigatórios no CI):
  - contagem dentro da janela;
  - virada da janela;
  - `reset_in` correto;
  - expiração da chave;
  - duas stores apontando para o mesmo Redis somam juntas (simula duas
    instâncias);
  - `EVALSHA` cai para `EVAL` depois de um `SCRIPT FLUSH`;
  - prefixo customizado.
- **Sem Redis**, com um cliente fake:
  - `on_error: :allow` deixa passar e loga uma vez;
  - `on_error: :deny` gera 503;
  - a URL com senha não aparece no log;
  - `url:` e `client:` juntos, ou nenhum, geram erro.
- **Integração** com o plugin `:rate_limit` real: 429 depois do limite,
  usando o Redis.

## Alternativas descartadas

- **A store dentro da `boto-security`, com o cliente Redis opcional**:
  carregamento sob demanda e mensagens de "instale a gem" espalhadas, que é o
  que a gem separada evita.
- **Uma gem só para o rate limit (`boto-rate-limit-redis`)**: as próximas
  integrações com Redis (sessions, cache) precisariam de outra gem cada.
- **Gem `redis` (alto nível)**: mais pesada, e só o `redis-client` é
  necessário.
- **`async-redis`**: nativo do ecossistema do Falcon, mas amarra a store ao
  Async. O `redis-client` também funciona com Puma.
- **Janela deslizante com sorted sets**: mais memória e mais trabalho no
  Redis por request. A janela fixa mantém o mesmo comportamento da
  `MemoryStore`.
