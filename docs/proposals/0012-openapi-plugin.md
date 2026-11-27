# 0012 — Plugin `:openapi` para servir o documento em produção

Status: **implementada**

## Problema

- O `/openapi.json` só existe com `BOTO_ENV=development`. Em produção, a
  única saída é gerar o arquivo com `boto openapi` e publicar fora do
  serviço, ou escrever um endpoint à mão que leia esse arquivo.
- O endpoint à mão tem custos: o `JSON.generate` roda a cada request, o
  endpoint aparece no próprio documento, e o boot falha se ninguém gerou o
  arquivo no build.
- Falta uma forma declarada no projeto, como os outros plugins, de servir o
  contrato em produção com o mesmo `:auth` do resto da API.

## API pública

### Uso

```ruby
# apps/pedidos/config/app.rb
Boto.configure do |app|
  app.use :health
  app.use :auth, strategy: :bearer, token: -> { Boto.credentials.api_token }
  app.use :openapi                       # GET /openapi.json, protegido pelo :auth acima
end
```

```ruby
app.use :openapi, path: "/docs/openapi.json", version: "2.3.0"
app.use :openapi, auth: false            # documento público, mesmo com :auth no projeto
```

### Opções

| Opção | Default | O que faz |
|---|---|---|
| `path:` | `"/openapi.json"` | Caminho do documento. Precisa começar com `/`. |
| `version:` | `"0.0.0"` | `info.version` do documento (ex.: `version: "0.10.0"`). |
| `auth:` | `true` | Com `true`, o `:auth` declarado no projeto guarda a rota. Sem `:auth` no projeto, não muda nada. |

- Responde a `GET` e `HEAD`, com `content-type: application/json`.
- O documento é o mesmo do `boto openapi`: o título vem do namespace do
  projeto, e as respostas de erro dos plugins (`401` do `:auth`, `429` do
  `:rate_limit`) continuam documentadas.
- **Relação com a rota de development:**
  - sem o plugin, nada muda: o `/openapi.json` continua existindo só em
    development;
  - com o plugin, ele assume a rota em qualquer ambiente, com o `path:` e o
    `auth:` dele. Assim o dev vê o mesmo comportamento da produção.
- Opções inválidas falham no boot:
  - `path:` sem `/` inicial;
  - `version:` que não é String;
  - `auth:` que não é booleano;
  - um endpoint do projeto no mesmo `GET` do `path:`, que ficaria escondido
    pelo plugin.

## Estrutura

```
gems/boto-rb/lib/boto/plugins/openapi.rb     # Boto::Plugins::Openapi, scope :global
gems/boto-rb/lib/boto/plugin.rb              # ORDER ganha :openapi, entre :csrf e :auth
gems/boto-rb/lib/boto/http/app.rb            # a rota de development sai quando o plugin está ligado
gems/boto-rb/test/boto/plugins/openapi_test.rb
```

- **No core (`boto-rb`), não na `boto-rb-security`:** o gerador de OpenAPI
  já vive no core, e o plugin não é uma proteção. É o mesmo caso do
  `:health`.
- **`attach(app)`:**
  - guarda o app;
  - acha o `:auth` declarado no projeto, quando `auth: true`;
  - confere se algum endpoint colide com o `path:`.
- **Leitura para outros plugins:** `#path` e `#auth?` são públicos, para o
  `:swagger_ui` (proposta 0013) apontar para o documento.
- **`start`:** gera o JSON uma vez e congela. Roda depois do `attach` de todos
  os plugins, então os `error_statuses` já estão disponíveis.
- **`call(env, app)`:**
  - fora do `path:` ou do `GET`/`HEAD`, passa adiante;
  - com `:auth`, chama `auth.call(env, documento)`, então o mesmo
    `401` com `WWW-Authenticate` do resto da API vale aqui;
  - sem `:auth`, responde direto.

## Fase do roadmap

Fase 1 (OpenAPI e plugins). Fica pronto antes do template `spa` da Fase 3,
que pode buscar o contrato de um serviço já publicado.

## Performance

- **Boot:** gera o documento uma vez (o mesmo trabalho que o App já faz em
  development) e guarda a String congelada.
- **Por request:** como plugin global, roda antes do roteamento. O custo é uma
  comparação de String no `PATH_INFO` e passa adiante. Nenhuma alocação.
- **Na rota:** devolve a mesma String congelada; não serializa por request.
- Sem o plugin, o caminho quente não muda. O cenário `hello` do benchmark
  confirma isso.

## Segurança

- **O que vaza:** o documento mostra todas as rotas, params e schemas. Isso
  ajuda quem quer atacar a API, então servir é opt-in (`app.use`).
- **Default protegido:** com `auth: true`, a rota exige a mesma credencial do
  resto da API. Tornar público exige escrever `auth: false`.
- **Ordem:** fica depois de `:hosts`, `:cors` e `:secure_headers`. O Host
  continua validado, e a CORS e os headers de segurança valem para a resposta.
- **Sem `:rate_limit` (decidido):** o `:rate_limit` não guarda a rota,
  porque é plugin de endpoint. A resposta é uma String pronta, sem acesso a
  banco.
- **Endpoints com `skip :auth`:** aparecem no documento normalmente. O
  documento descreve a API, não altera quem tem acesso a ela.

## Compatibilidade

- **Minor, sem quebra:** quem não usa o plugin não vê diferença.
- **CHANGELOG, seção Added:**
  - `app.use :openapi` (core), com `path:`, `version:` e `auth:`;
  - `:openapi` entra no `Boto::Plugin::ORDER`, entre `:csrf` e `:auth`.

## Testes planejados

- **Rota:**
  - `GET` e `HEAD` no path padrão e num `path:` customizado;
  - `production` e `development` respondem igual;
  - outro path ou verbo passa adiante.
- **Documento:**
  - igual ao `Boto::OpenAPI.generate` do app, com o `version:` informado;
  - gerado uma vez: duas respostas devolvem o mesmo objeto.
- **Auth (casos de ataque):**
  - com `:auth` no projeto, sem token responde 401;
  - token errado responde 401;
  - token certo responde 200;
  - `auth: false` responde 200 sem token;
  - sem `:auth` no projeto, responde 200.
- **Boot:**
  - `path:` inválido falha;
  - `version:` inválido falha;
  - `auth:` inválido falha;
  - um endpoint `GET` no mesmo path falha, com o nome do endpoint.
- **App:** sem o plugin, a rota de development continua como está. Com o
  plugin, ela não responde em outro caminho.
- **Ordem:** com `:hosts`, um Host não permitido recebe 403 antes do
  documento.

## Alternativas descartadas

- **Ligar a rota de development em produção por env (`BOTO_OPENAPI=1`):**
  config escondida fora do `config/app.rb`, e sem `:auth`.
- **Opção `openapi:` no `Boto.configure`:** o projeto já liga recursos com
  `app.use`. Uma segunda forma pesa mais do que um plugin.
- **Exigir o endpoint escrito à mão:** repete o JSON a cada request, aparece no
  documento e não tem `:auth` por padrão.
- **Plugin na `boto-rb-security`:** o gerador é do core, e servir o documento
  não é uma proteção.
- **Swagger UI embutido no core:** HTML, JS e CSS pesam no core. A UI vira a
  gem `boto-rb-swaggerui` (proposta 0013), que lê o `path` e o `auth` deste
  plugin.
