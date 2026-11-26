# Plano — Isolamento entre projetos

Status: **aprovado, em execução**
Proposta: `docs/proposals/0006-project-isolation.md`

## Objetivo

Verificar estaticamente, com o Prism, que cada projeto só usa o namespace dos
projetos que referencia diretamente. A verificação roda no boot e no comando
novo `boto check`.

## Contratos

```ruby
Boto::Isolation::Scanner.scan(source, path:)
# => Scan(used: [Use(constant: "Billing::Invoice", root: "Billing", line: 14)], declared: Set["Orders", "Users", "Show"])

Boto::Isolation.check(solution, root:, projects: nil)   # nil = todos
# => [Violation(project: "orders", path: "services/orders/operations/checkout.rb", line: 14,
#              constant: "Billing::Invoice", missing_ref: "billing")], ordenado por project, path e line

Boto::IsolationError.new(violations)   # < StandardError; #violations; mensagem agrupada por projeto + "Fix: boto ref <p> <ref>"
```

### Regras do scanner

- **Usos:** o scanner registra `ConstantReadNode` e `ConstantPathNode`, sempre
  pelo caminho mais externo (`Billing::Invoice` gera um uso só, não dois). Um
  `::Billing` conta com raiz `Billing`.
- **Declarações:** o caminho de `class` e `module` é uma declaração, não um
  uso. Todos os segmentos entram em `declared`, e também os alvos de
  `Const = ...`.
- **Superclasses** e constantes dentro de corpos de método contam como uso.

### Regras da checagem

1. Lê o código de `endpoints/`, `operations/`, `models/`, `schemas/`,
   `config/` e `test/` do projeto.
2. Um uso é violação quando a raiz dele é o namespace de **outro** projeto que
   não está nas refs diretas, e esse nome também não foi declarado pelo
   próprio projeto.

## Tasks

Cada task roda num subagente `task-runner` (Haiku), e as marcadas com ∥ rodam
em paralelo.

- **I1 — Scanner, checagem e erro** (core):
  - `gems/boto/lib/boto/solution/isolation.rb`,
    `isolation/scanner.rb` e `isolation_error.rb`;
  - testes com fixtures pequenas de solution em `Dir.mktmpdir`.
- **I2 ∥ — Boot** (depende de I1), em `gems/boto/lib/boto/solution/boot.rb`:
  - `Boot.new(solution, root:, env: ENV, warn_output: $stderr)`;
  - o `load(name)` verifica o projeto e as refs transitivas dele antes de
    carregar, cada projeto uma única vez por instância do Boot;
  - `env["BOTO_SKIP_ISOLATION"] == "1"` pula a verificação e escreve um
    aviso, uma vez só.
- **I3 ∥ — `boto check [projeto]`** (depende de I1), em
  `gems/boto-cli/lib/boto/cli/commands/check.rb`:
  - mostra o relatório e sai com 1 se houver violação;
  - sem violação, mostra `No isolation violations in N projects` e sai com 0.

## Fechar (eu faço)

1. Rodo as suítes das quatro gems.
2. Faço o fluxo de ponta a ponta:
   - `new` e `add` de dois projetos;
   - um uso sem ref: `boto check` e `boto run` falham;
   - `boto ref` corrige, e os dois passam.
3. Subo a versão para `0.6.0`, atualizo o CHANGELOG e faço o push.
