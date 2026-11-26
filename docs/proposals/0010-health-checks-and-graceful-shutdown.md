# 0010 — Health checks e graceful shutdown

Status: **implementada**

## Problema

- **Health check:** hoje é um endpoint gerado pelo template
  (`<Projeto>::Health`, em `GET /health`), que sempre responde
  `{"status":"ok"}`.
  - Ele não sabe se o Redis ou o banco estão de pé.
  - Não separa *liveness* (o processo está vivo?) de *readiness* (pode
    receber tráfego?).
  - Passa pelos plugins do projeto. Por isso o template precisa de
    `skip :auth, :rate_limit`, e o `:hosts` recusaria a sonda do orquestrador,
    que chega pelo IP do pod.
- **Shutdown:** o `boto run` não trata `SIGTERM`.
  - O Ruby encerra o processo na hora, e os requests em andamento são
    cortados.
  - O `boot.shutdown` roda no `ensure`, mas sem drenar nada antes.
  - O `SIGINT` (Ctrl-C) só imprime `Stopping`.

No PaaS, cada deploy derruba requests e não há como tirar uma instância do
balanceador antes de ela parar.

## API pública

### `config/app.rb`

```ruby
Boto.configure do |app|
  app.use :health                                   # GET /health/live e GET /health/ready
  app.use :health, checks: {                        # checagens próprias do projeto
    database: -> { DB.test_connection }
  }, timeout: 1                                     # segundos por checagem (padrão 1)
  app.use :auth, strategy: :bearer, tokens: -> { ... }
end
```

- **`GET /health/live`:** responde sempre `200 {"status":"ok"}` enquanto o
  processo atende. Não consulta nada externo: uma dependência fora do ar não
  pode fazer o orquestrador reiniciar o serviço.
- **`GET /health/ready`:**
  - responde `200` quando todas as checagens passam e `503` quando alguma
    falha, estoura o timeout ou quando o serviço está drenando (shutdown em
    andamento);
  - o corpo diz qual checagem falhou, sem a mensagem de erro:

    ```json
    {"status":"fail","checks":{"redis":"ok","database":"fail"}}
    ```

  - a mensagem completa vai para o log da app, nunca para a resposta.
- **Prioridade:** o `:health` é global e o primeiro da ordem fixa
  (`health -> hosts -> cors -> ...`). As sondas não passam por `:hosts`,
  `:auth` nem `:rate_limit`, e o endpoint não precisa de `skip`.
- **Fora do OpenAPI:** os caminhos são de infraestrutura e não entram no
  documento.

### Checagens dos plugins

```ruby
class Boto::Plugins::RateLimit < Boto::Plugin
  def health_checks = @store.respond_to?(:healthy?) ? { rate_limit_store: -> { @store.healthy? } } : {}
end
```

- **`Boto::Plugin#health_checks`:** devolve `{}` por padrão. Um plugin que
  depende de algo externo registra a sua checagem, e o `:health` junta as de
  todos os plugins do projeto com as de `checks:`.
- **`RateLimitStore#healthy?`:** faz um `PING` no Redis.
- **Retorno de cada checagem:** `true` ou qualquer valor verdadeiro conta
  como ok. `false`, `nil` ou exceção contam como falha.

### Graceful shutdown no `boto run`

```
$ boto run orders --shutdown-timeout 25 --drain-delay 5
```

No primeiro `SIGTERM` ou `SIGINT`:

1. **Drenagem:** a app entra em drenagem, e o `/health/ready` passa a
   responder `503`.
2. **Espera opcional:** se `--drain-delay N` estiver definido, o serviço
   espera N segundos (padrão 0) antes do passo 3. É o tempo para o balanceador
   perceber o 503 e parar de mandar requests.
3. **Fim das conexões novas:** o serviço para de aceitar conexões.
4. **Requests em andamento:** o serviço espera eles terminarem, até
   `--shutdown-timeout N` segundos (padrão 25, abaixo dos 30 s que o
   Kubernetes dá por padrão).
5. **Plugins:** chama o `boot.shutdown`, que já para os plugins na ordem
   inversa (proposta 0007), e sai com 0.

Um segundo sinal durante a drenagem encerra na hora, com saída 1.

## Estrutura

```
gems/boto-rb/lib/boto/plugins/health.rb      # :health no core: rotas live/ready, checagens, timeout, drenagem
gems/boto-rb/lib/boto/plugin.rb              # health_checks padrão; :health no início do ORDER
gems/boto-rb/lib/boto/http/app.rb            # drain!/draining? e contagem de requests em andamento
gems/boto-rb-security/lib/boto/plugins/rate_limit.rb   # health_checks da store
gems/boto-rb-redis/lib/boto/redis/rate_limit_store.rb  # healthy? (PING)
gems/boto-rb-cli/lib/boto/cli/commands/run.rb          # --shutdown-timeout, --drain-delay, sinais
gems/boto-rb-cli/lib/boto/cli/support/server.rb        # parar de aceitar e esperar conexões
gems/boto-rb-cli/templates/webapi/...                  # app.use :health no lugar do endpoint Health
```

- **Por que o `:health` fica no core**, e não numa gem de plugins:
  - não tem dependência;
  - todo template precisa dele;
  - ele depende do estado de drenagem da `Boto::App`.

  Ele é registrado em `Boto::Plugins::Health`, onde o `app.use` já procura os
  plugins.
- **Detalhe a confirmar na implementação:** parar o accept do Falcon sem
  derrubar as conexões abertas. O plano começa com uma spike curta para isso.
  Se o Falcon não permitir, a alternativa é fechar o listener e acompanhar os
  requests com o contador da app.

## Fase do roadmap

Fase 2: health checks e graceful shutdown. É pré-requisito do template
`microservice`.

## Performance

- **Por request:**
  - o `:health` compara o `PATH_INFO` com dois caminhos congelados e repassa
    o resto sem alocar;
  - a contagem de requests em andamento é um incremento e um decremento
    atômicos por request, sem lock.

  O benchmark mede antes e depois, porque o plugin está no caminho quente.
- **Checagens:** só rodam quando `/health/ready` é chamado, com timeout por
  checagem, e em paralelo nas fibras do Async.

## Segurança

- A resposta não expõe mensagens de erro nem endereços. Só aparece o nome da
  checagem e `ok`/`fail`.
- O `/health/*` fica fora do `:hosts` e do `:auth` de propósito, porque as
  sondas vêm de dentro do cluster sem credenciais. Ele não devolve dados da
  aplicação.
- O timeout impede que uma dependência lenta prenda a sonda e esgote as
  fibras.

## Compatibilidade

- Só adiciona: quem não usa `app.use :health` não muda nada.
- Projetos já gerados mantêm o endpoint `Health` próprio em `/health`, e os
  dois convivem, porque os caminhos são diferentes.
- O template `webapi` novo troca o endpoint e o `HealthSchema` por
  `app.use :health`.
- O `boto run` passa a drenar no `SIGTERM`/`SIGINT` em vez de cair na hora.
- **CHANGELOG:**
  - `Added`: `:health`, `Plugin#health_checks`, `RateLimitStore#healthy?`,
    `--shutdown-timeout` e `--drain-delay`;
  - `Changed`: o `boto run` faz graceful shutdown, e o template `webapi` usa
    `:health`.

## Testes planejados

- **`:health`:**
  - `/health/live` responde 200 mesmo com a checagem falhando;
  - `/health/ready` responde 200 com tudo ok;
  - responde 503 com uma checagem que retorna `false`, que lança exceção ou
    que estoura o timeout, sem a mensagem de erro no corpo e com o erro no
    log;
  - responde 503 durante a drenagem;
  - as checagens dos plugins entram junto com as de `checks:`;
  - responde antes de `:hosts` e `:auth`;
  - não aparece no OpenAPI;
  - opções inválidas falham no boot (checagem que não é callable, timeout
    menor ou igual a 0).
- **App:** `drain!` muda o `draining?`, e a contagem de requests em andamento
  sobe e desce, inclusive quando o endpoint lança.
- **RateLimitStore:** `healthy?` é `true` com Redis e `false` quando ele está
  fora do ar (Redis real ou client fake que falha).
- **`boto run`:**
  - com o servidor de teste, um sinal coloca a app em drenagem, espera um
    request lento terminar e só depois chama o `stop` dos plugins;
  - estourando o `--shutdown-timeout`, encerra mesmo assim;
  - um segundo sinal encerra na hora.
- **Benchmark:** os cenários `hello` e `db` antes e depois de ligar o
  `:health`.

## Alternativas descartadas

- **Manter o health como endpoint do usuário:** ele passa pelos plugins, e
  por isso precisa de `skip` e quebra com o `:hosts`. Além disso, não enxerga
  a drenagem nem as checagens dos plugins.
- **Um endpoint só (`/health`):** mistura liveness com readiness, e uma
  dependência fora do ar faria o orquestrador reiniciar um processo saudável.
- **Expor a mensagem de erro na resposta:** vaza detalhes de infraestrutura
  num endpoint sem autenticação.
- **Rodar as checagens em background num intervalo fixo:** cria estado
  compartilhado e tráfego para as dependências mesmo sem sonda. Sob demanda,
  com timeout, é mais simples.
- **Usar o `falcon serve` com o container dele:** ganharia o graceful
  shutdown pronto, mas o `boto run` perderia o controle de várias apps num
  processo, que é o modo dev do Boto.

## Ajustes depois da spike (antes da implementação)

- **Accept do Falcon:** a spike confirmou o caminho. O servidor usa um
  endpoint já ligado (`endpoint.bound`), e fechar esse listener faz as
  conexões novas serem recusadas, enquanto o request em andamento termina com
  200. O fiber de accept registra um `IOError` ao fechar, e esse aviso precisa
  ser tratado.
- **Contagem de requests em andamento:** fica no servidor do CLI
  (`Boto::CLI::Server`), num middleware fino em volta de cada app, e não na
  `Boto::App`. O caminho por request do core não ganha nada, e o servidor é
  quem precisa do número para drenar.
- **Drenagem:** `Boto::App#drain!` avisa os plugins por um hook novo,
  `Plugin#drain`, que não faz nada por padrão. O `:health` usa esse aviso para
  responder 503 no `/health/ready`. Assim nenhum request precisa consultar
  estado da app.

## Ajustes durante a implementação

- **`Plugin#attach(app)`:** o `:health` precisa enxergar os outros plugins da
  app para juntar as checagens. Por isso entrou mais um hook, que não faz nada
  por padrão e que a app chama antes do `start`. O `Boto::App#plugins` passou
  a ser público.
- **`error_output:`:** o `:health` aceita essa opção para o log das falhas,
  com `$stderr` como padrão, porque a app não expõe o logger dela.
- **Corte depois do timeout:** os requests que passam do `--shutdown-timeout`
  são cortados com `Fiber.scheduler.raise(task.fiber, Async::Cancel)`, o
  mesmo caminho do `Task#cancel`. Essa API do Async é meio interna e foi
  testada com o async 2.46.
