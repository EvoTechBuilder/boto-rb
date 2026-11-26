---
name: new-plugin
description: Use ao criar ou alterar um plugin do Boto (auth, cors, rate_limit, hosts, sessions, csrf, secure_headers, telemetry ou outro ligado via app.use). Cobre middleware, ordem, skip no endpoint, testes e CHANGELOG.
---

# Criar ou alterar um plugin

1. Para um plugin novo, use antes a skill `propose-api`.
2. Implemente o plugin na gem certa:
   - de segurança vai em `gems/boto-security/lib/boto/plugins/<nome>.rb`;
   - os outros vão na gem da área dele.
   
   Em ambos os casos, a classe é `Boto::Plugins::<Nome> < Boto::Plugin`, com:
   - `scope :global`, se roda antes do roteamento e vale também para
     404/405/preflight;
   - `scope :endpoint` (o padrão), se roda depois do roteamento e aceita
     `skip`;
   - um `configure(**opcoes)` privado;
   - `call(env, app)`, que chama `app.call(env)` para seguir ou devolve a
     tripla Rack.
3. Não há registro manual. `app.use :<nome>` resolve `Boto::Plugins::<Nome>`
   pelo nome da constante, e uma classe de terceiros também pode ser passada
   direto (`app.use MeuPlugin`).
4. Valide as opções no `configure` e lance `ArgumentError` com mensagem
   clara, para falhar no boot. Leia os segredos uma vez, com
   `Boto::Security::Secrets.resolve`.
5. Se for um plugin de segurança, coloque-o na posição certa da ordem fixa
   (hosts -> cors -> secure_headers -> sessions -> csrf -> auth -> rate_limit).
   A posição precisa ser atualizada em `Boto::Plugin::ORDER`, no CLAUDE.md e
   em `.claude/rules/security.md`.
6. Com `scope :endpoint`, o `skip :<nome>` no `Boto::Endpoint` já funciona e
   vale só para aquele endpoint. Um plugin global não aceita `skip`.
7. Se o plugin fizer parte do default de algum template, ligue-o no
   `config/app.rb` desse template.
8. Testes com `Rack::MockRequest`:
   - plugin ligado;
   - endpoint com `skip`;
   - opções inválidas falhando no boot;
   - casos de ataque (veja `.claude/rules/security.md`).
9. Se o plugin roda em todo request, use a skill `benchmark`.
10. Registre a mudança no `CHANGELOG.md`, na seção `Unreleased`.
