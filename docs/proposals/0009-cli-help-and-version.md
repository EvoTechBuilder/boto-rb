# 0009 — Ajuda e versão no CLI

Status: **implementada**

## Problema

Testei o CLI instalado:

- **`boto`, `boto -h` e `boto help`:** mostram só `usage` e a lista de
  comandos.
  - Não aparecem a versão nem as opções globais.
  - Os comandos vêm em ordem alfabética e com colunas desalinhadas.
- **`boto -v` e `boto --version`:** respondem `unknown command "-v"`.
- **`boto help new`:** ignora o `new` e mostra a ajuda geral.
- **`--help` em cada comando:** cada um se comporta de um jeito.
  - `boto new -h` tenta criar uma solution chamada `-h`.
  - `boto add -h` responde com erro.
  - `boto check -h` roda a checagem.
  - Só `run` e `test` mostram a ajuda, e sem descrever as opções.
  - O `graph` não tem `USAGE`.
- **Comando errado** (`boto nwe`): não sugere o comando certo.

## API pública (saídas)

```
$ boto            # também: boto -h, boto --help, boto help
Boto 0.7.3 - Ruby framework for APIs and microservices organized as solutions

Usage: boto <command> [options]

Commands:
  new       Create a new solution
  add       Add a project to the solution
  ref       Add a reference between projects
  graph     Show the dependency graph of the solution
  check     Check that projects only use the projects they reference
  run       Run the solution's services in one process
  test      Run the tests of the solution's projects
  openapi   Print or write the OpenAPI document of a project

Options:
  -h, --help      Show this help
  -v, --version   Show the version

Run "boto help <command>" for the options of a command.
Docs: https://github.com/EvoTechBuilder/boto-rb
```

```
$ boto -v         # também: boto --version, boto version
boto 0.7.3 (ruby 4.0.10)
```

```
$ boto help run   # também: boto run -h, boto run --help
Usage: boto run [project] [--port N] [--host H]

Run the solution's services in one process

Options:
  --port N   First port; each service gets the next one (default 3000)
  --host H   Host to bind (default 127.0.0.1)
```

```
$ boto chek
boto: unknown command "chek". Did you mean "check"?
Run "boto --help" to see the commands.
```

- **Ordem dos comandos:** segue o fluxo de uso (criar, adicionar, ligar,
  checar, rodar, testar, documentar), não a ordem alfabética. Cada comando
  declara a sua posição.
- **Ajuda de comando:** `-h` ou `--help` em qualquer posição depois do comando
  mostra a ajuda daquele comando e sai com 0, sem executar nada. Isso evita
  efeitos como o `boto new -h` tentar criar uma solution.
- **Opções:** cada comando declara as suas, com descrição (`OPTIONS`). A mesma
  lista alimenta o `OptionParser` e a ajuda, para não divergirem.
- **Versão:** `boto -v` mostra a versão do Boto e a do Ruby, que são as duas
  informações pedidas num relato de bug.
- **Sugestão:** o "Did you mean" usa o `DidYouMean::SpellChecker`, que já vem
  com o Ruby. Ele não sugere para trocas de letras em nomes muito curtos
  (`nwe` não vira `new`), e isso foi aceito para não manter um corretor
  próprio.
- **Códigos de saída:** ajuda e versão saem com 0, e comando desconhecido sai
  com 1.

## Estrutura

```
gems/boto-rb-cli/lib/boto/cli/runner.rb      # versão, ajuda geral, help <command>, -h/--help, sugestão
gems/boto-rb-cli/lib/boto/cli/command.rb     # help padrão a partir de USAGE, SUMMARY e OPTIONS; ordem
gems/boto-rb-cli/lib/boto/cli/commands/*.rb  # USAGE em todos (graph), OPTIONS com descrições, ORDER
```

## Fase do roadmap

É polimento da Fase 0 (CLI básico) e vale já, porque as gems estão
publicadas. A versão sobe para `0.8.0` junto com o resto do Unreleased.

## Performance

Não há impacto no runtime das apps. O CLI só formata texto.

## Segurança

Não há impacto.

## Compatibilidade

- `boto -v` e `--version` deixam de ser erro. A ajuda muda de formato, e quem
  fazia parse dela (improvável) quebra.
- `-h` e `--help` depois de um comando passam a mostrar a ajuda, em vez de
  serem tratados como argumento.
- **CHANGELOG:**
  - `Added`: `-v`/`--version`/`version`, `help <command>`, `-h` em cada
    comando e a sugestão de comando;
  - `Changed`: o formato e a ordem da ajuda geral.

## Testes planejados

- `boto`, `-h`, `--help` e `help`: versão, os oito comandos na ordem certa e
  alinhados, as opções globais e a dica de `help <command>`; saída 0;
- `-v`, `--version` e `version` imprimem `boto X (ruby Y)`; saída 0;
- `help run` e `run --help` imprimem a mesma ajuda, com as opções descritas;
- `new -h` mostra a ajuda e não cria nada;
- `help nada` e `nwe` respondem "unknown command", com sugestão quando houver
  uma parecida; saída 1;
- todo comando tem `SUMMARY`, `USAGE` e posição na ordem (teste que percorre
  `Commands`).

## Alternativas descartadas

- **Thor:** dependência a mais por algo que o `OptionParser` e algumas linhas
  resolvem.
- **Manter a ordem alfabética:** esconde o fluxo de uso e deixa o `new` perdido
  no meio da lista.
- **Ajuda que só imprime o `USAGE`:** sem descrever as opções, o usuário ainda
  precisa ler o código.
