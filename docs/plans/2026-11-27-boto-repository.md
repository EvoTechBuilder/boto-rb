# `Boto::Repository`, `:database` e migrations (proposta 0018)

Status: **concluído**

## Objetivo

Entregar a gem `boto-rb-data`:
- `Boto::Repository`, com o básico pronto sobre o Sequel;
- o plugin `:database`, com uma conexão por projeto, compatível com fibers e
  ligada ao `/health/ready`;
- migrations por projeto, com `boto db` e os geradores;
- a pasta `repositories/`, reconhecida por todo o Boto.

## Fora de escopo

- Derived queries compostas (`find_by_name_and_price_greater_than`).
- Repositórios em projetos `library`, que não têm `config/` nem conexão
  própria.
- Seeds e `boto db reset`.

## Task 1: pastas de código numa constante só (core e CLI)

- **Arquivos:**
  - `gems/boto-rb/lib/boto/solution/project.rb`:
    `CODE_DIRS = %w[endpoints operations models repositories schemas].freeze`;
  - `gems/boto-rb/lib/boto/solution/project_loader.rb`: usa
    `Project::CODE_DIRS`;
  - `gems/boto-rb/lib/boto/solution/isolation.rb`: usa
    `Project::CODE_DIRS + %w[config test]`;
  - `gems/boto-rb-cli/lib/boto/cli/commands/run.rb`: o glob do watcher é
    montado a partir de `Project::CODE_DIRS` e `config`;
  - `gems/boto-rb-cli/lib/boto/cli/support/project_folder.rb`: usa
    `Project::CODE_DIRS`;
  - testes.
- **Testes:**
  - `repositories/x_repository.rb` carrega como `Catalogo::XRepository`;
  - o isolamento vê violações nesse arquivo;
  - o reload reage a ele;
  - o `boto generate` recusa uma colisão com ele.
- **Dependências:** nenhuma.
- **Comando:** as suítes do `boto-rb` e do `boto-rb-cli`.

## Task 2: gem `boto-rb-data`, conexão e plugin `:database`

- **Arquivos:**
  - `gems/boto-rb-data/`:
    - gemspec (depende de `boto-rb` na mesma versão e de `sequel ~> 5`;
      `sqlite3` como dependência de desenvolvimento), `LICENSE` e
      `Rakefile`;
    - `lib/boto/database.rb` (Zeitwerk `for_gem_extension`) e
      `lib/boto/database/version.rb`;
  - `lib/boto/database/connections.rb`:
    - conexão por namespace, definida no `start` e removida no `stop`;
    - `Connections.for(namespace)` levanta um erro com o projeto e a linha
      que falta no `config/app.rb`;
  - `lib/boto/plugins/database.rb`:
    - opções `url:` (String ou lambda) e `pool:` (Integer positivo,
      padrão 5);
    - `attach` guarda o namespace do app;
    - `start` conecta com a extensão `fiber_concurrency` e registra a
      conexão;
    - `stop` desconecta;
    - `health_checks` tem `database`, que roda um `SELECT 1`;
    - a senha da URL nunca aparece em mensagem nem em `inspect`;
  - na raiz:
    - `Gemfile` ganha a gemspec;
    - `Rakefile` ganha a pasta em `GEM_DIRS`;
    - `bundle lock`;
  - testes com SQLite em memória.
- **Testes:**
  - opções inválidas falham no boot;
  - `start` e `stop`;
  - o health check fica `ok`, e `fail` com uma URL inalcançável;
  - a URL não aparece em erros;
  - duas fibers simultâneas usam conexões diferentes;
  - a conexão é por namespace;
  - um projeto sem `:database` recebe a mensagem de ajuda.
- **Dependências:** nenhuma. Roda em paralelo com a Task 1.
- **Comando:** `cd gems/boto-rb-data && bundle exec rake test`.

## Task 3: `Boto::Repository`, leitura

- **Arquivos:**
  - `lib/boto/repository.rb`:
    - `entity` e `table`;
    - `find`, `find!`, `all(order:, limit:, offset:)`;
    - `where(filtros, order:, limit:)`, com igualdade, Range, Array e nil;
    - `find_by_<campo>`, definidos quando o `entity` é declarado;
    - `exists?` e `count`;
    - `query { |dataset| }`, privado;
  - `lib/boto/database/entity_mapper.rb`:
    - converte a linha em entidade, ignorando colunas extras;
    - na primeira conexão, confere se os campos da entidade existem como
      colunas;
  - `lib/boto/repository/not_found.rb`;
  - no `start` do plugin `:database`, os repositórios do namespace
    (`Boto::Repository.subclasses` filtrados pelo namespace) são conferidos
    contra as tabelas, e um campo sem coluna faz o boot falhar.
- **Testes:**
  - cada método;
  - chave desconhecida em `where` é erro;
  - a conferência no boot;
  - `query` devolve entidades e é privado;
  - SQL injection: um valor com aspas em `where` e em `find_by_name` não
    quebra a consulta.
- **Dependências:** Task 2.
- **Comando:** `cd gems/boto-rb-data && bundle exec rake test`.

## Task 4: `Boto::Repository`, escrita e transação

- **Arquivos:**
  - `lib/boto/repository.rb`:
    - `create`, que devolve a entidade com id e timestamps;
    - `update(id, attrs)`, que devolve a entidade ou nil;
    - `delete(id)`, que devolve true ou false;
    - `transaction { }`;
    - `created_at` e `updated_at` preenchidos quando a entidade os declara;
    - recusa `id`, timestamps e chaves desconhecidas;
  - `lib/boto/repository/{unique_violation,foreign_key_violation}.rb`:
    mapeiam os erros do Sequel.
- **Testes:**
  - cada método;
  - o rollback da transação numa exceção;
  - os erros de unicidade e de chave estrangeira;
  - a recusa de mass assignment.
- **Dependências:** Task 3.
- **Comando:** `cd gems/boto-rb-data && bundle exec rake test`.

## Task 5: migrations (`boto-rb-data`)

- **Arquivos:**
  - `lib/boto/database/migrator.rb`: `migrate`, `rollback(steps:)` e `status`
    sobre o `Sequel::TimestampMigrator`, na pasta `db/migrations` do projeto;
  - `gems/boto-rb/lib/boto/solution/boot.rb`: novo
    `Boot#configuration(name, env_name:)` público, que monta a
    `Configuration` (com os `.env` e os arquivos de ambiente) sem iniciar o
    app. Assim o `boto db` lê a URL do `:database` sem a conferência das
    tabelas, que ainda não existem antes da primeira migration.
- **Testes:**
  - migrate, rollback e status num SQLite temporário;
  - o `Boot#configuration` não inicia plugins.
- **Dependências:** Task 2.
- **Comando:** as suítes do `boto-rb-data` e do `boto-rb`.

## Task 6: CLI (`boto db`, geradores e `boto test`)

- **Arquivos:**
  - `gems/boto-rb-cli/lib/boto/cli/commands/db.rb`:
    - `boto db migrate [projeto]`, `rollback <projeto> [--steps N]` e
      `status [projeto]`;
    - sem projeto, roda em todos os que declaram `:database`;
    - sem a gem `boto-rb-data`, a mensagem pede `gem "boto-rb-data"`;
  - `boto generate migration` e `boto generate repository`: templates e
    `Blueprint`;
  - `boto test` roda `boto db migrate` com `BOTO_ENV=test` antes, nos
    projetos com `:database`;
  - testes.
- **Testes:**
  - os subcomandos;
  - os geradores, com nome de migration com timestamp;
  - a mensagem sem a gem;
  - o `boto test` migra antes.
- **Dependências:** Tasks 4 e 5.
- **Comando:** `cd gems/boto-rb-cli && bundle exec rake test`.

## Fechamento (eu)

- **CI:**
  - a gem nova entra na publicação;
  - um serviço PostgreSQL entra no job de testes, com `DATABASE_URL` para a
    suíte da `boto-rb-data` rodar também em Postgres.
- **Benchmark:**
  - cenário `db_repository` (o `db` com `Boto::Repository`);
  - comparação com o `db`, com alvo de menos de 10% de diferença em req/s;
  - a medição de alocações.
- **Documentação:** CHANGELOG, README (seção de dados) e CLAUDE.md
  (estrutura, `repositories/` e `boto db`).
- **Testes:** suítes com e sem YJIT.
- **De ponta a ponta:**
  1. `boto new` e `boto add`;
  2. `boto g migration` e `boto db migrate`;
  3. `boto g repository`, operation e endpoint;
  4. `boto run` com create e get no SQLite;
  5. `boto test` com o banco de teste migrado.
- **Antes do release:** você cadastra o pending trusted publisher da
  `boto-rb-data` no RubyGems.
