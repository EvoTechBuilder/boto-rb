---
paths:
  - "gems/**/*.rb"
  - "examples/**/*.rb"
  - "benchmarks/**/*.rb"
---

# Código limpo e testável

## Nomes

- Pastas, arquivos, classes, métodos, variáveis e chaves de config ficam em
  inglês. Comentários e documentação podem ser em português.
- O nome diz a intenção (`resolve_route`, não `process`). Sem abreviações
  obscuras.

## Estrutura

- Cada classe tem uma responsabilidade e cada método faz uma coisa. Se um
  método passar de ~10 linhas ou uma classe de ~100, avalie dividir.
- Use guard clauses no lugar de `if` aninhado.
- Sem números ou strings mágicas: use constantes com nome.
- Sem código morto, código comentado ou abstração "para depois".
- Comente só o porquê que o código não mostra.

## Testável

- Dependências entram por argumento ou construtor, com um default razoável:
  relógio (`clock: Time`), env (`env: ENV`), IO, clientes HTTP, filas.
- Nada de estado global mutável. A única porta de entrada é
  `Boto.configure`, e o que ela produz é imutável depois do boot.
- Separe a lógica pura dos efeitos colaterais. A regra de negócio não faz IO
  direto.
- Todo comportamento público pode ser testado sem subir servidor nem acessar
  rede.
- Se algo é difícil de testar, a correção é no design, não em mais mocks.
