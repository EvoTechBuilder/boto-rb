# 0004 — Plugins de segurança (Fase 1, parte 2)

Status: **aprovada**

## Problema

Hoje um serviço do Boto aceita qualquer request: sem autenticação, CORS,
limite de taxa ou checagem de host. O CLAUDE.md define que cada proteção é um
plugin ligado no `config/app.rb` do projeto, e que o endpoint só declara
exceções (`skip`) ou exigências (`authenticate`). A Fase 1 pede `:auth`,
`:cors`, `:rate_limit` e `:hosts`.

## API pública

### `config/app.rb` do projeto

```ruby
# services/orders/config/app.rb
Boto.configure do |app|
  app.use :hosts, allow: %w[api.loja.com .loja.internal]
  app.use :cors, origins: %w[https://painel.loja.com], max_age: 600
  app.use :auth, strategy: :jwt,
          secret: -> { ENV.fetch("JWT_SECRET") }, algorithms: %w[HS256],
          issuer: "loja", audience: "orders"
  app.use :rate_limit, limit: 100, period: 60   # 100 requests por minuto por IP
end
```

- **`app.use(nome_ou_classe, **opções)`**:
  - o nome resolve `Boto::Plugins::<Nome>`;
  - uma classe de terceiros também funciona (`app.use MeuPlugin, ...`);
  - opções inválidas falham no boot, com mensagem clara;
  - o mesmo plugin declarado duas vezes também é erro.
- **Segredos**: são lambdas, lidas uma vez no boot, para não ficarem no
  código. Até existir o `boto credentials`, o padrão é `ENV`.

### Endpoint

```ruby
class Orders::Health < Boto::Endpoint
  get "/health"
  skip :auth, :rate_limit
  def call = { status: "ok" }
end

class Orders::Webhooks::Payment < Boto::Endpoint
  post "/webhooks/payment"
  authenticate :signature, secret: -> { ENV.fetch("PAYMENT_WEBHOOK_SECRET") },
                           header: "X-Signature"
  body Orders::PaymentEventSchema
  def call(body:) = Payments.record(body)
end

class Orders::Me < Boto::Endpoint
  get "/me"
  def call = { user: principal[:sub] }   # identidade autenticada
end
```

- **`skip(*plugins)`**: desliga plugins de endpoint (`:auth` e
  `:rate_limit`) só para aquele endpoint. Pular um plugin que não está ligado
  no projeto é erro no boot, para não esconder um erro de digitação.
- **`authenticate(estratégia, **opções)`**: usa outra estratégia só naquele
  endpoint, no lugar da do projeto.
- **`principal`**: devolve o que a estratégia autenticou. É um Hash congelado,
  por exemplo as claims do JWT, `{ user: "admin" }` no basic ou
  `{ key_id: ... }` na api_key. Sem auth, devolve `nil`.

### Estratégias do `:auth`

| Estratégia | Opções | Verificação |
|---|---|---|
| `:basic` | `credentials: -> { { "admin" => "senha" } }`, `realm:` | `Rack::Utils.secure_compare` em usuário e senha |
| `:bearer` | `tokens: -> { %w[...] }` | `secure_compare` contra cada token |
| `:api_key` | `keys: -> { { "id" => "chave" } }`, `header: "X-API-Key"` | `secure_compare` |
| `:jwt` | `secret:` ou `public_key:`, `algorithms:` (obrigatório), `issuer:`, `audience:`, `leeway:` | gem `jwt`, com algoritmos em allowlist, `exp`/`nbf` e iss/aud |
| `:signature` | `secret:`, `header:`, `algorithm: "sha256"`, `tolerance:` | HMAC do corpo bruto via OpenSSL + `secure_compare`; com `tolerance`, valida o timestamp |

- **Falha**: devolve 401 problem+json com `WWW-Authenticate`. A mensagem não
  diz qual parte falhou.

### Outros plugins

- **`:hosts`**:
  - `allow:` aceita nomes exatos e sufixos com ponto inicial
    (`.loja.internal`);
  - em development, `localhost`, `127.0.0.1` e `[::1]` são liberados por
    padrão;
  - um host fora da lista recebe 403 problem+json. Isso protege contra DNS
    rebinding.
- **`:cors`**:
  - opções: `origins:`, `methods:` (padrão: os verbos das rotas, incluindo
    QUERY), `headers:`, `expose:`, `credentials:` e `max_age:`;
  - responde o preflight `OPTIONS` mesmo sem rota;
  - `origins: "*"` junto com `credentials: true` é erro no boot.
- **`:rate_limit`**:
  - opções: `limit:`, `period:`, `key: ->(request) { ... }` (padrão: o IP em
    `REMOTE_ADDR`) e `store:`;
  - a store padrão é em memória, por processo, com janela fixa;
  - o excesso recebe 429 problem+json com `Retry-After`;
  - toda resposta traz os headers `RateLimit-Limit`, `RateLimit-Remaining` e
    `RateLimit-Reset`.

### OpenAPI

- Com `:auth` ligado, o documento ganha `components.securitySchemes` (http
  basic, http bearer com `bearerFormat: JWT`, ou apiKey) e `security` global.
- Um endpoint com `skip :auth` recebe `security: []`.

## Ordem e escopo dos plugins

Os plugins são middlewares Rack numa ordem fixa. Há dois escopos:

- **Globais** rodam antes do roteamento, então valem para 404, 405 e
  preflight: `hosts -> cors`, e depois `secure_headers -> sessions -> csrf`
  quando existirem (Fase 3).
- **De endpoint** rodam depois do roteamento e podem ser pulados:
  `auth -> rate_limit`.

A ordem do CLAUDE.md passa a incluir o `cors` logo depois do `hosts`, e o
CLAUDE.md vai ser atualizado. O CORS precisa vir antes do `auth`: um preflight
não leva credenciais.

## Estrutura

Os plugins de segurança vivem numa gem nova, `boto-security`. O core guarda só
a base dos plugins, para continuar mínimo, como pede o CLAUDE.md. É o mesmo
modelo da `boto-telemetry`.

```
gems/boto/lib/boto.rb                  # + Boto.configure
gems/boto/lib/boto/
  configuration.rb                     # captura do bloco durante o boot do projeto; resolve plugins por nome
  plugin.rb, plugin/stack.rb           # base: validação de opções, escopo (:global | :endpoint), ordem
  http/error.rb                        # + Unauthorized (401), Forbidden (403), TooManyRequests (429)
  endpoint/endpoint.rb                 # + skip, authenticate, principal
  http/app.rb                          # pilha global em volta; pilha de endpoint compilada por rota no boot
  solution/boot.rb                     # carrega config/app.rb do projeto
  openapi/...                          # securitySchemes

gems/boto-security/                    # depende de boto (= mesma versão) e de jwt
  boto-security.gemspec, Rakefile
  lib/boto/security.rb                 # Zeitwerk.for_gem_extension(Boto); Boto::Security::VERSION
  lib/boto/plugins/hosts.rb, cors.rb, rate_limit.rb, auth.rb
  lib/boto/plugins/rate_limit/memory_store.rb
  lib/boto/plugins/auth/{basic,bearer,api_key,jwt,signature}.rb

gems/boto-cli/templates/solution/Gemfile.erb       # + gem "boto-security"
gems/boto-cli/templates/webapi/config/app.rb.erb   # plugins padrão do template
```

- **`Boto.configure` sem estado global**: o `Boot` avalia o `config/app.rb`
  dentro de um contexto de captura. Chamar `Boto.configure` fora do boot de
  um projeto é erro.
- **Resolução por nome**: `app.use :auth` resolve `Boto::Plugins::Auth`. O
  namespace `Boto::Plugins` é compartilhado entre os loaders do Zeitwerk do
  core e da `boto-security`. Se a gem não estiver no Gemfile, o boot falha com
  `unknown plugin :auth (add gem "boto-security" to the Gemfile)`.
- **`jwt` como dependência da `boto-security`**: não fica opcional nem é
  carregada sob demanda, porque a gem de segurança é o lugar natural dela. O
  core continua sem nenhuma dependência nova.
- **Versões juntas**: a `boto-security` acompanha a versão do core (`= 0.4.0`),
  como a `boto-cli`.
- **Plugins da Fase 3**: `:secure_headers`, `:sessions` e `:csrf` entram nesta
  mesma gem.

## Template webapi

O `config/app.rb` gerado já liga os plugins padrão do CLAUDE.md:

```ruby
Boto.configure do |app|
  app.use :cors, origins: ENV.fetch("CORS_ORIGINS", "").split(",")
  app.use :auth, strategy: :bearer, tokens: -> { ENV.fetch("API_TOKENS", "").split(",") }
  app.use :rate_limit, limit: 300, period: 60
end
```

O `health` gerado ganha `skip :auth, :rate_limit`.

## Fase do roadmap

Fase 1, parte 2. Ficam para depois:

- `:secure_headers`, `:sessions` e `:csrf`, junto com o template `web` na
  Fase 3;
- a store Redis do `:rate_limit` e o `boto credentials`, na Fase 2 ou numa
  proposta à parte.

## Performance

- **No boot**:
  - os segredos são lidos;
  - as opções são validadas;
  - a pilha global é montada uma vez;
  - para cada rota, a pilha de endpoint é compilada já com os `skip`
    aplicados, e guardada na entrada do roteador. Um endpoint sem plugins não
    paga nada.
- **Por request**, só o trabalho do plugin:
  - `hosts`: uma consulta a um Set;
  - `cors`: uma comparação de origem;
  - `rate_limit`: um incremento sob Mutex;
  - `auth`: uma comparação ou verificação de assinatura.
- **Medição**: um cenário de benchmark `db_auth` (bearer + rate_limit) mede o
  custo, e os testes de alocação travam o caminho sem plugins como está hoje.

## Segurança

- **Comparações de segredo**: sempre com `Rack::Utils.secure_compare`, depois
  de normalizar o tamanho com um digest SHA-256. Assim não vaza o tamanho.
- **JWT**:
  - `algorithms:` é obrigatório;
  - `none` é sempre recusado;
  - `exp` é validado, e `iss`/`aud` quando configurados.
- **Signature**: o HMAC é calculado sobre o corpo bruto, lido uma vez e
  devolvido ao `rack.input` com `rewind`, para o schema ler depois.
- **Falhas de auth**: 401 sem detalhe. Os logs nunca registram o token, nem
  quando o `error_output` recebe uma exceção.
- **`:rate_limit` e o IP**: só confia em `X-Forwarded-For` com
  `trusted_proxies:` explícito. O padrão é `REMOTE_ADDR`.
- **Defaults seguros**:
  - CORS sem `origins` não libera nada;
  - `hosts` em production sem `allow` é erro no boot;
  - `skip` de um plugin desconhecido é erro no boot.

## Compatibilidade

- Tudo é aditivo: projetos sem `config/app.rb` funcionam como hoje, e quem não usa plugins não precisa da `boto-security`.
- A versão sobe para minor, `0.4.0`.
- O CHANGELOG ganha, em `Added`:
  - `Boto.configure`;
  - os 4 plugins;
  - as 5 estratégias de auth;
  - `skip`, `authenticate` e `principal`;
  - `securitySchemes` no OpenAPI;
  - o template com plugins;
  - a gem nova `boto-security`.
- A ordem de plugins documentada muda.

## Testes planejados

- **Por plugin, com `Rack::MockRequest`:**
  - **hosts**: host liberado, sufixo, host bloqueado e os defaults de
    development.
  - **cors**: preflight com e sem origem permitida, QUERY no
    `Access-Control-Allow-Methods`, credentials e o erro de `*` com
    credentials.
  - **rate_limit**: dentro do limite, estouro com 429 e `Retry-After`, reset
    da janela (com relógio injetado) e chave customizada.
- **Cada estratégia de auth:**
  - credencial certa, errada e ausente;
  - JWT expirado, com `alg` fora da allowlist, com `none` e com iss/aud
    errados;
  - signature com corpo alterado e com timestamp fora da tolerância.
- **No endpoint:**
  - `skip` só afeta aquele endpoint;
  - `skip` desconhecido dá erro no boot;
  - `authenticate` sobrepõe a estratégia do projeto;
  - `principal` dentro do `call`.
- **Ordem**: um preflight passa sem token, e um 404 também recebe os headers
  CORS.
- **Configuração:**
  - `Boto.configure` fora do boot é erro;
  - plugin duplicado é erro;
  - opções inválidas são erro;
  - um plugin sem a gem `boto-security` dá a mensagem certa.
- **OpenAPI**: `securitySchemes` e `security: []` no endpoint com `skip`.
- **Ponta a ponta**: `boto new`/`add webapi`, e depois `boto run` com
  `API_TOKENS`. O `curl` sem token dá 401, com token dá 200, e o `/health`
  responde sem token.

## Alternativas descartadas

- **Todos os plugins como middleware global antes do roteamento**: o `skip`
  por endpoint obrigaria a resolver a rota duas vezes por request.
- **Registro global de plugins (`Boto::Plugins.register`)**: estado global
  mutável. A resolução por constante já cobre os plugins de terceiros.
- **Uma gem por plugin**: quatro ou cinco gems para versionar e lançar juntas, e o template `webapi` já liga quase todas.
- **Plugins dentro do core**: contraria o "núcleo mínimo" do CLAUDE.md e traria a `jwt` para o core.
- **Implementar a verificação de JWT à mão sobre o OpenSSL**: o parsing e
  os detalhes do JWT são fonte comum de falhas, e o CLAUDE.md manda reaproveitar
  código auditado.
- **`rack-attack` para o rate limit**: uma dependência a mais por pouco
  ganho, e o Redis pode entrar depois pela interface `store:`.
- **Ler os segredos a cada request**: custo por request e risco de falhar no
  meio do tráfego. A rotação de segredo fica para o `boto credentials`.
