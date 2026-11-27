# 0015 — `title:` e `description:` no `:openapi`, e topbar do Boto no Swagger UI

Status: **implementada** (logo: rubi próprio)

## Problema

- **Título e descrição fixos:**
  - o `:openapi` usa o nome do namespace do projeto (`Pedidos`) como
    `info.title`, sem opção para mudar;
  - não há `info.description`, então o Swagger UI mostra a API sem nenhum
    texto de apresentação.
- **Página sem topbar:** a página do `:swagger_ui` usa só o
  `SwaggerUIBundle`. Fica sem a barra superior com logo, campo de URL e botão
  "Explore". Ligar a barra padrão traria a marca do Swagger, e a página deve
  mostrar a identidade do framework.

## API pública

```ruby
# apps/pedidos/config/app.rb
app.use :openapi,
        title: "Pedidos API",
        description: "Pedidos, pagamentos e entregas da Loja.",
        version: "1.4.0"
app.use :swagger_ui
```

```json
{ "openapi": "3.1.0",
  "info": { "title": "Pedidos API", "description": "Pedidos, pagamentos e entregas da Loja.", "version": "1.4.0" } }
```

| Opção | Default | O que faz |
|---|---|---|
| `title:` | namespace do projeto (`"Pedidos"`) | `info.title`, e também o `<title>` da página do Swagger UI. |
| `description:` | nenhuma (campo omitido) | `info.description`. O Swagger UI renderiza o texto como Markdown abaixo do título. |

- **Validação:** uma String não vazia para `title:`, e String para
  `description:`. Outro valor falha no boot, como as demais opções.

### Swagger UI

```
┌──────────────────────────────────────────────────────────────────────────┐
│ [◆ logo do Ruby] Boto      [ /openapi.json                  ] [Explore] │
└──────────────────────────────────────────────────────────────────────────┘
  Pedidos API  1.4.0  OAS 3.1
  Pedidos, pagamentos e entregas da Loja.
```

- **Topbar:** a barra padrão do Swagger UI (`StandaloneLayout`), com o campo
  de URL preenchido com o documento do `:openapi` e o botão "Explore".
- **Marca:** no lugar do logo do Swagger, o logo do Ruby, seguido do nome
  **Boto**. A troca é feita por CSS num arquivo `boto.css`, servido pelo
  plugin como os outros assets, sem script inline.
- **Sem opção nova no `:swagger_ui`:** o título da página vem do `title:` do
  `:openapi`.

## Estrutura

```
gems/boto-rb/lib/boto/plugins/openapi.rb          # title:, description:
gems/boto-rb/lib/boto/openapi.rb                  # generate(app, title:, version:, description: nil)
gems/boto-rb-swaggerui/vendor/swagger-ui/         # + swagger-ui-standalone-preset.js (do mesmo pacote 5.36.0)
gems/boto-rb-swaggerui/assets/boto.css            # esconde o logo do Swagger, mostra logo do Ruby + "Boto"
gems/boto-rb-swaggerui/assets/ruby.svg            # rubi desenhado pelo Boto (gema vermelha), sem licença extra
gems/boto-rb-swaggerui/lib/boto/swagger_ui/page.rb    # carrega o preset e o boto.css; layout "StandaloneLayout"
gems/boto-rb-swaggerui/lib/boto/swagger_ui/assets.rb  # lista fixa ganha os arquivos novos
gems/boto-rb-swaggerui/lib/tasks/vendor.rake          # extrai também o standalone preset
```

- **`OpenAPI#title`:** fica público, para o `:swagger_ui` usar no `<title>`.
- **Assets do Boto em `assets/`, separados de `vendor/`:** o
  `rake vendor:update` substitui o `vendor/` inteiro, e o CSS e o logo do Boto
  não podem ser apagados nessa troca.

## Fase do roadmap

Complemento da Fase 1 (OpenAPI e plugins), nas propostas 0012 e 0013.

## Performance

- **Por request:** nada muda. Os arquivos novos entram na mesma tabela montada
  no boot, com cache `immutable`.
- **Documento:** continua gerado uma vez no `start`.
- **Página:** o `swagger-ui-standalone-preset.js` soma cerca de 230 KB na
  primeira carga e fica em cache depois.

## Segurança

- **Escape:** o `title:` e o `description:` entram no documento via
  `JSON.generate`. O `<title>` da página já é escapado com `CGI.escapeHTML`.
- **Markdown da descrição:** quem renderiza é o Swagger UI, que sanitiza o
  HTML (DOMPurify). O texto vem do `config/app.rb`, nunca do request.
- **Campo "Explore":** o usuário pode digitar outra URL. O navegador busca
  esse documento com as regras de CORS dele. O servidor do Boto não faz
  nenhum request por causa disso.

## Compatibilidade

- **Minor, sem quebra:** sem `title:`, o título continua o namespace, e sem
  `description:`, o campo não aparece.
- **Visual do `:swagger_ui`:** passa a ter a topbar, o que é uma mudança
  visível, mas não de API.
- **CHANGELOG, seção Added:**
  - `title:` e `description:` no `:openapi`;
  - topbar com a marca do Boto no `:swagger_ui`.

## Testes planejados

- **`:openapi`:**
  - `title:` e `description:` aparecem em `info`;
  - os defaults são o namespace como título, e nenhum `description`;
  - um título vazio, ou que não é String, falha no boot;
  - um `description:` que não é String falha no boot.
- **`Boto::OpenAPI.generate`:** inclui `description` só quando ele é passado.
- **`:swagger_ui`:**
  - a página carrega o preset, o `boto.css` e usa `StandaloneLayout`;
  - o `<title>` vem do `title:` do `:openapi`;
  - o `ruby.svg`, o `boto.css` e o preset respondem 200, com o
    content-type e o cache certos;
  - continua sem script inline.

## Decisão sua: o logo do Ruby

- **Opção A, logo oficial do Ruby (recomendo, porque foi o pedido):**
  - o SVG publicado em ruby-lang.org, sob CC BY-SA 2.5;
  - pode ser redistribuído com atribuição: um `NOTICE` em `assets/` credita
    "Ruby logo © Yukihiro Matsumoto, CC BY-SA 2.5";
  - exige baixar o arquivo uma vez de ruby-lang.org.
- **Opção B, um rubi desenhado por nós:**
  - um SVG simples, uma gema vermelha;
  - sem licença extra e sem download;
  - não é o logo oficial.

## Alternativas descartadas

- **Opções de marca no `:swagger_ui` (`logo:`, `name:`):** ninguém pediu ainda.
  A marca do framework é o padrão, e personalizar fica para quando houver
  demanda.
- **Trocar o logo por um plugin JS do Swagger UI:** mais código e um script a
  mais. O CSS resolve.
- **Topbar sem o campo "Explore":** a barra padrão já traz o campo, e é o que
  a referência mostra.
- **Mudar o título do `boto openapi` (CLI), que hoje usa o nome do projeto em
  minúsculas:** fica para outra mudança, com a opção `--title`.
