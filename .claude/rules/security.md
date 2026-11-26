---
paths:
  - "gems/boto-security/lib/**/*.rb"
  - "gems/boto-redis/lib/**/*.rb"
  - "gems/boto/lib/boto/plugin.rb"
  - "gems/boto/lib/boto/plugin/**/*.rb"
  - "**/config/app.rb"
  - "**/credentials/**"
---

# Plugins de segurança

- Toda proteção é um middleware Rack ligado no projeto (`config/app.rb`). O
  endpoint só declara exceções (`skip`) ou exigências (`authenticate`).
- A ordem é fixa: hosts -> cors -> secure_headers -> sessions -> csrf -> auth
  -> rate_limit (`Boto::Plugin::ORDER`). Os globais (hosts, cors e os de
  sessão/CSRF) rodam antes do roteamento. Os de endpoint (auth e rate_limit)
  rodam depois e aceitam `skip`. Um plugin novo precisa de posição definida
  nessa lista.
- Nunca escreva primitiva de criptografia própria. Use OpenSSL (AES-256-GCM
  para cookies e credentials) e `Rack::Utils.secure_compare` para comparar
  segredos. Quando fizer sentido, reaproveite `rack-protection`.
- A chave vem das credentials criptografadas, nunca do código nem de um
  default embutido.
- Por padrão, a telemetria e os logs mascaram senhas, tokens e
  `Authorization`.
- Opções inválidas falham no boot com mensagem clara, não no primeiro request.
- Os testes cobrem os casos de ataque: sem token, token errado, token
  expirado, `skip` aplicado só ao endpoint certo, `Origin` divergente (csrf) e
  host não permitido (hosts).
