# 0014 — Reload automático no `boto run` em development

Status: **implementada**

## Problema

- Hoje o `boto run` carrega a solution uma vez. Qualquer mudança num
  endpoint, schema, operation, model ou `config/app.rb` exige parar o
  servidor (Ctrl-C) e rodar `boto run` de novo.
- No dia a dia, esse ciclo de editar, reiniciar e repetir o request é o que
  mais atrasa o desenvolvimento.

## API pública

### Uso

Nada a configurar. Em development (o padrão do `boto run`), o reload já vem
ligado:

```bash
boto run
# Boto running (Ctrl-C to stop, reload on)
#   pedidos  http://127.0.0.1:3000
#
# (você salva apps/pedidos/endpoints/users/show.rb e faz um request)
# Reloaded in 38 ms (1 file changed)
```

```bash
boto run --no-reload                 # desliga em development
BOTO_ENV=production boto run         # fora de development, sempre desligado
```

### Comportamento

- **O que dispara o reload:**
  - arquivos `.rb` em `endpoints/`, `schemas/`, `operations/`, `models/` e
    `config/` de qualquer projeto da solution;
  - arquivo criado, alterado ou removido;
  - pastas de teste não disparam nada.
- **Quando:** a checagem acontece no request, como no Rails. O primeiro
  request depois de salvar já vê o código novo, e não há thread nem processo
  extra rodando em segundo plano.
- **O que é refeito:**
  - a solution inteira, porque um projeto library pode ser usado por vários
    serviços;
  - os loaders do Zeitwerk são descarregados, e a checagem de isolamento
    roda de novo, então uma referência nova sem `refs` aparece na hora;
  - o `config/app.rb` é avaliado de novo;
  - os plugins são parados e iniciados;
  - as rotas são compiladas de novo.
- **Requests em andamento:** terminam no app antigo. Os requests novos
  esperam o reload acabar e vão para o app novo.
- **Se o reload falha** (erro de sintaxe, isolamento, opção de plugin
  inválida):
  - o request responde `500` em `application/problem+json`, com a classe e
    a mensagem do erro em `detail`;
  - o erro aparece no terminal;
  - o servidor continua de pé, e o próximo request depois de corrigir o
    arquivo tenta de novo.
- **O que não recarrega:**
  - mudança no `Botofile` que adiciona, remove ou troca o template de um
    projeto, porque as portas já estão abertas;
  - `Gemfile` e `Gemfile.lock`, porque as gems já estão carregadas.

  Nesses casos o terminal avisa `Botofile changed: restart boto run` (ou
  `Gemfile changed`) uma vez. Mudanças só de `refs:` no Botofile recarregam
  normalmente.

## Estrutura

```
gems/boto-rb-cli/lib/boto/cli/support/file_watcher.rb   # snapshot (caminho => mtime) e changed?
gems/boto-rb-cli/lib/boto/cli/support/reloader.rb       # reconstrói a solution e troca os apps
gems/boto-rb-cli/lib/boto/cli/support/reloading_app.rb  # Rack app de uma porta que delega ao app atual
gems/boto-rb-cli/lib/boto/cli/commands/run.rb           # --no-reload; liga o Reloader em development
```

- **`FileWatcher`:**
  - recebe a lista de diretórios e arquivos e tira um snapshot
    `{caminho => mtime}`;
  - `#changed?` compara com o snapshot anterior, detectando arquivo novo,
    removido ou alterado;
  - o glob e o `File.mtime` entram por argumento, para os testes rodarem sem
    disco.
- **`Reloader`:**
  - guarda o `Boto::Boot` atual e o mapa `porta => app`;
  - `#current(port)` checa o watcher e, se mudou algo, reconstrói tudo sob um
    `Mutex`, que respeita o fiber scheduler: `boot.shutdown`, um `Boot` novo
    a partir do Botofile relido e `boot.app(...)` para cada porta;
  - se a reconstrução falha, guarda o erro e responde com ele até a próxima
    mudança.
- **`ReloadingApp`:**
  - é o objeto que o `Server` recebe por porta;
  - `call(env)` pede o app atual ao `Reloader` e delega;
  - `drain!` repassa ao app atual e marca o `Reloader` para não recarregar
    mais durante o shutdown.
- **Sem mudança no core:** o `Boot` já sabe descarregar (`shutdown`) e
  carregar de novo. O reload usa só a API que já existe.

## Fase do roadmap

Ajuste da experiência de desenvolvimento (Fase 0/1, CLI). Não depende de
outras propostas.

## Performance

- **Produção:** nada muda. Sem reload, o `Server` recebe os apps direto, sem
  `ReloadingApp` no caminho.
- **Development, por request:** um glob e um `stat` por arquivo dos
  projetos. Numa solution com algumas centenas de arquivos, isso custa
  poucos milissegundos.
- **Development, no reload:** o custo do boot (eager load e compilação de
  rotas), normalmente dezenas de milissegundos. O tempo aparece na linha
  `Reloaded in N ms`.

## Segurança

- **Só em development:** fora dele o reload nunca liga, mesmo sem
  `--no-reload`.
- **Detalhes do erro na resposta:** o `500` de reload mostra a mensagem do
  erro, como o Boto já faz com exceções em development. Fora de development
  esse caminho não existe.
- **O que é lido:** só os arquivos dos projetos declarados no Botofile, sem
  seguir caminho vindo do request.

## Compatibilidade

- **Minor, sem quebra:** quem roda em development passa a ter reload; quem
  não quer usa `--no-reload`.
- **CHANGELOG, seção Added:** reload automático no `boto run` em
  development e a opção `--no-reload`.

## Testes planejados

- **`FileWatcher`** (com glob e mtime falsos):
  - sem mudança → `false`;
  - arquivo alterado, novo ou removido → `true`, uma vez só por mudança.
- **`Reloader`:**
  - mudança num endpoint → o próximo `current` devolve um app novo, com a
    rota nova;
  - sem mudança → o mesmo app;
  - erro de sintaxe → resposta `500` com a mensagem, e o próximo reload,
    depois da correção, volta ao normal;
  - os plugins do app antigo recebem `stop`;
  - `Botofile` com projeto novo → aviso uma vez e nenhuma troca;
  - depois do `drain!`, não recarrega.
- **`ReloadingApp`:** delega `call` e `drain!`.
- **`boto run`:**
  - em development usa `ReloadingApp`;
  - com `--no-reload`, ou fora de development, recebe os apps direto;
  - a ajuda lista `--no-reload`.
- **Integração** (fixture numa pasta temporária): sobe a solution, troca o
  corpo de um endpoint no disco e confere que o request seguinte devolve o
  valor novo.

## Alternativas descartadas

- **Reiniciar o processo inteiro a cada mudança (estilo `rerun`):** mais
  lento, derruba as conexões e repete o bind das portas. O Zeitwerk já
  descarrega e carrega o código no mesmo processo.
- **Gem `listen` (eventos do sistema de arquivos):** dependência nova, com
  extensões nativas por plataforma. O `stat` por request é suficiente para
  development.
- **Thread de polling em segundo plano:** estado extra e corrida com os
  requests. Checar no request é determinístico e testável.
- **Recarregar só o projeto que mudou:** um projeto library alimenta vários
  serviços, e o isolamento precisa ser checado de novo. Recarregar tudo é
  simples e correto, e o custo de boot é baixo.
- **Ligar o reload também em produção:** custo por request e risco de
  carregar código pela metade. Só faz sentido em development.
