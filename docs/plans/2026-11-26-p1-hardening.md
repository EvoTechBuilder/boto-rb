# Melhorias P1: OpenAPI, imutabilidade, constraints e Boot

Status: **concluído**

## Objetivo

Quatro melhorias independentes, cada uma com seus testes e seu commit. A Task
1 segue a proposta 0008, porque adiciona API pública aos plugins.

## O que a verificação encontrou

- **OpenAPI:** confirmado. Só 422, 404 e 401 são documentados, e a repetição
  já é evitada com `uniq`.
  - O core produz 400 e 413 sempre que lê o body (`body` ou params fora do
    path).
  - Os plugins não têm como dizer ao core quais códigos produzem.
  - O 405 fica de fora: é resposta do path, não da operação (proposta 0008).
- **Imutabilidade:** confirmado, e pior do que o relatório diz:
  - api_key, basic e bearer fazem `dup.freeze` raso: as Strings continuam
    sendo as do chamador;
  - o jwt faz `algorithms.freeze` no próprio Array do chamador, ou seja,
    congela um objeto que não é dele;
  - a signature guarda o `secret` do chamador sem copiar;
  - o jwt guarda o `secret` do chamador sem copiar.
- **Constraints:** confirmado. Testei e hoje são aceitos:
  - `Integer, min: 10, max: 1`;
  - `String, min: 1, max: 0`;
  - `Integer, min: Float::NAN`;
  - `Float, min: Float::INFINITY, max: 1`;
  - `Integer, enum: [1, 1]`.

  Um `enum` com valores fora de `min`/`max` (por exemplo
  `enum: [1, 2], min: 5`) também passa. Já são recusados: `enum: []`, `enum`
  com tipo errado, `pattern` sem Regexp e `min` em Boolean.
- **Boot:** confirmado.
  - Uma falha no `eager_load` deixa os loaders preparados no `@loaders`.
  - No `shutdown`, um `unload` que falha interrompe os outros e o Hash não é
    limpo.
  - O `ProjectLoader#unload` só faz `unregister` se o `unload` passar.

## Fora de escopo

- Tornar o limite de payload configurável.
- Mudar a forma como os plugins recebem opções.

## Task 1: erros de plugins e do core no OpenAPI (proposta 0008)

- **Arquivos:**
  - `gems/boto-rb/lib/boto/plugin.rb`;
  - `gems/boto-rb/lib/boto/http/app.rb`;
  - `gems/boto-rb/lib/boto/openapi.rb`;
  - `gems/boto-rb/lib/boto/openapi/operation.rb`;
  - `gems/boto-rb-security/lib/boto/plugins/auth.rb`;
  - `gems/boto-rb-security/lib/boto/plugins/auth/signature.rb`;
  - `gems/boto-rb-security/lib/boto/plugins/rate_limit.rb`;
  - `gems/boto-rb-redis/lib/boto/redis/rate_limit_store.rb`;
  - os testes espelhados.
- **Testes:** os da proposta 0008.
- **Dependências:** nenhuma. É a única task que toca o `app.rb` e o OpenAPI.

## Task 2: cópias congeladas nas configurações de auth

- **Arquivos:**
  - `gems/boto-rb-security/lib/boto/security/secrets.rb`: um helper
    `Secrets.frozen_copy(value)` copia e congela Strings, Arrays e Hashes de
    forma recursiva, sem tocar no objeto do chamador;
  - as cinco estratégias em `gems/boto-rb-security/lib/boto/plugins/auth/`
    passam a guardar só cópias congeladas: chaves, credenciais, tokens,
    algoritmos, secrets, header e prefix. O que vem de lambda já é resolvido
    uma vez no boot, pelo `Secrets.resolve`, e também passa pela cópia;
  - os testes de cada estratégia.
- **Testes:**
  - depois da configuração, alterar o Hash, o Array ou a String original não
    muda a autenticação;
  - o jwt não congela o Array do chamador;
  - o valor vindo de uma lambda também fica congelado.
- **Dependências:** nenhuma. Ela toca a `signature.rb`, que a Task 1 também
  altera, mas em métodos diferentes. Mesmo assim, faço o commit de uma antes
  de revisar a outra.

## Task 3: validação de constraints no boot

- **Arquivos:**
  - `gems/boto-rb/lib/boto/types/constraints.rb`;
  - `gems/boto-rb/test/boto/types/constraints_test.rb`, ou o teste já
    existente dessa área.
- **Regras novas, que falham no boot com `ArgumentError`:**
  - `min > max`;
  - `min` ou `max` NaN ou infinito;
  - em String e listas, `min` e `max` precisam ser Integer maiores ou iguais a
    zero;
  - `enum` com valores repetidos;
  - `enum` com algum valor que viola `min`, `max` ou `pattern`, ou seja, um
    valor que nunca seria aceito.
- **Testes:**
  - `min < max` e `min == max` passam;
  - `min > max`, NaN e infinito falham;
  - tamanho negativo ou fracionário falha;
  - `enum` repetido ou fora dos limites falha;
  - os casos que já são recusados continuam recusados.
- **Dependências:** nenhuma.

## Task 4: rollback no boot e shutdown resiliente

O contrato segue o lifecycle da 0007: falha no boot desfaz o que foi feito, e
uma falha ao encerrar é registrada e não impede o resto.

- **Arquivos:**
  - `gems/boto-rb/lib/boto/solution/project_loader.rb`: o `unload` faz o
    `unregister` num `ensure`;
  - `gems/boto-rb/lib/boto/solution/boot.rb`:
    - `load` desfaz os loaders que ele mesmo criou nessa chamada (`unload` e
      remoção do `@loaders`) quando o `setup` ou o `eager_load` falham, e
      relança o erro. Os loaders que já existiam antes da chamada ficam
      intactos;
    - `shutdown` tenta descarregar todos os loaders, registra cada falha no
      `warn_output` e limpa o `@loaders` sempre. Ele é idempotente;
    - depois de uma falha, o mesmo `Boot` consegue carregar de novo quando a
      causa some.
  - `gems/boto-rb/test/boto/solution/boot_test.rb` e
    `gems/boto-rb/test/boto/solution/project_loader_test.rb`.
- **Testes:**
  - falha no `setup`;
  - falha no `eager_load`, com fixture de código quebrado: os loaders novos
    são desfeitos e os antigos ficam;
  - falha num `unload`: os outros ainda descarregam e o erro vai para o
    `warn_output`;
  - `shutdown` chamado duas vezes;
  - `load` de novo depois de uma falha.
- **Dependências:** nenhuma. Ela toca o `boot.rb`, mas nenhuma outra task
  mexe nele.

## Execução

As tasks 1, 2, 3 e 4 rodam em paralelo, cada uma num subagente Haiku. Elas não
dividem arquivos de código, a não ser a `signature.rb` (tasks 1 e 2), que é
alterada em métodos diferentes. No fechamento:

- rodo as quatro suítes com e sem YJIT;
- atualizo o CHANGELOG;
- marco a 0008 como implementada.

Nenhuma task toca o caminho por request.

## Resultado

- Task 1 (OpenAPI): commit `feat: document core and plugin errors in openapi`. Task 2: `971837b`. Task 3: `b5c0422`. Task 4: `e0919ab`.
- Pendente: depois de um `eager_load` que falha, uma constante do projeto pode seguir definida mesmo após o unload (comportamento anterior, contornado no teardown do teste).
