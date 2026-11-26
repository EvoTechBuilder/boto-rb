# 0001 — Fundação (Fase 0)

Status: **aprovada**

## Problema

O repositório só tem a especificação. A Fase 0 precisa entregar o mínimo para
criar uma solution, declarar projetos e referências, servir endpoints e medir
performance:

- monorepo com as gems `boto` e `boto-cli`;
- Botofile com validação;
- CLI básico;
- `Boto::Endpoint`;
- testes;
- benchmark.

## API pública

### Botofile

```ruby
solution "shop"

project "domain", template: :library
project "orders", template: :webapi, refs: %w[domain]
```

- `solution(name)` aparece uma vez e é obrigatório.
- `project(name, template:, refs: [])`.
  - O nome segue `/\A[a-z][a-z0-9_]*\z/`, e o namespace sai dele em
    CamelCase (`order_items` -> `OrderItems::`).
  - A pasta é derivada do template: `library` -> `libs/`, `webapi` e
    `microservice` -> `services/`, `worker` -> `workers/`, `web` e `spa` ->
    `apps/`.
- A validação roda no carregamento. Cada erro aponta a linha do Botofile:
  - nome duplicado ou inválido;
  - template desconhecido;
  - referência a projeto inexistente;
  - referência a si mesmo;
  - ciclo, informado com o caminho completo (`a -> b -> c -> a`).

### Endpoint

```ruby
# services/orders/endpoints/users/show.rb
class Orders::Users::Show < Boto::Endpoint
  get "/users/:id"
  param :id, Integer

  def call(id:)
    Users.find(id) or not_found
  end
end

# services/orders/endpoints/users/index.rb
class Orders::Users::Index < Boto::Endpoint
  get "/users"
  param :page, Integer, default: 1
  param :active, Boto::Boolean, required: false

  def call(page:, active:)
    { page:, users: Users.list(page:, active:) }
  end
end

# services/orders/endpoints/users/create.rb
class Orders::Users::Create < Boto::Endpoint
  post "/users"
  status 201
  param :name, String

  def call(name:) = Users.create(name:)
end
```

- **Verbos**: `get`, `post`, `put`, `patch` e `delete`. `HEAD` responde
  automaticamente a partir do `get`.
- **Params**: vêm do path, da query string e do corpo JSON, nessa ordem de
  precedência.
  - Tipos da Fase 0: `String`, `Integer`, `Float` e `Boto::Boolean`.
  - Todo param é obrigatório, a não ser que tenha `default:` ou
    `required: false` (nesse caso chega como `nil`).
  - Params não declarados são descartados, como no strong parameters.
- **Retorno**:
  - `Hash` ou `Array` vira JSON com o status padrão (200, ou o declarado em
    `status`);
  - `nil` vira 204.
  - Schemas (`returns`) ficam para a Fase 1.
- **Helpers de erro**: `not_found`, `unprocessable(errors)` e
  `bad_request(detail)`. Eles lançam exceções do Boto, que o core converte
  em JSON.
- **Teste**: chame `Orders::Users::Show.new.call(id: 1)` direto, sem servidor.

### Erros JSON (RFC 9457, `application/problem+json`)

```json
{ "type": "about:blank", "title": "Unprocessable Content", "status": 422,
  "errors": [{ "param": "id", "message": "must be an Integer" }] }
```

Isso vale para 400, 404, 405 (com header `Allow`), 422 e 500.

### CLI (`boto-cli`, sem Thor: `OptionParser` da stdlib)

```
boto new shop                     # solution vazia: Botofile, Gemfile, .ruby-version, .gitignore, libs/ services/ workers/ apps/
boto add webapi orders            # esqueleto mínimo + entrada no Botofile
boto add library domain
boto ref orders domain            # edita o Botofile preservando comentários (via Prism)
boto graph                        # árvore de dependências em texto
boto run [orders]                 # um processo, uma porta por serviço (3000, 3001, ...)
boto test [orders] [--affected [--base main]]
```

- `boto add` na Fase 0 gera só o esqueleto dos templates `webapi` e
  `library`:
  - `webapi`: `endpoints/`, `operations/`, `models/`, `test/`, um endpoint de
    exemplo com teste e `config/app.rb`;
  - `library`: as mesmas pastas, sem `endpoints/`.
  
  A Fase 1 completa esses templates com schemas e OpenAPI.
- `boto test` roda cada projeto num subprocesso Minitest, isolado dos outros.
  `--affected` testa os projetos com arquivos alterados em relação a `--base`
  (o working tree e os arquivos não rastreados entram) e todos os projetos
  que dependem deles.
- `boto run` sobe a solution inteira num processo, como um monólito modular.
  Cada projeto servível ganha a própria porta, então as URLs são as mesmas de
  produção e o código não muda.

## Estrutura

```
gems/boto/                      # core, depende de rack (~> 3.1) e zeitwerk
  lib/boto.rb                   # Zeitwerk.for_gem
  lib/boto/version.rb
  lib/boto/endpoint.rb          # DSL (verbos, param, status) + helpers de erro
  lib/boto/boolean.rb           # tipo Boto::Boolean
  lib/boto/params.rb            # compila declarações em coercers, valida
  lib/boto/router.rb            # árvore radix por método
  lib/boto/error.rb             # Boto::Error e subclasses aninhadas (NotFound, BadRequest, ...)
  lib/boto/problem.rb           # monta resposta problem+json
  lib/boto/app.rb               # app Rack de um projeto: loader + descoberta + router
  lib/boto/project_loader.rb    # Zeitwerk por projeto, sob o namespace dele
  lib/boto/solution.rb          # modelo da solution, grafo, ordem topológica
  lib/boto/botofile.rb          # DSL do Botofile + validação
gems/boto-cli/                  # depende de boto e falcon
  exe/boto
  lib/boto/cli.rb               # despacho dos comandos
  lib/boto/cli/commands/{new,add,ref,graph,run,test}.rb
  lib/boto/cli/botofile_editor.rb   # edição via Prism
  lib/boto/cli/server.rb        # Boto::CLI::Server, adaptador; Falcon é o único na Fase 0
  templates/{solution,webapi,library}/
benchmarks/                     # Gemfile próprio: roda, sinatra, sequel, sqlite3
  apps/{boto,roda,sinatra}/{hello,db}
  run.rb                        # sobe cada app no Falcon, mede e compara com o baseline
Gemfile, Rakefile               # na raiz: `rake test` roda as gems
CHANGELOG.md, LICENSE, .ruby-version, .github/workflows/ci.yml
```

- **Descoberta de endpoints**: o loader do projeto faz `push_dir` de
  `endpoints/`, `operations/` e `models/` sob o namespace do projeto e roda
  `eager_load`. Depois o core percorre as constantes do namespace e registra
  as subclasses de `Boto::Endpoint`, sem registro global.

## Fase do roadmap

Fase 0.

## Performance

- **No boot:**
  - descobre os endpoints;
  - compila a árvore radix;
  - transforma as declarações de params num array congelado de coercers;
  - verifica as rotas: path param não declarado e rota duplicada geram erro
    no boot.
- **Por request:**
  1. faz o match na árvore, sem regex nos segmentos estáticos;
  2. faz o parse da query só se o endpoint declara params de query, e do JSON
     só se o content-type for JSON;
  3. aplica os coercers;
  4. cria uma instância do endpoint;
  5. serializa o retorno com `JSON.generate`.
  
  Fora o parse, a meta é alocar perto de zero objetos.
- A meta do benchmark é ficar à frente do Sinatra e perto do Roda no hello
  world.

## Segurança

- O Botofile é código Ruby e tem o mesmo nível de confiança do Gemfile.
- Só params declarados chegam ao endpoint, já com tipo. O corpo JSON tem
  limite de tamanho padrão de 1 MB, e o excesso responde 413.
- O 500 em produção (`BOTO_ENV=production`, que é o padrão) não expõe a
  mensagem nem o backtrace; em development, expõe.
- O `boto ref` só edita o Botofile, nunca executa código do usuário além de
  carregar o próprio Botofile.

## Compatibilidade

Primeira versão, `0.1.0`. O CHANGELOG começa com as entradas desta proposta.
Antes da `1.0`, a API pode mudar em versões minor.

## Testes planejados

- **Botofile**:
  - DSL válida;
  - cada erro de validação;
  - detecção de ciclo com o caminho;
  - ordem topológica.
- **Router**:
  - rota estática, dinâmica e mista;
  - prioridade da rota estática;
  - 404, 405 com `Allow` e `HEAD`;
  - rota duplicada no boot.
- **Params**:
  - coerção de cada tipo;
  - `default` e `required`;
  - descarte do que não foi declarado;
  - erros 422 agregados;
  - JSON inválido gera 400;
  - corpo grande gera 413.
- **Endpoint**: chamada direta, helpers de erro e `status`.
- **App**: request completo via `Rack::MockRequest` e descoberta num projeto
  fixture.
- **CLI** (em diretório temporário):
  - `new`, `add` e `ref` (preservando comentários);
  - `graph`;
  - seleção do `test --affected`;
  - o `run` sobe e responde na porta, num teste de integração.

## Fora de escopo da Fase 0

- Isolamento forçado entre projetos.
- `Botofile.lock` e gemspec por projeto.
- Schemas, OpenAPI, plugins, credentials, Puma e Docker.
- O `-t` do `boto new`.
- Os templates `microservice`, `worker`, `web` e `spa`.

Para o isolamento, a sugestão é uma checagem estática via Prism na Fase 1.
`Botofile.lock` e gemspec por projeto entram junto com o build Docker, na
Fase 2.

## Alternativas descartadas

- **Thor no CLI**: dependência a mais. O `OptionParser` cobre 6 comandos.
- **Prefixo de path por serviço no `boto run`**: muda as URLs entre dev e
  produção.
- **Registro global de endpoints via `inherited`**: estado global mutável,
  contra a rule `clean-code`.
- **Regenerar o Botofile inteiro no `boto ref`**: perde os comentários do
  usuário.
- **Erro em JSON próprio**: a RFC 9457 é padrão e já tem suporte em clientes
  e gateways.
