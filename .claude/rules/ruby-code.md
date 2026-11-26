---
paths:
  - "gems/**/*.rb"
  - "gems/**/*.gemspec"
---

# Código Ruby das gems do Boto

- `# frozen_string_literal: true` no topo de todo arquivo `.rb`.
- Use só o que o Ruby 3.4 oferece (o mínimo do gemspec). Nada exclusivo do 4.0
  sem fallback.
- Nome de arquivo e constante seguem o Zeitwerk (`lib/boto/endpoint.rb` ->
  `Boto::Endpoint`). Não use `require` manual para código da própria gem.
- Não adicione dependência de runtime sem discutir antes. O core é mínimo, e o
  que for opcional vira plugin.
- Toda mudança de comportamento em `lib/` vem com teste em `test/`.
- Mudança na API pública (classes, métodos, DSL do Botofile ou do endpoint,
  comandos do CLI) entra no `CHANGELOG.md`, na seção `Unreleased`, e respeita
  semver.
- Erros vão para o cliente sempre em JSON, pelo mecanismo central do core.
  Nunca monte a resposta de erro à mão dentro do endpoint.
