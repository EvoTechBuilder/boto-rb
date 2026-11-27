# 0022 — `boto plugin new`: gerar uma gem que estende o Boto

Status: **implementada**

Depende da 0021 (templates como gems), por causa do `--template`.

## Problema

- Criar uma gem que estende o Boto, com um plugin do `app.use` ou um template
  de projeto, exige copiar à mão o molde das gems oficiais:
  - gemspec e Zeitwerk com `for_gem_extension(Boto)`;
  - `version.rb` e a estrutura de testes;
  - o caminho que o `app.use` e a descoberta de templates esperam.
- Um detalhe errado faz a gem simplesmente não ser encontrada. Por exemplo: o
  arquivo fora de `lib/boto/plugins/`, ou o `template.rb` fora de
  `lib/boto/templates/<nome>/`.

## API pública

```bash
boto plugin new boto-rb-gateway --plugin gateway --template gateway
boto plugin new acme-boto-audit --plugin audit        # gem de terceiros, só com um plugin
boto plugin new boto-rb-helpers                       # só a gem base (biblioteca de apoio)
```

```
boto-rb-gateway/
├── boto-rb-gateway.gemspec        # depende de boto-rb (~> versão do CLI), MIT, Ruby >= 3.4
├── Gemfile
├── Rakefile                       # rake test
├── LICENSE
├── README.md                      # como instalar e usar (app.use / boto add)
├── CHANGELOG.md
├── .gitignore
├── lib/boto/
│   ├── gateway.rb                 # Zeitwerk.for_gem_extension(Boto), ignorando lib/boto/templates/ + module Boto::Gateway
│   ├── gateway/version.rb         # Boto::Gateway::VERSION = "0.1.0"
│   ├── plugins/gateway.rb         # --plugin gateway: Boto::Plugins::Gateway < Boto::Plugin
│   └── templates/gateway/         # --template gateway
│       ├── template.rb            # Boto::Template.define :gateway { folder "apps"; http true; files ... }
│       └── files/
│           ├── config/app.rb.erb
│           └── test/test_helper.rb.erb
└── test/
    ├── test_helper.rb
    ├── boto/plugins/gateway_test.rb    # flunk até ser escrito (como o boto generate)
    └── boto/templates/gateway_test.rb  # o template é descoberto e gera os arquivos (passa de saída)
```

- **Nome da extensão:**
  - vem do nome da gem, sem os prefixos `boto-rb-` ou `boto-`
    (`boto-rb-gateway` vira `gateway`, `boto-audit` vira `audit`);
  - `--name <nome>` sobrescreve;
  - define o módulo (`Boto::Gateway`) e o arquivo de entrada
    (`lib/boto/gateway.rb`).
- **`--plugin <nome>`:**
  - gera `Boto::Plugins::<Nome>`, com `configure`, `call` repassando para o
    app e os ganchos `start`, `stop`, `drain` e `health_checks` comentados;
  - o `app.use :<nome>` encontra o plugin sozinho, porque o core faz
    `require "boto/<nome>"`.
  - Atenção: o `require` usa o nome do plugin, então o arquivo de entrada da
    gem também se chama `boto/<nome do plugin>.rb` quando ele difere do nome
    da extensão. O gerador cria esse arquivo para fazer o `require` da
    entrada.
- **`--template <nome>`:**
  - gera o `template.rb` e um `files/` mínimo;
  - o padrão é `folder "apps"` e `http false`, e `--http` e
    `--folder libs|apps|workers` ajustam;
  - o teste gerado confere a descoberta (`Boto::Templates.fetch(:<nome>)`).
- **Validação:**
  - nome da gem com o formato do RubyGems (`\A[a-z0-9][a-z0-9_-]*\z`);
  - nomes de plugin e template com o formato do `app.use`
    (`\A[a-z][a-z0-9_]*\z`);
  - plugin ou template com nome reservado (`health`, `openapi`, `webapi`,
    `library`...) gera um aviso, não um erro, porque pode ser uma
    substituição intencional de plugin;
  - pasta que já existe é erro.
- **Zeitwerk:** o arquivo de entrada ignora `lib/boto/templates/`. Os
  `template.rb` são scripts de declaração, carregados pelo registro, e não
  constantes.
- **Fora de uma solution:** como o `boto new`, não precisa de Botofile. Dentro
  de uma, gera na pasta atual do mesmo jeito.
- **Saída:** `create <caminho>` para cada arquivo, e no fim
  `Next: cd boto-rb-gateway && bundle install && bundle exec rake test`.

## Estrutura

```
gems/boto-rb-cli/lib/boto/cli/commands/plugin.rb        # boto plugin new (subcomando, como boto db)
gems/boto-rb-cli/lib/boto/cli/support/extension_name.rb # gem -> extensão -> módulo, com as validações
gems/boto-rb-cli/templates/plugin/{base,plugin,template}/   # .erb de cada parte
```

- **Partes compostas:** a base é sempre gerada, e `plugin` e `template`
  entram só quando pedidos. É o mesmo `Generator` do `boto new`, com três
  diretórios de origem.

## Fase do roadmap

Fase 2, junto da 0021. É o que vai gerar a `boto-rb-gateway` (0023).

## Performance

Nada muda em runtime: é só o CLI escrevendo arquivos.

## Segurança

- **Nada é executado nem baixado:** não há `bundle install` nem `git init`,
  só arquivos escritos.
- **Caminhos:** tudo fica dentro da pasta nova, e os nomes validados não
  carregam `/` nem `..`.

## Compatibilidade

- **Minor, aditiva:** comando novo.
- **CHANGELOG:** Added `boto plugin new`.

## Testes planejados

- **`ExtensionName`:**
  - remoção de prefixos;
  - `--name`;
  - módulo em CamelCase;
  - nomes inválidos.
- **Gem base:** gerada e com o conteúdo esperado.
- **`--plugin`, `--template` e os dois juntos:** os arquivos certos são
  gerados, e `--http` e `--folder` mudam o `template.rb`.
- **Integração:**
  - a gem gerada roda a própria suíte (`bundle exec rake test`, apontando o
    Gemfile para o `boto-rb` local);
  - o teste do template passa;
  - o teste do plugin falha pelo `flunk`.
- **A gem gerada numa solution:**
  - `app.use :<plugin>` encontra o plugin;
  - `boto templates list` mostra o template;
  - `boto add <template>` gera o projeto.
- **Erros:**
  - pasta existente;
  - nome inválido;
  - aviso de nome reservado.

## Alternativas descartadas

- **Chamar o comando de `boto extension new` ou `boto gem new`:** "plugin" é o
  termo que a comunidade Ruby já usa (`rails plugin new`), mesmo para uma gem
  que só traz um template.
- **Rodar o `bundle gem` e ajustar o resultado:** o esqueleto dele não segue o
  molde das gems do Boto (Zeitwerk, `lib/boto/`), e o resultado varia com a
  versão do Bundler.
- **Gerar o CI e a publicação (GitHub Actions):** cada autor publica do seu
  jeito. Pode virar uma opção depois.
