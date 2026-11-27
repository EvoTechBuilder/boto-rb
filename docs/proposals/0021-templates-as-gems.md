# 0021 — Templates distribuídos como gems

Status: **implementada**

Base para a `boto-rb-gateway` (proposta seguinte).

## Problema

A lista de templates está fixa em vários pontos do Boto:

| Onde | O que fixa |
|---|---|
| `Boto::Project::TEMPLATE_DIRS` (core) | os nomes aceitos no Botofile e a pasta de cada um |
| `Project::HTTP_TEMPLATES` (core) | quem tinha `services/` (legado) |
| `Commands::Add::TEMPLATES` (CLI) | o que o `boto add` gera |
| `Commands::Run::SERVABLE_TEMPLATES` e `Commands::Openapi::SERVABLE_TEMPLATES` (CLI) | quem o `boto run` sobe e quem tem OpenAPI |
| `BlueprintBuilder::LIBRARY_TEMPLATE` (CLI) | quem não aceita `boto g endpoint` |
| `gems/boto-rb-cli/templates/<nome>/` | os arquivos do esqueleto |

Com isso, uma gem de fora (como a `boto-rb-gateway`) não consegue oferecer um
template novo, e o `boto templates list | install` do roadmap não existe.

## API pública

### Para quem usa

```bash
# Gemfile da solution: gem "boto-rb-gateway"
bundle install

boto templates list
#   library     libs/   (boto-rb-cli 0.17.0)
#   webapi      apps/   http   (boto-rb-cli 0.17.0)
#   gateway     apps/   http   (boto-rb-gateway 0.17.0)

boto templates install boto-rb-gateway   # acrescenta gem "boto-rb-gateway" ao Gemfile e manda rodar bundle install
boto add gateway borda --refs catalogo,users
```

```ruby
# Botofile
project "borda", template: :gateway, refs: %w[catalogo users]
```

- O `boto add` ganha `--refs a,b`, que vale para qualquer template.

### Para quem escreve um template

```
boto-rb-gateway/
└── lib/boto/templates/gateway/
    ├── template.rb          # a declaração
    └── files/               # o esqueleto, com .erb como os oficiais
        ├── config/app.rb.erb
        └── test/test_helper.rb.erb
```

```ruby
# lib/boto/templates/gateway/template.rb
Boto::Template.define :gateway do |t|
  t.folder "apps"                       # onde o projeto nasce
  t.http true                           # o boto run sobe, tem endpoints e OpenAPI
  t.files File.join(__dir__, "files")   # o esqueleto
  t.summary "Single entry point for the solution's HTTP services"
end
```

- **Opções de `Boto::Template.define`:**
  - `folder` é obrigatório e precisa ser `apps`, `libs` ou `workers`, as
    pastas da solution;
  - `http` vale `false` por padrão;
  - `files` é opcional: um template sem arquivos é aceito no Botofile, mas o
    `boto add` não o gera;
  - `summary` é opcional.
- **Variáveis disponíveis no `.erb`:** `name`, `namespace`, `refs` (Array de
  nomes), `boto_version` e `template`.
- **Descoberta:** o Boto carrega todo
  `lib/boto/templates/*/template.rb` encontrado pelo
  `Gem.find_files("boto/templates/*/template.rb")`, ou seja, das gems do bundle
  (Gemfile). Não há registro manual.

### Templates oficiais

- `library` e `webapi` passam a ser declarados do mesmo jeito.
  - A **declaração** fica no core (`gems/boto-rb/lib/boto/templates/`), porque
    o Botofile é lido também sem o CLI, por exemplo no `test_helper` gerado.
  - Os **arquivos** ficam no CLI, ligados à declaração pelo nome.
- `microservice`, `worker`, `web` e `spa` continuam reservados no core, sem
  arquivos, até seus templates existirem.
- **Nomes oficiais são reservados.** Uma gem não pode redefini-los, e o boot
  falha com o nome da gem.

### Erros

- **Template desconhecido no Botofile:** a mensagem lista os disponíveis e
  sugere a gem, por exemplo `unknown template :gateway (available: library,
  webapi; is its gem in the Gemfile?)`.
- **Mesmo template em duas gems:** o boot falha e cita as duas gems.
- **`template.rb` inválido** (pasta desconhecida, sem `folder`, opção que não
  existe): o boot falha com o caminho do arquivo.
- **`boto add` de um template sem `files`:** sai com
  `template :worker has no files yet`.

## Estrutura

```
gems/boto-rb/lib/boto/template.rb                  # Boto::Template (Data) + Template.define (DSL)
gems/boto-rb/lib/boto/templates.rb                 # registro: oficiais, descoberta via Gem.find_files, lookup, erros
gems/boto-rb/lib/boto/templates/{library,webapi,microservice,worker,web,spa}/template.rb   # declarações oficiais, no mesmo formato das gems
gems/boto-rb/lib/boto/solution/project.rb          # path e legacy_path perguntam ao registro; TEMPLATE_DIRS sai
gems/boto-rb/lib/boto/solution/botofile.rb         # valida pelo registro
gems/boto-rb-cli/lib/boto/cli/support/generator.rb # recebe o diretório de arquivos do template
gems/boto-rb-cli/lib/boto/cli/commands/add.rb      # registro + --refs
gems/boto-rb-cli/lib/boto/cli/commands/run.rb      # http? no lugar de SERVABLE_TEMPLATES
gems/boto-rb-cli/lib/boto/cli/commands/openapi.rb  # idem
gems/boto-rb-cli/lib/boto/cli/support/blueprint_builder.rb  # endpoint só em template http
gems/boto-rb-cli/lib/boto/cli/commands/templates.rb         # boto templates list | install
```

- **`HTTP_TEMPLATES` e o legado `services/`:** viram uma flag interna das
  declarações oficiais (`legacy_services`), sem aparecer na API pública.
- **A descoberta roda uma vez por processo, na primeira consulta, e é
  congelada.** O reload do `boto run` não redescobre gems, porque gem nova
  exige reiniciar, como já acontece com o Gemfile.

## Fase do roadmap

Fase 2 ("sistema de templates como gems"). É a base do template `gateway`, e
também do `microservice` e do `worker`.

## Performance

- **Boot:** um `Gem.find_files` e o `require` de alguns arquivos pequenos, uma
  vez por processo.
- **Por request:** nada. Templates só importam no boot e no CLI.

## Segurança

- **Código de gem roda no boot:** é o mesmo modelo de confiança de qualquer
  gem do Gemfile. Só é descoberto o que está no bundle, e nada é baixado sem o
  usuário pedir.
- **`boto templates install`:** só acrescenta a linha ao Gemfile, nunca roda o
  `bundle install`, para o usuário ver o que entra. O nome da gem é validado
  (`\A[a-z0-9][a-z0-9_-]*\z`).
- **Arquivos de template:** são renderizados só dentro da pasta do novo
  projeto. Um caminho que tente sair dela (`..`) é recusado, como no
  `boto generate`.
- **Nomes oficiais reservados:** uma gem não substitui o `webapi`
  silenciosamente.

## Compatibilidade

- **Minor, sem quebra:** os nomes e as pastas dos templates atuais não mudam,
  e os Botofiles existentes continuam válidos.
- **`Boto::Project::TEMPLATE_DIRS` sai:** é interna, mas é uma constante
  pública. O CHANGELOG aponta o `Boto::Templates.fetch(:nome).folder` como
  substituto.
- **CHANGELOG:**
  - Added: `Boto::Template.define`, a descoberta por gems,
    `boto templates list | install` e `boto add --refs`;
  - Changed: `TEMPLATE_DIRS` deu lugar ao registro.

## Testes planejados

- **Registro:**
  - os oficiais estão presentes;
  - uma gem de teste (pasta no `$LOAD_PATH` com
    `boto/templates/x/template.rb`) é descoberta;
  - a mesma definição em duas fontes é erro;
  - redefinir um nome oficial é erro;
  - um `template.rb` inválido dá erro com o caminho;
  - a descoberta acontece uma vez só.
- **Botofile:**
  - um template de gem é aceito;
  - um template desconhecido dá a mensagem nova.
- **`Project#path`:** segue o `folder` do template.
- **`boto add`:**
  - gera a partir dos `files` de um template de gem, com as variáveis
    `name`, `namespace`, `refs` e `boto_version`;
  - `--refs` escreve as refs no Botofile e as valida;
  - um template sem `files` dá erro.
- **`boto run` e `boto openapi`:**
  - sobem os templates `http`;
  - um template de gem `http` é servido.
- **`boto g endpoint`:** é recusado em templates que não são `http`.
- **`boto templates`:**
  - `list` mostra nome, pasta, `http` e a gem de origem;
  - `install` acrescenta a linha ao Gemfile e recusa nome inválido ou já
    presente.
- **Suítes atuais:** passam sem mudança de comportamento.

## Alternativas descartadas

- **Registro manual (`Boto::Templates.register` no `config/app.rb` ou no
  Botofile):** cada solution teria de saber como ligar a gem. A descoberta por
  convenção de arquivo é o que o `dotnet new install` também oferece.
- **Templates como pastas copiadas para a solution (`.boto/templates/`):**
  ninguém atualizaria a versão, e cada solution teria uma cópia divergente.
- **Template declarado só no CLI:** o Botofile, lido também sem o CLI (no
  `test_helper` gerado), não reconheceria o template.
- **`boto templates install` rodando o `bundle install`:** é uma ação com
  efeito de rede. Basta mostrar o próximo passo.
- **Hooks de template (código depois do `boto add`):** ninguém precisa ainda,
  e seria mais código de terceiros rodando no CLI.
