# 0020 — Carregar arquivos `.env` automaticamente

Status: **implementada**

Complementa a 0019 (configuração por ambiente).

## Problema

- Hoje os segredos e as URLs só chegam por variáveis exportadas no shell
  (`export DATABASE_URL=...`) ou pelo orquestrador. No dia a dia, cada dev
  precisa lembrar de exportá-las antes do `boto run`.
- O costume do ecossistema é deixar esses valores em arquivos `.env`, fora do
  git, mas o Boto não os lê.
- **Armadilha do `boto run`:** a solution roda num processo só, com um `ENV`
  só. Se cada projeto carregasse o seu `.env` direto no `ENV`, um
  `DATABASE_URL` sobrescreveria o outro, e um serviço passaria a falar com o
  banco do vizinho.

## API pública

### Onde ficam os arquivos

```
loja/
├── .env                         # da solution: compartilhado por todos os projetos
├── .env.local
├── .env.development
├── .env.development.local
└── apps/
    ├── catalogo/
    │   ├── .env                 # do projeto: só o catalogo enxerga
    │   └── .env.development.local
    └── pedidos/
        └── .env
```

### Ordem de precedência

O primeiro que tiver a chave vence:

| # | Fonte | Observação |
|---|---|---|
| 1 | variáveis já exportadas no processo (shell, CI, orquestrador) | nunca são sobrescritas por arquivo |
| 2 | `.env.<env>.local` | |
| 3 | `.env.local` | **não é lido no `test`**, para os testes não dependerem da máquina |
| 4 | `.env.<env>` | |
| 5 | `.env` | |

Os arquivos são lidos nos dois níveis. Para o projeto, a busca é: processo,
arquivos do projeto (de 2 a 5) e, por último, arquivos da solution (de 2 a 5).

### Como ler os valores: `app.env`

```ruby
# apps/catalogo/config/app.rb
Boto.configure do |app|
  app.use :database, url: -> { app.env.fetch("DATABASE_URL") }
  app.use :auth, strategy: :bearer, tokens: -> { app.env.fetch("API_TOKENS").split(",") }
end
```

```bash
# loja/.env                       (compartilhado)
REDIS_URL=redis://localhost:6379/0

# loja/apps/catalogo/.env.development
DATABASE_URL=sqlite://db/catalogo_development.sqlite3

# loja/apps/pedidos/.env.development
DATABASE_URL=sqlite://db/pedidos_development.sqlite3
```

- **`app.env`:** um objeto só de leitura, por projeto, com `fetch`, `[]` e
  `key?`, que segue a precedência acima.
  - No exemplo, `catalogo` e `pedidos` recebem cada um o seu `DATABASE_URL`,
    mesmo no mesmo processo do `boto run`.
  - Um `fetch` sem a chave e sem default levanta `KeyError` com o nome da
    chave, no boot, como o `ENV.fetch`.
- **Arquivos da solution:** também vão para o `ENV` real, sem sobrescrever o
  que já existe. Assim gems de terceiros que leem o `ENV` direto (o `REDIS_URL`
  do exemplo) enxergam os valores.
- **Arquivos dos projetos:** **não** vão para o `ENV`, e é isso que evita a
  colisão. Quem precisa do valor lê pelo `app.env`.
- **`ENV.fetch` no `config/app.rb`:** continua funcionando e enxerga o
  processo e os arquivos da solution. Os templates passam a usar `app.env`.

### `app.env` no resto do projeto

O mesmo `app.env` fica disponível fora do `config/`:

```ruby
# endpoint
class Catalogo::Orders::Checkout < Boto::Endpoint
  post "/orders/:id/checkout"

  def call(id:) = { redirect_to: "#{app.env.fetch("FRONTEND_URL")}/orders/#{id}/done" }
end

# operation
class Catalogo::SendReceipt < Boto::Operation
  def call = Catalogo::Mailer.deliver(link: "#{app.env.fetch("FRONTEND_URL")}/receipts/#{input.id}")
end

# qualquer outro código do projeto (models, repositories, módulos próprios)
Catalogo.app.env.fetch("FRONTEND_URL")
```

- **`Catalogo.app`:** um objeto congelado do projeto, montado pelo `Boot`, com
  `env` (o `Boto::Env` acima), `env_name` e `name`.
  - O `Boot` o define no módulo do namespace (`Catalogo`), que já é criado por
    projeto.
  - É definido de novo a cada boot, inclusive no reload do `boto run`.
- **`app` no `Boto::Endpoint` e no `Boto::Operation`:** um método de instância
  que devolve o `app` do projeto dono da classe.
  - O projeto é resolvido uma vez por classe, pelo primeiro segmento do nome,
    e guardado. Não aloca nada por request.
  - **Por que `app.env`, e não só `env`:** no endpoint, `env` já é o env do
    Rack (o request), de onde saem o `principal` e os headers. Reaproveitar o
    nome confundiria os dois.
- **Por que não um `Boto.env` global:** no `boto run` a solution roda num
  processo só. Um global teria de adivinhar de qual projeto é o código que
  chama, e os valores voltariam a se misturar. Pelo namespace, cada projeto
  enxerga só o seu.
- **Isolamento:**
  - `Pedidos.app` dentro do `catalogo` é o uso de outro projeto, e o
    `boto check` aponta como qualquer outra constante;
  - uma `library` não tem `config/` nem `app` próprio, então recebe os valores
    de quem a chama, como argumento.
- **Em testes que chamam o `call` direto:** funciona, porque o `test_helper`
  gerado já faz o boot do projeto.

### Formato dos arquivos

```bash
# comentário
DATABASE_URL=postgres://user:pass@localhost/catalogo
export API_TOKENS=a,b,c                   # "export " é aceito e ignorado
GREETING="olá\nmundo"                     # aspas duplas: \n, \t, \" e \\ são interpretados
RAW='sem $interpolação'                   # aspas simples: texto literal
EMPTY=
```

- **Subconjunto do formato do `dotenv`:** `CHAVE=valor`, `export`,
  comentários, aspas simples e duplas e linhas em branco.
- **Sem interpolação (`${VAR}`) e sem substituição de comando (`$(...)`).**
  Ler um `.env` nunca executa nada.
- **Chave:** precisa casar com `\A[A-Za-z_][A-Za-z0-9_]*\z`. Uma linha
  inválida faz o boot falhar com `arquivo:linha`.
- **Arquivo ausente:** é ignorado. Nenhum arquivo é obrigatório.

### Quando é lido

- Em todo carregamento de configuração:
  - `boto run`, `boto test` e `boto openapi`;
  - `boto db` (0018);
  - o `Boot` usado em produção.
- O ambiente é o `BOTO_ENV`, validado como na 0019.
- **Reload do `boto run`:** os `.env` entram no watcher. Mudar um arquivo de
  projeto recarrega a solution. Mudar um da solution pede reiniciar, como o
  `Gemfile`, porque o `ENV` do processo já foi alterado.

### `.gitignore`

O `boto new` passa a gerar o `.gitignore` com todos os arquivos `.env`, na raiz
e nos projetos:

```gitignore
.env
.env.local
.env.*
!.env.example
```

- **`.env.example`:** fica de fora do ignore, de propósito. É o lugar para
  documentar as chaves sem os valores, e o único que vai para o git.
- **Solutions já existentes:** o `.gitignore` não é alterado, porque o CLI
  não mexe em arquivos do usuário. O CHANGELOG traz as linhas para copiar.

## Estrutura

```
gems/boto-rb/lib/boto/env.rb                 # Boto::Env: leitura só de leitura, com precedência e fetch/[]/key?
gems/boto-rb/lib/boto/env/parser.rb          # parser do subconjunto; erro com arquivo:linha
gems/boto-rb/lib/boto/env/files.rb           # lista de arquivos por nível e ambiente
gems/boto-rb/lib/boto/configuration.rb       # app.env
gems/boto-rb/lib/boto/project_context.rb     # Catalogo.app: env, env_name, name (congelado)
gems/boto-rb/lib/boto/endpoint/endpoint.rb   # #app, resolvido uma vez por classe
gems/boto-rb/lib/boto/operation.rb           # #app, idem
gems/boto-rb/lib/boto/solution/boot.rb       # carrega a solution no ENV e entrega o Env de cada projeto
gems/boto-rb-cli/lib/boto/cli/commands/run.rb        # .env* no watcher
gems/boto-rb-cli/templates/solution/.gitignore       # linhas acima
gems/boto-rb-cli/templates/webapi/config/            # app.env no lugar de ENV
```

- **Parser próprio, não a gem `dotenv`:**
  - o subconjunto cabe em poucas linhas;
  - evita uma dependência de runtime no core;
  - deixa de fora a substituição de comando, que o `dotenv` suporta e que
    executaria código ao ler um arquivo.

## Fase do roadmap

Fase 1, junto da 0019 e antes da 0018. As URLs do banco passam a vir do
`app.env`.

## Performance

- **Boot:** lê até oito arquivos pequenos, quatro por nível. É desprezível.
- **Por request:** nada para os plugins, porque as lambdas são lidas no
  boot. Um `app.env.fetch` num endpoint é uma busca num Hash congelado, sem
  alocação.

## Segurança

- **Nada é executado:** sem interpolação e sem substituição de comando.
- **O processo vence os arquivos:** um segredo injetado pelo orquestrador
  nunca é trocado por um arquivo esquecido no container.
- **Isolamento por projeto:** um projeto não lê o `.env` de outro, nem no
  `boto run`.
- **Fora do git:** o `.gitignore` gerado ignora todos os `.env`, exceto o
  `.env.example`.
- **Mensagens de erro:** citam o arquivo, a linha e a chave, nunca o valor.
- **`.env.local` fora do `test`:** um valor da máquina do dev não muda o
  resultado da suíte.

## Compatibilidade

- **Minor, aditiva:** sem arquivos `.env`, nada muda.
- **Única mudança de comportamento:** quem já tinha um `.env` na raiz passa a
  tê-lo lido. Variáveis já exportadas continuam vencendo.
- **CHANGELOG:**
  - Added: leitura de `.env`, `app.env` e o `.gitignore` novo;
  - para solutions existentes, as linhas para acrescentar ao `.gitignore`.

## Testes planejados

- **Parser:**
  - `CHAVE=valor`, `export`, comentários e linhas em branco;
  - aspas simples literais e aspas duplas com escapes;
  - valor vazio;
  - linha inválida dá erro com arquivo e linha, sem o valor;
  - `$(cmd)` e `${VAR}` ficam como texto.
- **Precedência:** cada linha da tabela, nos dois níveis, e o processo sempre
  vence.
- **`.env.local`:** é ignorado no `test`.
- **Isolamento:** dois projetos com o mesmo `DATABASE_URL` em arquivos
  diferentes recebem valores diferentes no mesmo processo.
- **`ENV` real:** recebe só os arquivos da solution, sem sobrescrever.
- **`app.env`:**
  - `fetch` sem a chave levanta `KeyError` com o nome;
  - o objeto é só de leitura.
- **`BOTO_ENV`:** um valor inválido é recusado antes de virar nome de arquivo.
- **`app` fora do config:**
  - `app.env` funciona no endpoint, na operation e em `Catalogo.app`;
  - dois projetos no mesmo processo enxergam valores diferentes;
  - o reload troca o `Catalogo.app`;
  - `env` no endpoint continua sendo o env do Rack;
  - não há alocação por request (a medição de alocações não muda).
- **`boto new`:** o `.gitignore` gerado tem as linhas, e o `git check-ignore`
  confirma que `.env.example` não é ignorado.
- **Reload:** um `.env` de projeto recarrega, e um da solution só avisa.

## Alternativas descartadas

- **Gem `dotenv`:** dependência no core e substituição de comando
  (`$(...)`), que executa código ao ler o arquivo.
- **Carregar os `.env` dos projetos no `ENV`:** colide no `boto run`, porque o
  último projeto sobrescreveria os outros.
- **Prefixar as chaves por projeto (`CATALOGO_DATABASE_URL`):** funciona, mas
  muda o nome da variável entre o dev e a produção, onde cada serviço espera
  `DATABASE_URL`.
- **Ler `.env.local` também no `test`:** testes passariam numa máquina e
  falhariam em outra.
- **Ignorar só os `*.local` e commitar o `.env.<env>`:** é comum, mas exige
  disciplina para nunca pôr segredo nele. Ignorar todos, com o
  `.env.example` versionado, é o default mais seguro.
