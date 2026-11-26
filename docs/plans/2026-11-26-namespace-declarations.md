# Declarações fora do namespace do projeto

Status: **concluído**

## Objetivo

A checagem de isolamento passa a acusar `class`, `module` e constantes
declarados no topo de um arquivo fora do namespace do projeto. Exemplo: um
`class Tokens` ou um `TOKENS = ...` em `config/app.rb`. Em dev, todos os
projetos rodam no mesmo processo, e essas constantes vão para o `Object`, onde
um projeto reabre a constante do outro sem erro.

## Regra

- **Acusa:** uma declaração no nível de topo do arquivo (fora de qualquer
  `class` ou `module`) cuja raiz não é o namespace do projeto: `class Tokens`,
  `module Helpers`, `TOKENS = 1` e `::TOKENS = 1`.
- **Não acusa:**
  - `class Orders::X`, `module Orders` e `Orders::LIMIT = 1`;
  - declarações aninhadas, porque já estão sob o namespace de quem as contém;
  - arquivos de `test/`. O `boto test` roda cada projeto num processo
    separado, e os templates geram testes com nome prefixado
    (`OrdersHealthTest`).
- **Onde aparece:** no mesmo relatório (`boto check` e boot), num bloco
  separado por projeto, com a dica de mover a declaração para dentro do
  namespace. As mensagens das violações de ref não mudam.

## Fora de escopo

- Detectar monkey patch feito por `define_method` ou `const_set`.
- Mudar os templates.

## Task 1: scanner, checagem e mensagem

- **Arquivos:**
  - `gems/boto/lib/boto/solution/isolation/scanner.rb`;
  - `gems/boto/lib/boto/solution/isolation.rb`;
  - `gems/boto/lib/boto/solution/isolation_error.rb`;
  - os testes espelhados em `gems/boto/test/boto/solution/`.
- **Testes:**
  - o scanner lista as declarações de topo (class, module, constante, `::X`)
    e ignora as aninhadas;
  - a checagem acusa uma declaração de topo fora do namespace em `config/` e
    em `operations/`;
  - a checagem ignora `test/` e o próprio namespace;
  - a mensagem mostra o bloco novo e mantém o bloco de refs igual.
- **Comando:** `cd gems/boto && bundle exec rake test`, com e sem
  `RUBY_YJIT_ENABLE=1`.
