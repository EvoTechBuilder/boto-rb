# 0008 — Erros de plugins e do core no OpenAPI

Status: **implementada**

## Problema

O `Boto::OpenAPI::Operation#implicit_error_codes` documenta só três códigos:

- 422, quando o endpoint valida entrada;
- 404, quando a rota tem parâmetro de path;
- 401, quando há `:auth`.

Outras respostas que o próprio framework produz ficam de fora:

- **400 (core):** JSON inválido ou body que não é objeto, sempre que o
  endpoint lê o body.
- **413 (core):** body acima do limite.
- **413 (Signature):** a estratégia lê o body antes do endpoint.
- **429 (`:rate_limit`).**
- **503 (`:rate_limit`):** quando a store falha com `on_error: :deny`.

Hoje o core não tem como saber quais códigos um plugin produz, porque os
plugins vivem em outras gems.

## API pública

```ruby
class Boto::Plugins::RateLimit < Boto::Plugin
  # Statuses this plugin can answer for an endpoint it guards; documented by OpenAPI.
  def error_statuses = [429, *@store_error_statuses]
end
```

- **`Boto::Plugin#error_statuses`:** devolve `[]` por padrão. Cada plugin
  declara os códigos que pode responder num endpoint que ele guarda.
- **`Boto::App#plugins_for(endpoint)`:** novo, público. Lista os plugins que
  rodam naquele endpoint: os globais, os de endpoint que não foram pulados com
  `skip` e o `:auth` próprio de `authenticate`.
- O `Operation` passa a juntar:
  - os erros declarados com `errors`;
  - os implícitos do core: 422, 404 e, quando o endpoint lê o body (tem `body`
    ou params fora do path), 400 e 413;
  - os `error_statuses` dos plugins do endpoint.

  O resultado continua sem repetição e ordenado, como já é hoje.

### Códigos de cada plugin

| Plugin | `error_statuses` |
|---|---|
| `:auth` | `401` + os da estratégia (`:signature` → `413`) |
| `:rate_limit` | `429` + os da store (`RateLimitStore` com `on_error: :deny` → `503`) |
| `:hosts`, `:cors` | `[]` |

O `:hosts` e o `:cors` ficam vazios de propósito. O 403 deles aparece quando o
host é inválido ou quando o preflight é recusado. São erros de configuração ou
do `OPTIONS`, não do contrato de cada operação.

O 405 também fica de fora. Ele é uma resposta do *path* para um verbo que não
existe, e nunca da operação documentada.

## Estrutura

```
gems/boto-rb/lib/boto/plugin.rb                      # error_statuses padrão
gems/boto-rb/lib/boto/http/app.rb                     # plugins_for(endpoint)
gems/boto-rb/lib/boto/openapi.rb                      # passa os plugins ao Operation
gems/boto-rb/lib/boto/openapi/operation.rb            # 400/413 e error_statuses dos plugins
gems/boto-rb-security/lib/boto/plugins/auth.rb        # 401 + estratégia
gems/boto-rb-security/lib/boto/plugins/auth/signature.rb   # 413
gems/boto-rb-security/lib/boto/plugins/rate_limit.rb  # 429 + store
gems/boto-rb-redis/lib/boto/redis/rate_limit_store.rb # 503 com on_error: :deny
```

## Fase do roadmap

Completa o OpenAPI da Fase 1. Ela importa já, porque o cliente TypeScript da
Fase 3 vai ser gerado a partir desse documento.

## Performance

Nada muda por request. O documento é gerado uma vez, no boot (em
desenvolvimento) ou no `boto openapi`.

## Segurança

Não muda o comportamento. Só documenta respostas que já existem.

## Compatibilidade

- O documento gerado ganha respostas novas, e um cliente gerado a partir dele
  passa a conhecer esses erros.
- **CHANGELOG:**
  - `Added`: `Plugin#error_statuses` e `App#plugins_for`;
  - `Changed`: o OpenAPI documenta 400, 413, 429 e 503 quando eles se aplicam.

## Testes planejados

- endpoint com `body` documenta 400, 413 e 422;
- endpoint só com path param documenta 404, sem 400 e 413;
- `:auth` bearer documenta 401, e `:signature` documenta 401 e 413;
- endpoint com `:rate_limit` documenta 429, e com `skip :rate_limit` não
  documenta;
- `:rate_limit` com store Redis `on_error: :deny` documenta 503, e com
  `:allow` não;
- `errors 429` declarado junto do `:rate_limit` aparece uma vez só.

## Alternativas descartadas

- **Lista fixa de códigos no core por nome de plugin:** o core passaria a
  conhecer plugins de outras gems e não cobriria plugins de terceiros.
- **Documentar 405:** não é resposta da operação.
- **Exigir `errors` manual:** é o que já existe, e a documentação diverge do
  comportamento real.
