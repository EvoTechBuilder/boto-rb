# 0016 — `boto generate`: schemas, operations, endpoints e models com teste

Status: **implementada** (opção de testes no Botofile, com o nome `generators`)

## Problema

- Criar um schema, um endpoint, uma operation ou um model hoje é tudo à mão:
  o arquivo na pasta certa, o nome da constante com o namespace certo e o
  teste em `test/`, espelhando a pasta.
- O Zeitwerk liga o nome do arquivo ao da constante. Errar a pasta ou o nome
  quebra o boot.
- O teste costuma ficar para depois.

## API pública

```bash
boto generate <tipo> <projeto> <nome> [campos ou opções]
boto g ...                      # atalho
```

### Schema

```bash
boto generate schema catalogo product id:integer name:string price:float \
  active:boolean tags:[string] category:category available_on:date?
```

```ruby
# apps/catalogo/schemas/product_schema.rb
# frozen_string_literal: true

class Catalogo::ProductSchema < Boto::Schema
  field :id, Integer
  field :name, String
  field :price, Float
  field :active, Boto::Boolean
  field :tags, [String]
  field :category, Catalogo::CategorySchema
  field :available_on, Date, required: false
end
```

```ruby
# apps/catalogo/test/schemas/product_schema_test.rb
# frozen_string_literal: true

require "test_helper"

class Catalogo::ProductSchemaTest < Minitest::Test
  def test_coerces_a_valid_input
    flunk "fill a valid input for Catalogo::ProductSchema.coerce"
  end

  def test_rejects_an_invalid_input
    flunk "assert_raises(Boto::Types::Invalid) with an invalid input"
  end
end
```

- **Tipos:** `string`, `integer`, `float`, `boolean`, `date`, `time`, listas
  (`[tipo]`) e outros schemas do projeto pelo nome (`category` vira
  `Catalogo::CategorySchema`).
- **`?` no fim:** o campo vira `required: false`.
- **Sem campos:** gera o schema vazio, para preencher depois.

### Endpoint

```bash
boto generate endpoint catalogo products/show get /products/:id --returns product
boto generate endpoint catalogo products/create post /products --body create_product --returns product
```

```ruby
# apps/catalogo/endpoints/products/show.rb
# frozen_string_literal: true

class Catalogo::Products::Show < Boto::Endpoint
  get "/products/:id"
  param :id, String
  returns Catalogo::ProductSchema

  def call(id:)
    raise NotImplementedError
  end
end
```

- **Params do path:** cada `:param` da rota vira `param :nome, String`, e um
  campo `id:integer` troca o tipo.
- **Teste:** um teste com `Rack::MockRequest` na rota, usando o `APP` do
  `test_helper` e o token de desenvolvimento quando o projeto tem `:auth`. Ele
  falha (`flunk`) até ser escrito.

### Operation

```bash
boto generate operation catalogo create_product
```

```ruby
# apps/catalogo/operations/create_product.rb
# frozen_string_literal: true

module Catalogo::CreateProduct
  def self.call(input)
    raise NotImplementedError
  end
end
```

- **Nome de operation é um verbo** (`create_product`, `search_products`),
  nunca um caminho como `products/create`:
  - endpoints e operations são carregados no mesmo namespace do projeto;
  - `endpoints/products/create.rb` e `operations/products/create.rb` seriam
    os dois `Catalogo::Products::Create`, e o boot quebraria;
  - o gerador recusa, com uma mensagem, um nome que colida com uma constante
    que já existe no projeto.

### Model

```bash
boto generate model catalogo product id:integer name:string price:float
```

```ruby
# apps/catalogo/models/product.rb
# frozen_string_literal: true

Catalogo::Product = Data.define(:id, :name, :price)
```

- O Boto ainda não integra ORM, então o model gerado é um `Data`, imutável e
  sem banco.
- Quando houver integração com banco, o gerador ganha um `--orm`.

### Desligar os testes

O teste é gerado por padrão. Para desligar num comando:

```bash
boto generate schema catalogo product name:string --skip-tests
```

Para desligar de vez, a recomendação é **no Botofile**, não no
`config/app.rb`:

```ruby
# Botofile
solution "loja"

generators tests: false                                          # vale para a solution inteira
project "catalogo", template: :webapi, generators: { tests: true }   # um projeto pode voltar a gerar
```

**Por que não no `config/app.rb`, como você sugeriu:**

- O `config/app.rb` é configuração de **execução**: ele roda em cada boot, em
  produção também. Ao avaliá-lo, os plugins são construídos e os segredos
  lidos, e em production um `ENV.fetch` sem a variável derruba o comando.
- O `boto generate` é ferramenta de desenvolvimento. Para ler uma opção de
  dev, ele teria de executar o arquivo de produção.
- O Botofile já é onde a solution declara projetos e convenções, e o CLI já o
  lê em todos os comandos.

Se você preferir mesmo o `config/app.rb`, dá para implementar como
`app.generate_tests = false`, com o custo acima.

### Regras gerais

- **Nunca sobrescreve:** um arquivo que já existe faz o comando falhar, a não
  ser com `--force`.
- **Nomes:**
  - o `<nome>` é em snake_case;
  - pastas (`products/show`) viram módulos (`Products::Show`);
  - o namespace do projeto vem sempre na frente.
- **Saída:** a lista do que foi criado, como no `boto add`:
  ```
  create apps/catalogo/schemas/product_schema.rb
  create apps/catalogo/test/schemas/product_schema_test.rb
  ```
- **Validação:**
  - projeto inexistente, tipo desconhecido, verbo HTTP inválido e template de
    projeto sem a pasta são erros;
  - `library` não tem `endpoints/`, então `generate endpoint` num projeto
    `library` é erro.

## Estrutura

```
gems/boto-rb-cli/lib/boto/cli/commands/generate.rb        # comando, subcomandos e opções
gems/boto-rb-cli/lib/boto/cli/support/field_spec.rb       # "price:float", "tags:[string]", "date?" -> campo
gems/boto-rb-cli/lib/boto/cli/support/constant_name.rb    # "products/show" + projeto -> Catalogo::Products::Show
gems/boto-rb-cli/templates/generate/{schema,endpoint,operation,model}/   # arquivo e teste (.erb)
gems/boto-rb/lib/boto/solution/botofile.rb                # `generators tests:` e `generators: { tests: }` no project
```

## Fase do roadmap

Fase 1 (CLI e templates). Não depende de outras propostas.

## Performance

Nada muda em runtime: é só o CLI escrevendo arquivos.

## Segurança

- **Caminhos:** todo arquivo gerado fica dentro da pasta do projeto. Um nome
  com `..`, barra no começo ou caractere fora de `[a-z0-9_/]` é recusado.
- **Conteúdo:** o código gerado não lê nada de fora. O que vem dos argumentos
  só vira nome de constante, já validado.

## Compatibilidade

- **Minor:** comando novo, e chaves novas e opcionais no Botofile.
- **CHANGELOG, seção Added:** `boto generate` (e `boto g`), `--skip-tests`,
  `--force`, e `generators tests:` e `generators: { tests: }` no Botofile.

## Testes planejados

- **`FieldSpec`:** cada tipo, listas, schema por nome, `?` opcional e tipo
  inválido.
- **`ConstantName`:** pasta vira módulo; nomes inválidos ou com `..` são
  recusados.
- **Para cada tipo de gerador:** arquivo e teste no lugar certo, com conteúdo
  esperado; o código gerado carrega no boot (`boto check` e `boto test` numa
  solution temporária).
- **Endpoint:**
  - params do path com tipo padrão e com tipo informado;
  - `--body` e `--returns`;
  - verbo inválido é erro;
  - projeto `library` é erro.
- **Operation:** colisão com uma constante que já existe é erro.
- **Testes gerados:**
  - `--skip-tests` não cria o teste;
  - `generators tests: false` no Botofile também não;
  - `generators: { tests: true }` no projeto volta a gerar.
- **Escrita:** arquivo existente falha, e `--force` sobrescreve.
- **Botofile:** chaves novas validadas, e tipo errado é erro.

## Alternativas descartadas

- **`generate scaffold`, com schema, endpoints CRUD e operation de uma vez:**
  útil, mas maior. Fica para depois, sobre estes geradores.
- **Teste gerado que passa vazio:** um teste verde sem asserção esconde a
  falta de teste. O `flunk` deixa claro o que falta escrever.
- **Gerar o model com ORM (Sequel/ActiveRecord):** o Boto ainda não escolheu
  nem integra um ORM.
- **Arquivo `.boto.yml` para as opções do gerador:** um arquivo de
  configuração a mais. O Botofile já cumpre esse papel.
- **`generate tests:` e `generate_tests:` como nomes:** formas diferentes nos
  dois níveis, e `generate` soa como ação. `generators` tem o mesmo formato nos
  dois níveis e comporta opções futuras (como `orm:`).
