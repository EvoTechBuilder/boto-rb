# Configuração por ambiente e `.env` (propostas 0019 e 0020)

Status: **concluído**

## Objetivo

- `config/environments/<env>.rb` sobrescreve o `config/app.rb`, com mescla de
  opções e `app.remove`.
- Os arquivos `.env` são lidos sozinhos, com a precedência da 0020:
  - os da solution vão para o `ENV`;
  - os do projeto ficam no `app.env`;
  - o `app.env` também está disponível no endpoint, na operation e em
    `Catalogo.app`.

A proposta 0018 (`boto-rb-data`) ganha um plano próprio depois desta.

## Fora de escopo

- O plugin `:database` e o resto da 0018.
- Migração automática do `.gitignore` e dos `config/app.rb` de solutions já
  existentes.

## Task 1: `Boto::Env`, parser e lista de arquivos (core, puro)

- **Arquivos:**
  - `gems/boto-rb/lib/boto/env/parser.rb`:
    - `Parser.parse(text, path:)` devolve um Hash;
    - aceita o subconjunto da 0020;
    - erro com `arquivo:linha` e sem o valor na mensagem;
  - `gems/boto-rb/lib/boto/env/files.rb`:
    - `Files.for(dir, env_name:)` lista os arquivos na ordem de precedência;
    - deixa o `.env.local` de fora no `test`;
  - `gems/boto-rb/lib/boto/env.rb`:
    - `Boto::Env.new(layers)` é só de leitura, com `fetch`, `[]` e `key?`;
    - as camadas são Hashes em ordem: processo, projeto e solution;
    - o `fetch` sem a chave levanta `KeyError` com o nome;
    - o objeto é congelado;
  - testes de cada um.
- **Dependências:** nenhuma.
- **Comando:** `cd gems/boto-rb && bundle exec rake test`.

## Task 2: `Configuration` com declarações adiadas (core)

- **Arquivos:**
  - `gems/boto-rb/lib/boto/configuration.rb`:
    - o `use` guarda a declaração em vez de criar o plugin;
    - `phase` (`:app` ou `:environment`) controla a mescla entre arquivos e
      recusa a repetição no mesmo arquivo;
    - `remove`;
    - os plugins são criados no fim, uma vez, com as opções finais, mantendo
      a ordem fixa;
    - `Configuration.load(paths, env_name:, env:)` avalia vários arquivos;
    - o `env` vira `app.env`;
  - `gems/boto-rb/test/boto/configuration_test.rb`.
- **Testes:** os de `Configuration` da 0019, incluindo o caso em que a lambda
  do geral não roda quando o ambiente a substitui.
- **Dependências:** nenhuma. Roda em paralelo com a Task 1.
- **Comando:** `cd gems/boto-rb && bundle exec rake test`.

## Task 3: `Boot`, `.env` e `Catalogo.app` (core)

- **Arquivos:**
  - `gems/boto-rb/lib/boto/solution/boot.rb`:
    - valida o `BOTO_ENV`;
    - carrega os `.env` da solution no `ENV`, sem sobrescrever o que existe;
    - monta o `Boto::Env` de cada projeto;
    - avalia o `config/app.rb` e, depois, o `config/environments/<env>.rb`;
    - define o `Catalogo.app`;
  - `gems/boto-rb/lib/boto/project_context.rb`: `env`, `env_name` e `name`,
    congelado;
  - `gems/boto-rb/lib/boto/endpoint/endpoint.rb` e
    `gems/boto-rb/lib/boto/operation.rb`: `#app`, resolvido uma vez por
    classe;
  - testes do `Boot`, do endpoint e da operation, com fixtures em pasta
    temporária.
- **Testes:**
  - os de `Boot` e de `app` fora do config, da 0019 e da 0020;
  - dois projetos com `DATABASE_URL` diferentes no mesmo processo;
  - o processo vence os arquivos;
  - o `ENV` real só recebe os arquivos da solution.
- **Dependências:** Tasks 1 e 2.
- **Comando:** `cd gems/boto-rb && bundle exec rake test`.

## Task 4: templates, `.gitignore` e reload (CLI)

- **Arquivos:**
  - `gems/boto-rb-cli/templates/solution/.gitignore`: as linhas `.env*` da
    0020, com a exceção do `!.env.example`;
  - `gems/boto-rb-cli/templates/webapi/config/app.rb.erb`: sem `if`, usando
    `app.env.fetch`;
  - `gems/boto-rb-cli/templates/webapi/config/environments/{development,test,production}.rb.erb`;
  - `gems/boto-rb-cli/templates/webapi/test/test_helper.rb.erb`: sem o
    `ENV["API_TOKENS"] ||=`;
  - `gems/boto-rb-cli/lib/boto/cli/commands/run.rb`:
    - os `.env*` dos projetos entram no watcher de código;
    - os da solution entram nos `manifest_watchers`, com aviso de reiniciar;
  - testes do CLI.
- **Testes:**
  - `boto new` gera o `.gitignore`;
  - `boto add webapi` gera os três ambientes;
  - o projeto gerado sobe em development e em test sem variáveis;
  - em production, sem `API_TOKENS`, o boot falha com a chave;
  - o reload reage a um `.env` de projeto, e um `.env` da solution só avisa.
- **Dependências:** Task 3.
- **Comando:** `cd gems/boto-rb-cli && bundle exec rake test`.

## Fechamento (eu)

- CHANGELOG, com as linhas de `.gitignore` para solutions existentes; README
  (configuração por ambiente e `.env`); CLAUDE.md.
- Suítes com e sem YJIT, e a medição de alocações.
- De ponta a ponta:
  - `boto new` e `boto add`;
  - `.env` da solution e `.env.development` de dois projetos com o mesmo
    `DATABASE_URL`;
  - `boto run` com um endpoint devolvendo `app.env.fetch` de cada projeto;
  - `BOTO_ENV=production` sem as variáveis falha com a chave.
- Propostas 0019 e 0020 e o plano marcados como concluídos.
