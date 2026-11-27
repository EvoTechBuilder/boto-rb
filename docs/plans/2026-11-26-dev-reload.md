# Reload automático no `boto run` (proposta 0014)

Status: **concluído**

## Objetivo

Em development, o `boto run` recarrega a solution no primeiro request depois
de uma mudança nos arquivos dos projetos, sem reiniciar o processo.

## Fora de escopo

- Reload em produção.
- Gem `listen` e threads de polling.
- Reabrir portas quando o Botofile muda de projetos: nesse caso, só o aviso.
- Reload do `boto test`.

## Task 1: `FileWatcher`

- **Objetivo:** detectar arquivos criados, alterados ou removidos, comparando
  snapshots `{caminho => mtime}`.
- **Arquivos:**
  - `gems/boto-rb-cli/lib/boto/cli/support/file_watcher.rb`:
    - `Boto::CLI::FileWatcher.new(patterns, glob: Dir.method(:glob), mtime: File.method(:mtime))`,
      em que `patterns` é uma lista de globs absolutos;
    - o snapshot é tirado no `initialize`;
    - `#changed?` devolve `true` uma vez por mudança, atualizando o
      snapshot, e `false` sem mudança;
    - `#changes` devolve quantos arquivos mudaram na última checagem;
    - um arquivo apagado entre o glob e o `mtime` (`Errno::ENOENT`) conta como
      removido;
  - `gems/boto-rb-cli/test/boto/cli/support/file_watcher_test.rb`.
- **Testes:** com glob e mtime falsos, cobrir:
  - sem mudança;
  - arquivo alterado, novo ou removido, cada um só uma vez;
  - `ENOENT` entre o glob e o mtime;
  - a contagem de `changes`.
- **Dependências:** nenhuma.
- **Comando:** `cd gems/boto-rb-cli && bundle exec rake test`.

## Task 2: `Reloader` e `ReloadingApp`

- **Objetivo:**
  - reconstruir a solution quando o watcher acusar mudança;
  - trocar os apps por porta;
  - responder com o erro quando o reload falhar.
- **Arquivos:**
  - `gems/boto-rb-cli/lib/boto/cli/support/reloader.rb`:
    - `Reloader.new(root:, ports:, env_name:, out:, err:, load_solution:, watcher:, manifest_watchers:, clock:)`:
      - `ports` é `{nome => porta}`;
      - `load_solution` é um callable que relê o Botofile;
      - `watcher` cuida do código;
      - `manifest_watchers` é `{ "Botofile" => w, "Gemfile" => w }`;
    - o boot inicial monta um `Boto::Boot` e chama `boot.app(nome, env_name:)`
      para cada porta;
    - `#app_for(port)` devolve um `ReloadingApp`;
    - `#current(port)`: se o watcher mudou e não está drenando, reconstrói
      sob um `Mutex`:
      1. `boot.shutdown`;
      2. relê o Botofile;
      3. monta um `Boot` novo;
      4. monta os apps;
      5. imprime `Reloaded in N ms (K files changed)` no `out`;
    - **falha no reload:**
      - guarda o erro e imprime no `err`;
      - enquanto houver erro, `current` devolve um app que responde `500`
        `application/problem+json`, com `title "Reload failed"` e
        `detail "<Classe>: <mensagem>"`;
      - a próxima mudança tenta de novo;
    - **Botofile:**
      - se os projetos servidos ou os templates mudaram, imprime
        `Botofile changed: restart boto run` uma vez e não recarrega;
      - mudança só de `refs:` recarrega;
    - **Gemfile e Gemfile.lock:** imprime `Gemfile changed: restart boto run`
      uma vez;
    - `#drain!` marca drenando e repassa `drain!` aos apps atuais;
    - `#shutdown` chama o `boot.shutdown` atual;
  - `gems/boto-rb-cli/lib/boto/cli/support/reloading_app.rb`:
    - `call(env)` delega a `reloader.current(port).call(env)`;
    - `drain!` delega a `reloader.drain!`;
  - testes em `gems/boto-rb-cli/test/boto/cli/support/reloader_test.rb` e
    `reloading_app_test.rb`, usando uma solution de fixture copiada para um
    `Dir.mktmpdir`.
- **Testes:** a seção "Testes planejados" da 0014 para `Reloader` e
  `ReloadingApp`. A mudança de endpoint reescreve o arquivo na pasta
  temporária, e o watcher falso devolve `true`.
- **Dependências:** a interface do watcher (`changed?`, `changes`) da Task 1.
  Os testes usam um watcher falso, então roda em paralelo com a Task 1.
- **Comando:** `cd gems/boto-rb-cli && bundle exec rake test`.

## Task 3: `boto run` com reload

- **Objetivo:** ligar o reload no comando.
- **Arquivos:**
  - `gems/boto-rb-cli/lib/boto/cli/commands/run.rb`:
    - opção `--no-reload`;
    - com o env `development` e sem `--no-reload`:
      - monta o `Reloader`, com os watchers apontando para `endpoints`,
        `schemas`, `operations`, `models` e `config` de cada projeto da
        solution, além do `Botofile`, `Gemfile` e `Gemfile.lock`;
      - passa ao server os `ReloadingApp`;
      - anuncia `Boto running (Ctrl-C to stop, reload on)`;
      - no `ensure`, chama `reloader.shutdown`;
    - caso contrário, mantém o fluxo atual;
  - `gems/boto-rb-cli/test/boto/cli/commands/run_test.rb`.
- **Testes:**
  - em development, o server recebe `ReloadingApp`;
  - com `--no-reload`, ou com `env: {"BOTO_ENV" => "production"}`, recebe os
    apps direto;
  - a ajuda lista `--no-reload`;
  - integração: a solution numa pasta temporária, troca do corpo de um
    endpoint e o request seguinte devolve o novo;
  - os testes atuais continuam passando. Os que hoje assumem apps diretos
    passam `--no-reload`, ou o env de produção, quando precisarem.
- **Dependências:** Tasks 1 e 2.
- **Comando:** `cd gems/boto-rb-cli && bundle exec rake test`.

## Fechamento (eu)

- CHANGELOG (Added) e README (seção "Rodando a solution").
- Suítes com e sem YJIT.
- Teste manual de ponta a ponta:
  1. `boto run` numa solution nova;
  2. edito um endpoint e confiro o `curl` seguinte;
  3. introduzo um erro de sintaxe e confiro o 500 com a mensagem;
  4. corrijo e confiro que volta ao normal.
- Proposta e plano marcados como concluídos.
