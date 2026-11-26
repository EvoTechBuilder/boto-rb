---
paths:
  - "**/test/**/*.rb"
---

# Testes

- Use Minitest e siga o estilo já presente na gem.
- `test/` espelha a estrutura do código testado (`lib/boto/router.rb` ->
  `test/boto/router_test.rb`).
- Teste o endpoint chamando `call` direto, com os params como keyword args e
  sem subir servidor.
- Para testar a pilha Rack (roteador, plugins, ordem de middlewares), use
  `Rack::MockRequest`, sem adicionar gem de teste.
- Não use rede real, `sleep` nem dependência de ordem entre testes.
- A suíte precisa passar com YJIT ligado e desligado
  (`RUBY_YJIT_ENABLE=1` e sem a variável).
