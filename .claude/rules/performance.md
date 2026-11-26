---
paths:
  - "gems/boto/lib/**/*.rb"
---

# Caminho quente do core

O core está no caminho de cada request, e o benchmark no CI falha se a
performance piorar.

- Resolva no boot tudo o que puder: compilar rotas, ler a declaração dos
  params, montar a pilha de middlewares, criar os serializadores dos schemas.
- Em tempo de request, não use `define_method`, `method_missing`,
  `instance_variable_get`/`set`, `send` com nome dinâmico nem `Class.new`.
- Evite alocar objetos por request: congele strings e hashes constantes,
  reaproveite objetos imutáveis e não crie arrays ou hashes intermediários
  que poderiam ser evitados.
- Não use exceção para controle de fluxo no caminho normal (rota não
  encontrada, param inválido).
- Antes de mudar roteador, dispatch, params ou serialização, rode a skill
  `benchmark` antes e depois da mudança e informe a diferença.
