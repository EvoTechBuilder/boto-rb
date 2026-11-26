# Benchmarks do Boto

Compara o Boto com Roda e Sinatra em dois cenários: `hello` (`GET /` com JSON fixo) e `db` (`GET /users/:id` lendo um SQLite em memória via Sequel). Cada app roda num falcon próprio, com 50 conexões. Também mede alocações por request.

## Instalação

```sh
cd benchmarks
bundle install
```

Para medir outra cópia do repo (por exemplo a branch base, no CI), aponte `BOTO_ROOT` para a raiz dela antes do `bundle install`.

A carga usa `wrk` se estiver no PATH; senão usa `ab` (vem com o macOS e o Apache).

## Rodar

```sh
RUBY_YJIT_ENABLE=1 bundle exec ruby run.rb            # 3 rodadas por combinação
RUBY_YJIT_ENABLE=1 bundle exec ruby run.rb --quick    # 1 rodada, carga menor, para teste local
bundle exec ruby allocations.rb                       # só alocações por request
```

Os resultados saem em `results/latest.json`.

## Baseline e comparação

```sh
RUBY_YJIT_ENABLE=1 bundle exec ruby run.rb --save-baseline   # grava results/baseline.json
RUBY_YJIT_ENABLE=1 bundle exec ruby run.rb --compare         # compara o boto com o baseline
```

Regressão: req/s caiu mais de 5%, p99 subiu mais de 5%, ou alocações por request aumentaram. Nesse caso o script sai com código 1. Sem baseline, avisa e sai com 0. `--compare` e `--save-baseline` podem vir juntos: a comparação roda antes de gravar.

Compare sempre com o mesmo `RUBY_YJIT_ENABLE` com que gravou o baseline: o YJIT muda as alocações por request.

## Testes

```sh
bundle exec ruby -Itest -e 'Dir["test/**/*_test.rb"].sort.each { |f| require File.expand_path(f) }'
```

## Atenção

Números de máquinas diferentes não são comparáveis. Compare só resultados gerados na mesma máquina, com o mesmo Ruby e o mesmo YJIT.
