# Correções P0: body da Signature, namespaces e compilação de schemas

Status: **concluído**

## Objetivo

Corrigir três falhas independentes do core e do boto-rb-security, cada uma com
seus testes e seu próprio commit.

## Fora de escopo

- O lifecycle de plugins, que muda a API pública e segue pela proposta 0007.
- Tornar o limite de payload configurável por projeto. Hoje o limite é a
  constante `Boto::RequestBody::DEFAULT_LIMIT` (1 MB), e a Signature passa a
  usar a mesma constante.
- Proibir namespaces que já existem no Ruby ou em gems (um projeto `kernel`
  vira `Kernel`). É outra regra, e fica registrada como pendência.

## O que a verificação encontrou

- **Item 1 (Signature):** confirmado. `read_body` faz `input.read` sem limite.
  Além disso, num input sem `rewind` (o Rack 3 permite isso), o endpoint perde o
  body depois que a Signature o lê.
- **Item 2 (namespaces):** confirmado. `foo_bar`, `foo__bar` e `foo_bar_`
  passam no `NAME_FORMAT` e viram `FooBar`. O mesmo vale para `foo_1bar` e
  `foo1bar`, que viram `Foo1bar`. Por isso, endurecer o formato do nome não
  basta: a checagem precisa ser de unicidade.
- **Item 3 (schemas):** confirmado, e é pior que o descrito. Depois de uma
  falha no `compile!`, o `@compiling` fica `true`, a chamada seguinte a
  `compile!` retorna o schema como se estivesse pronto, e `serialize` entra em
  recursão infinita (`SystemStackError`).
- **Palavras reservadas do Ruby:** testei `end`, `if`, `self` e `nil`. Todas
  compilam e serializam, tanto de Hash quanto de objeto, porque `object.end` é
  Ruby válido. Proibi-las impediria chaves JSON comuns, como `"end"` num
  intervalo de datas. O conflito real é com métodos de `Object`:
  - `initialize` quebra o schema;
  - `object_id` e `send` substituem métodos que o Ruby e as bibliotecas usam.

## Task 1: limite de body na Signature

- **Arquivos:**
  - `gems/boto-rb/lib/boto/http/request_body.rb`: o novo método público
    `RequestBody.read(env, limit: DEFAULT_LIMIT)` devolve o body cru (String,
    `""` sem input). Ele usa a checagem de `CONTENT_LENGTH` e a leitura de
    `limit + 1` bytes que já existem, e lança
    `Boto::Error::PayloadTooLarge` (413). O `parse` passa a usar o `read`.
  - `gems/boto-rb-security/lib/boto/plugins/auth/signature.rb`: o `read_body`
    usa `Boto::RequestBody.read`. Com `rewind`, volta o input para o início.
    Sem `rewind`, troca `env["rack.input"]` por um `StringIO` com o body lido,
    para o endpoint ainda conseguir ler.
  - Testes espelhados nas duas gems.
- **Testes:**
  - body abaixo do limite;
  - body exatamente no limite;
  - body acima do limite, com e sem `CONTENT_LENGTH`;
  - `CONTENT_LENGTH` acima do limite, sem ler o body;
  - input sem `rewind`, com o endpoint ainda lendo o body;
  - teste de integração no boto-rb-security, com app completo e endpoint com
    `authenticate :signature`: um body grande responde 413 em
    `application/problem+json`.
- **Dependências:** nenhuma.

## Task 2: namespaces únicos entre projetos

- **Arquivos:**
  - `gems/boto-rb/lib/boto/solution/botofile.rb`: o `check_project` recusa um
    projeto cujo `namespace_name` já pertence a outro, com a mensagem
    `project "foo__bar" has the same namespace FooBar as project "foo_bar"`, o
    arquivo e a linha. A checagem roda no parse, antes de qualquer loader.
  - `gems/boto-rb/test/boto/solution/botofile_test.rb`.
- **Testes:**
  - `foo_bar` e `foo__bar` são recusados, e a mensagem cita os dois;
  - `foo_1bar` e `foo1bar` também;
  - nomes com namespaces distintos (`foo_bar` e `foobar`, que viram `FooBar` e
    `Foobar`) continuam válidos.
- **Dependências:** nenhuma.

## Task 3: estado de compilação e nomes de campos dos schemas

- **Arquivos:**
  - `gems/boto-rb/lib/boto/schema.rb`:
    - o `compile!` limpa o `@compiling` num `ensure`. Uma falha deixa o schema
      como não compilado, e uma nova chamada tenta compilar de novo e repete o
      erro, em vez de cair em recursão;
    - o `fields.freeze` só acontece depois que a compilação dá certo;
    - além da lista atual, o `field` recusa nomes que já são métodos públicos
      de `Boto::Schema` (ou seja, de `Object`: `object_id`, `send`, `method`,
      `dup`...), `initialize` e nomes que começam com `__boto`, prefixo dos
      métodos gerados.
  - `gems/boto-rb/test/boto/schema_test.rb`.
- **Testes:**
  - falha na compilação de um schema aninhado: o pai não fica compilado, e a
    segunda chamada repete o erro;
  - falha na geração de código: a segunda chamada repete o erro, sem
    `SystemStackError`, e `serialize` lança o erro original;
  - recompilação depois de corrigir a causa compila normalmente;
  - `object_id`, `send`, `initialize` e `__boto_x` são recusados;
  - `end` e `if` continuam aceitos e serializam.
- **Dependências:** nenhuma.

## Execução

As três tasks não têm arquivos em comum e rodam em paralelo, cada uma num
subagente Haiku. Depois, reviso cada diff, rodo as suítes com e sem YJIT e faço
um commit por task. A Task 3 mexe no schema, mas não no caminho por request,
então não precisa de benchmark.

Comando: `cd gems/<gem> && bundle exec rake test`, com e sem
`RUBY_YJIT_ENABLE=1`.

## Resultado

- Task 1: `cf77d24`. Task 2: `4ae8804`. Task 3: `9f493e4`.
- Pendente: namespaces que já existem no Ruby ou em gems (`kernel` -> `Kernel`); métodos privados do Kernel (`format`, `open`, `select`) seguem aceitos como nome de campo, porque não colidem com o código gerado.
