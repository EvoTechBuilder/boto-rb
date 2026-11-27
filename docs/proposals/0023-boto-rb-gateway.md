# 0023 — `boto-rb-gateway`: a solution numa porta só, com painel

Status: **implementada**

Depende da 0021 (templates como gems) e da 0022 (`boto plugin new`, que gera a
gem).

## Problema

- O `boto run` dá uma porta para cada projeto HTTP (3000, 3001, 3002...). Quem
  usa a solution, como um frontend, precisa saber qual porta é de qual serviço,
  e a ordem muda quando entra um projeto novo.
- Não existe um lugar para ver os serviços que estão de pé, as rotas de cada
  um e o estado do health check.

## API pública

### Criando o gateway

```bash
# Gemfile da solution: gem "boto-rb-gateway"
bundle install
boto add gateway borda --refs catalogo,users
```

```ruby
# Botofile
project "dominio",  template: :library
project "catalogo", template: :webapi, refs: %w[dominio]
project "users",    template: :webapi
project "borda",    template: :gateway, refs: %w[catalogo users]
```

- **As `refs` do gateway são os serviços que ele expõe.** Uma ref que não é
  HTTP (uma `library`, por exemplo) é erro no boot:
  `gateway borda: ref "dominio" is not an HTTP project`.

```ruby
# apps/borda/config/app.rb (gerado pelo template)
Boto.configure do |app|
  app.use :health
  app.use :gateway
end
```

```ruby
# opções, todas opcionais
app.use :gateway,
        prefixes: { "users" => "/contas" },   # padrão: "/<projeto>"
        panel: true                           # padrão: true em development, false nos outros
```

### Rodando

```
$ boto run
Gateway borda on http://localhost:3000
  catalogo  http://localhost:3000/catalogo
  users     http://localhost:3000/users
  panel     http://localhost:3000/_boto
Reloading on file changes (development)
```

- **Uma porta para usar:** quando a solution tem um gateway, tudo é acessado
  pela porta dele. Os serviços continuam com porta própria (veja `PORT`),
  mas ninguém precisa decorar qual é.
  - Cada serviço também responde na própria porta, além do prefixo. Os dois
    caminhos servem o mesmo app, no mesmo processo:
    `localhost:3000/catalogo/products` e `localhost:4101/products` dão a
    mesma resposta.
    - `PORT=4101`: essa porta;
    - `PORT=0` ou sem `PORT`: uma porta livre escolhida no boot.
  - Projetos HTTP que nenhum gateway referencia continuam com porta própria.
  - `boto run catalogo` sobe só o `catalogo`, na porta dele, como hoje.
- **Prefixo por serviço:** `GET /catalogo/products/1` chega ao `catalogo` como
  `GET /products/1`, com `SCRIPT_NAME` igual a `/catalogo`. O endpoint não
  muda nada.
- **Sem proxy:** os apps das refs rodam no mesmo processo do gateway, e a
  chamada é um `call` Rack direto, sem rede nem serialização.
- **Plugins:** os plugins globais do gateway (`:cors`, `:hosts`) valem para
  tudo o que passa por ele. Os plugins de cada serviço (`:auth`,
  `:rate_limit`...) continuam valendo dentro do serviço.
- **O que não casa com nenhum prefixo** vai para o próprio gateway (seus
  endpoints, o health dele ou o 404 JSON de sempre).

### A variável `PORT`

- **Vale para qualquer projeto HTTP, com ou sem gateway.**
  - Com gateway, um serviço sem `PORT` ganha uma porta livre, como
    `PORT=0`.
  - Sem gateway, um projeto sem `PORT` segue a porta sequencial de hoje
    (`--port`, `+1`...), que pula as portas já fixadas. Assim o `boto run`
    sem gateway continua como está.
- **`PORT` sempre existe no `app.env` de um projeto servido pelo
  `boto run`:** com o valor da porta em que ele de fato escuta, mesmo quando
  ninguém a definiu (`app.env.fetch("PORT")` nunca falha). Com `PORT=0`, o
  `app.env` traz a porta escolhida, não o `0`. Fora do `boto run` (`boto test`,
  `boto db`) não há servidor, e a `PORT` é a dos arquivos, se houver.
  - Origem no painel: o arquivo, para uma porta fixa; `boto run`, para uma
    porta escolhida.
- **Só conta a `PORT` dos `.env` do próprio projeto** (`apps/catalogo/.env*`).
  A `PORT` do processo ou do `.env` da raiz valeria para todos os projetos e
  daria conflito, então é ignorada aqui.
- **O gateway** usa a própria `PORT`, se tiver, ou a do `--port`.
- **Erros antes de subir:** `PORT` que não é um inteiro entre 0 e 65535, e
  duas portas fixas iguais (`catalogo and users both use PORT=4101`).
- **No anúncio do `boto run`** e no painel aparece a porta de verdade,
  inclusive a escolhida para `PORT=0`.

```
$ boto run
Gateway borda on http://localhost:3000
  catalogo  http://localhost:3000/catalogo   http://localhost:4101
  users     http://localhost:3000/contas     http://localhost:53817 (random)
  pedidos   http://localhost:3000/pedidos    http://localhost:61042 (random)
  panel     http://localhost:3000/_boto
```

### Painel `/_boto`

- **`GET /_boto`:** HTML simples, sem JavaScript. Para cada serviço:
  - nome, template, prefixo e a porta própria (fixa ou aleatória);
  - status do `/health/ready` (chamado no mesmo processo, quando o serviço usa
    `:health`; sem ele, aparece "sem health check");
  - as rotas (verbo e caminho, com o prefixo);
  - links para o `openapi.json` e, se o serviço usa `:swagger_ui`, para o
    Swagger;
  - as variáveis do projeto (`app.env`), num bloco que abre e fecha
    (`<details>`, sem JavaScript).
- **Variáveis da solution:** um bloco no topo com as variáveis dos `.env` da
  raiz (as que vão para o `ENV`).
- **Quais variáveis aparecem:** só as definidas nos arquivos `.env*` da
  solution ou do projeto. O resto do `ENV` do processo (`PATH`, `HOME`...)
  não aparece. Se o processo sobrescreve uma delas, a origem mostrada é
  `process`.
- **Cada variável mostra:** nome, valor e o arquivo de onde veio
  (`.env.local`, `apps/catalogo/.env.development`...).
- **Valores mascarados:**
  - um nome com `PASSWORD`, `SECRET`, `TOKEN`, `KEY`, `DSN` ou `CREDENTIAL`
    tem o valor inteiro trocado por `••••••••`;
  - uma URL com senha (`postgres://user:senha@host/db`) mostra a URL com só
    a senha mascarada;
  - o valor real nunca sai do processo, nem no HTML nem no JSON.
- **`GET /_boto/services.json`:** os mesmos dados em JSON (variáveis
  mascaradas do mesmo jeito), para scripts e testes.
- **CSS** num arquivo servido pelo próprio painel (`/_boto/panel.css`), sem
  estilo nem script inline.

### Em produção

- Fora do escopo desta proposta. Em `production`, o `app.use :gateway` falha
  no boot com
  `gateway runs in development and test only for now; in production, route with your ingress`.
- O gateway em produção (proxy reverso para serviços separados) fica para uma
  proposta futura.

### Assinaturas

- `Boto::Template.define ... { |t| t.mounts_refs true }`: opção nova do
  template (padrão `false`). O `boto run` não abre porta para as refs de um
  projeto com `mounts_refs`, e o `Boot` entrega a ele os apps das refs.
- `Boto::App#services`: Hash congelado `{ "catalogo" => <Boto::App>, ... }`
  com os apps das refs HTTP. Vazio em projetos sem `mounts_refs`. O plugin lê
  no `attach(app)`.
- `Boto::Plugins::Gateway < Boto::Plugin`, escopo global, opções `prefixes:` e
  `panel:`.

## Estrutura

### Gem nova (gerada com `boto plugin new boto-rb-gateway --plugin gateway --template gateway --http`)

```
gems/boto-rb-gateway/
├── lib/boto/gateway.rb                   # entrada (Zeitwerk for_gem_extension)
├── lib/boto/gateway/version.rb
├── lib/boto/gateway/mounts.rb            # prefixos -> apps (Rack::URLMap), validação dos prefixos
├── lib/boto/gateway/panel.rb             # /_boto, /_boto/services.json e /_boto/panel.css
├── lib/boto/gateway/service_info.rb      # Data: nome, template, prefixo, rotas, health, links
├── lib/boto/gateway/assets/panel.css
├── lib/boto/plugins/gateway.rb           # Boto::Plugins::Gateway: attach, call
└── lib/boto/templates/gateway/
    ├── template.rb                       # folder "apps", http true, mounts_refs true
    └── files/                            # config/app.rb, test/test_helper.rb, gemspec
```

- **Roteamento:** o `Rack::URLMap` do Rack já faz o casamento pelo prefixo
  mais longo, respeitando o limite de segmento (`/users` não casa com
  `/usersx`), e ajusta `SCRIPT_NAME` e `PATH_INFO`. O gateway não reimplementa
  isso.
- **Prefixos:** precisam começar com `/`, não podem ser `/`, não podem se
  repetir nem começar com `/_boto`. Erro no boot com o nome do serviço.

### Mudanças no core (`boto-rb`)

- `template.rb`: a opção `mounts_refs`.
- `solution/boot.rb`: ao montar um projeto com `mounts_refs`, monta antes os
  apps das refs HTTP (reaproveitando os já montados no mesmo `Boot`) e os
  passa para o `App`.
- `http/app.rb`: `services:` e `env:` no construtor, mais `#services` e
  `#env` (o mesmo `app.env` do projeto).
- **Origem das variáveis:** `Boto::Env#source(key)` devolve o arquivo de onde
  a variável veio, relativo à raiz da solution (`.env.local`,
  `apps/catalogo/.env.development`), ou `"process"`. `Boto::Env#file_keys`
  lista só as variáveis definidas em arquivos. O painel separa as da
  solution (arquivo na raiz) das do projeto por essa origem.
- **`SCRIPT_NAME` no OpenAPI:** o `/openapi.json` (de development e do plugin
  `:openapi`) ganha `servers: [{ url: SCRIPT_NAME }]` quando o app está
  montado num prefixo. Sem isso, o Swagger chamaria `/products` em vez de
  `/catalogo/products`. O documento é gerado uma vez por prefixo e guardado.

### Mudanças nas outras gems

- `boto-rb-swaggerui`: os links dos assets e do documento passam a levar o
  `SCRIPT_NAME`, com a página guardada por prefixo como no OpenAPI.
- `boto-rb-cli`, `commands/run.rb`: as portas (gateway, `PORT` de cada
  projeto e porta livre para `PORT=0`) e o anúncio novo.
- O CLI resolve as portas antes do boot e as passa ao `Boot`, que entrega a
  cada `App` a sua (`App#port`) e a grava como `PORT` no `app.env`. O painel
  lê dali.

## Fase do roadmap

Fase 2, junto dos templates como gems (é o primeiro template de terceiros) e
da melhoria do dev. O gateway de produção fica para depois.

## Performance

- **Boot:** os apps das refs são montados uma vez, como já acontece hoje no
  `boto run`. O mapa de prefixos é compilado no `attach`.
- **Por request:**
  - o `Rack::URLMap` percorre a lista de prefixos (um por serviço) e aloca o
    ajuste de `SCRIPT_NAME`/`PATH_INFO`. Custo pequeno e só no dev;
  - os serviços não mudam: o caminho quente do core continua igual, e o
    documento OpenAPI por prefixo sai de um cache.
- **Benchmark:** o cenário atual não passa pelo gateway, então não deve mudar.
  Vou rodar a skill `benchmark` por causa da mudança no `App`.

## Segurança

- **Painel:** expõe rotas, estado e variáveis (mascaradas) dos serviços. Fica ligado só em
  development, e o gateway inteiro não sobe em production nesta versão.
- **Prefixo e isolamento:** o serviço recebe só o caminho sem o prefixo; um
  `PATH_INFO` com `..` não escapa para outro serviço, porque o casamento é
  feito no caminho como chegou, e cada app roteia só o que é dele.
- **Variáveis de ambiente no painel:** só as dos arquivos `.env*`, nunca o
  `ENV` inteiro. Nomes sensíveis (`PASSWORD`, `SECRET`, `TOKEN`, `KEY`,
  `DSN`, `CREDENTIAL`) e a senha de URLs são mascarados antes de montar o
  HTML e o JSON, então o valor real não sai do processo. O painel continua só
  em development.
- **HTML do painel:** todo valor (nomes, caminhos de rotas) passa por escape;
  sem script inline, para funcionar com CSP restritiva.
- **Plugins do gateway na frente:** `:cors` e `:hosts` do gateway valem para
  todos os serviços, inclusive 404 e preflight, como num serviço só.

## Compatibilidade

- **Minor, aditiva:** sem gateway na solution, o `boto run` se comporta como
  hoje.
- **Mudança visível:** o `/openapi.json` de um app montado num prefixo ganha
  `servers`. Fora do gateway, nada muda.
- **CHANGELOG:**
  - Added: gem `boto-rb-gateway` (template `gateway`, plugin `:gateway`,
    painel `/_boto`), `Template#mounts_refs`, `App#services`, `App#env`,
    `Env#source`, `Env#file_keys`,
    `App#port`, `PORT` por projeto no `boto run`;
  - Changed: OpenAPI e Swagger UI respeitam o `SCRIPT_NAME`.
- **Release:** gem nova, então o pending trusted publisher da
  `boto-rb-gateway` precisa ser cadastrado antes.

## Testes planejados

- **Core:**
  - `mounts_refs` no `Template.define`, com o padrão `false`;
  - o `Boot` entrega os apps das refs em `App#services` e reaproveita os já
    montados;
  - ref que não é HTTP é erro;
  - `servers` no OpenAPI com e sem `SCRIPT_NAME`, e o cache por prefixo;
  - `Env#source` (arquivo da solution, do projeto e `process`) e
    `Env#file_keys`.
- **Gateway:**
  - prefixo padrão e sobrescrito;
  - `SCRIPT_NAME`/`PATH_INFO` que chegam ao serviço;
  - limite de segmento (`/usersx`);
  - caminho sem prefixo vai para o próprio gateway;
  - prefixo inválido, repetido ou em `/_boto` é erro;
  - boot em production falha com a mensagem;
  - `:cors` do gateway vale para o serviço.
- **Painel:**
  - HTML e JSON com serviços, rotas, health (ok, falhando e ausente) e links;
  - escape dos valores;
  - variáveis da solution e do projeto, com a origem; o `ENV` do processo
    fora; máscara por nome e da senha em URL, no HTML e no JSON;
  - `panel: false` e o padrão fora de development.
- **Swagger UI:** assets e documento com o prefixo.
- **CLI:**
  - com gateway, só a porta dele e as dos serviços com `PORT`;
  - `PORT=N`, `PORT=0` e sem `PORT` (porta livre, anunciada); o mesmo app
    responde no prefixo e na porta;
  - `app.env.fetch("PORT")` traz a porta real nos três casos;
  - `PORT` do processo e da raiz ignoradas; sem gateway, a `PORT` substitui a
    sequencial e a sequência pula as fixas;
  - `PORT` inválida e portas repetidas são erro;
  - projeto HTTP fora do gateway mantém a porta;
  - `boto run <serviço>` como hoje;
  - o anúncio novo;
  - o reload continua funcionando pelo gateway.
- **De ponta a ponta:** solution com dois webapis e um gateway; `boto run`;
  `curl` nos dois prefixos, no `/_boto` e no Swagger de um serviço.

## Alternativas descartadas

- **Proxy HTTP no dev (cada serviço na sua porta, gateway repassando):** mais
  latência, mais processos e portas, e nenhum ganho com tudo no mesmo
  processo.
- **Gateway no core:** o core é mínimo; quem não quer o gateway não carrega o
  código dele.
- **Roteamento próprio por prefixo:** o `Rack::URLMap` já resolve, testado e
  sem dependência nova.
- **Descobrir os serviços sem `refs` (todos os projetos HTTP):** as refs já
  dizem o que o gateway enxerga e seguem a regra de isolamento da solution.
- **Painel com SPA e JavaScript:** um HTML estático basta para listar
  serviços, e evita build de frontend na gem.
- **`boto run --expose` para dar porta a todos os serviços:** a `PORT` por
  projeto escolhe quais e qual porta, e já é a convenção de PaaS.
- **`X-Forwarded-Prefix` em vez de `SCRIPT_NAME`:** o header é coisa de proxy;
  dentro do processo, o `SCRIPT_NAME` é o contrato do Rack. Volta a ser
  discutido na proposta do gateway de produção.
