# Templates como gems e `boto plugin new` (propostas 0021 e 0022)

Status: **concluído**

## Objetivo

- Templates de projeto declarados por `Boto::Template.define`, descobertos nas
  gems do bundle, com os oficiais no mesmo mecanismo.
- O comando `boto plugin new`, que gera uma gem de extensão (plugin, template
  ou os dois).

## Fora de escopo

- A `boto-rb-gateway` (proposta 0023), que será gerada com o `boto plugin new`
  depois.
- Os templates `microservice`, `worker`, `web` e `spa`, que continuam
  reservados e sem arquivos.

## Task 1: registro de templates (core)

- **Arquivos:**
  - `gems/boto-rb/lib/boto/template.rb`:
    - `Boto::Template`, um `Data` com `name`, `folder`, `http`, `files`,
      `summary`, `source` (a gem ou `boto-rb`) e `legacy_services`;
    - `Template.define(name) { |t| ... }`, que valida a pasta
      (`apps`/`libs`/`workers`), a presença do `folder` e as opções;
  - `gems/boto-rb/lib/boto/templates.rb`:
    - o registro, com `fetch(name)` (`KeyError` com a lista e a dica da gem),
      `key?`, `all` e `http?(name)`;
    - descobre os oficiais e depois `Gem.find_files("boto/templates/*/template.rb")`,
      uma vez por processo, e congela;
    - definição duplicada e nome oficial redefinido por outra fonte são
      erros;
  - `gems/boto-rb/lib/boto/templates/{library,webapi,microservice,worker,web,spa}/template.rb`:
    as declarações oficiais. `webapi` e `microservice` têm `http true` e
    `legacy_services true`;
  - `gems/boto-rb/lib/boto/solution/project.rb`:
    - `path` e `legacy_path` usam o registro;
    - saem `TEMPLATE_DIRS` e `HTTP_TEMPLATES`;
  - `gems/boto-rb/lib/boto/solution/botofile.rb`: valida pelo registro, com a
    mensagem nova;
  - testes do registro (com uma gem falsa no `$LOAD_PATH`), do `Project` e do
    `Botofile`.
- **Dependências:** nenhuma.
- **Comando:** as suítes do `boto-rb` e do `boto-rb-cli`, que não pode
  quebrar.

## Task 2: CLI usa o registro, mais `boto add --refs`

- **Arquivos:**
  - `support/generator.rb`: aceita um diretório de origem. Para os oficiais
    sem `files`, usa `templates/<nome>` do CLI;
  - `commands/add.rb`:
    - os templates vêm do registro, e só os que têm arquivos podem ser
      gerados;
    - `--refs a,b` escreve e valida as refs no Botofile;
    - as variáveis do `.erb` incluem `refs` e `template`;
  - `commands/run.rb`, `commands/openapi.rb` e
    `support/blueprint_builder.rb`: usam `Boto::Templates.http?` no lugar das
    listas fixas;
  - testes.
- **Dependências:** Task 1.
- **Comando:** `cd gems/boto-rb-cli && bundle exec rake test`.

## Task 3: `boto templates list | install`

- **Arquivos:**
  - `commands/templates.rb`:
    - `list` mostra o nome, a pasta, `http` e a origem;
    - `install <gem>` acrescenta `gem "<gem>"` ao Gemfile da solution,
      recusando nome inválido e gem já presente, e imprime o próximo passo
      (`bundle install`);
  - testes.
- **Dependências:** Task 1. Roda em paralelo com a Task 2.
- **Comando:** `cd gems/boto-rb-cli && bundle exec rake test`.

## Task 4: `boto plugin new`

- **Arquivos:**
  - `commands/plugin.rb` e `support/extension_name.rb`;
  - `templates/plugin/{base,plugin,template}/`;
  - testes:
    - unidade de `ExtensionName`;
    - geração;
    - integração: gera numa pasta temporária, roda `bundle exec rake test` da
      gem gerada apontando para o `boto-rb` local, e numa solution o
      `app.use`, o `boto templates list` e o `boto add` com o template gerado.
- **Dependências:** Tasks 1, 2 e 3.
- **Comando:** `cd gems/boto-rb-cli && bundle exec rake test`.

## Fechamento (eu)

- CHANGELOG, README (templates e plugins de terceiros) e CLAUDE.md
  (`boto templates` e `boto plugin new`).
- Suítes com e sem YJIT.
- De ponta a ponta:
  1. `boto plugin new boto-demo --plugin demo --template demo`;
  2. uma solution com `gem "boto-demo", path: ...` no Gemfile;
  3. `boto templates list`;
  4. `boto add demo x`;
  5. `app.use :demo` e `boto run`.
