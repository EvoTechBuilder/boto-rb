# 0019 — Configuração por ambiente: `config/environments/<env>.rb`

Status: **implementada**

## Problema

- Hoje o `config/app.rb` é o único arquivo de configuração de um projeto. O
  que muda por ambiente vira `if` dentro dele, como no template `webapi`:
  ```ruby
  default_tokens = app.env_name == "development" ? "dev-token" : ""
  app.use :auth, strategy: :bearer, tokens: -> { ENV.fetch("API_TOKENS", default_tokens).split(",") }
  ```
- O `test_helper.rb` gerado precisa de um ajuste à parte
  (`ENV["API_TOKENS"] ||= "test-token"`) só para o projeto subir nos testes.
- Com o banco (proposta 0018), a URL também passa a mudar por ambiente:
  SQLite no dev e no test, PostgreSQL em produção. Os `if` só aumentariam.
- Não dá para declarar o mesmo plugin duas vezes, porque um segundo `app.use`
  é erro. Então não existe forma de um arquivo ajustar só uma opção.

## API pública

### Estrutura

```
apps/catalogo/config/
├── app.rb                     # geral: vale para todos os ambientes
└── environments/
    ├── development.rb         # só no BOTO_ENV=development
    ├── test.rb                # só no BOTO_ENV=test
    └── production.rb          # só no BOTO_ENV=production
```

### Exemplo

```ruby
# config/app.rb (geral)
Boto.configure do |app|
  app.use :health
  app.use :cors, origins: app.env.fetch("CORS_ORIGINS").split(",")
  app.use :auth, strategy: :bearer, tokens: -> { app.env.fetch("API_TOKENS").split(",") }
  app.use :rate_limit, limit: 300, period: 60
  app.use :database, url: -> { app.env.fetch("DATABASE_URL") }, pool: 10
end
```

```ruby
# config/environments/development.rb
Boto.configure do |app|
  app.use :cors, origins: %w[http://localhost:5173]
  app.use :auth, tokens: %w[dev-token]                        # só troca tokens; strategy continua :bearer
  app.use :database, url: "sqlite://db/catalogo_development.sqlite3"
  app.use :openapi, title: "Catálogo (dev)", auth: false      # plugin só do dev
  app.use :swagger_ui
end
```

```ruby
# config/environments/test.rb
Boto.configure do |app|
  app.use :auth, tokens: %w[test-token]
  app.use :database, url: "sqlite://db/catalogo_test.sqlite3"
  app.remove :rate_limit                                      # sem rate limit nos testes
end
```

```ruby
# config/environments/production.rb
Boto.configure do |app|
  app.use :hosts, allow: -> { app.env.fetch("ALLOWED_HOSTS").split(",") }
end
```

### Regras

- **Ordem:** o `config/app.rb` é avaliado primeiro, e depois o
  `config/environments/<BOTO_ENV>.rb`, se existir. Um ambiente sem arquivo
  usa só o geral.
- **`app.use` de um plugin já declarado mescla as opções:** o arquivo do
  ambiente só passa o que muda, e as outras opções ficam como no geral. Um
  plugin novo é adicionado.
- **O `app.use` repetido no mesmo arquivo continua sendo erro:** quase sempre
  é engano.
- **`app.remove :nome`:** tira um plugin declarado no geral. Remover um plugin
  que não foi declarado é erro.
- **Os plugins são criados só no fim, com as opções finais.** A lambda
  `-> { app.env.fetch("DATABASE_URL") }` do geral não roda em development quando o
  `development.rb` troca a `url:`, então o dev não precisa de variável que só
  produção tem.
- **Opções inválidas** continuam falhando no boot, agora depois da mescla,
  com a mensagem do plugin. Um arquivo de ambiente com erro de Ruby mostra o
  caminho dele.
- **`app.env_name`** continua disponível nos arquivos.
- **Nome do ambiente:** `BOTO_ENV`, que deve casar com
  `\A[a-z][a-z0-9_]*\z`. Um nome fora disso faz o boot falhar, para que um
  `BOTO_ENV=../x` não aponte para fora de `config/environments/`. Ambientes
  próprios (`staging.rb`) funcionam.

### Templates

- **`boto add webapi`:** gera os três arquivos de ambiente e remove o `if` do
  `app.rb`:
  - o dev usa `dev-token`;
  - o test usa `test-token`;
  - o `ENV["API_TOKENS"] ||=` sai do `test_helper.rb`;
  - production fica só com o comentário de exemplo.
- **`boto test`:** roda com `BOTO_ENV=test`, que já é o comportamento de hoje.

## Estrutura

```
gems/boto-rb/lib/boto/configuration.rb      # declarações adiadas, mescla, remove, build no fim
gems/boto-rb/lib/boto/solution/boot.rb      # avalia app.rb e environments/<env>.rb
gems/boto-rb-cli/templates/webapi/config/   # app.rb sem if + environments/{development,test,production}.rb
gems/boto-rb-cli/templates/webapi/test/test_helper.rb.erb   # sem o ENV["API_TOKENS"] ||=
```

- **`Configuration`:**
  - o `use` guarda a declaração (`nome`, classe e opções) em vez de criar o
    plugin;
  - um `phase` marca qual arquivo está sendo avaliado, para mesclar entre
    arquivos e recusar a repetição dentro do mesmo arquivo;
  - os plugins são criados uma vez, no fim do carregamento;
  - o resultado continua imutável.
- **`Boot#app` e o `boto run` com reload:** já leem o `config/` inteiro, e o
  watcher já cobre `config/**/*.rb`. Mudar um arquivo de ambiente recarrega a
  solution.

## Fase do roadmap

Fase 1, e é pré-requisito da 0018 (`:database`), cuja URL passa a ficar no
arquivo de cada ambiente.

## Performance

- **Boot:** um arquivo a mais por projeto, e a mescla de alguns Hashes.
- **Por request:** nada muda, porque os plugins continuam sendo criados uma
  vez.

## Segurança

- **Segredos de produção:** ficam em lambdas no `app.rb` ou no
  `production.rb`, e só rodam no ambiente que as usa. O dev não precisa delas
  e não as lê.
- **Caminho do arquivo:** o `BOTO_ENV` é validado antes de virar caminho de
  arquivo.
- **Sem configuração escondida:** o ambiente nunca liga sozinho um plugin que
  o arquivo não declara. O que está ligado está escrito no `app.rb` ou no
  arquivo do ambiente.

## Compatibilidade

- **Minor, aditiva:** um projeto sem `config/environments/` funciona como
  hoje.
- **Mudança de comportamento:** o mesmo plugin em `app.rb` e no arquivo de
  ambiente passa a mesclar. Antes isso nem existia, porque só havia um
  arquivo.
- **Projetos já gerados:** continuam com o `if` no `app.rb`, que segue
  funcionando. A migração é opcional e entra no CHANGELOG.
- **CHANGELOG:**
  - Added: `config/environments/<env>.rb`, a mescla de opções e o
    `app.remove`;
  - Changed: o template `webapi` passa a usar os arquivos de ambiente.

## Testes planejados

- **`Configuration`:**
  - a ordem é geral, depois o ambiente;
  - um `use` repetido entre arquivos mescla as opções;
  - um `use` repetido no mesmo arquivo é erro;
  - um plugin novo no ambiente é adicionado;
  - `remove` tira o plugin;
  - `remove` de um plugin que não existe é erro;
  - os plugins são criados uma vez, com as opções finais, e a lambda do geral
    não roda quando o ambiente a substitui;
  - opção inválida depois da mescla dá erro no boot;
  - a ordem fixa dos plugins é mantida.
- **`Boot`:**
  - o `environments/<env>.rb` só é lido no ambiente dele;
  - um ambiente sem arquivo funciona;
  - um `BOTO_ENV` inválido é recusado.
- **Template `webapi`:**
  - gera os três arquivos;
  - o projeto gerado sobe em development e em test sem variáveis de ambiente;
  - em production, sem `API_TOKENS`, o boot falha com a mensagem do
    `ENV.fetch`.
- **Reload:** mudar o `development.rb` recarrega a solution.

## Alternativas descartadas

- **`config/environments/*.yml`:** YAML não comporta lambdas para segredos e
  seria uma segunda linguagem de configuração.
- **`app.environment(:development) { ... }` dentro do próprio `app.rb`:** um
  arquivo só, mas que cresce com o número de ambientes. Arquivos separados
  deixam claro o que vale onde.
- **Recriar o plugin inteiro no arquivo do ambiente:** obrigaria a repetir
  todas as opções do geral (o `strategy: :bearer` do exemplo), e uma mudança
  no geral poderia ser esquecida no ambiente.
- **Cada ambiente herdar de outro (`production` herda de `staging`):** cadeia
  difícil de seguir. O geral mais um arquivo por ambiente basta.
