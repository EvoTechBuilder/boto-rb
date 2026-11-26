# 0006 — Isolamento entre projetos

Status: **aprovada**

## Problema

O CLAUDE.md define o isolamento como o diferencial do Boto: um projeto só
enxerga o código dos projetos que referencia, e acesso sem referência é erro.
Hoje nada disso é verificado.

Em dev, todos os projetos rodam no mesmo processo. Por isso, se `orders` usa
`Billing::Invoice` sem `refs: %w[billing]`, o código funciona: `Billing` já
foi carregado por outro projeto. Em produção, `orders` roda sozinho, só com
os projetos que referencia, e quebra com `NameError` na primeira request que
passar por ali.

A proposta 0001 sugeriu uma checagem estática com Prism para a Fase 1, e ela
ficou de fora.

## API pública

Não há DSL nova. O que muda é o comportamento.

### No boot (`boto run`, `boto test` e `BOOT.app`/`BOOT.load` dos testes)

```
Boto::IsolationError: project "orders" uses projects it does not reference:
  services/orders/operations/checkout.rb:14  Billing::Invoice  (billing is not in refs)
  services/orders/endpoints/receipts/show.rb:8  Billing  (billing is not in refs)
Fix: boto ref orders billing
```

- **Antes de carregar o código**, o `Boto::Boot` verifica o projeto pedido e
  cada referência transitiva dele.
- **Qualquer violação impede o boot**, com o arquivo, a linha, a constante e
  o comando que corrige.

### `boto check`

```
boto check            # verifica todos os projetos da solution; sai com 1 se houver violação
boto check orders     # só um projeto
```

É o mesmo relatório, para rodar no CI e no pre-commit.

## O que conta como violação

Um projeto **só pode usar o namespace dos projetos que ele referencia
diretamente** no Botofile, além do próprio namespace.

- **Referências transitivas não contam.** Se `orders -> billing -> domain`,
  `orders` não pode usar `Domain::` sem declarar `domain` também.
- **A violação** é uma constante cuja raiz (o primeiro segmento) é o
  namespace de **outro projeto da solution** que não está nas refs diretas.
  Exemplos: `Billing`, `Billing::Invoice`, `::Billing::Invoice`.
- **Não é violação:**
  - constantes do próprio projeto;
  - constantes de gems e do Ruby (`Boto::`, `JSON`, `Sequel`...), porque
    não são namespaces de projetos;
  - uma constante aninhada que o próprio projeto declara com o mesmo nome,
    por exemplo um `Orders::Billing` definido dentro de `orders`. Para isso,
    o checador junta os nomes de `class` e `module` declarados no projeto e
    ignora esses casos.
- **O que é lido:** os arquivos de `endpoints/`, `operations/`, `models/`,
  `schemas/` e `config/app.rb` de cada projeto. Os testes (`test/`) também,
  porque rodam isolados e quebrariam do mesmo jeito.

## Estrutura

```
gems/boto/lib/boto/solution/isolation.rb          # Boto::Isolation.check(solution, root:, projects:) -> [Violation]
gems/boto/lib/boto/solution/isolation/scanner.rb  # Prism: coleta constantes usadas e declaradas de um arquivo
gems/boto/lib/boto/solution/isolation_error.rb    # Boto::IsolationError, mensagem com a lista e o "Fix:"
gems/boto/lib/boto/solution/boot.rb               # chama a checagem antes de carregar
gems/boto-cli/lib/boto/cli/commands/check.rb      # boto check [project]
gems/boto-cli/templates/...                       # nada muda
```

- **Prism** é da stdlib desde o Ruby 3.3, então não entra nenhuma
  dependência nova.

## Fase do roadmap

Fecha a Fase 1, que era onde a proposta 0001 colocava essa checagem. A versão
sobe para `0.6.0`.

## Performance

- **Só no boot**, nunca por request. O Prism faz o parse de um arquivo comum
  em menos de 1 ms. Uma solution com algumas centenas de arquivos acrescenta
  algumas dezenas de milissegundos ao boot.
- **Cache por processo:** um mesmo projeto não é verificado duas vezes no
  mesmo processo. O `boto run` com vários serviços verifica cada um uma vez
  só.

## Segurança

Não há impacto direto. A checagem só lê código do próprio repositório, e o
Prism não executa nada.

## Compatibilidade

- **Quebra builds com violação.** Um projeto que hoje usa outro sem declarar
  passa a falhar no boot. Essa é a intenção: corrigir isso agora evita a
  falha em produção.
- **Saída de emergência:** a variável `BOTO_SKIP_ISOLATION=1` desliga a
  checagem do boot, com um aviso no log. O `boto check` continua acusando a
  violação. Isso existe para migrar código antigo.
- **CHANGELOG:**
  - `Added`: o `boto check` e a checagem no boot;
  - `Changed`: violação de isolamento passa a impedir o boot.

## Testes planejados

- **Scanner:**
  - constante simples;
  - constante com caminho (`A::B::C`) e com `::` na raiz;
  - constante dentro de `class`/`module` aninhado;
  - herança (`< Billing::Base`);
  - nomes declarados no próprio arquivo.
- **Isolation:**
  - uso de projeto referenciado é permitido;
  - uso de projeto não referenciado é violação, com arquivo e linha;
  - uso transitivo sem referência direta é violação;
  - gems e Ruby são ignorados;
  - constante aninhada própria com o mesmo nome de outro projeto não é
    violação;
  - os testes do projeto são lidos.
- **Boot:**
  - violação gera `IsolationError` com a mensagem e o `Fix:`;
  - sem violação, o boot segue como hoje;
  - `BOTO_SKIP_ISOLATION=1` pula a checagem e avisa.
- **CLI:** `boto check` sai com 0 sem violações, sai com 1 e mostra o
  relatório quando há violação, e aceita filtrar por projeto.
- **Ponta a ponta:**
  - `boto new` e `add` de dois projetos;
  - código usando o outro projeto sem ref: `boto run` falha com a mensagem;
  - `boto ref` corrige, e o boot volta a subir.

## Limitações conhecidas

- **Acesso dinâmico:** `Object.const_get("Billing")`, `constantize` e
  similares não são detectados. A checagem é estática.
- **Duas gems com o mesmo namespace de um projeto:** se uma gem define
  `Billing` e existe um projeto `billing`, os usos contam como do projeto. É
  um caso raro, e o nome do projeto pode ser trocado.

## Alternativas descartadas

- **Isolar em runtime**, carregando só os projetos referenciados no
  processo: o modo dev roda tudo junto de propósito (monólito modular), e um
  processo por projeto em dev perderia isso.
- **Permitir referências transitivas**: é mais permissivo, mas o código
  passaria a depender da estrutura interna de outro projeto. Uma ref
  transitiva removida quebraria quem nem sabia que dependia dela.
- **Checar só no `boto check` (CI)**: o erro apareceria tarde, depois do
  commit, enquanto o boot mostra o problema na hora.
- **Regex no lugar de Prism**: erraria em strings, comentários e heredocs.
  O Prism entende a sintaxe de verdade.
