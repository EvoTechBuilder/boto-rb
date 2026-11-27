# 0017 — `Boto::Operation` e `Boto::Operation::Result`

Status: **implementada**

## Problema

- As operations (regras de negócio em `operations/`) não têm um formato
  comum. O `boto generate operation` gera um módulo com `def self.call(input)`.
  Esse formato não comporta:
  - estado por chamada;
  - métodos privados que leem o input sem repassá-lo de método em método;
  - dependências injetadas para teste.
- Não há um jeito padrão de uma operation dizer "não deu certo, e o motivo é
  este" (produto não existe, estoque insuficiente). Hoje sobram duas saídas:
  - levantar exceção, o que mistura falha de negócio com bug;
  - devolver `nil` ou `false`, o que perde o motivo.
- Esse "não deu certo" ainda vira `if` no endpoint para escolher o status
  HTTP, repetido em cada um.

## API pública

### Operation

```ruby
# apps/catalogo/operations/create_product.rb
class Catalogo::CreateProduct < Boto::Operation
  def initialize(input, repository: Catalogo::Products)
    super(input)
    @repository = repository
  end

  def call
    return failure(:conflict, "a product named #{input.name} already exists") if @repository.exists?(input.name)

    success(@repository.create(input))
  end
end
```

A operation mais simples nem precisa de `initialize`. Um retorno comum vira
sucesso:

```ruby
class Catalogo::ListProducts < Boto::Operation
  def call = Catalogo::Products.all(tag: input.tag)   # vira success(lista)
end
```

### Result

O `.call` **sempre** devolve um `Boto::Operation::Result`:

```ruby
result = Catalogo::CreateProduct.call(input)

result.success?          # => false
result.failure?          # => true
result.value             # => nil na falha; o valor no sucesso
result.failure.code      # => :conflict
result.failure.message   # => "a product named Camiseta already exists"
result.failure.details   # => {} (dados extras, opcionais)
result.value!            # sucesso: o valor; falha: levanta Boto::Operation::FailedError

case result              # pattern matching (Data)
in { failure: nil, value: } then use(value)
in { failure: { code: :conflict } } then retry_later
end
```

- **`success(value = nil)`:** helper privado da operation, que monta um
  sucesso.
- **`failure(code, message = nil, **details)`:** helper privado que monta uma
  falha. O `code` é um Symbol, e `details` são dados extras para quem chamou.
- **Retorno comum, que não é `Result`:** o `.call` embrulha em
  `success(retorno)`. Assim, uma operation que nunca falha não precisa de
  cerimônia.
- **Exceções não são capturadas.** Bug continua sendo exceção e cai no 500 do
  mecanismo central. O `Result` é só para falhas de negócio previstas.

### No endpoint

Um endpoint pode devolver o `Result` direto, e o Boto traduz para HTTP:

```ruby
class Catalogo::Products::Create < Boto::Endpoint
  post "/products"
  body Catalogo::CreateProductSchema
  returns Catalogo::ProductSchema
  status 201
  errors 409

  def call(body:) = Catalogo::CreateProduct.call(body)
end
```

- **Sucesso:** o `value` segue o caminho normal (`returns`, `status`), como
  se o endpoint o tivesse devolvido.
- **Falha:** vira problem+json, com o status escolhido pelo `code`:

| `code` | Status |
|---|---|
| `:invalid` | 422 |
| `:unauthorized` | 401 |
| `:forbidden` | 403 |
| `:not_found` | 404 |
| `:conflict` | 409 |
| `:unprocessable` e qualquer outro | 422 |

```json
409
{ "type": "about:blank", "title": "Conflict", "status": 409,
  "detail": "a product named Camiseta already exists", "code": "conflict" }
```

- **O `code` entra na resposta** como membro de extensão do RFC 9457, e o
  cliente pode decidir por ele.
- **`details` não entram na resposta:** podem ter dados internos, e ficam só
  para quem chama em Ruby.
- **O endpoint ainda pode tratar o `Result` à mão** (`result.failure?`), se
  quiser outro formato de resposta.

### `boto generate operation`

```bash
boto g operation catalogo create_product
```

```ruby
# apps/catalogo/operations/create_product.rb
# frozen_string_literal: true

class Catalogo::CreateProduct < Boto::Operation
  def call
    raise NotImplementedError, "Catalogo::CreateProduct#call"
  end
end
```

```ruby
# apps/catalogo/test/operations/create_product_test.rb
# frozen_string_literal: true

require "test_helper"

class Catalogo::CreateProductTest < Minitest::Test
  def test_call
    flunk "call Catalogo::CreateProduct.call(input) and assert result.success? and result.value"
  end
end
```

O teste gerado não chama a operation: o `#call` gerado levanta
`NotImplementedError`, o que daria erro em vez da falha que indica o que falta.

### Assinaturas

```ruby
module Boto
  class Operation
    def self.call(...)                 # new(...).call, embrulhado em Result
    private_class_method :new
    def initialize(input = nil)
    def call                           # NotImplementedError
    private
    attr_reader :input
    def success(value = nil)           # => Result
    def failure(code, message = nil, **details)  # => Result

    Result  = Data.define(:value, :failure)  # success?, failure?, value!
    Failure = Data.define(:code, :message, :details)
    class FailedError < StandardError  # #result, levantado por value!
  end
end
```

## Estrutura

```
gems/boto-rb/lib/boto/operation.rb                # Boto::Operation
gems/boto-rb/lib/boto/operation/result.rb         # Boto::Operation::Result
gems/boto-rb/lib/boto/operation/failure.rb        # Boto::Operation::Failure
gems/boto-rb/lib/boto/operation/failed_error.rb   # Boto::Operation::FailedError
gems/boto-rb/lib/boto/http/app.rb                 # success_response reconhece Result
gems/boto-rb/lib/boto/http/problem.rb             # aceita o membro "code"
gems/boto-rb-cli/templates/generate/operation/    # gera a subclasse e o teste
```

- **Core (`boto-rb`):** sem dependências, e serve a todo template.
- **Nome:** `Boto::Operation` não colide com `Boto::OpenAPI::Operation`, que
  fica dentro de `Boto::OpenAPI`.
- **Isolamento:** o namespace `Boto::` é sempre permitido, então um projeto
  usa `Boto::Operation` sem referência no Botofile.

## Fase do roadmap

Fase 1, junto do `boto generate` (proposta 0016). Também prepara o template
`worker` (Fase 2): um job pode decidir entre retry e dead letter pelo
`failure.code`.

## Performance

- **Por chamada de operation:** a instância e o `Result`, que é um `Data`
  imutável. Na falha, também o `Failure`. É desprezível perto do trabalho de
  uma operation.
- **Caminho quente do endpoint:** o `success_response` ganha um `is_a?` por
  request, que só custa algo quando o endpoint devolve um `Result`. Sem
  `Result`, o custo é um teste de classe e nenhuma alocação. O benchmark
  confirma que `hello` e `db` não mudam.
- **Mapa de status:** um Hash congelado, montado no load.

## Segurança

- **Mensagem da falha:** vai para o cliente no `detail`, em qualquer ambiente.
  É uma mensagem de negócio escrita pelo dev, ao contrário da exceção, que só
  aparece em development.
- **`details`:** nunca vão para a resposta, porque podem ter dados internos.
- **`code`:** um Symbol escolhido pelo dev. Na resposta vira texto, sem
  conversão de entrada do usuário.
- **Exceções:** continuam no fluxo atual, um 500 sem detalhes em produção.

## Compatibilidade

- **Minor, aditiva:**
  - operations em módulo continuam funcionando;
  - endpoints que não devolvem `Result` não mudam.
- **`boto generate operation`:** passa a gerar uma classe em vez de um módulo.
  Os arquivos já gerados não mudam.
- **CHANGELOG:**
  - Added: `Boto::Operation`, `Result`, `Failure` e `FailedError`, e o
    endpoint que devolve `Result`;
  - Changed: o gerador de operation produz uma subclasse.

## Testes planejados

- **`.call`:**
  - um `success(x)` sai como está;
  - um `failure(:code, "msg", a: 1)` sai como está;
  - um retorno comum vira `success`;
  - argumentos posicionais e keywords chegam ao `initialize`;
  - sem argumentos, o `input` é `nil`.
- **`new` privado:**
  - `Subclasse.new` levanta `NoMethodError`;
  - o `.call` funciona.
- **Erros da operation:**
  - sem `#call`, levanta `NotImplementedError`;
  - uma exceção dentro do `#call` não vira `Result`.
- **`Result`:**
  - `success?` e `failure?`;
  - `value!` devolve o valor ou levanta `FailedError` com o `result`;
  - pattern matching funciona;
  - o objeto é imutável.
- **Endpoint (`Rack::MockRequest`):**
  - um `Result` de sucesso passa pelo `returns`, com o `status` declarado;
  - cada `code` da tabela vira o status certo;
  - um código desconhecido vira 422;
  - a resposta traz `detail` e `code`, e não traz `details`.
- **Gerador:**
  - o conteúdo gerado é a subclasse;
  - o `Boot` carrega o projeto com a operation gerada.
- **Benchmark:** `hello` e `db` sem mudança de alocação.

## Alternativas descartadas

- **Executar o `call` dentro do `initialize`:** o `new` sempre devolve a
  instância, então o resultado se perderia.
- **`Result` opcional, e o `.call` devolvendo o valor cru por padrão:** cada
  operation escolheria um formato, e quem chama nunca saberia o que vem.
  Embrulhar sempre torna o contrato previsível.
- **Gem de terceiros (`dry-monads`):** dependência e vocabulário grandes para
  um `Data` de duas linhas.
- **Capturar exceções e transformar em `failure`:** esconderia bugs atrás de
  um 422.
- **Expor `details` na resposta:** risco de vazar dados internos. Quem quiser
  pode montar a resposta à mão.
- **Validação do input dentro da operation (`input SomeSchema`):** os schemas
  já validam na borda. Pode virar uma proposta própria.
