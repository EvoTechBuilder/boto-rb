# 0018 — `Boto::Repository`, plugin `:database` e migrations (gem `boto-rb-data`)

Status: **aprovada** (depende da 0019 e da 0020)

## Problema

- O Boto não tem camada de dados. Cada projeto escolhe um ORM, configura a
  conexão e escreve à mão o mesmo `find`, `create`, `update` e `delete` para
  cada tabela.
- As operations (`Boto::Operation`) já recebem dependências pelo
  `initialize`, mas falta o par natural delas: um repositório com o básico
  pronto, no estilo do Spring Data JPA.
- Não há migrations, então criar e alterar tabelas fica fora do fluxo do
  `boto`.

## API pública

### Entidade, repositório e uso

```ruby
# apps/catalogo/models/product.rb
Catalogo::Product = Data.define(:id, :name, :price, :tags, :created_at, :updated_at)
```

```ruby
# apps/catalogo/repositories/product_repository.rb
class Catalogo::ProductRepository < Boto::Repository
  entity Catalogo::Product
  table :products

  # Consulta própria: o bloco recebe o dataset do Sequel e devolve entidades.
  def self.cheapest(limit: 10) = query { _1.order(:price).limit(limit) }
end
```

```ruby
repo = Catalogo::ProductRepository

repo.find(1)                              # => Catalogo::Product ou nil
repo.find!(1)                             # => Catalogo::Product ou levanta Boto::Repository::NotFound
repo.all(order: :name, limit: 50, offset: 0)
repo.where(price: 10..50, order: :price)  # Hash de filtros: igualdade, Range, Array (IN), nil (IS NULL)
repo.find_by_name("Caneca")               # gerado no boot, um por campo; devolve o primeiro ou nil
repo.exists?(name: "Caneca")
repo.count(price: 0..10)
repo.create(name: "Caneca", price: 39.9)  # => entidade com id, created_at, updated_at
repo.update(1, price: 29.9)               # => entidade atualizada, ou nil se o id não existe
repo.delete(1)                            # => true ou false
repo.transaction { ... }                  # transação na conexão do projeto
repo.cheapest                             # a consulta própria
```

```ruby
# apps/catalogo/operations/create_product.rb
class Catalogo::CreateProduct < Boto::Operation
  def initialize(input, repository: Catalogo::ProductRepository)
    super(input)
    @repository = repository
  end

  def call
    return failure(:conflict, "a product named #{input.name} already exists") if @repository.exists?(name: input.name)

    @repository.create(name: input.name, price: input.price, tags: input.tags || [])
  end
end
```

- **Entidade:** um `Data` imutável, não um objeto ativo. Os schemas a
  serializam direto no `returns`.
- **Colunas e campos:** uma coluna que a entidade não declara é ignorada na
  leitura. Um campo da entidade que não existe na tabela faz o boot falhar,
  com o nome do campo.
- **`created_at` e `updated_at`:** preenchidos sozinhos quando a entidade os
  declara.
- **`find_by_<campo>`:** definido no boot, um por membro da entidade. Nada de
  `method_missing` por request.
- **`query { |dataset| ... }`:** a porta de saída para consultas que o
  básico não cobre. Devolve entidades e fica restrito ao repositório
  (`private_class_method`). Expor o Sequel inteiro para fora do repositório
  amarraria o resto do código a ele.
- **Erros do banco:**
  - violação de unicidade levanta `Boto::Repository::UniqueViolation`;
  - violação de chave estrangeira levanta
    `Boto::Repository::ForeignKeyViolation`;
  - a operation decide se isso vira `failure(:conflict)`.

### Conexão: plugin `:database`

Com a configuração por ambiente da proposta 0019:

```ruby
# apps/catalogo/config/app.rb
Boto.configure do |app|
  app.use :health
  app.use :database, url: -> { app.env.fetch("DATABASE_URL") }, pool: 10
end

# apps/catalogo/config/environments/development.rb
Boto.configure { |app| app.use :database, url: "sqlite://db/catalogo_development.sqlite3" }

# apps/catalogo/config/environments/test.rb
Boto.configure { |app| app.use :database, url: "sqlite://db/catalogo_test.sqlite3" }
```

- **Uma conexão por projeto:** os repositórios do projeto
  (`Catalogo::*Repository`) usam a do `config/app.rb` dele.
- **Ciclo de vida:**
  - `start`: conecta e confere as entidades contra as tabelas;
  - `stop`: desconecta;
  - `health_checks`: um `SELECT 1` que entra no `/health/ready`.
- **Fibers:** a conexão usa a extensão `fiber_concurrency` do Sequel, então
  cada request do Falcon pega a sua conexão do pool.
- **Drivers:** o projeto adiciona o driver no Gemfile (`pg`, `mysql2` ou
  `sqlite3`), como em qualquer app Sequel.
- **Repositório sem `:database` no projeto:** a primeira chamada levanta um
  erro com o nome do projeto e a linha que falta no `config/app.rb`.

### Migrations

```bash
boto generate migration catalogo create_products
boto db migrate [projeto]          # sem projeto: todos os que usam :database
boto db rollback catalogo [--steps N]
boto db status [projeto]
```

```ruby
# apps/catalogo/db/migrations/20261127120000_create_products.rb
Sequel.migration do
  change do
    create_table(:products) do
      primary_key :id
      String :name, null: false, unique: true
      Float :price, null: false
      column :tags, :json, default: Sequel.lit("'[]'")
      DateTime :created_at, null: false
      DateTime :updated_at, null: false
    end
  end
end
```

- **Formato:** o DSL de migrations do próprio Sequel, com timestamp no nome.
  Cada projeto tem as suas, em `db/migrations/`.
- **URL do banco:** os comandos `boto db` usam a URL do plugin `:database`,
  avaliando o `config/app.rb` no `BOTO_ENV` atual (`development` por
  padrão). Não há um segundo lugar para configurar o banco.
- **`boto test`:** roda `boto db migrate` no ambiente `test` antes, para cada
  projeto com `:database`.

### Gerador

```bash
boto g repository catalogo product          # repositories/product_repository.rb + teste
```

```ruby
class Catalogo::ProductRepository < Boto::Repository
  entity Catalogo::Product
  table :products
end
```

O teste gerado roda contra o banco de teste, migrado pelo `boto test`, dentro
de uma transação que é desfeita no fim.

## Estrutura

```
gems/boto-rb-data/                                   # gem nova, opcional
├── boto-rb-data.gemspec                             # depende de boto-rb e sequel
├── lib/boto/database.rb
├── lib/boto/repository.rb                           # Boto::Repository (API acima)
├── lib/boto/repository/{not_found,unique_violation,foreign_key_violation}.rb
├── lib/boto/database/entity_mapper.rb                   # linha <-> Data, conferência das colunas
├── lib/boto/database/connections.rb                     # conexão por namespace, definida no start
├── lib/boto/database/migrator.rb                        # migrate, rollback e status sobre o Sequel::Migrator
└── lib/boto/plugins/database.rb                     # app.use :database

gems/boto-rb/lib/boto/solution/project.rb            # CODE_DIRS único, com repositories/
gems/boto-rb/lib/boto/solution/project_loader.rb     # usa Project::CODE_DIRS
gems/boto-rb/lib/boto/solution/isolation.rb          # usa Project::CODE_DIRS (+ config, test)
gems/boto-rb-cli/lib/boto/cli/commands/run.rb        # watcher usa Project::CODE_DIRS
gems/boto-rb-cli/lib/boto/cli/support/project_folder.rb  # colisão usa Project::CODE_DIRS
gems/boto-rb-cli/lib/boto/cli/commands/db.rb         # boto db migrate | rollback | status
gems/boto-rb-cli/lib/boto/cli/commands/test.rb       # migra o banco de teste antes
gems/boto-rb-cli/templates/generate/{repository,migration}/
```

- **A lista de pastas de código hoje se repete em quatro lugares:**
  - o loader;
  - o isolamento;
  - o watcher do reload;
  - o gerador.

  Ela passa a ser uma constante só, `Boto::Project::CODE_DIRS`, e
  `repositories/` entra nela. Uma pasta nova de código nunca mais fica fora de
  algum deles.
- **`repositories/` usa o namespace do projeto, como as outras pastas:**
  `repositories/product_repository.rb` vira `Catalogo::ProductRepository`.
- **Comandos `boto db` no CLI:** o CLI só chama a `boto-rb-data` quando ela
  está no Gemfile. Sem a gem, o comando explica que falta
  `gem "boto-rb-data"`.

## Fase do roadmap

Fase 1. É a peça que faltava para APIs reais, e também é a base do template
`microservice` (Fase 2), que já nasceria com banco.

## Performance

- **Boot:**
  - conecta;
  - lê as colunas de cada tabela uma vez e confere as entidades;
  - define os `find_by_<campo>`;
  - pré-compila o mapeamento linha → entidade.
- **Por chamada:**
  - o custo do Sequel (dataset e consulta);
  - uma alocação da entidade por linha;
  - nenhuma reflexão por request: os campos são resolvidos no boot.
- **Benchmark:** o cenário `db` passa a ter uma variante `db_repository`, com
  o mesmo SQLite, para medir o custo do Repository em cima do Sequel puro.
  Alvo: menos de 10% de diferença em req/s.
- **Caminho quente do core:** nada muda. A gem é opcional, e o core só ganha
  uma pasta na lista.

## Segurança

- **SQL injection:**
  - toda a API básica (`where`, `find_by_*`, `create`, `update`) passa pelos
    parâmetros do Sequel, nunca por interpolação;
  - o `query { }` dá acesso ao dataset, que também parametriza, e o SQL cru
    (`Sequel.lit`) fica sob responsabilidade de quem escreve;
  - `where` só aceita chaves que são campos da entidade, e uma chave
    desconhecida é erro, para um filtro vindo do request não escolher coluna.
- **Mass assignment:** `create` e `update` só aceitam campos da entidade, sem
  `id`, `created_at` e `updated_at`, que o repositório controla. Uma chave
  desconhecida é erro.
- **Credenciais:**
  - a URL vem de lambda, lida uma vez no boot, como os outros segredos;
  - a senha da URL é mascarada nos logs e nas mensagens de erro.
- **Health:** o check do banco diz só ok ou fail, sem mensagem de erro na
  resposta (já é o comportamento do `:health`).

## Compatibilidade

- **Minor, aditiva:**
  - gem nova e pasta nova;
  - quem não usa `boto-rb-data` não vê diferença;
  - a constante única de pastas é refatoração interna.
- **CHANGELOG:**
  - Added: gem `boto-rb-data` (`Boto::Repository`, `app.use :database` e
    migrations), `boto db` e `boto g repository` e `migration`;
  - Added: a pasta `repositories/` é carregada.
- **CI:** a gem nova entra na matriz e na publicação. Os testes usam SQLite em
  memória e, quando houver `DATABASE_URL`, PostgreSQL, com um serviço no CI
  como o do Redis.
- **Antes do primeiro release:** é preciso cadastrar um pending trusted
  publisher da `boto-rb-data` no RubyGems, como foi feito com a
  `boto-rb-swaggerui`.

## Testes planejados

- **`Boto::Repository`:** em SQLite em memória, e também em PostgreSQL quando
  houver `DATABASE_URL`:
  - `find`, `find!`, `all` (ordem, limite e offset);
  - `where` com igualdade, Range, Array e nil;
  - `find_by_*`, `exists?`, `count`;
  - `create` com id e timestamps;
  - `update` (inclusive de um id inexistente) e `delete`;
  - `transaction`, inclusive o rollback numa exceção;
  - `query`.
- **Erros:**
  - unicidade e chave estrangeira viram os erros do Boto;
  - chave desconhecida em `where`, `create` e `update` é erro;
  - um campo da entidade sem coluna faz o boot falhar;
  - um repositório sem `:database` dá erro com a dica.
- **Plugin `:database`:**
  - `start` e `stop`;
  - o health check fica `ok`, e `fail` com o banco fora;
  - a URL não aparece em erros;
  - duas fibers simultâneas usam conexões diferentes.
- **Migrations:**
  - o gerador cria o arquivo;
  - `migrate`, `rollback --steps` e `status` por projeto e para todos;
  - sem a gem, a mensagem pede o `gem "boto-rb-data"`.
- **Core:** `Project::CODE_DIRS` é usado pelo loader, pelo isolamento, pelo
  watcher e pelo gerador, e `repositories/` é carregada, checada e
  recarregada.
- **De ponta a ponta:**
  1. `boto new`;
  2. `boto add`;
  3. migration;
  4. `boto db migrate`;
  5. repository e operation;
  6. endpoint e `boto run`, com create e get no SQLite;
  7. `boto test` com o banco de teste migrado.

## Alternativas descartadas

- **ActiveRecord:** pesado, com convenções do Rails, e o model é o próprio
  repositório. Não combina com entidades `Data` imutáveis nem com operations
  que recebem o repositório.
- **SQL próprio sobre os drivers:** muito código para manter, quando o Sequel
  já resolve parametrização, pool, dialetos e migrations.
- **Namespace interno `Boto::Data`:** esconderia o `Data` do Ruby para todo
  código dentro de `Boto` (o core usa `Data.define` em vários lugares, e
  plugins de terceiros também usariam), e só quando a gem estivesse
  instalada. O namespace da gem é `Boto::Database`. O nome da gem continua
  `boto-rb-data`.
- **Repository no core:** o core ganharia a dependência do Sequel e dos
  drivers, que nem toda API usa.
- **Derived queries completas como as do Spring
  (`find_by_name_and_price_greater_than`):** um parser de nomes de método é
  mágica demais. O `where(name:, price: 10..)` cobre o mesmo, com Hash
  explícito.
- **SQLite em memória (`sqlite::memory:`) como banco de teste do projeto:** o
  `boto test` migra antes e os testes rodam em outro processo, que veria um
  banco vazio. Fica o arquivo `db/<projeto>_test.sqlite3`, e cada teste roda
  numa transação desfeita no fim. A suíte da própria gem pode usar memória,
  porque migra e testa no mesmo processo.
- **Adaptador próprio em memória para os testes:** o SQLite em memória é um
  banco real e roda tão rápido quanto, sem uma segunda implementação para
  manter em sincronia.
- **URL do banco num arquivo separado (`config/database.yml`):** seria um
  segundo lugar de configuração. O plugin no `config/app.rb` segue o padrão
  dos outros plugins.
