# Plano — Reduzir alocações por request

Status: **concluído** (2026-11-26). Resultado: `db` de 88 para 76 alocações por request, `hello` de 12 para 9, sem regressão de req/s nem de p99.

## Objetivo

Hoje o Boto aloca 88 objetos por request no cenário `db`, contra 80 do Roda.
O objetivo é cortar as alocações evitáveis do roteador e dos params, sem
mudar nenhuma API pública e sem piorar req/s nem p99.

## Diagnóstico

Rastreei um request de `GET /users/500` com
`ObjectSpace.trace_object_allocations`, com YJIT e depois do aquecimento.

- **Comum aos dois frameworks:** Sequel, SQLite e internos do Ruby somam
  cerca de 55 objetos.
- **Do Boto:** são 23 objetos. Os evitáveis estão nestes pontos:

| Onde | Hoje | Depois |
|---|---|---|
| `Router#segments_of`: `split` + `reject` | 2 arrays e 3 strings (uma vazia) | 1 array e 2 strings |
| `Router#params_for`: `zip(...).to_h` | 3 arrays e 1 Hash | 1 Hash |
| `Router#match`: `Match.new(target:, params:)` | Hash de keywords e o Match | só o Match |
| `Rack::Utils.unescape_path` sem `%` | 1 string por segmento dinâmico | 0 |
| `Params#call`: `errors = []` e pares do `to_h` | 1 array e 1 array por param, além do Hash | só o Hash |

A economia esperada é de 9 a 10 objetos por request, o que deixaria o Boto
abaixo do Roda. Isso é uma estimativa e será confirmado com medição.

## Fora de escopo

- Qualquer mudança de API pública ou de comportamento.
- Otimizar a resposta (tripla, headers e body) e a instância do endpoint. O
  Roda tem os mesmos custos aí.
- Alocações internas em C do JSON e do SQLite.

## Tasks

T1 e T2 não têm arquivos em comum e rodam em paralelo, num subagente
`task-runner` (Haiku) cada.

### T0 — Baseline (eu faço, antes das tasks)

Em `benchmarks/`:

- `bundle exec ruby allocations.rb`, com e sem `RUBY_YJIT_ENABLE=1`;
- `RUBY_YJIT_ENABLE=1 bundle exec ruby run.rb --quick --save-baseline`.

### T1 — Roteador sem alocações intermediárias

- **Arquivos:** `gems/boto/lib/boto/router.rb` e
  `gems/boto/test/boto/router_test.rb`.
- **`segments_of`:** percorre o path com `byteindex` e `byteslice`, ignora
  segmentos vazios e devolve um único array, sem `split` nem `reject`.
- **Valores dinâmicos:** só passam por `Rack::Utils.unescape_path` quando o
  segmento contém `%`.
- **`params_for`:** monta o Hash direto, com `each_with_index`, sem `zip`
  nem `to_h`.
- **`Match.new`:** recebe os argumentos posicionais.
- **Testes:**
  - todos os testes atuais continuam passando;
  - novos casos para paths com `//`, `/` final e `%20`;
  - teste de alocação: depois de aquecer, `match("GET", "/users/42")`
    aloca no máximo 6 objetos (array de segmentos, 2 strings, array de
    valores, Hash de params e o Match). A contagem é medida com
    `GC.stat(:total_allocated_objects)`.
- **Comando:** `cd gems/boto && bundle exec ruby -w -Ilib -Itest test/boto/router_test.rb`,
  com e sem YJIT.

### T2 — Params sem alocações no caminho feliz

- **Arquivos:** `gems/boto/lib/boto/params.rb` e
  `gems/boto/test/boto/params_test.rb`.
- **`#call`:** monta o Hash de resultado com `each`. O array de erros só é
  criado quando o primeiro erro aparece.
- **Erros:** o "is required" passa a lançar `ArgumentError`, tratado no
  mesmo `rescue` das coerções. Exceção só acontece no caminho de erro.
- **Testes:**
  - todos os testes atuais continuam passando: mesmos erros, agregação e
    precedência;
  - teste de alocação: depois de aquecer, `call` com um param `Integer`
    vindo do path aloca no máximo 1 objeto (o Hash).
- **Comando:** `cd gems/boto && bundle exec ruby -w -Ilib -Itest test/boto/params_test.rb`,
  com e sem YJIT.

### T3 — Medir depois e fechar (eu faço)

1. Rodo a suíte inteira, com e sem YJIT.
2. Rodo `allocations.rb` de novo e
   `RUBY_YJIT_ENABLE=1 bundle exec ruby run.rb --quick --compare`.
3. Monto a tabela antes e depois. Se req/s ou p99 piorarem, eu reporto
   antes de commitar.
4. Faço um commit por task (`perf(boto): ...`) e uma entrada no CHANGELOG
   em `Changed`.
