# 0024 — Convenções no `boto generate endpoint`

Status: **aprovada**

## Problema

- O `boto g endpoint` pede tudo explícito: verbo, rota, tipo de cada param de
  caminho e os schemas.
- Na maior parte dos casos, o nome da ação (`products/show`) já diz o resto.
- A ajuda mostra só a linha de uso, sem exemplos.

## API pública

```bash
boto g endpoint catalogo products/index     # GET    /products          --returns [product]
boto g endpoint catalogo products/show      # GET    /products/:id      --returns product
boto g endpoint catalogo products/create    # POST   /products          --body product_input --returns product
boto g endpoint catalogo products/update    # PATCH  /products/:id      --body product_input --returns product
boto g endpoint catalogo products/destroy   # DELETE /products/:id
boto g endpoint catalogo products/search    # QUERY  /products/search   --body product_filter --returns [product]

boto g endpoint catalogo admin/products/show      # GET /admin/products/:id
boto g endpoint catalogo products/show id:uuid    # o tipo do :id muda; o resto segue a convenção
boto g endpoint catalogo products/update put /products/:id   # explícito, como hoje
boto g endpoint catalogo products/publish post /products/:id/publish  # ação fora da lista: verbo e rota obrigatórios
```

- **Verbo e rota pela ação:** a última parte do nome é a ação, e as anteriores
  formam a rota (`admin/products/show` -> `/admin/products/:id`).
  - Ações conhecidas: `index`, `show`, `create`, `update`, `destroy` e
    `search`, conforme a tabela acima.
  - Outra ação sem verbo e rota é erro, com a lista das conhecidas e um
    exemplo da forma explícita.
  - Se o primeiro argumento depois do nome é um verbo (`get`, `post`...), vale
    a forma explícita de hoje, sem nada deduzido além dos itens abaixo.
- **Tipo dos params de caminho:** `:id` e `:<algo>_id` viram `Integer`, os
  outros `String`. Um `param:type` no comando sempre vence.
  - Hoje o padrão é `String` para todos. A mudança vale também na forma
    explícita.
- **Schemas pela ação** (só nas ações conhecidas):

  | Ação | `--returns` | `--body` |
  |---|---|---|
  | `index` | `[<recurso>]` | |
  | `show` | `<recurso>` | |
  | `create`, `update` | `<recurso>` | `<recurso>_input` |
  | `search` | `[<recurso>]` | `<recurso>_filter` |
  | `destroy` | | |

  - `<recurso>` é o singular da pasta (`products` -> `product`,
    `categories` -> `category`, `pedidos` -> `pedido`).
  - Um schema deduzido só entra se `schemas/<nome>_schema.rb` existe no
    projeto. Se não existe, fica de fora sem erro, e a saída avisa
    (`skip --returns product (no schemas/product_schema.rb)`).
  - `--body` e `--returns` explícitos vencem. `--no-body` e `--no-returns`
    desligam a dedução.
- **Saída:** além dos `create`, uma linha com o que foi deduzido, para não
  haver mágica escondida:
  `endpoint PATCH /products/:id  body: product_input  returns: product`.
- **Ajuda:** `boto help generate` e o erro de uso mostram a tabela das ações
  e exemplos.

## Estrutura

```
gems/boto-rb-cli/lib/boto/cli/support/endpoint_convention.rb   # ação -> verbo, rota e schemas; singular do recurso
gems/boto-rb-cli/lib/boto/cli/support/blueprint_builder.rb     # usa a convenção quando não há verbo
gems/boto-rb-cli/lib/boto/cli/support/endpoint_blueprint.rb    # tipo padrão do param pelo nome
gems/boto-rb-cli/lib/boto/cli/commands/generate.rb             # --no-body, --no-returns, ajuda e a linha de resumo
```

## Fase do roadmap

Melhoria do CLI, junto do `boto generate` (0016). Não muda o runtime.

## Performance

Nada muda em runtime: é só o CLI escrevendo arquivos.

## Segurança

Nada novo: os caminhos continuam validados pelo `Generator`, e a rota
deduzida passa pela mesma validação da rota explícita.

## Compatibilidade

- **Minor.** A forma explícita continua funcionando.
- **Mudança de comportamento:** um `:id` ou `:<algo>_id` sem tipo passa a ser
  `Integer`, não `String`. Só afeta arquivos gerados daqui para frente.
- **CHANGELOG:** Added (convenções, `--no-body`, `--no-returns`, ajuda) e
  Changed (tipo padrão dos params `id`).

## Testes planejados

- **Convenção:** cada ação conhecida, pastas aninhadas, ação desconhecida,
  singular (`products`, `categories`, `pedidos`, `status`).
- **Tipos:** `:id`, `:product_id`, `:slug` e `id:uuid` explícito.
- **Schemas:** existentes entram, ausentes ficam de fora com aviso, explícitos
  vencem, `--no-body` e `--no-returns`.
- **Forma explícita:** os testes atuais passam; `put /products/:id` gera como
  hoje.
- **Saída e ajuda:** a linha de resumo e os exemplos.

## Alternativas descartadas

- **`update` como `PUT`:** `PATCH` é a atualização parcial, o caso comum de
  API; quem quer `PUT` passa o verbo.
- **Gerar os schemas que faltam:** criaria arquivos que o usuário não pediu.
  Fica para o `boto g resource`.
- **Biblioteca de inflexão (ActiveSupport):** dependência grande para um
  singular simples, que só serve para procurar um arquivo que pode não
  existir.
