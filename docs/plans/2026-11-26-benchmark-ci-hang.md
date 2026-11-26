# Plano — Benchmark do CI parece travado

Status: **concluído** (2026-11-26)

## Diagnóstico

O passo "Save baseline from base branch" fica sem nenhuma saída por vários
minutos.

1. **Saída retida no buffer.** O `run.rb` só imprime a tabela no fim. Fora de
   um terminal, como no log do CI, o Ruby guarda o stdout num buffer
   (`$stdout.sync == false`, confirmado). O passo fica mudo do começo ao fim.
2. **O passo é longo de verdade.** Em modo completo são 3 rodadas por
   combinação, cada uma com aquecimento de 2s, medição de 10s e boot do
   Falcon. Na base são 6 combinações (cerca de 4 a 5 minutos); no código atual
   são 7. O job inteiro passa de 10 minutos sem nenhuma linha de log.
3. **Nada tem limite de tempo.** Não há timeout em:
   - parar o Falcon: um `Process.wait` depois do TERM;
   - `wrk` e `ab`;
   - as requisições de verificação;
   - o job do CI, que pode ficar até 6 horas, o padrão do GitHub.

   Se o Falcon ou a ferramenta de carga travarem, o passo nunca termina.
   Também não temos log do Falcon: a saída dele vai para `/dev/null`.

## Objetivo

O benchmark deve mostrar o progresso em tempo real e nunca ficar preso. Em
caso de falha, a mensagem precisa ser clara e mostrar o fim do log do Falcon.

## Tasks

B1 e B2 não têm arquivos em comum e rodam em paralelo, cada uma num
subagente `task-runner` (Haiku). A B3 eu faço.

### B1 — Limites de tempo e logs (`benchmarks/support/server.rb`, `support/load_test.rb` e os testes deles)

- **Parar o servidor:** depois do TERM no grupo de processos, espera até 10s
  com `Process.wait(pid, Process::WNOHANG)`. Se o processo não sair, manda
  KILL no grupo.
- **Ferramenta de carga:** `wrk` e `ab` rodam com limite de tempo (duração
  + 30s, ou 120s para o `ab`). Ao estourar, o processo é morto e entra um erro
  claro.
- **Requisições de verificação:** `open_timeout` e `read_timeout` de 5s.
- **Log do Falcon:** a saída vai para `results/logs/<framework>-<scenario>.log`
  (ignorado pelo git). Quando o servidor não sobe ou a verificação falha, o
  erro inclui as últimas 20 linhas do log.

### B2 — Progresso visível (`benchmarks/run.rb`, `support/runner.rb` e os testes)

- **Saída imediata:** `$stdout.sync = true` no `run.rb`.
- **Uma linha por rodada**, por exemplo
  `[3/21] boto db round 2/3 ... 18412 req/s, p99 26.0 ms`. A linha de início
  diz a ferramenta usada e quantas medições serão feitas.
- **Testes:** o runner recebe o `out` por injeção, para testar o progresso sem
  imprimir.

### B3 — CI (eu faço)

- **Limites:** `timeout-minutes: 30` no job `benchmark` e `timeout-minutes: 15`
  nos passos de baseline e de comparação.
- **Logs no artifact:** o upload passa a incluir os logs do Falcon da base e do
  código atual.

## Limitação conhecida

O próximo push ainda mede a base com os scripts antigos, que ficam mudos. Esse
passo continua sem saída até terminar, mas o `timeout-minutes` limita o tempo.
A partir do push seguinte, base e código atual mostram o progresso.

## Fechar

- Rodo os testes do benchmark e um `run.rb --quick` local, conferindo o
  progresso e a tabela.
- Faço os commits (`fix(benchmarks): ...` e `ci: ...`) e o push. Depois disso,
  confiro o próximo run do CI com você.
