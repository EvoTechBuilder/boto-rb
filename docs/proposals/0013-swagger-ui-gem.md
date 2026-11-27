# 0013 — Gem `boto-rb-swaggerui`: Swagger UI como plugin

Status: **implementada**

Depende da proposta 0012 (`app.use :openapi`).

## Problema

- Com o `:openapi` (0012), o serviço publica o contrato em JSON. Para ler e
  testar a API no navegador, ainda é preciso subir uma UI externa e apontar
  para esse JSON.
- O Swagger UI pesa (JS e CSS, cerca de 1,5 MB) e não tem lugar no core. Por
  isso ele vem numa gem opcional, como o `boto-rb-redis`.

## API pública

### Uso

```ruby
# apps/pedidos/pedidos.gemspec (gerenciado pelo Boto) ou Gemfile da solution
spec.add_dependency "boto-rb-swaggerui"
```

```ruby
# apps/pedidos/config/app.rb
Boto.configure do |app|
  app.use :auth, strategy: :basic, credentials: -> { Boto.credentials.docs }
  app.use :openapi, version: "0.10.0"
  app.use :swagger_ui                    # GET /docs
end
```

```ruby
app.use :swagger_ui, path: "/api-docs"
```

### Opções

| Opção | Default | O que faz |
|---|---|---|
| `path:` | `"/docs"` | Caminho da página. Os arquivos ficam em `<path>/assets/`. |

- **O que o plugin serve:**
  - `GET <path>`: a página HTML, que carrega o documento do `:openapi`;
  - `GET <path>/assets/<versão>/...`: o JS e o CSS do Swagger UI, mais o
    script que inicia a UI.
- **O que a UI mostra:**
  - o documento do `path` do `:openapi`, sem configuração extra;
  - o título da página é o namespace do projeto.
- **Auth:** a página segue o `auth:` do `:openapi`. Se o documento exige
  credencial, a página também exige.
- **Falhas no boot, com mensagem clara:**
  - sem `app.use :openapi` no projeto: a UI não teria o que mostrar;
  - documento protegido por um `:auth` que não seja `:basic` (bearer, jwt,
    api_key, signature):
    - o navegador não manda esses headers sozinho, então a página abriria
      e não carregaria o documento;
    - a mensagem sugere `auth: false` no `:openapi` ou `strategy: :basic`;
  - `path:` sem `/` inicial, ou um endpoint `GET` no mesmo caminho.

## Estrutura

```
gems/boto-rb-swaggerui/
├── boto-rb-swaggerui.gemspec          # depende de boto-rb (mesma versão)
├── LICENSE                            # MIT, do Boto
├── Rakefile                           # test + vendor:update
├── lib/boto/swagger_ui.rb             # Zeitwerk for_gem_extension(Boto)
├── lib/boto/swagger_ui/version.rb     # Boto::SwaggerUi::VERSION (igual às outras gems)
├── lib/boto/swagger_ui/assets.rb      # lê os arquivos uma vez e congela
├── lib/boto/swagger_ui/page.rb        # monta o HTML da página
├── lib/boto/plugins/swagger_ui.rb     # Boto::Plugins::SwaggerUi, scope :global
├── vendor/swagger-ui/                 # swagger-ui.css, swagger-ui-bundle.js, LICENSE (Apache-2.0), VERSION
└── test/
```

- **Assets embutidos na gem, sem CDN:**
  - funciona sem internet e atrás de firewall;
  - o CSP pode ficar em `'self'`;
  - a versão do Swagger UI é fixa e entra no CHANGELOG.
- **Sem script inline:** a UI é iniciada por um `.js` próprio, servido pelo
  plugin. Assim o futuro `:secure_headers` não precisa de `unsafe-inline`.
- **`rake vendor:update[VERSION]`:**
  - baixa o `swagger-ui-dist` daquela versão do registro do npm;
  - confere o `integrity` (sha512) publicado no registro;
  - grava em `vendor/`.
  Rodar é manual, por quem mantém o Boto; nunca no build do usuário.
- **Ordem:** `:swagger_ui` entra no `Boto::Plugin::ORDER` logo depois de
  `:openapi`, como o `:rate_limit` já está lá mesmo morando em outra gem.
- **Repositório:**
  - `Gemfile` da raiz ganha `gemspec path: "gems/boto-rb-swaggerui"`;
  - a CI testa a gem nova na mesma matriz;
  - a publicação entra na lista do job `publish`, depois do `boto-rb`;
  - a versão acompanha as outras gems;
  - o CLAUDE.md ganha a gem na seção do repositório.

## Fase do roadmap

Fase 1 (OpenAPI e plugins), logo depois da 0012.

## Performance

- **Boot:**
  - lê os arquivos do `vendor/` uma vez e guarda as Strings congeladas;
  - monta o HTML uma vez.
- **Por request:** plugin global. Fora da rota, o custo é um
  `start_with?` no `PATH_INFO` e passa adiante. Nenhuma alocação.
- **Na rota:**
  - devolve as Strings prontas;
  - os assets usam `cache-control: public, max-age=31536000, immutable`,
    porque a URL leva a versão do Swagger UI.
- **Sem o plugin:** nada muda. A gem nem é carregada.

## Segurança

- **Superfície:** a página só mostra o que o `:openapi` já publica. Proteção
  e exposição seguem o mesmo `auth:`.
- **"Try it out":** os requests saem do navegador do usuário, com as
  credenciais que ele digitar, e passam pelo `:auth` e pelo `:rate_limit` de
  cada endpoint como qualquer outro request.
- **Path traversal:** os assets saem de uma lista fixa montada no boot. Um
  caminho fora dela responde 404, e o disco nunca é lido por request.
- **Origem dos assets:** vêm do npm, com o `integrity` conferido. O
  `swagger-ui-dist` é Apache-2.0, e a licença vai junto em `vendor/`.
- **XSS:** o título (namespace do projeto) e o caminho do documento entram no
  HTML escapados.

## Compatibilidade

- **Gem nova, minor:** não muda nada para quem não a instala.
- **CHANGELOG, seção Added:**
  - gem `boto-rb-swaggerui` com `app.use :swagger_ui` (`path:`), e a versão
    do Swagger UI embutida;
  - `:swagger_ui` no `Boto::Plugin::ORDER`.

## Testes planejados

- **Rotas:**
  - `GET` e `HEAD` da página e de cada asset;
  - `path:` customizado;
  - asset inexistente responde 404;
  - `../` no caminho responde 404;
  - outro path passa adiante.
- **Página:**
  - aponta para o `path` do `:openapi`;
  - não tem script inline;
  - o título vem escapado.
- **Assets:** `content-type` e `cache-control` corretos; lidos uma vez só, com
  o mesmo objeto em duas respostas.
- **Auth:**
  - com `:openapi` protegido por `:basic`, a página responde 401 sem
    credencial e 200 com a credencial certa;
  - com `auth: false`, abre sem credencial.
- **Boot:**
  - falha sem `:openapi`;
  - falha com `:openapi` protegido por bearer;
  - falha com `path:` inválido;
  - falha com um endpoint no mesmo caminho.
- **Vendor:** a versão em `vendor/swagger-ui/VERSION` aparece na URL dos
  assets. O `rake vendor:update` não roda no CI.

## Alternativas descartadas

- **Carregar o Swagger UI de CDN (unpkg, jsDelivr):**
  - depende de internet;
  - obriga o CSP a liberar um host externo;
  - a versão pode mudar sem aviso.
- **Gem `swagger-ui_rails` ou parecida:** amarrada ao Rails, e o Boto só fala
  Rack.
- **Redoc no lugar do Swagger UI:** não tem "Try it out", e o pedido foi
  Swagger UI. Pode virar outra gem no mesmo molde.
- **Repassar o bearer token pelo `requestInterceptor` da UI:** a página
  precisaria guardar o token no navegador. Melhor recusar no boot e deixar a
  escolha explícita.
- **UI ligada só em development:** quem quer a UI em produção teria de
  contornar. Quem não quer, basta não usar o plugin.
