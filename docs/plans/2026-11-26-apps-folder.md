# Projetos HTTP em `apps/` e pastas sob demanda (proposta 0011)

Status: **concluído**

## Objetivo

`webapi` e `microservice` passam a viver em `apps/`, e o `boto new` deixa de
criar pastas de projeto vazias. Uma solution antiga, com projetos em
`services/`, falha com uma mensagem que mostra como corrigir.

## Fora de escopo

- Migrar pastas automaticamente.
- Templates `web`, `spa` e `worker`, que ainda não existem. Só a regra da
  pasta já fica valendo para eles.

## Task A1: core (boto-rb)

- **Arquivos:**
  - `gems/boto-rb/lib/boto/solution/project.rb`: em `TEMPLATE_DIRS`,
    `webapi` e `microservice` passam para `"apps"`, e a constante
    `LEGACY_HTTP_DIR = "services"` registra o caminho antigo;
  - `gems/boto-rb/lib/boto/solution/layout.rb` (novo):
    - `Boto::Layout.check!(solution, root:)` lança `Boto::LegacyLayoutError`
      quando algum projeto `webapi` ou `microservice` tem
      `services/<nome>` e não tem `apps/<nome>`;
    - a mensagem segue o formato da proposta e traz uma linha
      `Fix: git mv ...` por projeto;
  - `gems/boto-rb/lib/boto/solution/legacy_layout_error.rb` (novo);
  - `gems/boto-rb/lib/boto/solution/boot.rb`: `load` chama
    `Layout.check!` antes da checagem de isolamento;
  - fixtures: `git mv` de `gems/boto-rb/test/fixtures/*/services` para
    `apps`;
  - testes do core que citam `services/`.
- **Testes:**
  - `Project#path` para cada template;
  - `Layout.check!` passa sem legado, falha com legado (uma linha `Fix` por
    projeto) e passa quando as duas pastas existem;
  - o Boot falha com o erro;
  - as suítes existentes passam com as fixtures movidas.
- **Dependências:** nenhuma.

## Task A2: CLI (boto-rb-cli)

- **Arquivos:**
  - `gems/boto-rb-cli/templates/solution/`: remover `apps/`, `libs/`,
    `services/` e `workers/`, com os `.keep` deles;
  - `gems/boto-rb-cli/lib/boto/cli/command.rb`: o `solution` chama
    `Boto::Layout.check!` depois de carregar o Botofile;
  - `gems/boto-rb-cli/lib/boto/cli/runner.rb`: trata
    `Boto::LegacyLayoutError` como erro de uso, imprimindo `boto: ...` e
    saindo com 1, sem backtrace;
  - testes do CLI que citam `services/`.
- **Testes:**
  - o `boto new` não cria as quatro pastas;
  - `boto add webapi api` cria `apps/api`, e `boto add library dominio` cria
    `libs/dominio`;
  - `boto check` numa solution com legado sai com 1 e mostra o `Fix`;
  - o teste de integração do `run` continua passando.
- **Dependências:** A1.

## Execução

A1 roda primeiro, depois A2, cada uma num subagente Haiku e com o seu commit.
No fechamento:

- atualizo a seção "Estrutura de pastas" do `CLAUDE.md` e o CHANGELOG, com a
  migração;
- rodo as quatro suítes com e sem YJIT;
- confiro de ponta a ponta numa solution nova.
