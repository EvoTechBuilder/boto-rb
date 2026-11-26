---
name: benchmark
description: Use ao mexer no caminho quente do core do Boto (roteador, dispatch de endpoint, params, schemas, middlewares) ou ao comparar o Boto com Roda e Sinatra. Mede antes e depois e reporta a diferença.
---

# Benchmark

Os cenários ficam em `benchmarks/`: hello world e um cenário com banco. Cada
cenário tem um app equivalente em Boto, Roda e Sinatra.

## Regras de medição

- O mesmo servidor (Falcon), a mesma versão do Ruby e YJIT ligado para os
  três frameworks.
- Aquecimento antes de medir e pelo menos 3 rodadas por cenário. Reporte a
  mediana.
- Métricas: req/s, latência p99 e objetos alocados por request
  (diferença de `GC.stat(:total_allocated_objects)` em N requests divididos por
  N).
- Nada pesado rodando na máquina ao mesmo tempo.

## Passos

1. Antes de mudar o código, rode os cenários afetados e guarde os números
   (baseline).
2. Faça a mudança.
3. Rode os mesmos cenários de novo.
4. Mostre uma tabela com cenário, métrica, antes, depois e variação em %.
5. Use o limite de regressão definido em `benchmarks/`. Se ele ainda não
   existir, trate como regressão qualquer piora acima de 5% em req/s ou p99,
   ou qualquer alocação a mais por request. Nesse caso, reporte e pergunte
   antes de seguir.
