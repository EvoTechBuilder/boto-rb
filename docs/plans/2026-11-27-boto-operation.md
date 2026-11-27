# `Boto::Operation` e `Result` (proposta 0017)

Status: **concluído**

## Objetivo

Criar a classe base das operations no core, com o `Result` como retorno
padrão do `.call`. Um endpoint que devolve um `Result` tem a falha traduzida
para HTTP, e o `boto generate operation` passa a gerar a subclasse.

## Fora de escopo

- Validação de input na operation.
- Capturar exceções.
- Uso do `Result` em jobs: o template `worker` ainda não existe.

## Task 1: `Boto::Operation`, `Result`, `Failure` e `FailedError` (core)

- **Arquivos:**
  - `gems/boto-rb/lib/boto/operation.rb`;
  - `gems/boto-rb/lib/boto/operation/result.rb`, `failure.rb` e
    `failed_error.rb`;
  - `gems/boto-rb/test/boto/operation_test.rb` e
    `gems/boto-rb/test/boto/operation/result_test.rb`.
- **Testes:** os da proposta para `.call`, `new` privado, erros da operation
  e `Result`, incluindo o pattern matching e o `value!`.
- **Dependências:** nenhuma.
- **Comando:** `cd gems/boto-rb && bundle exec rake test`.

## Task 2: endpoint que devolve `Result` (core)

- **Arquivos:**
  - `gems/boto-rb/lib/boto/http/app.rb`:
    - o `success_response` reconhece `Boto::Operation::Result`;
    - um sucesso segue com o `value`;
    - uma falha responde problem+json, com o status escolhido pelo mapa de
      códigos;
  - `gems/boto-rb/lib/boto/http/problem.rb`: o `response` aceita `code:`, que
    entra na resposta só quando é passado;
  - testes em `gems/boto-rb/test/boto/http/`.
- **Testes:**
  - sucesso com `returns` e `status`;
  - cada `code` do mapa;
  - código desconhecido vira 422;
  - a resposta tem `detail` e `code`, e não tem `details`;
  - endpoints sem `Result` não mudam.
- **Dependências:** Task 1.
- **Comando:** `cd gems/boto-rb && bundle exec rake test`.

## Task 3: gerador de operation (CLI)

- **Arquivos:**
  - `gems/boto-rb-cli/templates/generate/operation/file.rb.erb` e
    `test.rb.erb`: geram a subclasse e o teste da proposta;
  - `gems/boto-rb-cli/test/boto/cli/commands/generate_test.rb`.
- **Testes:**
  - o conteúdo gerado;
  - o `Boot` carrega o projeto com a operation gerada;
  - chamar a operation gerada levanta `NotImplementedError`.
- **Dependências:** Task 1. Roda em paralelo com a Task 2.
- **Comando:** `cd gems/boto-rb-cli && bundle exec rake test`.

## Fechamento (eu)

- CHANGELOG, README (seção de operations e `Result`) e CLAUDE.md
  (`operations/` com `Boto::Operation`).
- Suítes com e sem YJIT.
- `benchmarks/allocations.rb`: `hello` e `db` com as mesmas alocações.
- De ponta a ponta: uma operation com `failure(:conflict)` chamada por um
  endpoint responde 409 com `code` no `boto run`.
