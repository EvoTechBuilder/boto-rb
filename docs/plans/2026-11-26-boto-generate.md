# `boto generate` (proposta 0016)

Status: **concluído**

## Objetivo

Criar o `boto generate` (e o atalho `boto g`), que gera schema, endpoint,
operation e model no lugar certo do projeto, sempre com o teste. O teste pode
ser desligado por comando (`--skip-tests`) ou no Botofile.

## Fora de escopo

- `generate scaffold`, que geraria um CRUD inteiro.
- Model com ORM.
- Geradores para os templates `worker`, `web` e `spa`.

## Task 1: opção de testes no Botofile (core)

- **Arquivos:**
  - `gems/boto-rb/lib/boto/solution/botofile.rb`:
    - método `generators(tests:)` na DSL, que aceita só `true` ou `false` e
      pode ser chamado uma vez só;
    - `project(..., generators: {})`, um Hash que hoje só aceita a chave
      `tests:` (`true` ou `false`), com chave desconhecida virando erro;
  - `gems/boto-rb/lib/boto/solution/project.rb`: o `Data` ganha
    `generators`, com default `{}` congelado (`initialize` com keyword
    default);
  - `gems/boto-rb/lib/boto/solution/solution.rb`:
    - `Solution.new(..., generators: {})`;
    - `#generate_tests?(project_name)`: o `tests` do projeto se estiver
      definido, senão o da solution, senão `true`;
  - testes de `botofile`, `project` e `solution`.
- **Testes:**
  - o default é `true`;
  - `generators tests: false` desliga para todos;
  - um projeto com `generators: { tests: true }` volta a gerar;
  - chave desconhecida em `generators` é erro, com a linha;
  - valor não booleano é erro, com a linha;
  - `generators` declarado duas vezes é erro;
  - os Botofiles atuais continuam válidos.
- **Dependências:** nenhuma.
- **Comando:** `cd gems/boto-rb && bundle exec rake test`.

## Task 2: `FieldSpec` e `ConstantName` (CLI, puros)

- **Arquivos:**
  - `gems/boto-rb-cli/lib/boto/cli/support/field_spec.rb`:
    - `FieldSpec.parse("price:float", namespace: "Catalogo")` devolve um
      objeto com `name`, `type_source` (`"Float"`, `"[String]"`,
      `"Catalogo::CategorySchema"`, `"Boto::Boolean"`, `"Date"`, `"Time"`) e
      `required`;
    - o `?` no fim marca o campo como opcional;
    - nome ou tipo inválido levanta `Boto::CLI::Error`;
  - `gems/boto-rb-cli/lib/boto/cli/support/constant_name.rb`:
    - `ConstantName.new("products/show", namespace: "Catalogo")` oferece
      `#constant` (`"Catalogo::Products::Show"`), `#relative_path`
      (`"products/show"`) e `#segments`;
    - um nome fora de `\A[a-z][a-z0-9_]*(/[a-z][a-z0-9_]*)*\z` levanta
      `Boto::CLI::Error`, o que barra `..` e barra inicial;
  - testes dos dois.
- **Dependências:** nenhuma. Roda em paralelo com a Task 1.
- **Comando:** `cd gems/boto-rb-cli && bundle exec rake test`.

## Task 3: comando `generate`, com `schema` e `model`

- **Arquivos:**
  - `gems/boto-rb-cli/lib/boto/cli/commands/generate.rb`:
    - uso: `boto generate <schema|model|endpoint|operation> <projeto> <nome> [campos] [--skip-tests] [--force]`;
    - o atalho `g` fica registrado no runner;
    - lê a solution e resolve o projeto;
    - decide se gera o teste com `--skip-tests` e
      `solution.generate_tests?(projeto)`;
    - recusa arquivo existente sem `--force`;
    - imprime `create <caminho>` para cada arquivo;
  - templates em `gems/boto-rb-cli/templates/generate/schema/` e
    `.../model/` (arquivo e teste `.erb`, com `flunk` no teste);
  - testes do comando para `schema` e `model`, numa solution temporária.
- **Dependências:** Tasks 1 e 2.
- **Comando:** `cd gems/boto-rb-cli && bundle exec rake test`.

## Task 4: `endpoint` e `operation`

- **Arquivos:**
  - `generate.rb` ganha:
    - **`endpoint`:** verbo, rota, `--body`, `--returns` e campos de tipo
      para params do path, que por padrão são `String`;
    - **`operation`:** recusa uma colisão com uma constante que já existe nos
      arquivos do projeto, e recusa um nome com `/`;
    - os dois recusam projeto `library`;
  - templates em `templates/generate/endpoint/` e `.../operation/`:
    - o teste do endpoint usa `Rack::MockRequest` com o `APP`;
    - se o `config/app.rb` do projeto tiver `:auth`, o teste já manda o
      header `Bearer dev-token`;
  - testes do comando.
- **Dependências:** Task 3.
- **Comando:** `cd gems/boto-rb-cli && bundle exec rake test`.

## Fechamento (eu)

- A ajuda do CLI lista `generate`.
- CHANGELOG, README (referência do CLI e uma seção curta) e CLAUDE.md.
- Suítes com e sem YJIT.
- De ponta a ponta numa solution nova:
  1. gero cada tipo de arquivo;
  2. `boto check` passa;
  3. o `boto test` falha só pelos `flunk` dos testes gerados;
  4. o `boto run` sobe a rota gerada.
- Proposta e plano marcados como concluídos.
