# Ajuda e versão no CLI (proposta 0009)

Status: **concluído**

## Objetivo

Implementar as saídas da proposta 0009: ajuda geral, versão, ajuda por
comando, opções descritas e sugestão de comando.

## Fora de escopo

- Novos comandos (`templates`), cores no terminal e autocomplete do shell.

## Task C1: metadados e ajuda de cada comando

- **Arquivos:**
  - `gems/boto-rb-cli/lib/boto/cli/command.rb`:
    - `Command.help` monta o texto da ajuda a partir de `USAGE`, `SUMMARY`
      e `OPTIONS`;
    - `Command.position` lê a constante `POSITION`, que define a ordem na
      lista;
    - `Command.options` devolve `OPTIONS`, que por padrão é vazio.
  - `gems/boto-rb-cli/lib/boto/cli/commands/*.rb`:
    - todo comando tem `SUMMARY`, `USAGE` (o `graph` ganha um) e
      `POSITION`;
    - `run`, `test` e `openapi` declaram `OPTIONS` com flag, argumento e
      descrição;
    - o `OptionParser` desses três passa a ser montado a partir da mesma
      lista, para a ajuda e o parser não divergirem;
    - o `USAGE` passa a começar com `Usage:`;
    - os erros de uso seguem mostrando a linha de uso.
  - Testes em `gems/boto-rb-cli/test/boto/cli/command_test.rb` e nos testes
    dos comandos.
- **Testes:**
  - todo comando em `Commands` tem `SUMMARY`, `USAGE` e `POSITION`, sem
    posições repetidas;
  - o `help` de `run` lista `--port` e `--host` com descrição;
  - as opções continuam funcionando como antes.
- **Dependências:** nenhuma.

## Task C2: Runner

- **Arquivos:**
  - `gems/boto-rb-cli/lib/boto/cli/runner.rb`:
    - ajuda geral no formato da proposta: cabeçalho com a versão, comandos
      por `POSITION` com colunas alinhadas, opções globais, dica e link;
    - `-v`, `--version` e `version` imprimem `boto X (ruby Y)`;
    - `help <command>`;
    - `-h` ou `--help` em qualquer posição depois do comando mostram a ajuda
      do comando, sem executá-lo;
    - um comando desconhecido recebe sugestão com
      `DidYouMean::SpellChecker`;
    - ajuda e versão saem com 0, e comando desconhecido sai com 1.
  - `gems/boto-rb-cli/test/boto/cli/runner_test.rb`.
- **Testes:** os da proposta 0009.
- **Dependências:** C1.

## Execução

As duas tasks rodam em sequência, cada uma num subagente Haiku e com o seu
commit. No fechamento:

- rodo as suítes;
- atualizo o CHANGELOG;
- marco a proposta 0009 como implementada.

Não há impacto no runtime das apps.

## Resultado

- C1: `704637b`. C2: commit `feat(cli): show version, full help and per-command help`.
- A sugestão usa o `DidYouMean::SpellChecker`, que não sugere `new` para `nwe` (troca de letras em nome curto). A proposta foi ajustada.
- Um teste do Runner (erro de isolamento sem backtrace) estava depois de `private` e nunca rodava; agora roda.
