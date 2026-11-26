# 0007 — Lifecycle de plugins

Status: **em revisão**

## Problema

O `Boto::Plugin` só define o contrato HTTP (`call(env, app)`). Nada avisa um
plugin quando a app sobe ou desce. Já o `Boot#shutdown` só descarrega os
loaders do Zeitwerk.

Um plugin que segura recursos externos não tem onde liberá-los. Exemplos:

- o pool de conexões da `Boto::Redis::RateLimitStore`;
- no futuro, as sessões em Redis, o exporter da telemetria e o consumidor de
  filas do `worker`.

Hoje esses recursos só são liberados quando o processo morre. Os testes e o
`boto openapi`, que sobem e descem apps no mesmo processo, deixam conexões
abertas.

## API pública

### Quem escreve um plugin

```ruby
class Boto::Plugins::Telemetry < Boto::Plugin
  scope :global

  def start
    @exporter = Exporter.connect(@endpoint)   # pode lançar: o boot falha
  end

  def stop
    @exporter&.shutdown                       # deve tolerar recurso já fechado
  end

  def call(env, app) = ...
end
```

- `start` e `stop` são opcionais, e o padrão não faz nada. Os plugins que
  existem hoje não mudam.
- **`start`** roda uma vez, depois que todos os plugins do projeto foram
  construídos e antes de a app atender o primeiro request. A ordem é a de
  `Boto::Plugin::ORDER`.
- **`stop`** roda na ordem inversa da inicialização, e só nos plugins que
  chegaram a iniciar.

### Quem usa a app (CLI, testes, servidor próprio)

```ruby
boot = Boto::Boot.new(solution, root: root)
app  = boot.app("orders")    # já iniciada: start rodou em todos os plugins
# ...
boot.shutdown                # para as apps que criou (stop) e descarrega os loaders
```

- `Boto::App#start` e `Boto::App#stop` são públicos, para quem monta a app sem
  o `Boot`. Os dois são idempotentes: chamar duas vezes não faz nada na
  segunda.
- **Falha no `start`:** os plugins que já iniciaram são parados em ordem
  inversa, e o boot lança `Boto::App::BootError` com o plugin e a causa
  original. Nenhuma app fica meio iniciada.
- **Falha no `stop`:** é registrada no `error_output` da app e não interrompe
  os demais. Um plugin que falha ao fechar não pode impedir os outros de
  fecharem.

### Mudanças nos plugins atuais

- `:rate_limit` ganha `stop`, que chama `store.close` quando a store
  responde a `close`.
- `Boto::Redis::RateLimitStore#close` encerra o pool de conexões e é
  idempotente.
- A `MemoryStore` não muda.

### CLI

- `boto run`: no `INT`/`TERM`, depois de o Falcon parar, o comando chama
  `boot.shutdown`, que já está no `ensure` e passa a parar as apps.
- `boto openapi`: já chama `boot.shutdown` no `ensure`.

## Estrutura

```
gems/boto-rb/lib/boto/plugin.rb             # start/stop padrão (no-op)
gems/boto-rb/lib/boto/http/app.rb           # App#start/#stop, ordem, falhas, idempotência
gems/boto-rb/lib/boto/solution/boot.rb      # app inicia; shutdown para as apps antes dos loaders
gems/boto-rb-security/lib/boto/plugins/rate_limit.rb      # stop -> store.close
gems/boto-rb-redis/lib/boto/redis/rate_limit_store.rb     # close
```

## Fase do roadmap

É base da Fase 2, que traz health checks, graceful shutdown, OpenTelemetry e
`worker`, e entra antes dela. A versão sobe para `0.8.0`.

## Performance

- Nada muda por request: `start` e `stop` rodam uma vez no boot e uma vez no
  shutdown.
- O `call` dos plugins não ganha checagem de estado.

## Segurança

- Um `stop` que não roda pode deixar conexões abertas, mas não expõe dados.
- Um erro de `start` não pode subir uma app sem um plugin de segurança. Por
  isso a falha aborta o boot, em vez de só registrar o erro e seguir.

## Compatibilidade

- Só adiciona: plugins sem `start` e `stop` seguem funcionando.
- **Muda um comportamento:** `Boot#app` passa a devolver a app já iniciada, e
  `Boot#shutdown` passa a parar as apps. Quem monta `Boto::App.new` direto e
  quer o lifecycle precisa chamar `start` e `stop`.
- **CHANGELOG:**
  - `Added`: `Plugin#start`/`#stop`, `App#start`/`#stop` e
    `RateLimitStore#close`;
  - `Changed`: `Boot#shutdown` para as apps.

## Testes planejados

- **App:**
  - `start` em ordem;
  - `stop` em ordem inversa;
  - `start` e `stop` idempotentes;
  - falha no terceiro `start`: os dois primeiros param e o boot lança
    `BootError`;
  - falha num `stop`: os outros ainda param e o erro aparece no
    `error_output`.
- **Boot:**
  - `app` devolve a app iniciada;
  - `shutdown` para as apps antes de descarregar os loaders;
  - `shutdown` duas vezes não falha.
- **rate_limit:** o `stop` fecha a store que tem `close` e ignora a que não
  tem.
- **RateLimitStore:** depois do `close`, o pool fica fechado, e um segundo
  `close` não falha. O teste usa Redis real, como os testes de integração
  que já existem.
- **CLI:** o `boto run` para as apps no shutdown.

## Alternativas descartadas

- **`at_exit` em cada plugin:** não roda nos testes nem no `boto openapi`,
  que descem apps no meio do processo, e a ordem fica sem garantia.
- **Hooks no Falcon:** prende o lifecycle a um servidor, e o `Boto::Server`
  existe para o servidor ser trocável.
- **Iniciar no primeiro request (lazy):** um erro de conexão só apareceria em
  produção, no primeiro request, e não no boot.
- **Registro global de recursos:** é estado global mutável, que a rule
  `clean-code` proíbe.
